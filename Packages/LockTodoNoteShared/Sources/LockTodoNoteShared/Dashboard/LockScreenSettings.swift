import Foundation

/// How the Lock Screen card is composed: which template, what it may show, and
/// the D-Day and image slots that feed it.
///
/// The Flutter build kept these in standard UserDefaults, out of reach of the
/// extensions, which is why the intent had to re-read a flattened copy from the
/// dashboard payload. They now live in the App Group so intents read the real
/// settings directly.
public struct LockScreenSettings: Hashable, Sendable {
    public static let defaultTextFontWeight = "regular"
    public static let defaultTextScale = 1.0
    public static let minTextScale = 0.85
    public static let maxTextScale = 1.25

    public var showTodos: Bool
    public var showMemos: Bool
    public var showCompletedTodos: Bool
    public var template: LockScreenTemplate
    /// Legacy single-slot image, kept as the fallback for both image templates.
    public var imageFileName: String?
    public var imageMemoFileName: String?
    public var imageTodoFileName: String?
    public var ddayTitle: String?
    public var ddayTargetDate: Date?
    public var ddayMemo: String?
    public var textFontWeight: String
    public var textScale: Double
    public var shortcutInsertPriority: ShortcutInsertPriority
    public var selectedContentSection: ShortcutInsertPriority
    public var syncCalendarSelectionToLockScreen: Bool

    public init(
        showTodos: Bool = true,
        showMemos: Bool = true,
        showCompletedTodos: Bool = false,
        template: LockScreenTemplate = .default,
        imageFileName: String? = nil,
        imageMemoFileName: String? = nil,
        imageTodoFileName: String? = nil,
        ddayTitle: String? = nil,
        ddayTargetDate: Date? = nil,
        ddayMemo: String? = nil,
        textFontWeight: String = LockScreenSettings.defaultTextFontWeight,
        textScale: Double = LockScreenSettings.defaultTextScale,
        shortcutInsertPriority: ShortcutInsertPriority = .todo,
        selectedContentSection: ShortcutInsertPriority = .todo,
        syncCalendarSelectionToLockScreen: Bool = true
    ) {
        self.showTodos = showTodos
        self.showMemos = showMemos
        self.showCompletedTodos = showCompletedTodos
        self.template = template
        self.imageFileName = imageFileName
        self.imageMemoFileName = imageMemoFileName
        self.imageTodoFileName = imageTodoFileName
        self.ddayTitle = ddayTitle
        self.ddayTargetDate = ddayTargetDate
        self.ddayMemo = ddayMemo
        self.textFontWeight = textFontWeight
        self.textScale = Self.clampTextScale(textScale)
        self.shortcutInsertPriority = shortcutInsertPriority
        self.selectedContentSection = selectedContentSection
        self.syncCalendarSelectionToLockScreen = syncCalendarSelectionToLockScreen
    }

    public static func clampTextScale(_ value: Double) -> Double {
        min(max(value, minTextScale), maxTextScale)
    }

    /// Where a Shortcuts capture lands.
    ///
    /// Memo-only and todo-only templates decide for themselves. Mixed layouts
    /// follow the Todo/Memo input tab the user most recently selected.
    public func resolveShortcutTarget() -> ShortcutInsertPriority {
        switch template {
        case .dateMemo, .imageMemo, .ddayMemo: .memo
        case .dateTodo, .imageTodo: .todo
        case .calendarItems, .memoTodo: selectedContentSection
        }
    }

    /// The image slot the active template draws from.
    public var activeImageFileName: String? {
        switch template {
        case .imageMemo: imageMemoFileName ?? imageFileName
        case .imageTodo: imageTodoFileName ?? imageFileName
        default: imageFileName
        }
    }

    // MARK: - Persistence

    public static func load(from defaults: UserDefaults) -> LockScreenSettings {
        let legacyImage = defaults.string(forKey: FlutterPreferenceKeys.imageFileName)
        return LockScreenSettings(
            showTodos: defaults.object(forKey: FlutterPreferenceKeys.showTodos) as? Bool ?? true,
            showMemos: defaults.object(forKey: FlutterPreferenceKeys.showMemos) as? Bool ?? true,
            showCompletedTodos: defaults.object(forKey: FlutterPreferenceKeys.showCompletedTodos) as? Bool ?? false,
            template: LockScreenTemplate(fromStored: defaults.string(forKey: FlutterPreferenceKeys.layout)),
            imageFileName: legacyImage,
            imageMemoFileName: defaults.string(forKey: FlutterPreferenceKeys.imageMemoFileName) ?? legacyImage,
            imageTodoFileName: defaults.string(forKey: FlutterPreferenceKeys.imageTodoFileName) ?? legacyImage,
            ddayTitle: defaults.string(forKey: FlutterPreferenceKeys.ddayTitle),
            ddayTargetDate: FlutterDate.parse(defaults.string(forKey: FlutterPreferenceKeys.ddayTargetDate)),
            ddayMemo: defaults.string(forKey: FlutterPreferenceKeys.ddayMemo),
            textFontWeight: defaults.string(forKey: FlutterPreferenceKeys.textFontWeight) ?? defaultTextFontWeight,
            textScale: defaults.object(forKey: FlutterPreferenceKeys.textScale) as? Double ?? defaultTextScale,
            shortcutInsertPriority: ShortcutInsertPriority(
                fromStored: defaults.string(forKey: FlutterPreferenceKeys.shortcutInsertPriority)
            ),
            selectedContentSection: ShortcutInsertPriority(
                fromStored: defaults.string(forKey: FlutterPreferenceKeys.selectedContentSection)
            ),
            syncCalendarSelectionToLockScreen: defaults.object(
                forKey: FlutterPreferenceKeys.syncCalendarSelectionToLockScreen
            ) as? Bool ?? true
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(showTodos, forKey: FlutterPreferenceKeys.showTodos)
        defaults.set(showMemos, forKey: FlutterPreferenceKeys.showMemos)
        defaults.set(showCompletedTodos, forKey: FlutterPreferenceKeys.showCompletedTodos)
        defaults.set(template.rawValue, forKey: FlutterPreferenceKeys.layout)
        defaults.setOrRemove(imageFileName, forKey: FlutterPreferenceKeys.imageFileName)
        defaults.setOrRemove(imageMemoFileName, forKey: FlutterPreferenceKeys.imageMemoFileName)
        defaults.setOrRemove(imageTodoFileName, forKey: FlutterPreferenceKeys.imageTodoFileName)
        defaults.setOrRemove(ddayTitle, forKey: FlutterPreferenceKeys.ddayTitle)
        defaults.setOrRemove(ddayMemo, forKey: FlutterPreferenceKeys.ddayMemo)
        defaults.setOrRemove(
            ddayTargetDate.map(FlutterDate.localString),
            forKey: FlutterPreferenceKeys.ddayTargetDate
        )
        defaults.set(textFontWeight, forKey: FlutterPreferenceKeys.textFontWeight)
        defaults.set(Self.clampTextScale(textScale), forKey: FlutterPreferenceKeys.textScale)
        defaults.set(shortcutInsertPriority.rawValue, forKey: FlutterPreferenceKeys.shortcutInsertPriority)
        defaults.set(selectedContentSection.rawValue, forKey: FlutterPreferenceKeys.selectedContentSection)
        defaults.set(
            syncCalendarSelectionToLockScreen,
            forKey: FlutterPreferenceKeys.syncCalendarSelectionToLockScreen
        )
    }
}

extension UserDefaults {
    /// Stores a trimmed string, or removes the key when there is nothing to keep.
    public func setOrRemove(_ value: String?, forKey key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            set(trimmed, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
