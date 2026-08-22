import Foundation

/// Looks up a Lock Screen string in this extension's own catalog.
///
/// The keys are resolved at runtime rather than through `String(localized:)`
/// literals because the views were written against a key-based helper. The
/// catalog (`Localizable.xcstrings`) carries every supported language; a missing key
/// falls back to readable English so an internal key is never shown to users.
func localized(_ key: String) -> String {
    localized(key, defaultValue: widgetEnglishFallbacks[key] ?? "")
}

func localized(_ key: String, defaultValue: String) -> String {
    let defaults = UserDefaults(suiteName: "group.com.namslab.glancecard")
    if let language = defaults?.string(forKey: "app.languageOverride"),
       let resourcePath = Bundle.main.path(forResource: language, ofType: "lproj"),
       let languageBundle = Bundle(path: resourcePath) {
        return languageBundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
}

func widgetLocale() -> Locale {
    let defaults = UserDefaults(suiteName: "group.com.namslab.glancecard")
    if let language = defaults?.string(forKey: "app.languageOverride"), !language.isEmpty {
        return Locale(identifier: language)
    }
    return .current
}

private let widgetEnglishFallbacks: [String: String] = [
    "addImage": "+ Image",
    "addMemo": "+ Memo",
    "addTodo": "+ Todo",
    "allItemsHidden": "Lock Screen items are off",
    "calendar": "Calendar",
    "dDayToday": "D-Day",
    "dday": "D-Day",
    "hiddenContent": "Hidden",
    "memo": "Memo",
    "noEvents": "No events",
    "noMemo": "No memo",
    "noTasks": "No tasks",
    "openApp": "Open",
    "openAppToRefresh": "Open the app to refresh today",
    "refreshRequired": "Open app to refresh",
    "refreshToday": "Refresh today's list",
    "today": "Today",
    "todo": "Todo",
    "whatAreYouWaitingFor": "What are you waiting for?",
]
