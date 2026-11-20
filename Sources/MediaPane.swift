import SwiftUI
import AppKit
import ApplicationServices

// Public Apple Events only. No private MediaRemote symbols or synthetic media keys.
// Browser access begins only after the user selects “Connecter”.
struct MediaPane: View {
    @Environment(\.notchBoardPresented) private var boardPresented
    @StateObject private var media: BrowserMediaModel
    @State private var showHelp = false
    @Environment(\.notchPalette) private var palette
    private let compact: Bool
    private let short: Bool
    private let minimal: Bool
    private var accent: Color { palette.accent }

    init(demo: Bool = false, compact: Bool = false, short: Bool = false, minimal: Bool = false) {
        self.minimal = minimal
        self.short = short
        self.compact = compact
        _media = StateObject(wrappedValue: BrowserMediaModel(demo: demo))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: minimal ? 4 : compact ? 6 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform").foregroundStyle(accent)
                Text("À L’ÉCOUTE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(minimal ? 0.8 : 2)
                    .lineLimit(1)
                Spacer()
                Circle().fill(media.track?.playing == true ? accent : Color.white.opacity(0.22))
                    .frame(width: 5, height: 5)

            }
            HStack(spacing: 5) {
                ForEach(MediaSource.allCases) { source in
                    Button { media.select(source) } label: {
                        Text(source.rawValue).font(.system(size: 10, weight: .medium)).fixedSize()
                        .padding(.horizontal, compact ? 4 : 6).padding(.vertical, 7)
                        .foregroundStyle(media.source == source ? accent : .white.opacity(0.45))
                        .background(media.source == source ? accent.opacity(0.1) : Color.clear)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            if let track = media.track {
                player(track)
            } else if minimal {
                ScrollView { idle.frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollIndicators(.hidden)
            } else {
                idle
            }
            Spacer(minLength: 0)
            HStack {
                if !minimal {
                    Text(media.source == .podcasts ? "APPLE PODCASTS" : "YOUTUBE · \(media.source.rawValue.uppercased())")
                        .font(.system(size: 8, weight: .medium)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.28))
                }
                Spacer()
                Button { showHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }.buttonStyle(.plain).help("Connexion et confidentialité")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connecter votre lecteur").font(.headline)
                        Text("Dans Safari › Réglages › Développeur, cochez « Autoriser JavaScript à partir des évènements Apple ». Si l’onglet manque, activez les fonctionnalités pour les développeurs dans Avancés.")
                        Button("Ouvrir les réglages Safari") { media.openSafariSettings() }
                        Text("Revenez dans NotchX et cliquez sur Connecter Safari. macOS peut vous demander d’autoriser NotchX à piloter Safari.")
                        Text("Podcasts : cette version ouvre l’app. Les commandes sont détectées via Accessibilité, avec votre autorisation. La compatibilité dépend des libellés exposés par Podcasts. Le titre de l’épisode n’est pas lu.")
                    }.font(.system(size: 11)).lineSpacing(3).padding(18).frame(width: 310)
                }
                if media.connected && !media.demo {
                    Button { media.disconnect() } label: { Image(systemName: "xmark.circle").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.35)).help("Déconnecter le lecteur")
                        .accessibilityLabel("Déconnecter le lecteur")
                }
            }
        }
        .padding(compact ? 9 : 16)
        .foregroundStyle(.white.opacity(0.93))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { media.setPresented(boardPresented) }
        .onChange(of: boardPresented) { _, value in media.setPresented(value) }
        .onDisappear { media.setPresented(false) }
    }

    private func player(_ track: BrowserTrack) -> some View {
        VStack(alignment: .leading, spacing: minimal ? 4 : compact ? 6 : 10) {
            if !short {
                artwork
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: compact ? 15 : 16, weight: .medium)).lineLimit(minimal ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(track.title)
                if !minimal {
                    Text(track.author.isEmpty ? "YouTube" : track.author).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.43)).lineLimit(1)
                }
            }
            progress(track)
            playbackControls(track)
            if !media.message.isEmpty {
                Text(media.message).font(.system(size: 10)).foregroundStyle(accent.opacity(0.8))
                    .lineLimit(short ? 1 : 2).help(media.message)
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(
                colors: [accent.opacity(0.18), palette.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(accent.opacity(0.18), lineWidth: 1).frame(width: compact ? 29 : 68, height: compact ? 29 : 68)
            Circle().stroke(accent.opacity(0.11), lineWidth: 1).frame(width: compact ? 22 : 58, height: compact ? 22 : 58)
            Image(systemName: media.source == .podcasts ? "mic.fill" : "play.rectangle.fill")
                .font(.system(size: compact ? 20 : 28, weight: .light)).foregroundStyle(accent.opacity(0.8))
        }.frame(height: compact ? 32 : 76)
    }

    private func progress(_ track: BrowserTrack) -> some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(accent).frame(width: geometry.size.width * track.progress)
                }
            }.frame(height: 2)
            HStack {
                Text(time(track.elapsed))
                Spacer()
                Text(track.duration > 0 ? time(track.duration) : "DIRECT")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.32))
        }
    }

    private func playbackControls(_ track: BrowserTrack) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            control("gobackward.15", label: "Reculer de 15 secondes", command: .back)
            Button { media.command(.toggle) } label: {
                Image(systemName: track.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: compact ? 35 : 40, height: compact ? 35 : 40).foregroundStyle(Color.black.opacity(0.85))
                    .background(accent).clipShape(Circle())
            }.buttonStyle(.plain).help(track.playing ? "Mettre en pause" : "Lire")
            .accessibilityLabel(track.playing ? "Mettre en pause" : "Lire")
            control("goforward.15", label: "Avancer de 15 secondes", command: .forward)
            Spacer(minLength: 0)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: minimal ? 4 : compact ? 6 : 10) {
            if !minimal {
                Image(systemName: media.source == .podcasts ? "mic" : "headphones")
                    .font(.system(size: short ? 19 : 31, weight: .ultraLight)).foregroundStyle(accent.opacity(0.65))
                    .frame(height: short ? 20 : compact ? 30 : 60)
            }
            Text(media.source == .podcasts ? "Apple Podcasts" : "Aucune lecture")
                .font(.system(size: compact ? 17 : 21, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text(media.source == .podcasts
                 ? media.message.isEmpty ? "Connectez les commandes avec l’autorisation Accessibilité. Le titre de l’épisode reste dans Podcasts." : media.message
                 : media.message.isEmpty ? "Lancez une vidéo YouTube dans \(media.source.rawValue), puis connectez le lecteur." : media.message)
                .font(.system(size: 11)).lineSpacing(2).foregroundStyle(.white.opacity(0.60))
                .lineLimit(short ? 3 : 5)
                .help(media.message)
            Button {
                if media.source == .podcasts { media.connectPodcasts() }
                else if media.connected { media.refresh() }
                else { media.connect() }
            } label: {
                HStack(spacing: 8) {
                    Text(media.source == .podcasts ? "Connecter Podcasts" : media.connected ? "Actualiser" : "Connecter \(media.source.rawValue)")
                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    .padding(.vertical, 8).padding(.horizontal, compact ? 8 : 13)
                    .background(accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).disabled(media.busy)
            if media.source == .podcasts {
                if media.podcastControlsAvailable {
                    HStack(spacing: 24) {
                        Button { media.podcastCommand(.back) } label: { Image(systemName: "gobackward") }.help("Reculer selon le réglage Podcasts")
                        Button { media.podcastCommand(.toggle) } label: { Image(systemName: "playpause.fill") }
                        Button { media.podcastCommand(.forward) } label: { Image(systemName: "goforward") }.help("Avancer selon le réglage Podcasts")
                    }.buttonStyle(.plain).foregroundStyle(accent).padding(.top, 5)
                }
                Button("Ouvrir Podcasts") { media.openSource() }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
            } else {
                Button(media.safariAutomationDenied ? "Ouvrir Automatisation" : "Réglages Safari…") {
                    if media.safariAutomationDenied { media.openAutomationSettings() }
                    else { media.openSafariSettings() }
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }
        }
    }

    private func control(_ icon: String, label: String, command: MediaCommand) -> some View {
        Button { media.command(command) } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(.white.opacity(0.65))
                .frame(width: 25, height: 32)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private func time(_ value: Double) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private enum MediaSource: String, CaseIterable, Identifiable {
    case safari = "Safari", podcasts = "Podcasts"
    var id: String { rawValue }
    var bundleID: String {
        switch self { case .safari: return "com.apple.Safari"; case .podcasts: return "com.apple.podcasts" }
    }
}
private enum MediaCommand { case toggle, back, forward }
private struct BrowserTrack: Decodable {
    var title: String
    var author: String
    var elapsed: Double
    var duration: Double
    var playing: Bool
    var url: String
    var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
}

private final class BrowserMediaModel: ObservableObject {
    @Published var source: MediaSource = .safari
    @Published var track: BrowserTrack?
    @Published var connected = false
    @Published var busy = false
    @Published var message = ""
    @Published private(set) var safariAutomationDenied = false
    @Published var podcastControlsAvailable = false
    let demo: Bool
    private var timer: Timer?
    private var generation = 0
    private var presented = false
    private let safariPreference = "notch.media.rememberSafari"
    private var safariRetryRequired = false
    private let queue = DispatchQueue(label: "NotchX.browser-media", qos: .utility)

    init(demo: Bool) {
        self.demo = demo
        if demo { track = BrowserTrack(title: "Le temps de prendre le temps", author: "Une pause, un peu de musique", elapsed: 154, duration: 286, playing: true, url: "") }
    }
    deinit { timer?.invalidate() }
    func select(_ value: MediaSource) {
        guard source != value else { return }
        stopConnection()
        source = value
        restoreSafariConnection()
        if demo { track = BrowserTrack(title: value == .podcasts ? "Ce que le silence raconte" : "Le temps de prendre le temps", author: value == .podcasts ? "Les idées au calme · Épisode 28" : "Une pause, un peu de musique", elapsed: 154, duration: 286, playing: true, url: "") }
    }
    func connect() {
        guard !demo, source == .safari else { return }
        UserDefaults.standard.set(true, forKey: safariPreference)
        safariRetryRequired = false
        beginSafariConnection()
    }
    private func restoreSafariConnection() {
        guard !demo, source == .safari, presented, !connected, !safariRetryRequired,
              UserDefaults.standard.bool(forKey: safariPreference) else { return }
        beginSafariConnection()
    }
    private func beginSafariConnection() {
        connected = true
        safariAutomationDenied = false
        timer?.invalidate()
        let polling = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(polling, forMode: .common)
        timer = polling
        refresh()
    }
    func disconnect() {
        if !demo, source == .safari {
            UserDefaults.standard.removeObject(forKey: safariPreference)
            safariRetryRequired = false
        }
        stopConnection()
    }
    private func stopConnection() {
        generation += 1; timer?.invalidate(); timer = nil
        connected = false; busy = false; message = ""; podcastControlsAvailable = false
        safariAutomationDenied = false
        if !demo { track = nil }
    }
    // AX permission is requested only in response to this explicit button press.
    func connectPodcasts() {
        guard !demo else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            message = "Autorisez NotchX dans Réglages Système → Confidentialité et sécurité → Accessibilité, puis reconnectez."
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: MediaSource.podcasts.bundleID).first else {
            message = "Ouvrez Podcasts et lancez un épisode, puis reconnectez."; return
        }
        busy = true
        let token = generation
        queue.async { [weak self] in
            guard let self = self else { return }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            let available = self.findPodcastButton(root, command: .toggle) != nil
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.busy = false; self.podcastControlsAvailable = available; self.connected = available
                self.message = available ? "Commandes disponibles · titre dans Podcasts."
                    : "Commandes non exposées. Affichez le lecteur dans Podcasts, puis reconnectez."
            }
        }
    }
    func podcastCommand(_ command: MediaCommand) {
        guard !demo, AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: MediaSource.podcasts.bundleID).first else { return }
        guard !busy else { return }
        busy = true
        let token = generation
        queue.async { [weak self] in
            guard let self = self else { return }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            let button = self.findPodcastButton(root, command: command)
            let result = button.map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.busy = false
                if result != .success { self.message = "Commande non exposée. Ouvrez le lecteur Podcasts." }
            }
        }
    }
    private func findPodcastButton(_ root: AXUIElement, command: MediaCommand) -> AXUIElement? {
        // Exact semantic labels only; never guess from position or scrape unrelated text.
        let labels: Set<String>
        switch command {
        case .toggle: labels = ["play", "pause", "play/pause", "lecture", "lire", "mettre en pause", "lecture/pause"]
        case .back: labels = ["skip back", "skip backward", "rewind 15 seconds", "skip back 15 seconds", "reculer de 15 secondes", "reculer de 15 s"]
        case .forward: labels = ["skip forward", "forward 30 seconds", "skip forward 30 seconds", "avancer de 30 secondes", "avancer de 30 s"]
        }
        var pending: [(AXUIElement, Int, Bool)] = [(root, 0, false)]
        var count = 0
        let deadline = Date().addingTimeInterval(3)
        while let (node, depth, inheritedScope) = pending.popLast(), count < 250, Date() < deadline {
            count += 1
            func text(_ name: String) -> String {
                var value: CFTypeRef?
                return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? (value as? String ?? "") : ""
            }
            let identifier = text(kAXIdentifierAttribute).lowercased().filter { $0.isLetter || $0.isNumber }
            let description = text(kAXDescriptionAttribute).lowercased()
            let scoped = inheritedScope || ["nowplaying", "playbackcontrols", "playerbar", "miniplayer"].contains(where: identifier.contains)
                || ["now playing", "player", "playback controls", "lecteur", "commandes de lecture", "à l’écoute"].contains(description)
            if scoped && text(kAXRoleAttribute) == kAXButtonRole {
                let candidates = [text(kAXTitleAttribute), text(kAXDescriptionAttribute), text(kAXHelpAttribute)]
                if candidates.contains(where: { labels.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) { return node }
            }
            if depth < 12 {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success,
                   let elements = children as? [AXUIElement] {
                    pending.append(contentsOf: elements.prefix(70).reversed().map { ($0, depth + 1, scoped) })
                }
            }
        }
        return nil
    }
    func openSource() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
            message = "\(source.rawValue) n’est pas installé."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func openAutomationSettings() {
        guard !demo, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func openSafariSettings() {
        guard !demo, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MediaSource.safari.bundleID) else { return }
        message = "Dans Safari, ouvrez Réglages (⌘,) › Développeur."
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, _ in
            // Use Accessibility only if the user previously approved it, as for Podcasts.
            guard let application, AXIsProcessTrusted() else { return }
            DispatchQueue.main.async {
                Self.showSafariDeveloperSettings(pid: application.processIdentifier)
            }
        }
    }

    private static func showSafariDeveloperSettings(pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let menuValue = axValue(application, kAXMenuBarAttribute),
              CFGetTypeID(menuValue) == AXUIElementGetTypeID() else { return }
        let menuBar = unsafeDowncast(menuValue, to: AXUIElement.self)
        guard let safariMenu = axChildren(menuBar).first(where: { axValue($0, kAXTitleAttribute) as? String == "Safari" }),
              let preferences = axChildren(safariMenu).flatMap(axChildren).first(where: {
                  axValue($0, kAXIdentifierAttribute) as? String == "Preferences"
              }),
              AXUIElementPerformAction(preferences, kAXPressAction as CFString) == .success else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let windows = axValue(application, kAXWindowsAttribute) as? [AXUIElement] else { return }
            for window in windows {
                guard let toolbar = axChildren(window).first(where: { axValue($0, kAXRoleAttribute) as? String == kAXToolbarRole }) else { continue }
                if let developer = axChildren(toolbar).first(where: {
                    let title = axValue($0, kAXTitleAttribute) as? String
                    return title == "Développeur" || title == "Developer"
                }) {
                    AXUIElementPerformAction(developer, kAXPressAction as CFString)
                    return
                }
            }
        }
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    func setPresented(_ value: Bool) {
        presented = value
        if value, source == .safari {
            if connected { refresh() }
            else { restoreSafariConnection() }
        }
    }
    func refresh() {
        guard presented, connected, source != .podcasts, !busy, !demo else { return }
        run(command: nil)
    }
    func command(_ command: MediaCommand) {
        if demo {
            guard var value = track else { return }
            switch command { case .toggle: value.playing.toggle(); case .back: value.elapsed = max(0, value.elapsed - 15); case .forward: value.elapsed = min(value.duration, value.elapsed + 15) }
            track = value; return
        }
        guard connected, !busy, let current = track else { return }
        run(command: command, target: current.url)
    }
    private func run(command: MediaCommand?, target: String = "") {
        let selected = source, token = generation
        guard NSRunningApplication.runningApplications(withBundleIdentifier: selected.bundleID).isEmpty == false else {
            track = nil; message = "Ouvrez \(selected.rawValue) avec une vidéo YouTube."; return
        }
        busy = true
        let script = Self.script(source: selected, command: command, target: target)
        queue.async { [weak self] in
            let response = Self.execute(script)
            DispatchQueue.main.async {
                guard let self = self, token == self.generation else { return }
                self.busy = false
                if let error = response.error {
                    self.track = nil
                    let transientCodes = ["(-600)", "(-609)", "(-1712)", "(-1728)"]
                    if transientCodes.contains(where: error.contains) {
                        self.message = "Safari est en cours de chargement."
                        return
                    }
                    self.safariAutomationDenied = error.contains("(-1743)")
                    self.message = self.safariAutomationDenied
                        ? "Dans Automatisation, autorisez NotchX à contrôler Safari."
                        : "Dans Safari › Réglages › Développeur, autorisez JavaScript à partir des évènements Apple."
                    // Stop after failure: never repeat a denied permission request on a timer.
                    self.safariRetryRequired = true
                    self.connected = false; self.timer?.invalidate(); self.timer = nil
                } else if let value = try? JSONDecoder().decode(BrowserTrack.self, from: response.output) {
                    self.track = value; self.message = ""; self.safariAutomationDenied = false
                } else {
                    self.track = nil; self.message = "Aucune vidéo détectée. Lancez YouTube dans \(selected.rawValue)."
                }
            }
        }
    }

    private static func execute(_ script: String) -> (output: Data, error: String?) {
        // NSAppleScript is main-thread-only. A short-lived interpreter lets a browser prompt
        // or busy tab wait without blocking the panel.
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = output
        task.standardError = output
        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (data, task.terminationStatus == 0 ? nil : String(decoding: data, as: UTF8.self))
        } catch {
            return (Data(), error.localizedDescription)
        }
    }

    private static func quote(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    private static func script(source: MediaSource, command: MediaCommand?, target: String) -> String {
        let targetJSON = (try? JSONEncoder().encode(target)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        var action = ""
        if let command = command {
            switch command {
            case .toggle: action = "if(v.paused){v.play().catch(()=>{});}else{v.pause();}"
            case .back: action = "v.currentTime=Math.max(0,v.currentTime-15);"
            case .forward: action = "v.currentTime=Math.min(Number.isFinite(v.duration)?v.duration:v.currentTime+15,v.currentTime+15);"
            }
        }
        let js = """
        (()=>{if(!/(^|\\.)youtube\\.com$/.test(location.hostname))return '';const v=document.querySelector('video');if(!v)return '';if(\(targetJSON)!==''&&location.href!==\(targetJSON))return '';\(action)const m=n=>document.querySelector(n)?.textContent?.trim()||'';return JSON.stringify({title:m('h1.ytd-watch-metadata yt-formatted-string')||document.title.replace(/ - YouTube$/,''),author:m('ytd-channel-name #text'),elapsed:Number.isFinite(v.currentTime)?v.currentTime:0,duration:Number.isFinite(v.duration)?v.duration:0,playing:!v.paused&&!v.ended,url:location.href});})()
        """
        let evaluate = "do JavaScript \(quote(js)) in t"
        // Inspect YouTube tabs only. Prefer a playing tab, then the first paused tab.
        // Control actions are scoped to the exact URL last displayed.
        return """
        with timeout of 4 seconds
            tell application id "\(source.bundleID)"
                set firstResult to ""
                set inspected to 0
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t as text
                        if u starts with "https://www.youtube.com/" or u starts with "https://youtube.com/" or u starts with "https://m.youtube.com/" then
                            set inspected to inspected + 1
                            set payload to \(evaluate)
                            if payload is not "" then
                                if firstResult is "" then set firstResult to payload
                                if payload contains "\\\"playing\\\":true" then return payload
                                \(command != nil ? "return payload" : "")
                            end if
                            if inspected is greater than 20 then return firstResult
                        end if
                    end repeat
                end repeat
                return firstResult
            end tell
        end timeout
        """
    }
}
