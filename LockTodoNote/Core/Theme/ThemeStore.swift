import SwiftUI
import LockTodoNoteShared

/// Appearance mode. Raw values match the migrated `themeMode` preference.
enum AppThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    init(fromStored value: String?) {
        self = AppThemeMode(rawValue: value ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @Published var mode: AppThemeMode {
        didSet { defaults?.set(mode.rawValue, forKey: FlutterPreferenceKeys.themeMode) }
    }

    @Published var colorTheme: AppColorTheme {
        didSet { defaults?.set(colorTheme.rawValue, forKey: FlutterPreferenceKeys.colorTheme) }
    }

    private let defaults: UserDefaults?

    init(store: AppGroupStore = AppGroupStore()) {
        let defaults = store.defaults
        self.defaults = defaults
        self.mode = AppThemeMode(fromStored: defaults?.string(forKey: FlutterPreferenceKeys.themeMode))
        // `.none` is a storage-only value, never a user selection.
        let stored = AppColorTheme(fromStored: defaults?.string(forKey: FlutterPreferenceKeys.colorTheme))
        self.colorTheme = stored == .none ? .default : stored
    }

    func palette(for colorScheme: ColorScheme) -> AppPalette {
        AppPalette.resolved(colorScheme: colorScheme, theme: colorTheme)
    }
}
