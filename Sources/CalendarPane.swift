import SwiftUI
import EventKit
import AppKit

// Calendar access is deliberately read-only in this app. EventKit requires the
// system's "full access" permission to read events; no save/remove API is used.
private enum CalendarKeys {
    static let hidden = "notchx.calendar.hiddenIdentifiers"
    static let mode = "notchx.calendar.viewMode"
    static let weekStart = "notchx.calendar.weekStartsMonday"
    static func hiddenIDs(_ raw: String) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? [])
    }
    static func encode(_ ids: Set<String>) -> String {
        String(data: (try? JSONEncoder().encode(ids.sorted())) ?? Data(), encoding: .utf8) ?? "[]"
    }
}

private struct CourseCalendar: Identifiable {
    let id: String
    let title: String
}
private struct CourseEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let calendarID: String
    let allDay: Bool
}

@MainActor private final class CourseStore: ObservableObject {
    @Published var authorization = EKEventStore.authorizationStatus(for: .event)
    @Published var calendars: [CourseCalendar] = []
    @Published var events: [CourseEvent] = []
    @Published var error: String?
    @Published var requesting = false
    private lazy var eventStore = EKEventStore()
    let demo: Bool
    init(demo: Bool = false) {
        self.demo = demo
        if demo { seed() }
    }
    var readable: Bool { demo || authorization == .fullAccess }
    var needsSystemSettings: Bool { authorization == .denied || authorization == .restricted }
    func request() {
        guard !demo, !requesting else { return }
        updateAuthorization()
        if readable { return }
        if needsSystemSettings {
            openPrivacySettings()
            return
        }
        error = nil
        requesting = true
        NSApp.activate(ignoringOtherApps: true)
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.requesting = false
                self.updateAuthorization()
                if !granted && !self.needsSystemSettings {
                    self.error = error?.localizedDescription ?? "macOS n’a pas accordé l’accès."
                }
            }
        }
    }
    private func updateAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess && authorization != .fullAccess {
            eventStore.reset()
        }
        authorization = status
        if readable { error = nil }
    }
    func openPrivacySettings() {
        guard !demo, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        if !NSWorkspace.shared.open(url) {
            error = "Ouvrez Réglages Système → Confidentialité et sécurité → Calendriers."
        }
    }
    func refresh(from start: Date, to end: Date) {
        if demo { seed(); return }
        updateAuthorization()
        guard readable else { calendars = []; events = []; return }
        let available = eventStore.calendars(for: .event)
        calendars = available.map { .init(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: available)
        events = eventStore.events(matching: predicate).enumerated().map { index, event in
            CourseEvent(id: "\(event.eventIdentifier ?? "event")-\(event.startDate.timeIntervalSince1970)-\(index)", title: event.title ?? "Sans titre", start: event.startDate, end: event.endDate, location: event.location ?? "", calendarID: event.calendar.calendarIdentifier, allDay: event.isAllDay)
        }.sorted { $0.start < $1.start }
    }
    private func seed() {
        let cal = Calendar(identifier: .gregorian)
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        calendars = [.init(id: "courses", title: "Université · cours"),
                     .init(id: "td", title: "Travaux dirigés"),
                     .init(id: "perso", title: "Personnel")]
        let specs: [(Int, Int, Int, Int, String, String, String)] = [
            (16, 9, 0, 120, "Mécanique des fluides", "Amphi A · Bâtiment sciences", "courses"),
            (16, 14, 0, 90, "Mathématiques · TD", "Salle B204", "td"),
            (17, 10, 0, 120, "Thermodynamique", "Amphi C", "courses"),
            (17, 15, 0, 120, "Projet de groupe", "Bibliothèque", "perso"),
            (18, 8, 30, 120, "Électronique", "Salle C112", "courses"),
            (18, 13, 30, 180, "Physique · TP", "Laboratoire 3", "td"),
            (19, 9, 0, 120, "Analyse numérique", "Amphi A", "courses"),
            (19, 10, 0, 60, "Permanence projet", "Salle B108", "perso"),
            (19, 13, 30, 90, "Résistance des matériaux", "Salle B204", "td"),
            (20, 9, 0, 120, "Anglais scientifique", "Salle D012", "courses"),
            (20, 14, 0, 120, "Conception · atelier", "Atelier 2", "td")]
        events = specs.enumerated().map { i, item in
            let start = date(item.0, item.1, item.2)
            return CourseEvent(id: "demo-\(i)", title: item.4, start: start, end: start.addingTimeInterval(Double(item.3) * 60), location: item.5, calendarID: item.6, allDay: false)
        }
    }
}

struct CalendarPane: View {
    @StateObject private var store: CourseStore
    @State private var date: Date
    @State private var showingCalendars = false
    @State private var lastPresentationDay = Date()
    @Environment(\.notchBoardPresented) private var presented
    @Environment(\.notchStaticPreview) private var staticPreview
    private var showConnectionPreview: Bool {
        staticPreview && CommandLine.arguments.contains("--calendar-disconnected")
    }
    @AppStorage(CalendarKeys.hidden) private var hiddenRaw = "[]"
    @AppStorage(CalendarKeys.mode) private var mode = "week"
    @AppStorage(CalendarKeys.weekStart) private var monday = true
    @Environment(\.notchPalette) private var palette
    private let compact: Bool
    private var accent: Color { palette.accent }
    init(demo: Bool = false, compact: Bool = false) {
        self.compact = compact
        _store = StateObject(wrappedValue: CourseStore(demo: demo))
        _date = State(initialValue: demo ? Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))! : Date())
    }
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = monday ? 2 : 1; return c }
    private var periodLength: Int {
        switch mode {
        case "day": 1
        case "twoDays": 2
        default: 7
        }
    }
    private var days: [Date] {
        let start = periodLength == 7
            ? calendar.dateInterval(of: .weekOfYear, for: date)!.start
            : calendar.startOfDay(for: date)
        return (0..<periodLength).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var rangeEvents: [CourseEvent] {
        visible.filter { $0.start < calendar.date(byAdding: .day, value: 1, to: days.last!)! && $0.end > days.first! }
    }
    private var hidden: Set<String> { CalendarKeys.hiddenIDs(hiddenRaw) }
    private var visible: [CourseEvent] { store.events.filter { !hidden.contains($0.calendarID) } }
    private var hourHeight: CGFloat {
        switch periodLength {
        case 1: 52
        case 2: compact ? 22 : 25
        default: compact ? 17 : 20
        }
    }
    private var hours: Range<Int> { store.demo ? 8..<19 : 0..<24 }
    private var initialHour: Int {
        guard !store.demo else { return 8 }
        let earliest = rangeEvents.filter { !$0.allDay }.map { calendar.component(.hour, from: $0.start) }.min()
        return min(8, earliest ?? 8)
    }
    private func refresh() { store.refresh(from: days.first!, to: calendar.date(byAdding: .day, value: 1, to: days.last!)!) }
    var body: some View {
        VStack(spacing: 0) {
            if store.readable && !showConnectionPreview {
                header.padding(.horizontal, compact ? 13 : 20).padding(.vertical, compact ? 8 : 11)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                calendarBody.overlay(alignment: .topTrailing) {
                    if rangeEvents.isEmpty {
                        Text(store.calendars.isEmpty ? "Aucun calendrier disponible" : "Aucun événement sur cette période")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule()).padding(.top, 62).padding(.trailing, 12)
                    }
                }
            } else {
                CalendarAccessControls(store: store, firstRunPreview: showConnectionPreview)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if store.readable && !showConnectionPreview {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    footer(now: store.demo ? referenceNow : context.date)
                }
                .padding(.horizontal, compact ? 13 : 20).padding(.vertical, compact ? 7 : 9)
            }
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 19))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .onAppear { if presented { refresh() } }
        .onChange(of: date) { _, _ in refresh() }
        .onChange(of: mode) { _, _ in refresh() }
        .onChange(of: monday) { _, _ in refresh() }
        .onChange(of: presented) { _, active in
            guard active, !store.demo else { return }
            let now = Date()
            if !calendar.isDate(now, inSameDayAs: lastPresentationDay),
               calendar.isDate(date, inSameDayAs: lastPresentationDay) {
                date = now
            }
            lastPresentationDay = now
            refresh()
        }
        .onChange(of: store.authorization) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))).capitalized).font(.system(size: compact ? 19 : 23, weight: .medium, design: .rounded))
                }
                Spacer()
                HStack(spacing: 2) {
                    viewButton("Jour", value: "day")
                    viewButton("2 jours", value: "twoDays")
                    viewButton("Semaine", value: "week")
                }
                .padding(3)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
            HStack(spacing: 10) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Période précédente")
                Button("Aujourd’hui") { date = store.demo ? Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))! : Date() }
                Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Période suivante")
                Text(periodTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { showingCalendars.toggle() } label: { Label("Calendriers", systemImage: "line.3.horizontal.decrease") }
                    .popover(isPresented: $showingCalendars) { CalendarSelection(store: store, hiddenRaw: $hiddenRaw).padding(18).frame(width: 280) }
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
        }
    }
    private func viewButton(_ label: String, value: String) -> some View {
        Button {
            mode = value
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mode == value ? accent : Color.white.opacity(0.62))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 5).padding(.horizontal, compact ? 7 : 11)
                .background(mode == value ? accent.opacity(0.19) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isSelected] : [])
    }
    private var periodTitle: String {
        let french = Locale(identifier: "fr_FR")
        if periodLength == 1 {
            return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(french))
        }
        guard let first = days.first, let last = days.last else { return "" }
        let shortDate = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(french)
        let start = calendar.isDate(first, equalTo: last, toGranularity: .month)
            ? first.formatted(.dateTime.day().locale(french)) : first.formatted(shortDate)
        return "\(start) – \(last.formatted(shortDate))"
    }
    private func move(_ direction: Int) { date = calendar.date(byAdding: .day, value: direction * periodLength, to: date)! }
    private var calendarBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(date.formatted(.dateTime.timeZone(.iso8601(.short))))
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).frame(width: 36)
                ForEach(days, id: \.self) { day in
                    let isToday = calendar.isDate(day, inSameDayAs: referenceNow)
                    Button {
                        date = day
                        if periodLength == 7 { mode = "day" }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR"))).capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: compact ? 15 : 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isToday ? Color.black : Color.white.opacity(0.9))
                                .frame(width: 28, height: 22)
                                .background(isToday ? accent : Color.clear, in: Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "fr_FR"))))
                    .accessibilityAddTraits(calendar.isDate(day, inSameDayAs: date) ? [.isSelected] : [])
                }
            }
            if visible.contains(where: { $0.allDay && $0.start < calendar.date(byAdding: .day, value: 1, to: days.last!)! && $0.end > days.first! }) {
                HStack(alignment: .top, spacing: 0) {
                    Text("Journée").font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 36)
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 3) { ForEach(events(on: day).filter(\.allDay)) { event in
                            Text(event.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(palette.calendarInk)
                                .lineLimit(2)
                                .padding(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.calendarInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                                .help(event.title)
                        }}.frame(maxWidth: .infinity).padding(.horizontal, 3)
                    }
                }.padding(.bottom, 8)
            }
            if staticPreview {
                GeometryReader { geometry in
                    timelineGrid
                        .frame(height: geometry.size.height, alignment: .top)
                        .clipped()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) { timelineGrid }
                        .onAppear { proxy.scrollTo(initialHour, anchor: .top) }
                        .onChange(of: date) { _, _ in proxy.scrollTo(initialHour, anchor: .top) }
                        .onChange(of: mode) { _, _ in proxy.scrollTo(initialHour, anchor: .top) }
                }
            }
        }
    }
    private var timelineGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, height: hourHeight, alignment: .top)
                        .id(hour)
                }
            }
            ForEach(days, id: \.self) { day in
                DayTimeline(day: day, events: events(on: day).filter { !$0.allDay },
                            calendar: calendar, hours: hours, hourHeight: hourHeight, ink: palette.calendarInk)
            }
        }
        .padding(.top, 4)
    }
    private func events(on day: Date) -> [CourseEvent] {
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        return visible.filter { $0.start < end && $0.end > day }
    }
    private var referenceNow: Date {
        store.demo ? Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 15))! : Date()
    }
    private func nextEvent(now: Date) -> CourseEvent? {
        visible.filter { !$0.allDay && $0.end > now && calendar.isDate($0.start, inSameDayAs: now) }.min { $0.start < $1.start }
    }
    private func footer(now: Date) -> some View {
        HStack(spacing: 7) {
            Circle().fill(store.readable ? Color.green.opacity(0.8) : accent).frame(width: 5, height: 5)
            if !store.demo { Text(store.readable ? "Lecture seule" : "Calendriers non connectés") }
            if store.readable, let upcoming = nextEvent(now: now) {
                if !store.demo { Text("·").foregroundStyle(.tertiary) }
                Text("\(upcoming.start <= now ? "En cours" : "À " + upcoming.start.formatted(date: .omitted, time: .shortened)) · \(upcoming.title)").lineLimit(1).help(upcoming.title)
            }
            Spacer()
            if store.readable { Text("\(rangeEvents.count) événements") }
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

private struct DayTimeline: View {
    let day: Date
    let events: [CourseEvent]
    let calendar: Calendar
    let hours: Range<Int>
    let hourHeight: CGFloat
    let ink: Color
    @State private var selected: String?
    private struct Placement: Identifiable {
        let event: CourseEvent
        let lane: Int
        var lanes: Int
        let start: Double
        let end: Double
        var id: String { event.id }
    }
    private var placements: [Placement] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        let sorted = events.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
        var result: [Placement] = []
        var group: [Int] = []
        var laneEnds: [Double] = []
        var clusterEnd = -1.0
        func finish() { for index in group { result[index].lanes = max(1, laneEnds.count) }; group = []; laneEnds = [] }
        for event in sorted {
            func minute(_ date: Date) -> Double {
                if date <= day { return 0 }; if date >= dayEnd { return 1440 }
                let components = calendar.dateComponents([.hour, .minute], from: date)
                return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
            let start = minute(event.start), end = max(start + 1, minute(event.end))
            // Include the visual minimum height in overlap grouping so short
            // events do not paint over the next course.
            let visualEnd = max(end, start + 18 / hourHeight * 60)
            if start >= clusterEnd { finish(); clusterEnd = -1 }
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(visualEnd) } else { laneEnds[lane] = visualEnd }
            group.append(result.count)
            result.append(.init(event: event, lane: lane, lanes: 1, start: start, end: end))
            clusterEnd = max(clusterEnd, visualEnd)
        }
        finish()
        return result
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.045)).frame(width: 1)
                ForEach(hours, id: \.self) { hour in
                    Rectangle().fill(.white.opacity(0.075)).frame(height: 1)
                        .offset(y: CGFloat(hour - hours.lowerBound) * hourHeight)
                }
                ForEach(placements) { item in
                    let width = max(1, (geometry.size.width - 6) / Double(item.lanes))
                    let height = max(16, (item.end - item.start) / 60 * hourHeight - 2)
                    Button {
                        selected = item.id
                    } label: {
                        eventCard(item.event, compact: width < 110, height: height)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(1, width - 3), height: height, alignment: .topLeading)
                    .clipped()
                    .offset(x: 4 + Double(item.lane) * width, y: (item.start / 60 - Double(hours.lowerBound)) * hourHeight)
                    .popover(isPresented: Binding(get: { selected == item.id }, set: { if !$0 { selected = nil } })) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.event.title).font(.headline)
                            Text(rangeLabel(item.event)).foregroundStyle(.secondary)
                            if !item.event.location.isEmpty { Label(item.event.location, systemImage: "location") }
                        }
                        .padding(16).frame(minWidth: 160, maxWidth: 330, alignment: .leading)
                    }
                }
            }
        }.frame(maxWidth: .infinity).frame(height: CGFloat(hours.count) * hourHeight)
    }
    private func rangeLabel(_ event: CourseEvent) -> String {
        "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
    }
    private func eventCard(_ event: CourseEvent, compact: Bool, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: compact ? 9 : 12, weight: .semibold))
                    .lineLimit(height >= 29 ? 2 : 1).foregroundStyle(ink)
                if height >= 36 {
                    Text(compact ? event.start.formatted(date: .omitted, time: .shortened) : rangeLabel(event))
                        .font(.system(size: compact ? 8 : 10, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.74)).lineLimit(1)
                }
                if height >= 54, !event.location.isEmpty {
                    Text(event.location).font(.system(size: compact ? 8 : 11)).foregroundStyle(ink.opacity(0.68)).lineLimit(1)
                }
            }.padding(.vertical, 3).padding(.horizontal, 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(ink.opacity(0.14), lineWidth: 1))
        .help("\(event.title)\n\(event.start.formatted(date: .abbreviated, time: .shortened)) – \(event.end.formatted(date: .abbreviated, time: .shortened))\n\(event.location)")
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarSelection: View {
    @ObservedObject var store: CourseStore
    @Binding var hiddenRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Calendriers visibles").font(.headline)
            if store.calendars.isEmpty { Text("Connectez vos calendriers pour choisir ceux à afficher.").font(.caption).foregroundStyle(.secondary) }
            ForEach(store.calendars) { item in
                Toggle(isOn: Binding(get: { !CalendarKeys.hiddenIDs(hiddenRaw).contains(item.id) }, set: { enabled in
                    var hidden = CalendarKeys.hiddenIDs(hiddenRaw)
                    if enabled { hidden.remove(item.id) } else { hidden.insert(item.id) }
                    hiddenRaw = CalendarKeys.encode(hidden)
                })) { Text(item.title).font(.system(size: 12)) }.toggleStyle(.checkbox)
            }
        }
    }
}

private struct CalendarAccessControls: View {
    @ObservedObject var store: CourseStore
    var firstRunPreview = false

    private var needsSettings: Bool { !firstRunPreview && store.needsSystemSettings }

    var body: some View {
        VStack(spacing: 7) {
            Text(needsSettings ? "Accès à Calendrier indisponible" : "Afficher mon emploi du temps")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Button(store.requesting ? "Demande en cours…" : needsSettings ? "Ouvrir Confidentialité" : "Connecter mes calendriers") {
                if needsSettings { store.openPrivacySettings() }
                else { store.request() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(store.requesting)
            Text(needsSettings
                 ? "Dans Calendriers, autorisez l’accès complet pour NotchX."
                 : "Choisissez l’accès complet pour afficher vos cours.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(error)
                if !needsSettings {
                    Button("Ouvrir Confidentialité") { store.openPrivacySettings() }
                        .buttonStyle(.link)
                }
            }
        }
        .multilineTextAlignment(.center)
    }
}

struct CalendarPreferences: View {
    @StateObject private var store = CourseStore()
    @AppStorage(CalendarKeys.hidden) private var hiddenRaw = "[]"
    @AppStorage(CalendarKeys.weekStart) private var monday = true
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Commencer la semaine le lundi", isOn: $monday)
            if store.readable {
                CalendarSelection(store: store, hiddenRaw: $hiddenRaw)
            } else {
                CalendarAccessControls(store: store)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.authorization) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refresh() }
    }
    private func refresh() {
        let start = Calendar.current.startOfDay(for: Date())
        store.refresh(from: start, to: start.addingTimeInterval(86400))
    }
}
