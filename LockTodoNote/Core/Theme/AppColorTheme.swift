import SwiftUI

/// The nine accent themes, carried over from the Flutter build with the same
/// ids so a migrated `colorTheme` preference still resolves.
enum AppColorTheme: String, CaseIterable, Identifiable, Sendable {
    case byeokcheong
    case chuhyang
    case jangdan
    case cheonghyeon
    case haenghwang
    case chunyu
    case seolbaek
    case byeokja
    case chwiram
    /// Monochrome fallback; not offered in the picker.
    case none

    static let `default` = AppColorTheme.byeokcheong
    static let selectable: [AppColorTheme] = allCases.filter { $0 != .none }

    var id: String { rawValue }

    init(fromStored value: String?) {
        self = AppColorTheme(rawValue: value ?? "") ?? .default
    }

    var palette: Palette {
        switch self {
        case .byeokcheong:
            Palette(display: 0x5B7CFA, primary: 0x5B7CFA, softLight: 0xEFF3FF, softDark: 0x111936)
        case .chuhyang:
            Palette(display: 0xC19287, primary: 0xA56F64, softLight: 0xFFF1EE, softDark: 0x241815)
        case .jangdan:
            Palette(display: 0xE16350, primary: 0xD64F3B, softLight: 0xFFEFEC, softDark: 0x2A1110)
        case .cheonghyeon:
            Palette(display: 0x566A8E, primary: 0x566A8E, softLight: 0xEFF3FA, softDark: 0x111722)
        case .haenghwang:
            Palette(display: 0xF1A862, primary: 0xB96D22, softLight: 0xFFF3E4, softDark: 0x25180B)
        case .chunyu:
            Palette(display: 0xDCEAA2, primary: 0x6F7F24, softLight: 0xF7FBE7, softDark: 0x181D0B)
        case .seolbaek:
            Palette(display: 0xE2E7E4, primary: 0x5F7370, softLight: 0xF4F7F6, softDark: 0x141918)
        case .byeokja:
            Palette(display: 0x8C9ED9, primary: 0x667BD0, softLight: 0xF0F3FF, softDark: 0x15182A)
        case .chwiram:
            Palette(display: 0x68C7C1, primary: 0x1D8F89, softLight: 0xEAFBFA, softDark: 0x0B211F)
        case .none:
            Palette(display: 0x000000, primary: 0x000000, softLight: 0x000000, softDark: 0x000000)
        }
    }

    struct Palette: Sendable {
        let display: Color
        let primary: Color
        let softLight: Color
        let softDark: Color

        init(display: UInt32, primary: UInt32, softLight: UInt32, softDark: UInt32) {
            self.display = Color(hex: display)
            self.primary = Color(hex: primary)
            self.softLight = Color(hex: softLight)
            self.softDark = Color(hex: softDark)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
