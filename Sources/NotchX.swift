import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum Preference {
    static let hover = "notch.hover"
    static let keepOpen = "notch.keepOpen"
    static let screen = "notch.screen"
    static let size = "notch.panelSize"

    static func register() {
        UserDefaults.standard.register(defaults: [
            hover: true, keepOpen: false, screen: "builtIn", size: "compact"
        ])
    }
}

private enum PanelMotion {
    static let hoverDelay: TimeInterval = 0.20
    static let openDuration: TimeInterval = 0.16
    static let closeDuration: TimeInterval = 0.16
}

private enum NotchGeometry {
    static let shoulder: CGFloat = 13
}

private enum PanelSize: String {
    case compact, large

    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: Preference.size) ?? "") ?? .compact
    }

    var dimensions: CGSize {
        switch self {
        case .compact: CGSize(width: 590, height: 270)
        case .large: CGSize(width: 650, height: 310)
        }
    }
}

@main
struct NotchX {
    @MainActor
    static func main() {
        Preference.register()
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--export-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            let dimensions = PanelSize.selected.dimensions
            let inset: CGFloat = CommandLine.arguments.contains("--preview-notch-edge") ? 32 : 0
            let shoulders = inset > 0 ? NotchGeometry.shoulder * 2 : 0
            let view = NotchPaletteScope {
                Board(demo: true, pinned: false, togglePin: {}, showSettings: {}, close: {})
            }
            .frame(width: dimensions.width + shoulders, height: dimensions.height + inset)
            .environment(\.notchTopInset, inset)
            .environment(\.notchCameraWidth, 185)
            .environment(\.notchStaticPreview, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fputs("Impossible de rendre l’aperçu.\n", stderr)
                exit(1)
            }
            do {
                try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let delegate = NotchController(demo: CommandLine.arguments.contains("--preview"))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
private final class NotchController: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let demo: Bool
    private var statusItem: NSStatusItem?
    private var panel: NotchPanel?
    private var settings: NSWindow?
    private var monitors: [Any] = []
    private var trackingTimer: Timer?
    private var enteredAt: TimeInterval?
    private var expanded = false
    private var pointerReachedPanel = false
    private var suppressHover = false
    private var expandedScreen: CGDirectDisplayID?
    private let boardState = BoardState()
    private var transitionID = 0

    init(demo: Bool) {
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if demo {
            showPreviewWindow()
            return
        }
        configureStatusItem()
        if let screen = activeScreen { preparePanel(for: screen) }
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 0.02, target: self, selector: #selector(trackPointer), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            Task { @MainActor in self?.closeOnOutsideClick() }
        }) { monitors.append(monitor) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trackingTimer?.invalidate()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        demo
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchX")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "NotchX · Clic droit pour les réglages"
        statusItem = item
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let item = statusItem {
            let menu = NSMenu()
            menu.addItem(withTitle: expanded ? "Replier NotchX" : "Afficher NotchX",
                         action: #selector(toggleBoard), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Réglages…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quitter NotchX", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            defer { item.menu = nil }
            item.button?.performClick(nil)
        } else {
            toggleBoard()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleBoard() {
        if expanded { closeBoard() }
        else { openBoard() }
    }

    private var activeScreen: NSScreen? {
        let screens = NSScreen.screens
        if defaults.string(forKey: Preference.screen) == "pointer" {
            let point = NSEvent.mouseLocation
            return screens.first { isOverNotch(point, on: $0) }
                ?? screens.first { $0.frame.contains(point) }
                ?? screens.first
        }
        return screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first
    }

    private func notchCenter(_ screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }

    private func notchWidth(_ screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return max(96, right.minX - left.maxX)
        }
        return 112
    }

    private func notchBottom(_ screen: NSScreen) -> CGFloat {
        let inset = screen.safeAreaInsets.top
        return inset > 0 ? screen.frame.maxY - inset + 1 : screen.visibleFrame.maxY
    }

    private func isOverNotch(_ point: NSPoint, on screen: NSScreen) -> Bool {
        let halfWidth = (notchWidth(screen) + 12) / 2
        // The pointer can sit exactly at maxY, which CGRect.contains excludes.
        return abs(point.x - notchCenter(screen)) <= halfWidth
            && point.y >= notchBottom(screen) - 12
            && point.y <= screen.frame.maxY
    }

    private func topInset(_ screen: NSScreen) -> CGFloat {
        screen.safeAreaInsets.top > 0 ? screen.frame.maxY - notchBottom(screen) : 0
    }

    private func boardFrame(_ screen: NSScreen) -> NSRect {
        let dimensions = PanelSize.selected.dimensions
        let inset = topInset(screen)
        let shoulders = inset > 0 ? NotchGeometry.shoulder * 2 : 0
        let width = min(dimensions.width + shoulders, screen.visibleFrame.width - 24)
        let height = min(dimensions.height, screen.visibleFrame.height - 24)
        let center = notchCenter(screen)
        let x = min(max(center - width / 2, screen.visibleFrame.minX + 12), screen.visibleFrame.maxX - width - 12)
        return NSRect(x: x, y: notchBottom(screen) - height, width: width, height: height + inset)
    }

    private func configure(_ window: NSPanel) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
    }

    private func preparePanel(for screen: NSScreen) {
        guard panel == nil else { return }
        let window = NotchPanel(contentRect: boardFrame(screen), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        configure(window)
        window.title = "NotchX"
        window.hasShadow = true
        window.becomesKeyOnlyIfNeeded = true
        window.onEscape = { [weak self] in self?.closeBoard() }
        let host = NSHostingView(rootView: BoardContainer(state: boardState,
            togglePin: { [weak self] in self?.togglePin() },
            showSettings: { [weak self] in self?.showSettings() },
            close: { [weak self] in self?.closeBoard() }))
        host.sizingOptions = []
        window.contentView = host
        panel = window
        host.layoutSubtreeIfNeeded()
    }

    private func openBoard(byHover: Bool = false) {
        guard let screen = activeScreen else { return }
        preparePanel(for: screen)
        guard let panel else { return }
        expanded = true
        pointerReachedPanel = byHover
        boardState.presented = true
        boardState.pinned = defaults.bool(forKey: Preference.keepOpen)
        boardState.originWidth = notchWidth(screen)
        boardState.topInset = topInset(screen)
        expandedScreen = screen.displayID
        transitionID += 1
        let animation = transitionID
        let wasVisible = panel.isVisible
        panel.ignoresMouseEvents = false
        let frame = boardFrame(screen)
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        panel.orderFrontRegardless()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || wasVisible {
            boardState.revealed = true
        } else {
            // Give the hosting view one frame to lay out the collapsed mask.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
                guard let self, self.transitionID == animation else { return }
                self.boardState.revealed = true
            }
        }
    }

    private func closeBoard() {
        guard expanded else { return }
        expanded = false
        boardState.presented = false
        boardState.revealed = false
        expandedScreen = nil
        enteredAt = nil
        suppressHover = true
        panel?.ignoresMouseEvents = true
        transitionID += 1
        let animation = transitionID
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel?.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + PanelMotion.closeDuration + 0.02) { [weak self] in
                guard let self, self.transitionID == animation else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func togglePin() {
        let value = !defaults.bool(forKey: Preference.keepOpen)
        defaults.set(value, forKey: Preference.keepOpen)
        boardState.pinned = value
    }

    private func closeOnOutsideClick() {
        guard expanded, !defaults.bool(forKey: Preference.keepOpen),
              let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        closeBoard()
    }

    @objc private func trackPointer() {
        let point = NSEvent.mouseLocation
        if expanded, let panel {
            let overNotch = NSScreen.screens.first { $0.displayID == expandedScreen }
                .map { isOverNotch(point, on: $0) } ?? false
            let overPopover = panel.childWindows?.contains { $0.isVisible && $0.frame.contains(point) } ?? false
            if panel.frame.contains(point) || overNotch || overPopover {
                pointerReachedPanel = true
            } else if pointerReachedPanel && !defaults.bool(forKey: Preference.keepOpen)
                        && NSEvent.pressedMouseButtons & 1 == 0 {
                closeBoard()
            }
            return
        }
        guard let screen = activeScreen else { return }
        guard isOverNotch(point, on: screen) else {
            enteredAt = nil
            suppressHover = false
            return
        }
        guard defaults.bool(forKey: Preference.hover), !suppressHover else {
            enteredAt = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let enteredAt, now - enteredAt >= PanelMotion.hoverDelay {
            openBoard(byHover: true)
        } else if enteredAt == nil {
            enteredAt = now
        }
    }

    @objc private func displayChanged() {
        enteredAt = nil
        guard expanded,
              let screen = NSScreen.screens.first(where: { $0.displayID == expandedScreen }) ?? activeScreen else { return }
        expandedScreen = screen.displayID
        boardState.originWidth = notchWidth(screen)
        boardState.topInset = topInset(screen)
        panel?.setFrame(boardFrame(screen), display: true)
    }

    @objc private func showSettings() {
        closeBoard()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 440),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Réglages de NotchX"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NotchSettings(
                quit: { [weak self] in self?.quit() }))
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    private func showPreviewWindow() {
        let dimensions = PanelSize.selected.dimensions
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: dimensions),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NotchX · Aperçu"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: NotchPaletteScope {
            Board(demo: true, pinned: false, togglePin: {}, showSettings: {}, close: { NSApp.terminate(nil) })
        })
        window.center()
        settings = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private final class BoardState: ObservableObject {
    @Published var presented = false
    @Published var pinned = false
    @Published var revealed = false
    @Published var originWidth: CGFloat = 112
    @Published var topInset: CGFloat = 0
}

private struct BoardContainer: View {
    @ObservedObject var state: BoardState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let togglePin: () -> Void
    let showSettings: () -> Void
    let close: () -> Void

    var body: some View {
        NotchPaletteScope {
            Board(demo: false, pinned: state.pinned, togglePin: togglePin, showSettings: showSettings, close: close)
        }
        .environment(\.notchBoardPresented, state.presented)
        .environment(\.notchTopInset, state.topInset)
        .environment(\.notchCameraWidth, state.originWidth)
        .mask(RevealMask(progress: state.revealed ? 1 : 0, originWidth: state.originWidth, attached: state.topInset > 0))
        .animation(reduceMotion ? nil : state.revealed
            ? .easeOut(duration: PanelMotion.openDuration)
            : .easeInOut(duration: PanelMotion.closeDuration), value: state.revealed)
        .accessibilityHidden(!state.presented)
    }
}

private struct RevealMask: Shape {
    var progress: CGFloat
    let originWidth: CGFloat
    let attached: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = min(1, max(0, progress))
        let startWidth = min(originWidth, rect.width)
        let width = startWidth + (rect.width - startWidth) * fraction
        let height = rect.height * fraction
        let visible = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return PanelSilhouette(attached: attached).path(in: visible)
    }
}

private struct PanelSilhouette: Shape {
    let attached: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(28, rect.height / 2, rect.width / 4)
        guard attached else {
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }

        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let shoulder = min(NotchGeometry.shoulder, rect.height / 3, rect.width / 6)
        let innerLeft = left + shoulder
        let innerRight = right - shoulder
        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addQuadCurve(to: CGPoint(x: innerRight, y: top + shoulder),
                          control: CGPoint(x: innerRight, y: top))
        path.addLine(to: CGPoint(x: innerRight, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: innerRight - radius, y: bottom),
                          control: CGPoint(x: innerRight, y: bottom))
        path.addLine(to: CGPoint(x: innerLeft + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: innerLeft, y: bottom - radius),
                          control: CGPoint(x: innerLeft, y: bottom))
        path.addLine(to: CGPoint(x: innerLeft, y: top + shoulder))
        path.addQuadCurve(to: CGPoint(x: left, y: top),
                          control: CGPoint(x: innerLeft, y: top))
        path.closeSubpath()
        return path
    }
}

private struct NotchCameraWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct NotchTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct BoardPresentedKey: EnvironmentKey {
    static let defaultValue = true
}

private struct StaticPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var notchCameraWidth: CGFloat {
        get { self[NotchCameraWidthKey.self] }
        set { self[NotchCameraWidthKey.self] = newValue }
    }

    fileprivate var notchTopInset: CGFloat {
        get { self[NotchTopInsetKey.self] }
        set { self[NotchTopInsetKey.self] = newValue }
    }

    var notchBoardPresented: Bool {
        get { self[BoardPresentedKey.self] }
        set { self[BoardPresentedKey.self] = newValue }
    }

    var notchStaticPreview: Bool {
        get { self[StaticPreviewKey.self] }
        set { self[StaticPreviewKey.self] = newValue }
    }
}

private enum BoardSection: String, CaseIterable, Identifiable {
    case overview = "Accueil"
    case shelf = "Dépôt"

    var id: Self { self }
    var icon: String {
        switch self {
        case .overview: "house"
        case .shelf: "tray"
        }
    }
}

private struct ShelfDropTarget: DropDelegate {
    @Binding var targeted: Bool
    let accept: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        return accept(info.itemProviders(for: [.fileURL]))
    }
}

private struct Board: View {
    @Environment(\.notchPalette) private var palette
    @Environment(\.notchBoardPresented) private var presented
    @StateObject private var shelf: FileShelf
    @State private var section: BoardSection
    @State private var fileOverPanel = false
    private var accent: Color { palette.accent }
    @Environment(\.notchTopInset) private var topInset
    @Environment(\.notchCameraWidth) private var cameraWidth
    let demo: Bool
    let pinned: Bool
    let togglePin: () -> Void
    let showSettings: () -> Void
    let close: () -> Void

    init(demo: Bool, pinned: Bool, togglePin: @escaping () -> Void,
         showSettings: @escaping () -> Void, close: @escaping () -> Void) {
        self.demo = demo
        self.pinned = pinned
        self.togglePin = togglePin
        self.showSettings = showSettings
        self.close = close
        _shelf = StateObject(wrappedValue: FileShelf(demo: demo))
        _section = State(initialValue: demo && CommandLine.arguments.contains("--preview-shelf") ? .shelf : .overview)
    }

    var body: some View {
        Group {
            if demo {
                panelContent
            } else {
                panelContent
                    .onDrop(of: [.fileURL], delegate: ShelfDropTarget(targeted: $fileOverPanel) { providers in
                        guard shelf.accept(providers) else { return false }
                        section = .shelf
                        return true
                    })
                    .onChange(of: fileOverPanel) { _, targeted in
                        if targeted { section = .shelf }
                    }
                    .onChange(of: presented) { _, visible in
                        if !visible { fileOverPanel = false }
                    }
            }
        }
        .tint(accent)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private var panelContent: some View {
        GeometryReader { geometry in
            let attached = topInset > 0
            let shoulder = attached ? NotchGeometry.shoulder : 0
            let bodyHeight = geometry.size.height - topInset
            let compact = bodyHeight < 320
            let mediaWidth = min(214, max(166, (geometry.size.width - shoulder * 2) * 0.235))
            let outline = PanelSilhouette(attached: attached)
            let cameraGap = cameraWidth + 18
            let width = geometry.size.width - shoulder * 2
            let integrated = topInset >= 26 && (width - cameraGap - 24) / 2 >= 174
            VStack(spacing: 0) {
                if integrated {
                    integratedHeader(cameraGap: cameraGap)
                        .frame(height: topInset)
                        .padding(.bottom, 3)
                } else {
                    header
                }
                ZStack {
                    HStack(alignment: .top, spacing: 12) {
                        MediaPane(demo: demo, compact: compact, short: bodyHeight < 295)
                            .frame(width: mediaWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 19))
                        CalendarPane(demo: demo, compact: compact)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, integrated ? 5 : 0)
                    }
                    .environment(\.notchBoardPresented, presented && section == .overview)
                    .opacity(section == .overview ? 1 : 0)
                    .allowsHitTesting(section == .overview)
                    .accessibilityHidden(section != .overview)
                    if section == .shelf {
                        FileShelfPane(shelf: shelf, targeted: fileOverPanel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, shoulder)
            .padding(.top, integrated ? 0 : topInset)
            .background(alignment: .top) {
                palette.surface.overlay(alignment: .top) {
                    if attached {
                        LinearGradient(colors: [.black, palette.surface], startPoint: .top, endPoint: .bottom)
                            .frame(height: topInset)
                    }
                }
            }
            .clipShape(outline)
            .overlay {
                outline.stroke(.white.opacity(attached ? 0.065 : 0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var title: some View {
        Text("NotchX")
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerActions: some View {
        HStack(spacing: 4) {
            headerButton(pinned ? "pin.fill" : "pin", pinned ? "Désépingler" : "Épingler",
                         active: pinned, action: togglePin)
            headerButton("gearshape", "Réglages", action: showSettings)
            headerButton("chevron.up", "Replier", action: close)
        }
    }

    private func integratedHeader(cameraGap: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                sectionPicker
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: cameraGap).accessibilityHidden(true)

            HStack(spacing: 6) {
                title.frame(maxWidth: .infinity, alignment: .center)
                headerActions
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            title
            Spacer()
            sectionPicker
            Spacer()
            if demo {
                Text("Données de démonstration")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                headerActions
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 34)
    }

    private var sectionPicker: some View {
        HStack(spacing: 2) {
            ForEach(BoardSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize()
                        .foregroundStyle(section == item ? accent : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(section == item ? accent.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func headerButton(_ icon: String, _ label: String, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? accent : Color.secondary)
                .frame(width: 29, height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NotchSettings: View {
    @AppStorage(Preference.hover) private var hover = true
    @AppStorage(Preference.keepOpen) private var keepOpen = false
    @AppStorage(Preference.screen) private var screen = "builtIn"
    @AppStorage(Preference.size) private var size = PanelSize.compact.rawValue
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?
    let quit: () -> Void

    var body: some View {
        TabView {
            ScrollView {
                Form {
                    Section("Panneau") {
                        Toggle("Ouvrir au survol de l’encoche", isOn: $hover)
                        Toggle("Garder le panneau ouvert", isOn: $keepOpen)
                        Picker("Écran", selection: $screen) {
                            Text("Écran avec encoche ou principal").tag("builtIn")
                            Text("Écran sous le pointeur").tag("pointer")
                        }
                        Picker("Taille", selection: $size) {
                            Text("Compact").tag(PanelSize.compact.rawValue)
                            Text("Grand").tag(PanelSize.large.rawValue)
                        }
                    }
                    Section("Démarrage") {
                        Toggle("Ouvrir NotchX à l’ouverture de session", isOn: Binding(
                            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                            set: setLogin))
                        if loginStatus == .requiresApproval {
                            Button("Valider dans les réglages macOS") { SMAppService.openSystemSettingsLoginItems() }
                        }
                        if let loginError { Text(loginError).foregroundStyle(.red) }
                    }
                    Button("Quitter NotchX", action: quit)
                }
                .formStyle(.grouped)
            }
            .tabItem { Label("Général", systemImage: "gearshape") }
            PalettePreferences()
                .tabItem { Label("Apparence", systemImage: "paintpalette") }
            CalendarPreferences()
                .tabItem { Label("Calendrier", systemImage: "calendar") }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 410)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}
