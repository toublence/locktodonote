import Foundation
import LockTodoNoteShared
import SwiftUI

/// Resolves every app string from the user's current in-app language instead
/// of Foundation's process-wide language, which is fixed at launch.
func appString(localized key: String, defaultValue: String) -> String {
    let defaults = UserDefaults(suiteName: "group.com.namslab.glancecard")
    guard
        let language = defaults?.string(forKey: AppLanguagePreference.selectionKey),
        let path = Bundle.main.path(forResource: language, ofType: "lproj"),
        let bundle = Bundle(path: path)
    else {
        return Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
    }
    return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
}

func appLocale() -> Locale {
    let defaults = UserDefaults(suiteName: "group.com.namslab.glancecard")
    return Locale(identifier: AppLanguagePreference.resolvedLocaleIdentifier(from: defaults))
}

func appDateString(
    _ date: Date,
    dateStyle: DateFormatter.Style = .medium,
    timeStyle: DateFormatter.Style = .none
) -> String {
    let formatter = DateFormatter()
    formatter.locale = appLocale()
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: date)
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case spanish = "es"
    case hindi = "hi"
    case german = "de"
    case french = "fr"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case arabic = "ar"

    var id: String { rawValue }

    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .system:
            appString(localized: "settings.systemLanguage", defaultValue: "System Default")
        case .english: "English"
        case .korean: "한국어"
        case .japanese: "日本語"
        case .spanish: "Español"
        case .hindi: "हिन्दी"
        case .german: "Deutsch"
        case .french: "Français"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .arabic: "العربية"
        }
    }
}

enum AppLanguagePreference {
    static let selectionKey = "app.languageOverride"

    static func resolvedLocaleIdentifier(from defaults: UserDefaults?) -> String {
        if let value = defaults?.string(forKey: selectionKey),
           let language = AppLanguage(rawValue: value),
           language != .system {
            return language.rawValue
        }
        return Locale.preferredLanguages.first ?? Locale.current.identifier
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    @Published private(set) var selection: AppLanguage

    private let appGroup: AppGroupStore

    init(appGroup: AppGroupStore = AppGroupStore()) {
        self.appGroup = appGroup
        let stored = appGroup.defaults?.string(forKey: AppLanguagePreference.selectionKey)
        self.selection = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        // Earlier builds used AppleLanguages and needed a relaunch. Every app
        // string now reads our App Group preference directly, so remove the
        // legacy process-wide override.
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    var locale: Locale { selection.locale }

    func select(_ language: AppLanguage) {
        guard language != selection else { return }

        if language == .system {
            appGroup.defaults?.removeObject(forKey: AppLanguagePreference.selectionKey)
        } else {
            appGroup.defaults?.set(language.rawValue, forKey: AppLanguagePreference.selectionKey)
        }

        selection = language
        appGroup.reloadWidgetTimelines()
    }
}
