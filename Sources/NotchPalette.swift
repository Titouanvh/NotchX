import AppKit
import SwiftUI

struct NotchPalette {
    let surface: Color
    let panel: Color
    let accent: Color

    static let classic = NotchPalette(surface: PaletteColor.color("141416"),
                                     panel: PaletteColor.color("202024"),
                                     accent: PaletteColor.color("D8D8DE"))

    var calendarInk: Color {
        guard let background = NSColor(panel).usingColorSpace(.sRGB),
              let tint = NSColor(accent).usingColorSpace(.sRGB) else { return .primary }
        let brightness = background.redComponent * 0.2126
            + background.greenComponent * 0.7152 + background.blueComponent * 0.0722
        let neutral: Double = brightness > 0.55 ? 0.08 : 0.96
        let weight = 0.12
        return Color(.sRGB,
                     red: neutral * (1 - weight) + Double(tint.redComponent) * weight,
                     green: neutral * (1 - weight) + Double(tint.greenComponent) * weight,
                     blue: neutral * (1 - weight) + Double(tint.blueComponent) * weight)
    }

    fileprivate static func resolve(_ preset: String, surface: String, panel: String, accent: String) -> NotchPalette {
        if preset == "custom" {
            return NotchPalette(surface: PaletteColor.color(surface),
                                panel: PaletteColor.color(panel, fallback: "202024"),
                                accent: PaletteColor.color(accent, fallback: "D8D8DE"))
        }
        return PalettePreset.catalog.first { $0.id == preset }?.palette ?? .classic
    }
}

private enum PaletteFamily: String, CaseIterable, Identifiable {
    case essentials = "Classiques"
    case neon = "Néon et rétrofuturiste"
    case pastels = "Pastels"
    case warm = "Tons naturels"

    var id: Self { self }
}

private struct PalettePreset: Identifiable {
    let id: String
    let name: String
    let family: PaletteFamily
    let palette: NotchPalette

    init(_ id: String, _ name: String, _ family: PaletteFamily, _ surface: String, _ panel: String, _ accent: String) {
        self.id = id
        self.name = name
        self.family = family
        palette = NotchPalette(surface: PaletteColor.color(surface),
                               panel: PaletteColor.color(panel),
                               accent: PaletteColor.color(accent))
    }

    static let catalog: [Self] = [
        .init("classic", "Classique", .essentials, "141416", "202024", "D8D8DE"),
        .init("graphite", "Graphite", .essentials, "101114", "25272C", "B9C3D4"),
        .init("ink", "Noir encre", .essentials, "08090B", "17191F", "F2F2F5"),
        .init("ocean", "Océan", .essentials, "111820", "1C2935", "91C9E8"),
        .init("nord", "Nord", .essentials, "242933", "2E3440", "88C0D0"),
        .init("slate", "Ardoise", .essentials, "171E27", "253140", "BACCE0"),
        .init("matrix", "Matrix", .neon, "06100A", "0E2114", "62FF78"),
        .init("cyberpunk", "Cyberpunk", .neon, "140B2A", "27183F", "F8EF63"),
        .init("laser", "Rose laser", .neon, "1B081A", "35112F", "FF72D3"),
        .init("tron", "Cyan électrique", .neon, "061620", "122938", "59EAFC"),
        .init("ultraviolet", "Ultraviolet", .neon, "12091F", "2B1646", "C791FF"),
        .init("synthwave", "Synthwave", .neon, "1B1030", "31204E", "FF986D"),
        .init("lime", "Citron vert", .neon, "121808", "232F0E", "C7FB55"),
        .init("dracula", "Dracula", .neon, "21222C", "282A36", "FF79C6"),
        .init("tokyo", "Tokyo Night", .neon, "1A1B26", "24283B", "9AB8FD"),
        .init("mocha", "Catppuccin Mocha", .pastels, "181825", "1E1E2E", "CBA6F7"),
        .init("macchiato", "Catppuccin Macchiato", .pastels, "1E2030", "24273A", "F5BDE6"),
        .init("frappe", "Catppuccin Frappé", .pastels, "232634", "303446", "A6D189"),
        .init("rose", "Rosé Pine", .pastels, "191724", "1F1D2E", "EBBCBA"),
        .init("lilac", "Lilas", .pastels, "201A2B", "302540", "DEC7FC"),
        .init("mint", "Menthe", .pastels, "122320", "1C342D", "B0E5CE"),
        .init("powder", "Bleu poudré", .pastels, "17202C", "233243", "BAD9FE"),
        .init("peach", "Pêche", .pastels, "261C21", "372932", "FFD1BB"),
        .init("warm", "Chaleureuse", .warm, "171415", "282124", "F2AB85"),
        .init("gruvbox", "Gruvbox", .warm, "1D2021", "282828", "FABD2F"),
        .init("flexoki", "Flexoki", .warm, "100F0F", "1C1B1A", "E5AE59"),
        .init("terracotta", "Terre cuite", .warm, "261612", "3A2520", "F0A088"),
        .init("espresso", "Espresso", .warm, "1A1310", "2A201B", "DFC0A0"),
        .init("forest", "Forêt", .warm, "121B14", "222E23", "BBD398"),
        .init("sage", "Sauge", .warm, "1B211A", "293128", "C5CCAA"),
    ]
}

private struct NotchPaletteKey: EnvironmentKey {
    static let defaultValue = NotchPalette.classic
}

extension EnvironmentValues {
    var notchPalette: NotchPalette {
        get { self[NotchPaletteKey.self] }
        set { self[NotchPaletteKey.self] = newValue }
    }
}

struct NotchPaletteScope<Content: View>: View {
    @AppStorage("notch.palette") private var preset = "classic"
    @AppStorage("notch.palette.surface") private var surface = "141416"
    @AppStorage("notch.palette.panel") private var panel = "202024"
    @AppStorage("notch.palette.accent") private var accent = "D8D8DE"
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let palette = NotchPalette.resolve(preset, surface: surface, panel: panel, accent: accent)
        content
            .environment(\.notchPalette, palette)
            .tint(palette.accent)
    }
}

struct PalettePreferences: View {
    @AppStorage("notch.palette") private var preset = "classic"
    @AppStorage("notch.palette.surface") private var surface = "141416"
    @AppStorage("notch.palette.panel") private var panel = "202024"
    @AppStorage("notch.palette.accent") private var accent = "D8D8DE"

    private var palette: NotchPalette {
        .resolve(preset, surface: surface, panel: panel, accent: accent)
    }

    @Environment(\.notchStaticPreview) private var staticPreview
    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    var body: some View {
        if staticPreview {
            gallery.padding(16)
        } else {
            ScrollView {
                gallery.padding(8)
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(PaletteFamily.allCases) { family in
                VStack(alignment: .leading, spacing: 8) {
                    Text(family.rawValue).font(.headline).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(PalettePreset.catalog.filter { $0.family == family }) { item in
                            tile(item.name, id: item.id, colors: item.palette)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Sur mesure").font(.headline).accessibilityAddTraits(.isHeader)
                tile("Personnalisée", id: "custom",
                     colors: .resolve("custom", surface: surface, panel: panel, accent: accent))
                if preset == "custom" {
                    ColorPicker("Fond", selection: colorBinding($surface, background: true), supportsOpacity: false)
                    ColorPicker("Panneaux", selection: colorBinding($panel, background: true), supportsOpacity: false)
                    ColorPicker("Accent", selection: colorBinding($accent, background: false), supportsOpacity: false)
                    Button("Réinitialiser les couleurs") {
                        surface = "141416"
                        panel = "202024"
                        accent = "D8D8DE"
                    }
                }
            }
        }
    }

    private func tile(_ name: String, id: String, colors: NotchPalette) -> some View {
        let selected = preset == id
        return Button {
            preset = id
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(colors.surface)
                    RoundedRectangle(cornerRadius: 3).fill(colors.panel)
                    RoundedRectangle(cornerRadius: 3).fill(colors.accent)
                }
                .frame(height: 17)
                .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(selected ? 0.55 : 0.14), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func colorBinding(_ storage: Binding<String>, background: Bool) -> Binding<Color> {
        Binding(get: { PaletteColor.color(storage.wrappedValue) }, set: { color in
            storage.wrappedValue = PaletteColor.hex(color, background: background)
        })
    }
}

private enum PaletteColor {
    static func color(_ hex: String, fallback: String = "141416") -> Color {
        let valid = hex.count == 6 && hex.allSatisfy { $0.isHexDigit }
        let value = UInt32(valid ? hex : fallback, radix: 16) ?? 0x141416
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255, opacity: 1)
    }

    static func hex(_ color: Color, background: Bool) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
            return background ? "141416" : "D8D8DE"
        }
        var components = [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
            .map { min(1, max(0, $0)) }
        if background {
            // Keep all background channels below 0.22 so light foreground text stays legible.
            let maximum = components.max() ?? 0
            if maximum > 0.22 { components = components.map { $0 * 0.22 / maximum } }
        } else {
            // A pastel accent remains readable as small text on every allowed dark background.
            let minimum = components.min() ?? 0
            if minimum < 0.65 {
                let mix = (0.65 - minimum) / (1 - minimum)
                components = components.map { $0 + (1 - $0) * mix }
            }
        }
        return components.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}
