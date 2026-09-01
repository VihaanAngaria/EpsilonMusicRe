import SwiftUI
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Accent colors matching the Android app's ThemeScreen palette.
struct AccentOption: Identifiable {
    let name: String
    let color: Color
    let hex: String
    var id: String { hex }
}

/// App-level preferences, persisted to UserDefaults — mirrors the Android
/// app's DataStore preference keys that make sense on iOS.
/// (Plain @Published + didSet persistence so every change publishes to
/// subscribed views, unlike @AppStorage inside an ObservableObject.)
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: Appearance
    @Published var themeModeRaw: String {
        didSet { UserDefaults.standard.set(themeModeRaw, forKey: "themeMode") }
    }
    @Published var pureBlack: Bool {
        didSet { UserDefaults.standard.set(pureBlack, forKey: "pureBlack") }
    }
    @Published var dynamicTheme: Bool {
        didSet { UserDefaults.standard.set(dynamicTheme, forKey: "dynamicTheme") }
    }
    @Published var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "accentHex") }
    }

    // MARK: Player behavior (mirrors Android PlayerSettings)
    @Published var autoplayRelated: Bool {
        didSet { UserDefaults.standard.set(autoplayRelated, forKey: "autoplayRelated") }
    }
    @Published var skipOnStreamError: Bool {
        didSet { UserDefaults.standard.set(skipOnStreamError, forKey: "skipOnStreamError") }
    }
    @Published var defaultSearchFilterRaw: String {
        didSet { UserDefaults.standard.set(defaultSearchFilterRaw, forKey: "defaultSearchFilter") }
    }

    private init() {
        let defaults = UserDefaults.standard
        themeModeRaw = defaults.string(forKey: "themeMode") ?? ThemeMode.dark.rawValue
        pureBlack = defaults.object(forKey: "pureBlack") as? Bool ?? true
        dynamicTheme = defaults.object(forKey: "dynamicTheme") as? Bool ?? true
        accentHex = defaults.string(forKey: "accentHex") ?? "#ED5564"
        autoplayRelated = defaults.object(forKey: "autoplayRelated") as? Bool ?? true
        skipOnStreamError = defaults.object(forKey: "skipOnStreamError") as? Bool ?? true
        defaultSearchFilterRaw = defaults.string(forKey: "defaultSearchFilter") ?? SearchFilter.songs.rawValue
    }

    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .dark }
        set { themeModeRaw = newValue.rawValue }
    }

    var defaultSearchFilter: SearchFilter {
        get { SearchFilter(rawValue: defaultSearchFilterRaw) ?? .songs }
        set { defaultSearchFilterRaw = newValue.rawValue }
    }

    var accentColor: Color {
        Color.fromHexSafe(accentHex) ?? .epsAccent
    }

    /// All accent options — Epsilon red first, then a Material-style palette
    /// matching the Android color picker grid.
    static let accentOptions: [AccentOption] = [
        AccentOption(name: "Epsilon", color: Color(red: 237/255, green: 85/255, blue: 100/255), hex: "#ED5564"),
        AccentOption(name: "Crimson", color: Color(red: 220/255, green: 38/255, blue: 38/255), hex: "#DC2626"),
        AccentOption(name: "Sunset", color: Color(red: 249/255, green: 115/255, blue: 22/255), hex: "#F97316"),
        AccentOption(name: "Amber", color: Color(red: 245/255, green: 158/255, blue: 11/255), hex: "#F59E0B"),
        AccentOption(name: "Lime", color: Color(red: 132/255, green: 204/255, blue: 22/255), hex: "#84CC16"),
        AccentOption(name: "Emerald", color: Color(red: 16/255, green: 185/255, blue: 129/255), hex: "#10B981"),
        AccentOption(name: "Teal", color: Color(red: 20/255, green: 184/255, blue: 166/255), hex: "#14B8A6"),
        AccentOption(name: "Sky", color: Color(red: 14/255, green: 165/255, blue: 233/255), hex: "#0EA5E9"),
        AccentOption(name: "Indigo", color: Color(red: 99/255, green: 102/255, blue: 241/255), hex: "#6366F1"),
        AccentOption(name: "Violet", color: Color(red: 139/255, green: 92/255, blue: 246/255), hex: "#8B5CF6"),
        AccentOption(name: "Fuchsia", color: Color(red: 217/255, green: 70/255, blue: 239/255), hex: "#D946EF"),
        AccentOption(name: "Rose", color: Color(red: 251/255, green: 113/255, blue: 133/255), hex: "#FB7185"),
    ]
}

// MARK: - Theme colors (dark/light, pure black) — replicates the MaterialKolor TonalSpot scheme

extension Color {
    static let epsAccent = Color(red: 237.0 / 255.0, green: 85.0 / 255.0, blue: 100.0 / 255.0)

    static func fromHexSafe(_ hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255.0,
                     green: Double((rgb >> 8) & 0xFF) / 255.0,
                     blue: Double(rgb & 0xFF) / 255.0)
    }
}

/// Concrete palette resolved from settings + optional dynamic artwork color.
/// Mirrors the Android app's surface container levels.
struct EpsPalette {
    let accent: Color
    let background: Color
    let surface: Color
    let surfaceHigh: Color
    let surfaceHighest: Color
    let textPrimary: Color
    let textSecondary: Color

    static func resolve(isDark: Bool, pureBlack: Bool, accent: Color) -> EpsPalette {
        if isDark {
            if pureBlack {
                return EpsPalette(
                    accent: accent,
                    background: .black,
                    surface: Color(white: 0.09),
                    surfaceHigh: Color(white: 0.14),
                    surfaceHighest: Color(white: 0.19),
                    textPrimary: .white,
                    textSecondary: Color(white: 0.64))
            }
            return EpsPalette(
                accent: accent,
                background: Color(red: 0.055, green: 0.055, blue: 0.07),
                surface: Color(red: 0.12, green: 0.12, blue: 0.145),
                surfaceHigh: Color(red: 0.17, green: 0.17, blue: 0.20),
                surfaceHighest: Color(red: 0.23, green: 0.23, blue: 0.26),
                textPrimary: .white,
                textSecondary: Color(white: 0.64))
        }
        return EpsPalette(
            accent: accent,
            background: Color(red: 0.965, green: 0.965, blue: 0.98),
            surface: .white,
            surfaceHigh: Color(red: 0.93, green: 0.93, blue: 0.95),
            surfaceHighest: Color(red: 0.88, green: 0.88, blue: 0.91),
            textPrimary: Color(red: 0.09, green: 0.09, blue: 0.11),
            textSecondary: Color(white: 0.42))
    }
}

extension Color {
    init?(hexString hex: String) {
        self = Color.fromHexSafe(hex) ?? .epsAccent
    }
}

// MARK: - Dynamic color extraction from artwork (MaterialKolor equivalent)

enum ArtworkColorExtractor {

    /// Average + saturation-boosted dominant color, like Palette + TonalSpot's seed.
    static func dominantColor(from image: UIImage) -> Color? {
        guard let color = dominantUIColor(from: image) else { return nil }
        return Color(color)
    }

    static func dominantUIColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0

        // Convert to HSB, clamp brightness into a mid range so it stays readable as accent.
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1)
        uiColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let clampedSat = max(sat, 0.45)
        let clampedBri = min(max(bri, 0.55), 0.78)
        return UIColor(hue: hue, saturation: clampedSat, brightness: clampedBri, alpha: 1)
    }
}
