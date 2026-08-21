import SwiftUI

/// Semantic colours for the app chrome. Two bases — light and the pure-black
/// dark theme the Flutter build used — recoloured by the selected accent.
struct AppPalette: Sendable {
    var background: Color
    var surface: Color
    var surfaceElevated: Color
    var surfaceSoft: Color
    var premiumSurface: Color
    var premiumBorder: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var border: Color
    var strongBorder: Color
    var primary: Color
    var onPrimary: Color
    var accent: Color
    var accentSoft: Color
    var success: Color
    var warning: Color
    var danger: Color

    static let light = AppPalette(
        background: Color(hex: 0xF7F8FC),
        surface: .white,
        surfaceElevated: .white,
        surfaceSoft: Color(hex: 0xF1F4FF),
        premiumSurface: Color(hex: 0xF2F5FF),
        premiumBorder: Color(hex: 0xDDE5FF),
        textPrimary: Color(hex: 0x172033),
        textSecondary: Color(hex: 0x667085),
        textTertiary: Color(hex: 0x8A94A6),
        border: Color(hex: 0xE8ECF4),
        strongBorder: Color(hex: 0xD8DEEA),
        primary: Color(hex: 0x5B7CFA),
        onPrimary: .white,
        accent: Color(hex: 0x5B7CFA),
        accentSoft: Color(hex: 0x5B7CFA, opacity: 0.1),
        success: Color(hex: 0x18C37E),
        warning: Color(hex: 0xFF5A5F),
        danger: Color(hex: 0xFF5A5F)
    )

    /// True black, not a dark grey — it lets the OLED Lock Screen aesthetic
    /// carry into the app, which is what the Flutter build shipped.
    static let pureBlack = AppPalette(
        background: .black,
        surface: .black,
        surfaceElevated: Color(hex: 0x0A0A0A),
        surfaceSoft: Color(hex: 0x111111),
        premiumSurface: Color(hex: 0x08080D),
        premiumBorder: Color(hex: 0x242138),
        textPrimary: .white,
        textSecondary: Color(hex: 0xD1D5DB),
        textTertiary: Color(hex: 0x8A8A8A),
        border: Color(hex: 0x2A2A2A),
        strongBorder: Color(hex: 0x333333),
        primary: Color(hex: 0x3C7DB7),
        onPrimary: .white,
        accent: Color(hex: 0x3C7DB7),
        accentSoft: Color(hex: 0x3C7DB7, opacity: 0.18),
        success: Color(hex: 0x10B981),
        warning: Color(hex: 0xFF5C7A),
        danger: Color(hex: 0xEF4444)
    )

    static func resolved(colorScheme: ColorScheme, theme: AppColorTheme) -> AppPalette {
        var base = colorScheme == .dark ? pureBlack : light
        guard theme != .none else { return base }
        let palette = theme.palette
        base.primary = palette.primary
        base.accent = palette.primary
        base.accentSoft = colorScheme == .dark ? palette.softDark : palette.softLight
        if colorScheme == .light {
            base.premiumSurface = palette.softLight
            base.premiumBorder = palette.display.opacity(0.5)
        }
        return base
    }
}

private struct AppPaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette.light
}

extension EnvironmentValues {
    var palette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}
