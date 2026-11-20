import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// References only: removing an entry never changes the original file.
@MainActor
final class FileShelf: ObservableObject {
    struct Entry: Identifiable {
        let id: UUID
        var name: String
        var url: URL?
        var bookmark: Data?
        var missing: Bool
        var demoSymbol: String?
    }

    private struct SavedEntry: Codable {
        let id: UUID
        let name: String
        let path: String
        let bookmark: Data?
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var importing = false
    @Published var error: String?
    let isDemo: Bool
    private let storageKey = "notch.fileShelf.v1"
    private var scopedURLs: [UUID: URL] = [:]
    private var batches: [Int: [Result<URL, Error>?]] = [:]
    private var issuedBatch = 0
    private var nextBatch = 0
    private let defaults: UserDefaults
    private var pendingBatches = 0

    init(demo: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDemo = demo
        if demo {
            entries = [("Présentation.pdf", "doc.richtext"), ("Visuels", "folder"),
                       ("Notes de réunion.txt", "doc.text"), ("Maquette.png", "photo")].map {
                Entry(id: UUID(), name: $0.0, url: nil, bookmark: nil,
                      missing: false, demoSymbol: $0.1)
            }
            return
        }
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            let saved = try JSONDecoder().decode([SavedEntry].self, from: data)
            for record in saved {
                var stale = false
                let resolved = record.bookmark.flatMap {
                    try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI],
                             relativeTo: nil, bookmarkDataIsStale: &stale)
                }
                let url = (resolved ?? URL(fileURLWithPath: record.path)).standardizedFileURL
                guard !entries.contains(where: { $0.url == url }) else { continue }
                retainAccess(url, id: record.id)
                let missing = !FileManager.default.fileExists(atPath: url.path)
                let bookmark = stale ? (try? makeBookmark(url)) ?? record.bookmark : record.bookmark
                entries.append(Entry(id: record.id, name: missing ? record.name : url.lastPathComponent,
                                     url: url, bookmark: bookmark, missing: missing, demoSymbol: nil))
            }
            persist()
        } catch {
            self.error = "La liste enregistrée ne peut pas être relue."
        }
    }

    deinit {
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    /// Synchronously accepts file URLs; resolves each batch serially, preserving drop order.
    @discardableResult
    func accept(_ providers: [NSItemProvider]) -> Bool {
        guard !isDemo else { return false }
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        pendingBatches += 1
        importing = true
        let batch = issuedBatch
        issuedBatch += 1
        batches[batch] = Array(repeating: nil, count: files.count)
        // Start every load while the system is still executing the drop handler.
        for (index, provider) in files.enumerated() {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                let result: Result<URL, Error>
                if let error { result = .failure(error) }
                else {
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let string = item as? String { url = URL(string: string) }
                    else { url = nil }
                    if let url, url.isFileURL { result = .success(url) }
                    else { result = .failure(CocoaError(.fileReadUnsupportedScheme)) }
                }
                Task { @MainActor in self?.complete(result, index: index, batch: batch) }
            }
        }
        return true
    }

    private func complete(_ result: Result<URL, Error>, index: Int, batch: Int) {
        batches[batch]?[index] = result
        while let ready = batches[nextBatch], ready.allSatisfy({ $0 != nil }) {
            for result in ready.compactMap({ $0 }) {
                switch result {
                case .success(let url): insert(url)
                case .failure: error = "Un fichier n’a pas pu être ajouté. Réessayez depuis le Finder."
                }
            }
            batches.removeValue(forKey: nextBatch)
            nextBatch += 1
            pendingBatches -= 1
        }
        importing = pendingBatches > 0
    }

    private func insert(_ original: URL) {
        let url = original.standardizedFileURL.resolvingSymlinksInPath()
        guard !entries.contains(where: { $0.url?.standardizedFileURL.resolvingSymlinksInPath() == url }) else { return }
        let id = UUID()
        retainAccess(url, id: id)
        let bookmark: Data?
        do { bookmark = try makeBookmark(url) }
        catch {
            bookmark = nil
            self.error = "Accès conservé pour cette session ; le fichier devra peut-être être retrouvé à la réouverture."
        }
        entries.append(Entry(id: id, name: url.lastPathComponent, url: url, bookmark: bookmark,
                             missing: !FileManager.default.fileExists(atPath: url.path), demoSymbol: nil))
        persist()
    }

    private func makeBookmark(_ url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            // Non-sandboxed installations can retain ordinary, rename-tracking bookmarks.
            return try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    private func retainAccess(_ url: URL, id: UUID) {
        if url.startAccessingSecurityScopedResource() { scopedURLs[id] = url }
    }

    private func persist() {
        guard !isDemo else { return }
        let saved = entries.compactMap { entry -> SavedEntry? in
            guard let url = entry.url else { return nil }
            return SavedEntry(id: entry.id, name: entry.name, path: url.path, bookmark: entry.bookmark)
        }
        do { defaults.set(try JSONEncoder().encode(saved), forKey: storageKey) }
        catch { self.error = "La liste n’a pas pu être enregistrée." }
    }

    func remove(_ entry: Entry) {
        guard !isDemo else { return }
        scopedURLs.removeValue(forKey: entry.id)?.stopAccessingSecurityScopedResource()
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func open(_ entry: Entry) {
        guard !isDemo, let url = entry.url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { markMissing(entry.id); return }
        if !NSWorkspace.shared.open(url) { error = "Aucune application n’a pu ouvrir ce fichier." }
    }

    func reveal(_ entry: Entry) {
        guard !isDemo, let url = entry.url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { markMissing(entry.id); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func locate(_ entry: Entry) {
        guard !isDemo else { return }
        let panel = NSOpenPanel()
        panel.title = "Retrouver « \(entry.name) »"
        panel.prompt = "Retrouver"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let self, let url = panel.url,
                      let index = self.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
                guard !self.entries.contains(where: { $0.id != entry.id && $0.url == normalized }) else {
                    self.error = "Ce fichier est déjà dans le dépôt."; return
                }
                do {
                    let bookmark = try self.makeBookmark(normalized)
                    self.scopedURLs.removeValue(forKey: entry.id)?.stopAccessingSecurityScopedResource()
                    self.retainAccess(normalized, id: entry.id)
                    self.entries[index] = Entry(id: entry.id, name: normalized.lastPathComponent, url: normalized,
                                                bookmark: bookmark, missing: false, demoSymbol: nil)
                    self.persist()
                } catch { self.error = "L’accès à ce fichier n’a pas pu être enregistré." }
            }
        }
    }

    func provider(for entry: Entry) -> NSItemProvider {
        guard !isDemo, let url = entry.url, FileManager.default.fileExists(atPath: url.path) else {
            if !isDemo { markMissing(entry.id) }
            return NSItemProvider()
        }
        // NSURL writes public.file-url, keeping a normal Finder-compatible file drag.
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = entry.name
        return provider
    }

    private func markMissing(_ id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].missing = true }
        error = "Fichier introuvable. Utilisez « Retrouver » pour rétablir son accès."
    }
}

struct FileShelfPane: View {
    @ObservedObject var shelf: FileShelf
    var targeted: Bool
    @Environment(\.notchPalette) private var palette
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Dépôt", systemImage: "tray")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(shelf.importing ? "Ajout…" : "\(shelf.entries.count) fichier\(shelf.entries.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            if shelf.entries.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Glissez des fichiers ici")
                        .font(.system(size: 13, weight: .medium))
                    Text("Déposez depuis le Finder, puis glissez vers une autre app.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shelf.entries.count <= 4 {
                grid
                Spacer(minLength: 0)
            } else {
                ScrollView { grid }.scrollIndicators(.hidden)
            }
            HStack(spacing: 6) {
                Image(systemName: targeted ? "arrow.down.circle" : "link")
                Text(targeted ? "Relâchez pour ajouter au dépôt" : "Les originaux restent à leur emplacement.")
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(targeted ? palette.accent : .clear, lineWidth: 1.5))
        .foregroundStyle(.white.opacity(0.92))
        .alert("Dépôt", isPresented: Binding(get: { shelf.error != nil }, set: { if !$0 { shelf.error = nil } })) {
            Button("OK") { shelf.error = nil }
        } message: { Text(shelf.error ?? "") }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(shelf.entries) { entry in
                cardContent(entry)
            }
        }
    }

    private func cardContent(_ entry: FileShelf.Entry) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
            Group {
                if let symbol = entry.demoSymbol {
                    Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.7))
                } else if let url = entry.url, !entry.missing {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                } else {
                    Image(systemName: "doc.badge.ellipsis").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                }
            }.frame(width: 28, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(entry.missing ? "Introuvable · clic pour retrouver" : "Glisser ou double-cliquer")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if !shelf.isDemo && !entry.missing, let url = entry.url {
                    FileShelfDragSurface(url: url, open: { shelf.open(entry) }, reveal: { shelf.reveal(entry) })
                }
            }
            if !shelf.isDemo {
                Button { shelf.remove(entry) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45)).frame(width: 20, height: 24)
                }.buttonStyle(.plain).help("Retirer du dépôt ; conserver l’original")
                    .accessibilityLabel("Retirer \(entry.name) du dépôt")
            }
        }
        .padding(.horizontal, 10).frame(height: 55)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { entry.missing ? shelf.locate(entry) : shelf.open(entry) }
        .onTapGesture { if entry.missing { shelf.locate(entry) } }
        .contextMenu {
            if !shelf.isDemo {
                if entry.missing { Button("Retrouver…") { shelf.locate(entry) } }
                else {
                    Button("Ouvrir") { shelf.open(entry) }
                    Button("Afficher dans le Finder") { shelf.reveal(entry) }
                }
                Divider()
                Button("Retirer du dépôt") { shelf.remove(entry) }
            }
        }
        .help(entry.url?.path ?? entry.name)
    }
}

/// Native file dragging advertises copy only, including when modifier keys change.
private struct FileShelfDragSurface: NSViewRepresentable {
    let url: URL
    let open: () -> Void
    let reveal: () -> Void

    func makeNSView(context: Context) -> FileShelfDragView { FileShelfDragView() }
    func updateNSView(_ view: FileShelfDragView, context: Context) {
        view.url = url
        view.openFile = open
        view.revealFile = reveal
        view.toolTip = url.path
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel(url.lastPathComponent)
        view.setAccessibilityRole(.button)
    }
}

private final class FileShelfDragView: NSView, NSDraggingSource {
    var url: URL?
    var openFile: (() -> Void)?
    var revealFile: (() -> Void)?
    private var mouseStart: NSPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseStart = convert(event.locationInWindow, from: nil)
        dragging = false
        if event.clickCount == 2 { openFile?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseStart, let url else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { openFile?(); return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32),
                              contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseStart = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        mouseStart = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Ouvrir", action: #selector(openAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let reveal = NSMenuItem(title: "Afficher dans le Finder", action: #selector(revealAction), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    @objc private func openAction() { openFile?() }
    @objc private func revealAction() { revealFile?() }
    override func accessibilityPerformPress() -> Bool { openFile?(); return true }
}
