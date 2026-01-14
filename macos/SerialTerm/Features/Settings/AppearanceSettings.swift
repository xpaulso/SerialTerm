import SwiftUI
import AppKit

/// Terminal appearance settings (fonts and colors)
struct AppearanceSettings: Codable, Equatable {
    var fontName: String = "SF Mono"
    var fontSize: CGFloat = 13
    var foregroundColor: CodableColor = CodableColor(.white)
    var backgroundColor: CodableColor = CodableColor(red: 0.1, green: 0.1, blue: 0.12)
    var cursorColor: CodableColor = CodableColor(.green)
    var selectionColor: CodableColor = CodableColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.5)

    // ANSI colors
    var ansiBlack: CodableColor = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
    var ansiRed: CodableColor = CodableColor(red: 0.8, green: 0.2, blue: 0.2)
    var ansiGreen: CodableColor = CodableColor(red: 0.2, green: 0.8, blue: 0.2)
    var ansiYellow: CodableColor = CodableColor(red: 0.8, green: 0.8, blue: 0.2)
    var ansiBlue: CodableColor = CodableColor(red: 0.2, green: 0.4, blue: 0.8)
    var ansiMagenta: CodableColor = CodableColor(red: 0.8, green: 0.2, blue: 0.8)
    var ansiCyan: CodableColor = CodableColor(red: 0.2, green: 0.8, blue: 0.8)
    var ansiWhite: CodableColor = CodableColor(red: 0.8, green: 0.8, blue: 0.8)

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var nsBackgroundColor: NSColor { backgroundColor.nsColor }
    var nsForegroundColor: NSColor { foregroundColor.nsColor }
    var nsCursorColor: NSColor { cursorColor.nsColor }
    var nsSelectionColor: NSColor { selectionColor.nsColor }

    /// Available monospace fonts
    static var availableFonts: [String] {
        let fontManager = NSFontManager.shared
        let monospacedFonts = fontManager.availableFontFamilies.filter { family in
            if let font = NSFont(name: family, size: 12) {
                return font.isFixedPitch
            }
            return false
        }
        return monospacedFonts.sorted()
    }

    /// Preset themes
    static let themes: [String: AppearanceSettings] = [
        "Default Dark": AppearanceSettings(),
        "Light": AppearanceSettings(
            foregroundColor: CodableColor(.black),
            backgroundColor: CodableColor(.white),
            cursorColor: CodableColor(.black),
            selectionColor: CodableColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 0.5)
        ),
        "Solarized Dark": AppearanceSettings(
            foregroundColor: CodableColor(red: 0.51, green: 0.58, blue: 0.59),
            backgroundColor: CodableColor(red: 0.0, green: 0.17, blue: 0.21),
            cursorColor: CodableColor(red: 0.51, green: 0.58, blue: 0.59)
        ),
        "Monokai": AppearanceSettings(
            foregroundColor: CodableColor(red: 0.97, green: 0.97, blue: 0.95),
            backgroundColor: CodableColor(red: 0.15, green: 0.16, blue: 0.13),
            cursorColor: CodableColor(red: 0.97, green: 0.97, blue: 0.95),
            ansiRed: CodableColor(red: 0.98, green: 0.15, blue: 0.45),
            ansiGreen: CodableColor(red: 0.65, green: 0.89, blue: 0.18),
            ansiYellow: CodableColor(red: 0.90, green: 0.86, blue: 0.45),
            ansiBlue: CodableColor(red: 0.40, green: 0.85, blue: 0.94),
            ansiMagenta: CodableColor(red: 0.68, green: 0.51, blue: 1.0)
        ),
        "Dracula": AppearanceSettings(
            foregroundColor: CodableColor(red: 0.97, green: 0.97, blue: 0.95),
            backgroundColor: CodableColor(red: 0.16, green: 0.16, blue: 0.21),
            cursorColor: CodableColor(red: 0.94, green: 0.47, blue: 0.62),
            ansiRed: CodableColor(red: 1.0, green: 0.33, blue: 0.33),
            ansiGreen: CodableColor(red: 0.31, green: 0.98, blue: 0.48),
            ansiYellow: CodableColor(red: 0.95, green: 0.98, blue: 0.48),
            ansiBlue: CodableColor(red: 0.74, green: 0.58, blue: 0.98),
            ansiMagenta: CodableColor(red: 1.0, green: 0.47, blue: 0.66),
            ansiCyan: CodableColor(red: 0.55, green: 0.91, blue: 0.99)
        ),
        "Green Screen": AppearanceSettings(
            foregroundColor: CodableColor(red: 0.2, green: 1.0, blue: 0.2),
            backgroundColor: CodableColor(red: 0.0, green: 0.1, blue: 0.0),
            cursorColor: CodableColor(red: 0.2, green: 1.0, blue: 0.2)
        ),
        "Amber": AppearanceSettings(
            foregroundColor: CodableColor(red: 1.0, green: 0.7, blue: 0.0),
            backgroundColor: CodableColor(red: 0.1, green: 0.05, blue: 0.0),
            cursorColor: CodableColor(red: 1.0, green: 0.7, blue: 0.0)
        )
    ]
}

/// Color that can be encoded/decoded
struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = color.redComponent
        self.green = color.greenComponent
        self.blue = color.blueComponent
        self.alpha = color.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(nsColor)
    }
}

/// Manager for appearance settings persistence
@MainActor
class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    @Published var settings: AppearanceSettings {
        didSet {
            save()
        }
    }

    private let defaultsKey = "AppearanceSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let settings = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            self.settings = settings
        } else {
            self.settings = AppearanceSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func applyTheme(_ name: String) {
        if let theme = AppearanceSettings.themes[name] {
            settings = theme
        }
    }

    func reset() {
        settings = AppearanceSettings()
    }
}
