import ActivityKit
import LockTodoNoteShared
import Foundation
import SwiftUI
import UIKit
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct GlanceCardLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GlanceDashboardAttributes.self) { context in
      GlanceDashboardActivityView(
        state: context.state,
        isStale: activityIsStale(context)
      )
        .activityBackgroundTint(Color.black.opacity(0.78))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(localized("calendar"))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Text(context.state.calendarTitle ?? localized("today"))
              .font(.caption.bold())
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(compactLabel(for: context.state))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Text(compactText(for: context.state))
              .font(.caption.bold())
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.8)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(todoSummary(for: context.state))
              .font(.caption)
              .lineLimit(1)
              .truncationMode(.tail)
            HStack(spacing: 8) {
              if #available(iOSApplicationExtension 17.0, *),
                 let firstTodo = context.state.todoItems.first(where: { !$0.isDone }) {
                Button(
                  intent: ToggleTodoIntent(
                    todoId: firstTodo.id,
                    source: "dynamic_island"
                  )
                ) {
                  Label(firstTodo.text, systemImage: "checkmark.circle")
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
              }
              if showsMemoAction(for: context.state) {
                ActionLink(
                  title: localized("addMemo"),
                  systemImage: "square.and.pencil",
                  url: "glancecard://quick-memo?source=live_activity"
                )
              }
              if showsTodoAction(for: context.state) {
                ActionLink(
                  title: localized("addTodo"),
                  systemImage: "checklist",
                  url: "glancecard://quick-todo?source=live_activity"
                )
              }
              if !showsMemoAction(for: context.state) && !showsTodoAction(for: context.state) {
                ActionLink(
                  title: localized("openApp"),
                  systemImage: "arrow.up.forward.app",
                  url: "glancecard://dashboard?source=live_activity"
                )
              }
            }
          }
        }
      } compactLeading: {
        Image(systemName: dynamicIslandSymbol(for: context.state))
      } compactTrailing: {
        Text(dynamicIslandCountText(for: context.state))
          .font(.caption2.bold())
      } minimal: {
        Text(dynamicIslandMinimalText(for: context.state))
          .font(.caption2.bold())
      }
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private func activityIsStale(
  _ context: ActivityViewContext<GlanceDashboardAttributes>
) -> Bool {
  if #available(iOS 16.2, *) {
    return context.isStale
  }
  return false
}

@available(iOSApplicationExtension 16.1, *)
private struct GlanceDashboardActivityView: View {
  let state: GlanceDashboardAttributes.ContentState
  let isStale: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if isStale {
        Link(destination: URL(string: "glancecard://dashboard?source=live_activity")!) {
          Label(localized("refreshRequired"), systemImage: "arrow.clockwise")
            .font(.caption2.bold())
          .foregroundStyle(.yellow)
        }
      }
      layoutContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: 152, alignment: .topLeading)
    .clipped()
  }

  @ViewBuilder
  private var layoutContent: some View {
    switch state.lockScreenLayout ?? "calendarItems" {
    case "memoTodo":
      MemoTodoSectionView(state: state)
    case "dateMemo", "dateTodo":
      RatioColumns(
        leadingRatio: 0.3,
        minLeadingWidth: 88,
        maxLeadingWidth: 170,
        leading: DateColumn(state: state),
        trailing: MemoTodoSectionView(state: state, showsAddActions: true)
      )
    case "imageMemo", "imageTodo":
      RatioColumns(
        leadingRatio: 0.36,
        minLeadingWidth: 104,
        maxLeadingWidth: 240,
        leading: ImageColumn(state: state),
        trailing: MemoTodoSectionView(state: state)
      )
    case "ddayMemo":
      RatioColumns(
        leadingRatio: 0.34,
        minLeadingWidth: 96,
        maxLeadingWidth: 190,
        leading: DdayColumn(state: state, showsTitle: false),
        trailing: DdayTextColumn(state: state)
      )
    case "ddayTodo":
      RatioColumns(
        leadingRatio: 0.34,
        minLeadingWidth: 96,
        maxLeadingWidth: 190,
        leading: DdayColumn(state: state, showsTitle: true),
        trailing: TodoColumn(state: state)
      )
    case "imageDday":
      RatioColumns(
        leadingRatio: 0.36,
        minLeadingWidth: 104,
        maxLeadingWidth: 240,
        leading: ImageColumn(state: state),
        trailing: DdayTextColumn(state: state, showsDdayText: true)
      )
    default:
      CalendarItemsLayout(state: state)
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct CalendarItemsLayout: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let state: GlanceDashboardAttributes.ContentState

  var body: some View {
    RatioColumns(
      leadingRatio: horizontalSizeClass == .compact ? 0.39 : 0.34,
      minLeadingWidth: 124,
      maxLeadingWidth: 260,
      leading: CalendarColumn(state: state),
      trailing: MemoTodoSectionView(state: state, showsAddActions: true)
    )
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct MemoTodoSectionView: View {
  let state: GlanceDashboardAttributes.ContentState
  var showsAddActions = true

  private var selectedSection: String {
    selectedContentSection(for: state)
  }

  var body: some View {
    standardContent
  }

  private var standardContent: some View {
    VStack(alignment: .leading, spacing: 5) {
      sectionHeader

      if state.privacyMode == "hidden" {
        PrivacySummaryView(systemImage: "lock.fill", text: localized("hiddenContent"))
      } else if state.privacyMode == "countOnly" {
        PrivacySummaryView(
          systemImage: "number",
          text: selectedSection == "memo"
            ? "\(state.memoCount ?? state.memoItems.count)"
            : "\(max(state.totalCount - state.doneCount, 0))"
        )
      } else if state.privacyMode == "titleOnly" {
        PrivacySummaryView(
          systemImage: selectedSection == "memo" ? "note.text" : "checklist",
          text: selectedSection == "memo"
            ? (state.memoTitle?.isEmpty == false ? state.memoTitle! : localized("memo"))
            : localized("todo")
        )
      } else if !state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
        Text(localized("allItemsHidden"))
          .font(.caption.bold())
          .lineLimit(2)
          .truncationMode(.tail)
      } else if selectedSection == "memo" {
        MemoColumn(state: state, showsHeader: false)
      } else {
        TodoColumn(state: state, showsHeader: false)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var sectionHeader: some View {
    if #available(iOSApplicationExtension 26.0, *) {
      GlassEffectContainer(spacing: 4) {
        sectionHeaderContent
      }
    } else {
      sectionHeaderContent
    }
  }

  private var sectionHeaderContent: some View {
    HStack(spacing: 4) {
        ContentSectionTab(
          title: localized("todo"),
          systemImage: "checklist",
          section: "todo",
          isSelected: selectedSection == "todo",
          isEnabled: state.showTodosOnLockScreen
        )
        ContentSectionTab(
          title: localized("memo"),
          systemImage: "square.and.pencil",
          section: "memo",
          isSelected: selectedSection == "memo",
          isEnabled: state.showMemosOnLockScreen
        )
        if showsAddActions {
          Spacer(minLength: 0)
          selectedAction
        }
    }
  }

  @ViewBuilder
  private var selectedAction: some View {
    if selectedSection == "memo", showsMemoAction(for: state) {
      CompactIconActionLink(
        title: localized("addMemo"),
        url: "glancecard://quick-memo?source=live_activity"
      )
    } else if selectedSection == "todo", showsTodoAction(for: state) {
      CompactIconActionLink(
        title: localized("addTodo"),
        url: "glancecard://quick-todo?source=live_activity"
      )
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct PrivacySummaryView: View {
  let systemImage: String
  let text: String

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct ContentSectionTab: View {
  let title: String
  let systemImage: String
  let section: String
  let isSelected: Bool
  let isEnabled: Bool

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *), isEnabled {
      Button(intent: SelectContentSectionIntent(section: section)) {
        tabContent
      }
      .buttonStyle(.plain)
    } else {
      tabContent
    }
  }

  private var tabContent: some View {
    ContentSectionLabel(
      title: title,
      systemImage: systemImage,
      isSelected: isSelected,
      isEnabled: isEnabled
    )
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct ContentSectionLabel: View {
  let title: String
  let systemImage: String
  let isSelected: Bool
  let isEnabled: Bool

  @ViewBuilder
  var body: some View {
    if #available(iOSApplicationExtension 26.0, *) {
      label
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 68)
        .glassEffect(
          isSelected
            ? .regular.tint(Color.green.opacity(0.34)).interactive()
            : .regular.interactive(),
          in: Capsule()
        )
        .opacity(isEnabled ? 1 : 0.42)
    } else {
      label
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 68)
        .background(backgroundColor, in: Capsule())
        .opacity(isEnabled ? 1 : 0.42)
    }
  }

  private var label: some View {
    Label(title, systemImage: systemImage)
      .font(.caption.bold())
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .foregroundStyle(foregroundColor)
  }

  private var foregroundColor: Color {
    isSelected ? Color.green : Color.white.opacity(0.74)
  }

  private var backgroundColor: Color {
    isSelected ? Color.green.opacity(0.18) : Color.white.opacity(0.1)
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct CompactIconActionLink: View {
  let title: String
  let url: String

  @ViewBuilder
  var body: some View {
    if #available(iOSApplicationExtension 26.0, *) {
      linkLabel
        .glassEffect(.regular.interactive(), in: Circle())
    } else {
      linkLabel
        .background(Color.white.opacity(0.16), in: Circle())
    }
  }

  private var linkLabel: some View {
    Link(destination: URL(string: url)!) {
      Image(systemName: "plus")
        .font(.system(size: 11, weight: .bold))
        .frame(width: 28, height: 28)
    }
    .accessibilityLabel(title)
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct ActionLink: View {
  let title: String
  let systemImage: String
  let url: String

  var body: some View {
    Link(destination: URL(string: url)!) {
      Label(title, systemImage: systemImage)
        .font(.caption2.bold())
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.14), in: Capsule())
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct CompactActionLink: View {
  let title: String
  let systemImage: String
  let url: String

  var body: some View {
    Link(destination: URL(string: url)!) {
      HStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.system(size: 8, weight: .bold))
          .imageScale(.small)
        Text(title)
          .font(.system(size: 9, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
      .padding(.horizontal, 5)
      .padding(.vertical, 4)
      .background(Color.white.opacity(0.16), in: Capsule())
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct RatioColumns<Leading: View, Trailing: View>: View {
  let leadingRatio: CGFloat
  let minLeadingWidth: CGFloat
  let maxLeadingWidth: CGFloat
  let leading: Leading
  let trailing: Trailing

  init(
    leadingRatio: CGFloat,
    minLeadingWidth: CGFloat = 0,
    maxLeadingWidth: CGFloat = .infinity,
    leading: Leading,
    trailing: Trailing
  ) {
    self.leadingRatio = leadingRatio
    self.minLeadingWidth = minLeadingWidth
    self.maxLeadingWidth = maxLeadingWidth
    self.leading = leading
    self.trailing = trailing
  }

  var body: some View {
    GeometryReader { proxy in
      let spacing: CGFloat = proxy.size.width < 420 ? 8 : 12
      let dividerWidth: CGFloat = 1
      let contentWidth = proxy.size.width - spacing * 2 - dividerWidth
      let leadingWidth = min(
        max(contentWidth * leadingRatio, minLeadingWidth),
        min(maxLeadingWidth, contentWidth * 0.5)
      )
      HStack(alignment: .top, spacing: spacing) {
        leading
          .frame(
            width: leadingWidth,
            height: proxy.size.height,
            alignment: .topLeading
          )
        Divider()
          .opacity(0.18)
          .padding(.vertical, 2)
        trailing
          .frame(
            width: contentWidth - leadingWidth,
            height: proxy.size.height,
            alignment: .topLeading
          )
      }
    }
    .frame(minHeight: 82)
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct CalendarColumn: View {
  let state: GlanceDashboardAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(monthText)
        .font(.caption.bold())
        .lineLimit(1)
      LazyVGrid(columns: columns, alignment: .center, spacing: 1) {
        ForEach(weekdayLabels, id: \.self) { weekday in
          Text(weekday)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        ForEach(days) { day in
          DayCell(day: day)
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(minimum: 12), spacing: 1), count: 7)
  }

  private var weekdayLabels: [String] {
    let formatter = DateFormatter()
    formatter.locale = activityLocale(state)
    let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
    guard symbols.count == 7 else { return [] }
    return symbols
  }

  private var monthText: String {
    if state.localeCode != nil, let selected = selectedDate {
      return localizedMonth(selected, locale: activityLocale(state))
    }
    if let month = state.monthText, !month.isEmpty {
      return month
    }
    return localizedMonth(selectedDate ?? Date(), locale: activityLocale(state))
  }

  private var days: [GlanceCalendarDayState] {
    if state.calendarDays.isEmpty {
      return fallbackDays
    }
    return state.calendarDays
  }

  private var fallbackDays: [GlanceCalendarDayState] {
    let calendar = Calendar.current
    let selected = selectedDate ?? Date()
    let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selected)
    guard
      let year = selectedComponents.year,
      let month = selectedComponents.month,
      let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
      let daysRange = calendar.range(of: .day, in: .month, for: firstDay)
    else {
      return []
    }

    let leadingDays = calendar.component(.weekday, from: firstDay) - 1
    let visibleDays = ((leadingDays + daysRange.count + 6) / 7) * 7
    let start = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay) ?? firstDay
    let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())

    return (0..<visibleDays).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
        return nil
      }
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      let isSelected = components.year == selectedComponents.year &&
        components.month == selectedComponents.month &&
        components.day == selectedComponents.day
      let isToday = components.year == todayComponents.year &&
        components.month == todayComponents.month &&
        components.day == todayComponents.day
      let day = components.day ?? 0
      return GlanceCalendarDayState(
        id: dateId(date),
        day: day,
        weekday: "",
        isSelected: isSelected,
        isToday: isToday,
        isCurrentMonth: components.month == month,
        hasItems: state.itemDateIds.contains(dateId(date)) ||
          (isSelected && (!state.todoItems.isEmpty || !state.memoItems.isEmpty)),
        todoItems: [],
        memoItems: []
      )
    }
  }

  private var selectedDate: Date? {
    guard let raw = state.selectedDate else { return nil }
    if let isoDate = ISO8601DateFormatter().date(from: raw) {
      return isoDate
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: raw) {
      return date
    }
    return formatter.date(from: String(raw.prefix(10)))
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
}

@available(iOSApplicationExtension 16.1, *)
private struct DateColumn: View {
  let state: GlanceDashboardAttributes.ContentState

  var body: some View {
    VStack(alignment: .center, spacing: 3) {
      VStack(alignment: .center, spacing: 3) {
        Text(monthText)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(dayText)
          .font(.system(size: dayFontSize, weight: .heavy, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Text(weekdayText)
          .font(.caption.bold())
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var dayFontSize: CGFloat {
    38
  }

  private var monthText: String {
    if state.localeCode != nil, let selected = selectedDate {
      return localizedMonth(selected, locale: activityLocale(state))
    }
    if let month = state.monthText, !month.isEmpty {
      return month
    }
    return localizedMonth(selectedDate ?? Date(), locale: activityLocale(state))
  }

  private var dayText: String {
    if let selected = selectedDate {
      return "\(Calendar.current.component(.day, from: selected))"
    }
    if let raw = state.calendarDate, !raw.isEmpty {
      return raw
    }
    return "•"
  }

  private var weekdayText: String {
    if let selected = selectedDate {
      let formatter = DateFormatter()
      formatter.locale = activityLocale(state)
      formatter.setLocalizedDateFormatFromTemplate("EEE")
      return formatter.string(from: selected)
    }
    if let text = state.selectedDateText, !text.isEmpty {
      return text
    }
    return localized("today")
  }

  private var selectedDate: Date? {
    guard let raw = state.selectedDate else { return nil }
    if let isoDate = ISO8601DateFormatter().date(from: raw) {
      return isoDate
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: raw) {
      return date
    }
    return formatter.date(from: String(raw.prefix(10)))
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct DayCell: View {
  let day: GlanceCalendarDayState

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      Button(intent: SelectDateIntent(dateString: day.id)) {
        DayCellContent(day: day, isSelected: day.isSelected)
      }
      .buttonStyle(.plain)
    } else {
      DayCellContent(day: day, isSelected: day.isSelected)
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct DayCellContent: View {
  let day: GlanceCalendarDayState
  let isSelected: Bool

  var body: some View {
    ZStack(alignment: .bottom) {
      Text("\(day.day)")
        .font(.system(size: 8.5, weight: isSelected ? .heavy : .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(dayNumberColor)
        .frame(width: isSelected ? 18 : 16, height: 14)
        .background(selectedBackground)
        .overlay {
          if day.isToday && !isSelected {
            RoundedRectangle(cornerRadius: 5)
              .stroke(Color.white.opacity(0.45), lineWidth: 1)
          }
        }
        .shadow(color: isSelected ? selectedDateColor.opacity(0.75) : Color.clear, radius: 3)
      Circle()
        .fill(itemDotColor)
        .frame(width: 2.5, height: 2.5)
        .offset(y: 1.5)
    }
    .frame(height: 15)
    .opacity(day.isCurrentMonth || isSelected ? 1 : 0.72)
  }

  private var dayNumberColor: Color {
    if isSelected {
      return Color.white
    }
    return day.isCurrentMonth ? Color.white : Color.white.opacity(0.32)
  }

  private var selectedDateColor: Color {
    Color(red: 0.56, green: 0.67, blue: 1)
  }

  @ViewBuilder
  private var selectedBackground: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: 5)
        .fill(selectedDateColor)
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    } else {
      Color.clear
    }
  }

  private var itemDotColor: Color {
    if !day.hasItems {
      return Color.clear
    }
    if isSelected {
      return Color.white
    }
    return Color.white.opacity(day.isCurrentMonth ? 0.72 : 0.32)
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct ImageColumn: View {
  let state: GlanceDashboardAttributes.ContentState

  var body: some View {
    ZStack {
      if let image = lockScreenImage(fileName: state.imageFileName) {
        FullColorLockScreenImage(image: image)
      } else {
        VStack(spacing: 5) {
          Image(systemName: "photo.badge.plus")
            .font(.system(size: 18, weight: .bold))
          Text(localized("addImage"))
            .font(.caption2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white.opacity(0.82))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.12))
      }
      LinearGradient(
        colors: [Color.black.opacity(0.04), Color.black.opacity(0.24)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct DdayColumn: View {
  let state: GlanceDashboardAttributes.ContentState
  var showsTitle = false

  var body: some View {
    VStack(alignment: .center, spacing: 5) {
      Text(localized("dday"))
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(ddayText)
        .font(.system(size: 31, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.62)
      if showsTitle, let title = state.ddayTitle, !title.isEmpty {
        Text(title)
          .font(.caption2.bold())
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var ddayText: String {
    let value = state.ddayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? localized("dDayToday") : value
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct DdayTextColumn: View {
  let state: GlanceDashboardAttributes.ContentState
  var showsDdayText = false

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if showsDdayText {
        Text(ddayText)
          .font(.system(size: dashboardTextSize(state, base: 20), weight: dashboardTextWeight(state)))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Text(titleText)
        .font(.system(size: dashboardTextSize(state, base: 12), weight: dashboardTextWeight(state)))
        .lineLimit(2)
        .truncationMode(.tail)
      if let memo = state.ddayMemo, !memo.isEmpty {
        Text(memo)
          .font(.system(size: dashboardTextSize(state, base: 11), weight: dashboardTextWeight(state)))
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var ddayText: String {
    let value = state.ddayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? localized("dDayToday") : value
  }

  private var titleText: String {
    let value = state.ddayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? localized("whatAreYouWaitingFor") : value
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct FullColorLockScreenImage: View {
  let image: UIImage

  var body: some View {
    if #available(iOSApplicationExtension 18.0, *) {
      Image(uiImage: image)
        .resizable()
        .widgetAccentedRenderingMode(.fullColor)
        .aspectRatio(contentMode: .fill)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    } else {
      imageView
    }
  }

  private var imageView: some View {
    Image(uiImage: image)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct MemoColumn: View {
  let state: GlanceDashboardAttributes.ContentState
  var showsAddAction = false
  var showsHeader = true

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsHeader {
        HStack(spacing: 5) {
          Image(systemName: "square.and.pencil")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(localized("memo"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if showsAddAction {
            Spacer(minLength: 0)
            CompactActionLink(
              title: localized("addMemo"),
              systemImage: "square.and.pencil",
              url: "glancecard://quick-memo?source=live_activity"
            )
          }
        }
      }
      if memoRows.isEmpty {
        Text(localized("noMemo"))
          .font(.system(size: dashboardTextSize(state), weight: dashboardTextWeight(state)))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        ForEach(Array(memoRows.prefix(visibleRowLimit).enumerated()), id: \.offset) { _, row in
          Link(destination: URL(string: "glancecard://cards/\(row.memo.id)")!) {
            HStack(spacing: 4) {
              Image(systemName: "note.text")
                .font(.caption2)
              Text(row.text)
                .font(.system(size: dashboardTextSize(state), weight: dashboardTextWeight(state)))
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
        }
      }
      if showsAddAction && !showsHeader {
        Spacer(minLength: 0)
        HStack {
          Spacer(minLength: 0)
          ActionLink(
            title: localized("addMemo"),
            systemImage: "square.and.pencil",
            url: "glancecard://quick-memo?source=live_activity"
          )
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var visibleRowLimit: Int {
    (state.textScale ?? 1) > 1.08 ? 3 : 4
  }

  private var memoRows: [(memo: GlanceMemoState, text: String)] {
    state.memoItems.flatMap { memo in
      memoDisplayLines(memo).map { (memo: memo, text: $0) }
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct TodoColumn: View {
  let state: GlanceDashboardAttributes.ContentState
  var showsAddAction = false
  var showsHeader = true

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsHeader {
        HStack(spacing: 5) {
          Image(systemName: "checklist")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(localized("todo"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if showsAddAction {
            Spacer(minLength: 0)
            CompactActionLink(
              title: localized("addTodo"),
              systemImage: "checklist",
              url: "glancecard://quick-todo?source=live_activity"
            )
          }
        }
      }
      if state.todoItems.isEmpty {
        Text(localized("noTasks"))
          .font(.system(size: dashboardTextSize(state), weight: dashboardTextWeight(state)))
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        ForEach(Array(state.todoItems.prefix(visibleRowLimit)), id: \.self) { item in
          if item.isDone {
            TodoRow(item: item, state: state)
          } else if #available(iOSApplicationExtension 17.0, *) {
            Button(
              intent: ToggleTodoIntent(
                todoId: item.id,
                source: "live_activity"
              )
            ) {
              TodoRow(item: item, state: state)
            }
            .buttonStyle(.plain)
          } else {
            TodoRow(item: item, state: state)
          }
        }
      }
      if showsAddAction && !showsHeader {
        Spacer(minLength: 0)
        HStack {
          Spacer(minLength: 0)
          ActionLink(
            title: localized("addTodo"),
            systemImage: "checklist",
            url: "glancecard://quick-todo?source=live_activity"
          )
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var visibleRowLimit: Int {
    (state.textScale ?? 1) > 1.08 ? 3 : 4
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct TodoRow: View {
  let item: GlanceTodoState
  let state: GlanceDashboardAttributes.ContentState

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 14, weight: .medium))
      Text(item.text)
        .font(.system(size: dashboardTextSize(state), weight: dashboardTextWeight(state)))
        .lineLimit(1)
        .truncationMode(.tail)
        .strikethrough(item.isDone)
        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
    }
  }
}

private func dashboardTextSize(_ state: GlanceDashboardAttributes.ContentState, base: CGFloat = 14) -> CGFloat {
  let scale = min(max(state.textScale ?? 1.0, 0.85), 1.25)
  return base * scale
}

private func dashboardTextWeight(_ state: GlanceDashboardAttributes.ContentState) -> Font.Weight {
  state.textFontWeight == "bold" ? .bold : .medium
}

private func showsMemoAction(for state: GlanceDashboardAttributes.ContentState) -> Bool {
  switch state.lockScreenLayout ?? "calendarItems" {
  case "memoTodo", "calendarItems", "dateMemo", "dateTodo", "imageMemo", "imageTodo":
    return selectedContentSection(for: state) == "memo" && state.showMemosOnLockScreen
  case "ddayMemo":
    return true
  case "ddayTodo", "imageDday":
    return false
  default:
    return state.showMemosOnLockScreen
  }
}

private func showsTodoAction(for state: GlanceDashboardAttributes.ContentState) -> Bool {
  switch state.lockScreenLayout ?? "calendarItems" {
  case "memoTodo", "calendarItems", "dateMemo", "dateTodo", "imageMemo", "imageTodo":
    return selectedContentSection(for: state) == "todo" && state.showTodosOnLockScreen
  case "ddayTodo":
    return true
  case "ddayMemo", "imageDday":
    return false
  default:
    return state.showTodosOnLockScreen
  }
}

private func selectedContentSection(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.selectedContentSection == "memo" && state.showMemosOnLockScreen {
    return "memo"
  }
  if state.selectedContentSection == "todo" && state.showTodosOnLockScreen {
    return "todo"
  }
  return state.showTodosOnLockScreen ? "todo" : "memo"
}

private func usesInlineActions(for state: GlanceDashboardAttributes.ContentState) -> Bool {
  switch state.lockScreenLayout ?? "calendarItems" {
  case "memoTodo", "dateMemo", "dateTodo", "ddayMemo", "ddayTodo":
    return true
  default:
    return false
  }
}

private func lockScreenImage(fileName: String?) -> UIImage? {
  guard
    let fileName,
    !fileName.isEmpty,
    let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.namslab.glancecard"
    )
  else {
    return nil
  }
  if let data = UserDefaults(suiteName: "group.com.namslab.glancecard")?
    .data(forKey: lockScreenImageDataKey(fileName)),
    let image = UIImage(data: data) {
    return image
  }
  let url = container
    .appendingPathComponent("LockScreenImages", isDirectory: true)
    .appendingPathComponent(fileName)
  if let image = UIImage(contentsOfFile: url.path)
    ?? (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
  {
    return activitySizedImage(image)
  }
  return nil
}

private func memoDisplayText(_ memo: GlanceMemoState) -> String {
  let title = memo.title.trimmingCharacters(in: .whitespacesAndNewlines)
  let bodyPreview = memo.bodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  if !title.isEmpty && !bodyPreview.isEmpty && title != bodyPreview {
    return "\(title)\n\(bodyPreview)"
  }
  if !title.isEmpty {
    return title
  }
  if !bodyPreview.isEmpty {
    return bodyPreview
  }
  return localized("noMemo")
}

private func memoDisplayLines(_ memo: GlanceMemoState) -> [String] {
  memoDisplayText(memo)
    .components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
}

private func lockScreenImageDataKey(_ fileName: String) -> String {
  "lock_screen_image_data.\(fileName)"
}

private func activitySizedImage(_ image: UIImage) -> UIImage {
  // Large iPad Live Activities can devote roughly 240 x 132 points to the
  // image column. Preserve enough pixels for a 2x display instead of scaling
  // the old 96 x 84 thumbnail until it looks soft.
  let size = CGSize(width: 480, height: 264)
  guard image.size.width > 0, image.size.height > 0 else {
    return image
  }
  let scale = max(size.width / image.size.width, size.height / image.size.height)
  let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
  let origin = CGPoint(
    x: (size.width - drawSize.width) / 2,
    y: (size.height - drawSize.height) / 2
  )
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  return UIGraphicsImageRenderer(size: size, format: format).image { _ in
    image.draw(in: CGRect(origin: origin, size: drawSize))
  }
}

private func compactText(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.privacyMode == "hidden" {
    return localized("hiddenContent")
  }
  if state.privacyMode == "countOnly" {
    return selectedContentSection(for: state) == "memo"
      ? "\(state.memoCount ?? state.memoItems.count)"
      : "\(max(state.totalCount - state.doneCount, 0))"
  }
  if state.privacyMode == "titleOnly" {
    return selectedContentSection(for: state) == "memo"
      ? (state.memoTitle?.isEmpty == false ? state.memoTitle! : localized("memo"))
      : localized("todo")
  }
  if isDdayLayout(state), let text = state.ddayText, !text.isEmpty {
    return text
  }
  if !state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
    return localized("allItemsHidden")
  }
  if state.showTodosOnLockScreen, let first = state.todoItems.first {
    return first.isDone ? "✓ \(first.text)" : first.text
  }
  if state.showMemosOnLockScreen, let first = state.memoItems.first {
    return first.title
  }
  if !state.showTodosOnLockScreen && state.showMemosOnLockScreen {
    return localized("noMemo")
  }
  return localized("noTasks")
}

private func compactLabel(for state: GlanceDashboardAttributes.ContentState) -> String {
  if isDdayLayout(state) {
    return localized("dday")
  }
  if !state.showTodosOnLockScreen && state.showMemosOnLockScreen {
    return localized("memo")
  }
  if state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
    return localized("todo")
  }
  if !state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
    return localized("openApp")
  }
  return localized("todo")
}

private func minimalText(for state: GlanceDashboardAttributes.ContentState) -> String {
  if isDdayLayout(state), let text = state.ddayText, !text.isEmpty {
    return text
  }
  if !state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
    return "–"
  }
  if state.showTodosOnLockScreen && !state.todoItems.isEmpty {
    return state.todoItems.first?.isDone == true ? "✓" : "□"
  }
  return "•"
}

private func dynamicIslandSymbol(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.privacyMode == "hidden" { return "lock.fill" }
  if isDdayLayout(state) { return "calendar.badge.clock" }
  if state.showTodosOnLockScreen { return "checkmark.circle" }
  return "note.text"
}

private func dynamicIslandCountText(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.privacyMode == "hidden" { return "–" }
  if state.privacyMode == "countOnly" {
    return selectedContentSection(for: state) == "memo"
      ? "\(state.memoCount ?? 0)"
      : "\(max(state.totalCount - state.doneCount, 0))"
  }
  if state.privacyMode == "titleOnly" { return "•" }
  if isDdayLayout(state), let text = state.ddayText, !text.isEmpty { return text }
  let remaining = state.todoItems.filter { !$0.isDone }.count
  if state.showTodosOnLockScreen, remaining > 0 { return "\(remaining)" }
  if state.showMemosOnLockScreen { return "Memo \(state.memoItems.count)" }
  return "–"
}

private func dynamicIslandMinimalText(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.privacyMode == "hidden" { return "–" }
  if state.privacyMode == "countOnly" {
    return selectedContentSection(for: state) == "memo"
      ? "\(state.memoCount ?? 0)"
      : "\(max(state.totalCount - state.doneCount, 0))"
  }
  if state.privacyMode == "titleOnly" { return "•" }
  if isDdayLayout(state), let text = state.ddayText, !text.isEmpty { return text }
  let remaining = state.todoItems.filter { !$0.isDone }.count
  if state.showTodosOnLockScreen { return "\(remaining)" }
  return state.showMemosOnLockScreen ? "\(state.memoItems.count)" : "–"
}

private func todoSummary(for state: GlanceDashboardAttributes.ContentState) -> String {
  if state.privacyMode == "hidden" {
    return localized("hiddenContent")
  }
  if state.privacyMode == "countOnly" {
    return "\(max(state.totalCount - state.doneCount, 0))"
  }
  if state.privacyMode == "titleOnly" {
    return localized("todo")
  }
  if isDdayLayout(state), let text = state.ddayText, !text.isEmpty {
    let title = state.ddayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return title.isEmpty ? text : "\(text) · \(title)"
  }
  if !state.showTodosOnLockScreen && !state.showMemosOnLockScreen {
    return localized("allItemsHidden")
  }
  if !state.showTodosOnLockScreen || state.todoItems.isEmpty {
    if state.showMemosOnLockScreen, let first = state.memoItems.first {
      return first.title
    }
    if !state.showTodosOnLockScreen && state.showMemosOnLockScreen {
      return localized("noMemo")
    }
    return localized("noTasks")
  }
  return state.todoItems.prefix(5)
    .map { "\($0.isDone ? "●" : "○") \($0.text)" }
    .joined(separator: " · ")
}

private func isDdayLayout(_ state: GlanceDashboardAttributes.ContentState) -> Bool {
  switch state.lockScreenLayout ?? "" {
  case "ddayMemo", "ddayTodo", "imageDday":
    return true
  default:
    return false
  }
}

private func countdownLine(for state: GlanceDashboardAttributes.ContentState) -> String? {
  guard let text = state.countdownText, !text.isEmpty else { return nil }
  if let title = state.countdownTitle, !title.isEmpty {
    return "\(title) · \(text)"
  }
  return text
}

private func activityLocale(_ state: GlanceDashboardAttributes.ContentState) -> Locale {
  guard let localeCode = state.localeCode, !localeCode.isEmpty else {
    return .current
  }
  return Locale(identifier: localeCode)
}

private func localizedMonth(_ date: Date, locale: Locale) -> String {
  let formatter = DateFormatter()
  formatter.locale = locale
  formatter.setLocalizedDateFormatFromTemplate("MMM")
  return formatter.string(from: date)
}
