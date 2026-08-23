import Foundation

/// A todo as it appears on the Lock Screen. `id` is the composite
/// `cardId:itemId` that completion intents send back.
public struct DashboardTodoItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var isDone: Bool

    public init(id: String, text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }

    public init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String ?? dictionary["text"] as? String else { return nil }
        self.id = id
        self.text = dictionary["text"] as? String ?? ""
        self.isDone = dictionary["isDone"] as? Bool ?? false
    }

    public var dictionary: [String: Any] {
        ["id": id, "text": text, "isDone": isDone]
    }
}

/// A memo as it appears on the Lock Screen.
public struct DashboardMemoItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bodyPreview: String?

    public init(id: String, title: String, bodyPreview: String? = nil) {
        self.id = id
        self.title = title
        self.bodyPreview = bodyPreview
    }

    public init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else { return nil }
        self.id = id
        self.title = dictionary["title"] as? String ?? ""
        self.bodyPreview = dictionary["bodyPreview"] as? String
    }

    public var dictionary: [String: Any] {
        var result: [String: Any] = ["id": id, "title": title]
        if let bodyPreview { result["bodyPreview"] = bodyPreview }
        return result
    }
}

/// One cell of the Live Activity calendar grid.
public struct DashboardCalendarDay: Codable, Hashable, Identifiable, Sendable {
    /// `yyyy-MM-dd`, also the payload the date-selection intent sends back.
    public var id: String
    public var day: Int
    public var weekday: String
    public var isSelected: Bool
    public var isToday: Bool
    public var isCurrentMonth: Bool
    public var hasItems: Bool
    public var todoItems: [DashboardTodoItem]
    public var memoItems: [DashboardMemoItem]

    public init(
        id: String,
        day: Int,
        weekday: String,
        isSelected: Bool,
        isToday: Bool,
        isCurrentMonth: Bool = true,
        hasItems: Bool,
        todoItems: [DashboardTodoItem],
        memoItems: [DashboardMemoItem]
    ) {
        self.id = id
        self.day = day
        self.weekday = weekday
        self.isSelected = isSelected
        self.isToday = isToday
        self.isCurrentMonth = isCurrentMonth
        self.hasItems = hasItems
        self.todoItems = todoItems
        self.memoItems = memoItems
    }

    public init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else { return nil }
        self.id = id
        self.day = (dictionary["day"] as? NSNumber)?.intValue ?? 0
        self.weekday = dictionary["weekday"] as? String ?? ""
        self.isSelected = dictionary["isSelected"] as? Bool ?? false
        self.isToday = dictionary["isToday"] as? Bool ?? false
        self.isCurrentMonth = dictionary["isCurrentMonth"] as? Bool ?? true
        self.hasItems = dictionary["hasItems"] as? Bool ?? false
        self.todoItems = (dictionary["todoItems"] as? [[String: Any]] ?? [])
            .compactMap(DashboardTodoItem.init(dictionary:))
        self.memoItems = (dictionary["memoItems"] as? [[String: Any]] ?? [])
            .compactMap(DashboardMemoItem.init(dictionary:))
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "day": day,
            "weekday": weekday,
            "isSelected": isSelected,
            "isToday": isToday,
            "isCurrentMonth": isCurrentMonth,
            "hasItems": hasItems,
            "todoItems": todoItems.map(\.dictionary),
            "memoItems": memoItems.map(\.dictionary),
        ]
    }
}

/// Everything the Lock Screen needs, in the exact dictionary shape the shipped
/// widget extension already reads from the App Group.
public struct DashboardSnapshot: Hashable, Sendable {
    public var calendarTitle: String?
    public var calendarText: String?
    public var calendarDate: String?
    public var selectedDate: Date?
    public var selectedDateText: String?
    public var monthText: String?
    public var localeCode: String?
    public var calendarDays: [DashboardCalendarDay]
    public var preparedNextDay: DashboardCalendarDay?
    public var memoTitle: String?
    public var memoText: String?
    public var memoId: String?
    public var memoItems: [DashboardMemoItem]
    public var memoCount: Int
    public var todayTitle: String?
    public var todayText: String?
    public var todoItems: [DashboardTodoItem]
    public var doneCount: Int
    public var totalCount: Int
    public var lockScreenLayout: String
    public var imageFileName: String?
    public var showTodosOnLockScreen: Bool
    public var showMemosOnLockScreen: Bool
    public var showCompletedTodosOnLockScreen: Bool
    public var textFontWeight: String
    public var textScale: Double
    public var countdownTitle: String?
    public var countdownText: String?
    public var ddayTitle: String?
    public var ddayTargetDate: Date?
    public var ddayText: String?
    public var ddayMemo: String?
    public var shortcutInsertPriority: String
    public var selectedContentSection: String
    public var privacyMode: String
    public var updatedAt: Date

    public init(
        calendarTitle: String? = nil,
        calendarText: String? = nil,
        calendarDate: String? = nil,
        selectedDate: Date? = nil,
        selectedDateText: String? = nil,
        monthText: String? = nil,
        localeCode: String? = nil,
        calendarDays: [DashboardCalendarDay] = [],
        preparedNextDay: DashboardCalendarDay? = nil,
        memoTitle: String? = nil,
        memoText: String? = nil,
        memoId: String? = nil,
        memoItems: [DashboardMemoItem] = [],
        memoCount: Int = 0,
        todayTitle: String? = nil,
        todayText: String? = nil,
        todoItems: [DashboardTodoItem] = [],
        doneCount: Int = 0,
        totalCount: Int = 0,
        lockScreenLayout: String = LockScreenTemplate.default.rawValue,
        imageFileName: String? = nil,
        showTodosOnLockScreen: Bool = true,
        showMemosOnLockScreen: Bool = true,
        showCompletedTodosOnLockScreen: Bool = true,
        textFontWeight: String = LockScreenSettings.defaultTextFontWeight,
        textScale: Double = LockScreenSettings.defaultTextScale,
        countdownTitle: String? = nil,
        countdownText: String? = nil,
        ddayTitle: String? = nil,
        ddayTargetDate: Date? = nil,
        ddayText: String? = nil,
        ddayMemo: String? = nil,
        shortcutInsertPriority: String = ShortcutInsertPriority.todo.rawValue,
        selectedContentSection: String = ShortcutInsertPriority.todo.rawValue,
        privacyMode: String = PrivacyMode.full.rawValue,
        updatedAt: Date = Date()
    ) {
        self.calendarTitle = calendarTitle
        self.calendarText = calendarText
        self.calendarDate = calendarDate
        self.selectedDate = selectedDate
        self.selectedDateText = selectedDateText
        self.monthText = monthText
        self.localeCode = localeCode
        self.calendarDays = calendarDays
        self.preparedNextDay = preparedNextDay
        self.memoTitle = memoTitle
        self.memoText = memoText
        self.memoId = memoId
        self.memoItems = memoItems
        self.memoCount = memoCount
        self.todayTitle = todayTitle
        self.todayText = todayText
        self.todoItems = todoItems
        self.doneCount = doneCount
        self.totalCount = totalCount
        self.lockScreenLayout = lockScreenLayout
        self.imageFileName = imageFileName
        self.showTodosOnLockScreen = showTodosOnLockScreen
        self.showMemosOnLockScreen = showMemosOnLockScreen
        self.showCompletedTodosOnLockScreen = showCompletedTodosOnLockScreen
        self.textFontWeight = textFontWeight
        self.textScale = textScale
        self.countdownTitle = countdownTitle
        self.countdownText = countdownText
        self.ddayTitle = ddayTitle
        self.ddayTargetDate = ddayTargetDate
        self.ddayText = ddayText
        self.ddayMemo = ddayMemo
        self.shortcutInsertPriority = shortcutInsertPriority
        self.selectedContentSection = selectedContentSection
        self.privacyMode = privacyMode
        self.updatedAt = updatedAt
    }

    public var remainingCount: Int { totalCount - doneCount }
    public var hasTasks: Bool { totalCount > 0 }

    /// The App Group payload. Keys and value types match what the shipped
    /// widget and intents parse today.
    public func dictionary(dashboardId: String = AppGroupKeys.liveActivityDashboardId, isPro: Bool) -> [String: Any] {
        var result: [String: Any] = [
            "dashboardId": dashboardId,
            "isPro": isPro,
            "calendarDays": calendarDays.map(\.dictionary),
            "memoItems": memoItems.map(\.dictionary),
            "memoCount": memoCount,
            "todoItems": todoItems.map(\.dictionary),
            "doneCount": doneCount,
            "totalCount": totalCount,
            "lockScreenLayout": lockScreenLayout,
            "showTodosOnLockScreen": showTodosOnLockScreen,
            "showMemosOnLockScreen": showMemosOnLockScreen,
            "showCompletedTodosOnLockScreen": showCompletedTodosOnLockScreen,
            "textFontWeight": textFontWeight,
            "textScale": textScale,
            "shortcutInsertPriority": shortcutInsertPriority,
            "selectedContentSection": selectedContentSection,
            "privacyMode": privacyMode,
            // Dart wrote seconds since epoch as a double; the widget divides by
            // nothing and feeds it straight into Date(timeIntervalSince1970:).
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
        let optionals: [String: Any?] = [
            "calendarTitle": calendarTitle,
            "calendarText": calendarText,
            "calendarDate": calendarDate,
            "selectedDate": selectedDate.map(FlutterDate.localString),
            "selectedDateText": selectedDateText,
            "monthText": monthText,
            "localeCode": localeCode,
            "preparedNextDay": preparedNextDay?.dictionary,
            "memoTitle": memoTitle,
            "memoText": memoText,
            "memoId": memoId,
            "todayTitle": todayTitle,
            "todayText": todayText,
            "imageFileName": imageFileName,
            "countdownTitle": countdownTitle,
            "countdownText": countdownText,
            "ddayTitle": ddayTitle,
            "ddayTargetDate": ddayTargetDate.map(FlutterDate.localString),
            "ddayText": ddayText,
            "ddayMemo": ddayMemo,
        ]
        for (key, value) in optionals {
            if let value { result[key] = value }
        }
        return result
    }

    public init(dictionary: [String: Any]) {
        calendarTitle = dictionary["calendarTitle"] as? String
        calendarText = dictionary["calendarText"] as? String
        calendarDate = dictionary["calendarDate"] as? String
        selectedDate = FlutterDate.parse(dictionary["selectedDate"] as? String)
        selectedDateText = dictionary["selectedDateText"] as? String
        monthText = dictionary["monthText"] as? String
        localeCode = dictionary["localeCode"] as? String
        calendarDays = (dictionary["calendarDays"] as? [[String: Any]] ?? [])
            .compactMap(DashboardCalendarDay.init(dictionary:))
        preparedNextDay = (dictionary["preparedNextDay"] as? [String: Any])
            .flatMap(DashboardCalendarDay.init(dictionary:))
        memoTitle = dictionary["memoTitle"] as? String
        memoText = dictionary["memoText"] as? String
        memoId = dictionary["memoId"] as? String
        memoItems = (dictionary["memoItems"] as? [[String: Any]] ?? [])
            .compactMap(DashboardMemoItem.init(dictionary:))
        memoCount = (dictionary["memoCount"] as? NSNumber)?.intValue ?? memoItems.count
        todayTitle = dictionary["todayTitle"] as? String
        todayText = dictionary["todayText"] as? String
        todoItems = (dictionary["todoItems"] as? [[String: Any]] ?? [])
            .compactMap(DashboardTodoItem.init(dictionary:))
        doneCount = (dictionary["doneCount"] as? NSNumber)?.intValue ?? 0
        totalCount = (dictionary["totalCount"] as? NSNumber)?.intValue ?? 0
        lockScreenLayout = dictionary["lockScreenLayout"] as? String ?? LockScreenTemplate.default.rawValue
        imageFileName = dictionary["imageFileName"] as? String
        showTodosOnLockScreen = dictionary["showTodosOnLockScreen"] as? Bool ?? true
        showMemosOnLockScreen = dictionary["showMemosOnLockScreen"] as? Bool ?? true
        showCompletedTodosOnLockScreen = dictionary["showCompletedTodosOnLockScreen"] as? Bool ?? true
        textFontWeight = dictionary["textFontWeight"] as? String ?? LockScreenSettings.defaultTextFontWeight
        textScale = (dictionary["textScale"] as? NSNumber)?.doubleValue ?? LockScreenSettings.defaultTextScale
        countdownTitle = dictionary["countdownTitle"] as? String
        countdownText = dictionary["countdownText"] as? String
        ddayTitle = dictionary["ddayTitle"] as? String
        ddayTargetDate = FlutterDate.parse(dictionary["ddayTargetDate"] as? String)
        ddayText = dictionary["ddayText"] as? String
        ddayMemo = dictionary["ddayMemo"] as? String
        shortcutInsertPriority = dictionary["shortcutInsertPriority"] as? String ?? ShortcutInsertPriority.todo.rawValue
        selectedContentSection = dictionary["selectedContentSection"] as? String ?? ShortcutInsertPriority.todo.rawValue
        privacyMode = dictionary["privacyMode"] as? String ?? PrivacyMode.full.rawValue
        if let seconds = (dictionary["updatedAt"] as? NSNumber)?.doubleValue {
            updatedAt = Date(timeIntervalSince1970: seconds)
        } else {
            updatedAt = Date()
        }
    }
}
