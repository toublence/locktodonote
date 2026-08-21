import LockTodoNoteShared
import SwiftUI
import WidgetKit

private let appGroupId = "group.com.namslab.glancecard"
private let representativeCardKey = "representativeCard"
private let dashboardStateKey = "dashboard_state"
private let queuedAnalyticsEventsKey = "queued_analytics_events"

struct GlanceCardWidgetEntry: TimelineEntry {
  let date: Date
  let dashboard: SharedDashboardSnapshot
}

struct SharedDashboardSnapshot {
  let calendarTitle: String
  let calendarText: String
  let memoTitle: String
  let todoItems: [GlanceTodoState]
  let doneCount: Int
  let totalCount: Int
  let privacyMode: String
  let templateId: String
  let hasMemo: Bool
  let isPremium: Bool
  let isConfigured: Bool
  let needsRefresh: Bool

  static let placeholder = SharedDashboardSnapshot(
    calendarTitle: localized("today"),
    calendarText: localized("noEvents"),
    memoTitle: localized("noMemo"),
    todoItems: [],
    doneCount: 0,
    totalCount: 0,
    privacyMode: "full",
    templateId: "",
    hasMemo: false,
    isPremium: false,
    isConfigured: false,
    needsRefresh: false
  )
}

struct GlanceCardTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> GlanceCardWidgetEntry {
    GlanceCardWidgetEntry(date: Date(), dashboard: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (GlanceCardWidgetEntry) -> Void) {
    let now = Date()
    completion(GlanceCardWidgetEntry(date: now, dashboard: loadDashboard(for: now)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceCardWidgetEntry>) -> Void) {
    let now = Date()
    let startOfTomorrow = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    ) ?? now.addingTimeInterval(24 * 60 * 60)
    let dashboard = loadDashboard(for: now)
    enqueueAnalyticsEvent(
      name: "widget_timeline_requested",
      parameters: analyticsParameters(from: dashboard, source: "widget", result: "success")
    )
    let entries = [
      GlanceCardWidgetEntry(date: now, dashboard: dashboard),
      GlanceCardWidgetEntry(
        date: startOfTomorrow,
        dashboard: loadDashboard(for: startOfTomorrow)
      ),
    ]
    completion(
      Timeline(
        entries: entries,
        policy: .after(startOfTomorrow.addingTimeInterval(15 * 60))
      )
    )
  }

  private func loadDashboard(for date: Date = Date()) -> SharedDashboardSnapshot {
    let defaults = UserDefaults(suiteName: appGroupId)
    if let payload = defaults?.dictionary(forKey: dashboardStateKey) {
      let day = calendarDay(in: payload, for: date)
      let updatedAt = (payload["updatedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
      let needsRefresh = day == nil && !(updatedAt.map {
        Calendar.current.isDate($0, inSameDayAs: date)
      } ?? false)
      let dayTodos = todoItems(from: day?["todoItems"])
      let dayDoneCount = dayTodos.filter(\.isDone).count
      let dayMemos = day?["memoItems"] as? [[String: Any]] ?? []
      let firstMemoTitle = dayMemos.first?["title"] as? String
      return SharedDashboardSnapshot(
        calendarTitle: day == nil
          ? (payload["calendarTitle"] as? String ?? localized("today"))
          : localizedDateTitle(date),
        calendarText: needsRefresh
          ? localized("openAppToRefresh")
          : day?["weekday"] as? String
          ?? payload["calendarText"] as? String
          ?? localized("noEvents"),
        memoTitle: day == nil
          ? (payload["memoTitle"] as? String
              ?? payload["todayTitle"] as? String
              ?? localized("noMemo"))
          : firstMemoTitle ?? localized("noMemo"),
        todoItems: needsRefresh
          ? []
          : day == nil ? todoItems(from: payload["todoItems"]) : dayTodos,
        doneCount: needsRefresh
          ? 0
          : (day == nil ? (payload["doneCount"] as? Int ?? 0) : dayDoneCount),
        totalCount: needsRefresh
          ? 0
          : (day == nil ? (payload["totalCount"] as? Int ?? 0) : dayTodos.count),
        privacyMode: payload["privacyMode"] as? String ?? "full",
        templateId: payload["lockScreenLayout"] as? String ?? "",
        hasMemo: day == nil
          ? (!(payload["memoItems"] as? [[String: Any]] ?? []).isEmpty
              || (payload["memoTitle"] as? String ?? "").isEmpty == false)
          : !dayMemos.isEmpty,
        isPremium: payload["isPro"] as? Bool ?? false,
        isConfigured: true,
        needsRefresh: needsRefresh
      )
    }
    guard let card = defaults?.dictionary(forKey: representativeCardKey) else { return .placeholder }
    let title = card["title"] as? String ?? "LockTodoNote"
    return SharedDashboardSnapshot(
      calendarTitle: localized("today"),
      calendarText: localized("noEvents"),
      memoTitle: title,
      todoItems: [],
      doneCount: 0,
      totalCount: 0,
      privacyMode: "full",
      templateId: "",
      hasMemo: false,
      isPremium: false,
      isConfigured: true,
      needsRefresh: false
    )
  }

  private func calendarDay(in payload: [String: Any], for date: Date) -> [String: Any]? {
    let targetId = dateId(date)
    let days = payload["calendarDays"] as? [[String: Any]] ?? []
    if let day = days.first(where: { $0["id"] as? String == targetId }) {
      return day
    }
    let prepared = payload["preparedNextDay"] as? [String: Any]
    return prepared?["id"] as? String == targetId ? prepared : nil
  }

  private func dateId(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  private func localizedDateTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("MMM d")
    return formatter.string(from: date)
  }
}

struct GlanceCardLockScreenWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "GlanceCardLockScreenWidget", provider: GlanceCardTimelineProvider()) { entry in
      GlanceCardWidgetView(dashboard: entry.dashboard)
        .widgetURL(URL(string: "glancecard://dashboard?source=widget"))
    }
    .configurationDisplayName("LockTodoNote")
    .description("오늘의 할 일과 메모를 잠금화면과 홈 화면에서 이어서 봅니다.")
    .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

struct GlanceCardWidgetView: View {
  let dashboard: SharedDashboardSnapshot

  @Environment(\.widgetFamily) private var family

  @ViewBuilder
  var body: some View {
    if family == .systemMedium {
      MediumDashboardWidget(dashboard: dashboard)
    } else {
      accessoryContent
    }
  }

  private var accessoryContent: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(localized("calendar"))
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(dashboard.calendarTitle)
          .font(.caption.bold())
          .lineLimit(1)
        Text(dashboard.calendarText)
          .font(.caption2)
          .lineLimit(1)
      }
      Divider().opacity(0.35)
      VStack(alignment: .leading, spacing: 2) {
        Text(todoLine)
          .font(.caption.bold())
          .lineLimit(1)
        Text(memoLine)
          .font(.caption2)
          .lineLimit(1)
      }
    }
  }

  private var todoLine: String {
    if dashboard.needsRefresh {
      return localized("refreshToday")
    }
    if dashboard.privacyMode == "hidden", !dashboard.todoItems.isEmpty {
      return "○ \(localized("hiddenContent"))"
    }
    if let first = dashboard.todoItems.first {
      return "\(first.isDone ? "●" : "○") \(first.text)"
    }
    return localized("noTasks")
  }

  private var memoLine: String {
    if dashboard.needsRefresh {
      return localized("openApp")
    }
    if dashboard.privacyMode == "hidden", dashboard.memoTitle != localized("noMemo") {
      return localized("hiddenContent")
    }
    return dashboard.memoTitle
  }
}

private struct MediumDashboardWidget: View {
  let dashboard: SharedDashboardSnapshot

  var body: some View {
    Group {
      if #available(iOSApplicationExtension 17.0, *) {
        content
          .containerBackground(for: .widget) {
            Color.black.opacity(0.86)
          }
      } else {
        content.background(Color.black.opacity(0.86))
      }
    }
  }

  private var content: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text(dashboard.calendarTitle)
          .font(.headline)
          .lineLimit(1)
        Text(dashboard.calendarText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer(minLength: 0)
        Link(destination: URL(string: "glancecard://quick-memo?source=widget")!) {
          Label(localized("addMemo"), systemImage: "square.and.pencil")
            .font(.caption.bold())
            .lineLimit(1)
        }
      }
      .frame(width: 104, alignment: .leading)

      Divider().opacity(0.28)

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(localized("todo"))
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Link(destination: URL(string: "glancecard://quick-todo?source=widget")!) {
            Image(systemName: "plus.circle.fill")
              .font(.title3)
          }
          .accessibilityLabel(localized("addTodo"))
        }

        if dashboard.todoItems.filter({ !$0.isDone }).isEmpty {
          Text(dashboard.needsRefresh ? localized("openAppToRefresh") : localized("noTasks"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          ForEach(Array(dashboard.todoItems.filter { !$0.isDone }.prefix(3))) { item in
            todoRow(item)
          }
        }

        if dashboard.hasMemo {
          Spacer(minLength: 0)
          Label(dashboard.memoTitle, systemImage: "note.text")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .foregroundStyle(.white)
    .padding(16)
  }

  @ViewBuilder
  private func todoRow(_ item: GlanceTodoState) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      Button(intent: ToggleTodoIntent(todoId: item.id, source: "widget")) {
        rowLabel(item)
      }
      .buttonStyle(.plain)
    } else {
      Link(destination: URL(string: "glancecard://dashboard?source=widget")!) {
        rowLabel(item)
      }
    }
  }

  private func rowLabel(_ item: GlanceTodoState) -> some View {
    HStack(spacing: 7) {
      Image(systemName: "circle")
        .font(.caption)
      Text(item.text)
        .font(.subheadline)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
  }
}

private func todoItems(from value: Any?) -> [GlanceTodoState] {
  if let texts = value as? [String] {
    return texts.map { GlanceTodoState(id: $0, text: $0) }
  }
  guard let rows = value as? [[String: Any]] else { return [] }
  return rows.map {
    GlanceTodoState(
      id: $0["id"] as? String ?? $0["text"] as? String ?? "",
      text: $0["text"] as? String ?? "",
      isDone: $0["isDone"] as? Bool ?? false
    )
  }
}


private func enqueueAnalyticsEvent(name: String, parameters: [String: Any]) {
  let defaults = UserDefaults(suiteName: appGroupId)
  var rows = defaults?.array(forKey: queuedAnalyticsEventsKey) as? [[String: Any]] ?? []
  rows.append([
    "name": name,
    "parameters": parameters,
    "created_at": Date().timeIntervalSince1970
  ])
  defaults?.set(rows.suffix(100).map { $0 }, forKey: queuedAnalyticsEventsKey)
  defaults?.synchronize()
}

private func analyticsParameters(
  from dashboard: SharedDashboardSnapshot,
  source: String,
  result: String
) -> [String: Any] {
  [
    "source": source,
    "task_count": dashboard.totalCount,
    "todo_count": dashboard.totalCount,
    "remaining_count": dashboard.todoItems.filter { !$0.isDone }.count,
    "completed_count": dashboard.doneCount,
    "has_memo": dashboard.hasMemo,
    "template_id": dashboard.templateId,
    "setup_type": "widget",
    "widget_type": "lock_screen",
    "ios_version": ProcessInfo.processInfo.operatingSystemVersionString,
    "device_family": "ios_widget_extension",
    "is_premium": dashboard.isPremium,
    "result": result
  ]
}
