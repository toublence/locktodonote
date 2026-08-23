#if os(iOS)
import ActivityKit
#endif
import Foundation

/// The Live Activity payload.
///
/// The type name is deliberately unchanged from the Flutter build. ActivityKit
/// keys running activities by their attributes type, so renaming this would
/// leave any activity started before the update unreachable — the app could
/// neither refresh nor end it, stranding a stale card on the Lock Screen.
///
/// `ContentState` lives outside the attributes as `DashboardActivityState` so
/// the payload logic can be unit-tested on a platform without ActivityKit; the
/// nested name is preserved through a typealias, and the encoded form is
/// identical either way.
#if os(iOS)
public struct GlanceDashboardAttributes: ActivityAttributes {
    public typealias ContentState = DashboardActivityState

    public var dashboardId: String

    public init(dashboardId: String = AppGroupKeys.liveActivityDashboardId) {
        self.dashboardId = dashboardId
    }
}
#endif

public struct DashboardActivityState: Codable, Hashable, Sendable {
        public var calendarTitle: String?
        public var calendarText: String?
        public var calendarDate: String?
        public var selectedDate: String?
        public var selectedDateText: String?
        public var monthText: String?
        public var localeCode: String?
        /// Always empty on the wire: the grid is rebuilt in the extension from
        /// `itemDateIds` to stay inside the ~4 KB payload budget.
        public var calendarDays: [GlanceCalendarDayState]
        public var itemDateIds: [String]
        public var todayTitle: String?
        public var todayText: String?
        public var memoTitle: String?
        public var memoText: String?
        public var memoId: String?
        public var memoItems: [GlanceMemoState]
        public var memoCount: Int?
        public var todoItems: [GlanceTodoState]
        public var doneCount: Int
        public var totalCount: Int
        public var lockScreenLayout: String?
        public var selectedContentSection: String?
        public var imageFileName: String?
        public var showTodosOnLockScreen: Bool
        public var showMemosOnLockScreen: Bool
        public var textFontWeight: String?
        public var textScale: Double?
        public var countdownTitle: String?
        public var countdownText: String?
        public var ddayTitle: String?
        public var ddayTargetDate: String?
        public var ddayText: String?
        public var ddayMemo: String?
        public var privacyMode: String?
        public var updatedAt: Double

        public init(
            calendarTitle: String? = nil,
            calendarText: String? = nil,
            calendarDate: String? = nil,
            selectedDate: String? = nil,
            selectedDateText: String? = nil,
            monthText: String? = nil,
            localeCode: String? = nil,
            calendarDays: [GlanceCalendarDayState] = [],
            itemDateIds: [String] = [],
            todayTitle: String? = nil,
            todayText: String? = nil,
            memoTitle: String? = nil,
            memoText: String? = nil,
            memoId: String? = nil,
            memoItems: [GlanceMemoState] = [],
            memoCount: Int? = nil,
            todoItems: [GlanceTodoState] = [],
            doneCount: Int = 0,
            totalCount: Int = 0,
            lockScreenLayout: String? = nil,
            selectedContentSection: String? = nil,
            imageFileName: String? = nil,
            showTodosOnLockScreen: Bool = true,
            showMemosOnLockScreen: Bool = true,
            textFontWeight: String? = nil,
            textScale: Double? = nil,
            countdownTitle: String? = nil,
            countdownText: String? = nil,
            ddayTitle: String? = nil,
            ddayTargetDate: String? = nil,
            ddayText: String? = nil,
            ddayMemo: String? = nil,
            privacyMode: String? = nil,
            updatedAt: Double = Date().timeIntervalSince1970
        ) {
            self.calendarTitle = calendarTitle
            self.calendarText = calendarText
            self.calendarDate = calendarDate
            self.selectedDate = selectedDate
            self.selectedDateText = selectedDateText
            self.monthText = monthText
            self.localeCode = localeCode
            self.calendarDays = calendarDays
            self.itemDateIds = itemDateIds
            self.todayTitle = todayTitle
            self.todayText = todayText
            self.memoTitle = memoTitle
            self.memoText = memoText
            self.memoId = memoId
            self.memoItems = memoItems
            self.memoCount = memoCount
            self.todoItems = todoItems
            self.doneCount = doneCount
            self.totalCount = totalCount
            self.lockScreenLayout = lockScreenLayout
            self.selectedContentSection = selectedContentSection
            self.imageFileName = imageFileName
            self.showTodosOnLockScreen = showTodosOnLockScreen
            self.showMemosOnLockScreen = showMemosOnLockScreen
            self.textFontWeight = textFontWeight
            self.textScale = textScale
            self.countdownTitle = countdownTitle
            self.countdownText = countdownText
            self.ddayTitle = ddayTitle
            self.ddayTargetDate = ddayTargetDate
            self.ddayText = ddayText
            self.ddayMemo = ddayMemo
            self.privacyMode = privacyMode
            self.updatedAt = updatedAt
        }
}

public struct GlanceCalendarDayState: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var day: Int
    public var weekday: String
    public var isSelected: Bool
    public var isToday: Bool
    public var isCurrentMonth: Bool
    public var hasItems: Bool
    public var todoItems: [GlanceTodoState]
    public var memoItems: [GlanceMemoState]

    public init(
        id: String,
        day: Int,
        weekday: String,
        isSelected: Bool,
        isToday: Bool,
        isCurrentMonth: Bool,
        hasItems: Bool,
        todoItems: [GlanceTodoState],
        memoItems: [GlanceMemoState]
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
}

public struct GlanceTodoState: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var isDone: Bool

    public init(id: String, text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        // Activities encoded before this field existed decode as unfinished.
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
    }
}

public struct GlanceMemoState: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bodyPreview: String?

    public init(id: String, title: String, bodyPreview: String? = nil) {
        self.id = id
        self.title = title
        self.bodyPreview = bodyPreview
    }
}

extension DashboardActivityState {
    /// Builds the wire payload from a snapshot, dropping the calendar grid and
    /// keeping only the day ids that carry content.
    public init(snapshot: DashboardSnapshot) {
        self.init(
            calendarTitle: snapshot.calendarTitle,
            calendarText: snapshot.calendarText,
            calendarDate: snapshot.calendarDate,
            selectedDate: snapshot.selectedDate.map(FlutterDate.localString),
            selectedDateText: snapshot.selectedDateText,
            monthText: snapshot.monthText,
            localeCode: snapshot.localeCode,
            calendarDays: [],
            itemDateIds: snapshot.calendarDays.filter(\.hasItems).map(\.id),
            todayTitle: snapshot.todayTitle,
            todayText: snapshot.todayText,
            memoTitle: snapshot.memoTitle,
            memoText: snapshot.memoText,
            memoId: snapshot.memoId,
            memoItems: snapshot.memoItems.map {
                GlanceMemoState(id: $0.id, title: $0.title, bodyPreview: $0.bodyPreview)
            },
            memoCount: snapshot.memoCount,
            todoItems: snapshot.todoItems.map {
                GlanceTodoState(id: $0.id, text: $0.text, isDone: $0.isDone)
            },
            doneCount: snapshot.doneCount,
            totalCount: snapshot.totalCount,
            lockScreenLayout: snapshot.lockScreenLayout,
            selectedContentSection: snapshot.selectedContentSection,
            imageFileName: snapshot.imageFileName,
            showTodosOnLockScreen: snapshot.showTodosOnLockScreen,
            showMemosOnLockScreen: snapshot.showMemosOnLockScreen,
            textFontWeight: snapshot.textFontWeight,
            textScale: snapshot.textScale,
            countdownTitle: snapshot.countdownTitle,
            countdownText: snapshot.countdownText,
            ddayTitle: snapshot.ddayTitle,
            ddayTargetDate: snapshot.ddayTargetDate.map(FlutterDate.localString),
            ddayText: snapshot.ddayText,
            ddayMemo: snapshot.ddayMemo,
            privacyMode: snapshot.privacyMode,
            updatedAt: snapshot.updatedAt.timeIntervalSince1970
        )
    }
}
