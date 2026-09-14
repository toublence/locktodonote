import Foundation
import SwiftUI
import UIKit
import LockTodoNoteShared

/// App-side rendering of the same snapshot sent to ActivityKit. Callers may
/// inject clearly marked preview-only content without writing it to storage.
struct DashboardPreviewCard: View {
    let snapshot: DashboardSnapshot
    var height: CGFloat = 152
    var previewImageData: Data? = nil

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            switch LockScreenTemplate(fromStored: snapshot.lockScreenLayout) {
            case .calendarItems:
                split(leadingRatio: 0.34) {
                    PreviewCalendar(snapshot: snapshot)
                } trailing: {
                    PreviewItems(snapshot: snapshot, mode: selectedMode)
                }
            case .memoTodo:
                split(leadingRatio: 0.5) {
                    PreviewItems(snapshot: snapshot, mode: .memo)
                } trailing: {
                    PreviewItems(snapshot: snapshot, mode: .todo)
                }
            case .dateMemo, .dateTodo:
                split(leadingRatio: 0.3) {
                    PreviewDate(snapshot: snapshot)
                } trailing: {
                    PreviewItems(snapshot: snapshot, mode: selectedMode)
                }
            case .imageMemo, .imageTodo:
                split(leadingRatio: 0.36) {
                    PreviewImage(fileName: snapshot.imageFileName, previewImageData: previewImageData)
                } trailing: {
                    PreviewItems(snapshot: snapshot, mode: selectedMode)
                }
            case .ddayMemo:
                split(leadingRatio: 0.34) {
                    PreviewDday(snapshot: snapshot)
                } trailing: {
                    PreviewItems(snapshot: snapshot, mode: .memo)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .topLeading)
        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            appString(localized: "preview.lockScreen", defaultValue: "Current Lock Screen preview")
        )
    }

    private var selectedMode: PreviewContentMode {
        if snapshot.selectedContentSection == "memo", snapshot.showMemosOnLockScreen {
            return .memo
        }
        return snapshot.showTodosOnLockScreen ? .todo : .memo
    }

    private func split<Leading: View, Trailing: View>(
        leadingRatio: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leadingView = leading()
        let trailingView = trailing()
        return GeometryReader { proxy in
            let spacing: CGFloat = 10
            let available = proxy.size.width - spacing * 2 - 1
            HStack(alignment: .top, spacing: spacing) {
                leadingView
                    .frame(width: available * leadingRatio, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                Divider().overlay(Color.white.opacity(0.18))
                trailingView
                    .frame(width: available * (1 - leadingRatio), alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private enum PreviewContentMode: Equatable {
    case todo
    case memo
}

private struct PreviewCalendar: View {
    let snapshot: DashboardSnapshot

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(monthTitle)
                .font(.caption.bold())
                .lineLimit(1)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(snapshot.calendarDays) { day in
                    ZStack(alignment: .bottom) {
                        Text("\(day.day)")
                            .font(.system(size: 8.5, weight: day.isSelected ? .bold : .medium))
                            .foregroundStyle(day.isCurrentMonth ? Color.white : Color.white.opacity(0.35))
                            .frame(maxWidth: .infinity, minHeight: 13)
                            .background(
                                day.isSelected ? Color(red: 0.56, green: 0.67, blue: 1) : .clear,
                                in: Capsule()
                            )
                        Circle()
                            .fill(day.hasItems ? Color.white.opacity(0.8) : .clear)
                            .frame(width: 2, height: 2)
                    }
                    .frame(height: 14)
                }
            }
        }
    }

    private var monthTitle: String {
        guard let date = snapshot.selectedDate else { return snapshot.calendarTitle ?? "" }
        return date.formatted(.dateTime.month(.wide).locale(appLocale()))
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return [] }
        return symbols
    }
}

private struct PreviewItems: View {
    let snapshot: DashboardSnapshot
    let mode: PreviewContentMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: mode == .todo ? "checklist" : "square.and.pencil")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if snapshot.privacyMode == PrivacyMode.hidden.rawValue {
                privacySummary(
                    appString(localized: "privacy.hidden", defaultValue: "Hidden"),
                    systemImage: "lock.fill"
                )
            } else if snapshot.privacyMode == PrivacyMode.countOnly.rawValue {
                privacySummary(
                    mode == .todo
                        ? "\(max(snapshot.totalCount - snapshot.doneCount, 0))"
                        : "\(snapshot.memoCount)",
                    systemImage: "number"
                )
            } else if snapshot.privacyMode == PrivacyMode.titleOnly.rawValue {
                privacySummary(
                    mode == .memo && snapshot.memoTitle?.isEmpty == false
                        ? snapshot.memoTitle!
                        : title,
                    systemImage: mode == .todo ? "checklist" : "note.text"
                )
            } else if mode == .todo {
                if snapshot.todoItems.isEmpty {
                    emptyText(appString(localized: "home.noTodos", defaultValue: "No todos yet"))
                } else {
                    ForEach(snapshot.todoItems.prefix(5)) { item in
                        HStack(spacing: 5) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                            Text(item.text)
                                .font(.caption)
                                .lineLimit(1)
                                .strikethrough(item.isDone)
                        }
                    }
                }
            } else if snapshot.memoItems.isEmpty {
                emptyText(appString(localized: "home.noMemos", defaultValue: "No memos yet"))
            } else {
                ForEach(snapshot.memoItems.prefix(4)) { memo in
                    HStack(spacing: 5) {
                        Image(systemName: "note.text").font(.caption2)
                        Text(memo.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var title: String {
        mode == .todo
            ? appString(localized: "home.todos", defaultValue: "Todos")
            : appString(localized: "home.memos", defaultValue: "Memos")
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private func privacySummary(_ value: String, systemImage: String) -> some View {
        Label(value, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct PreviewDate: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 2) {
            Text(
                snapshot.selectedDate?.formatted(
                    .dateTime.month(.abbreviated).locale(appLocale())
                ) ?? ""
            )
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(dayText)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
            Text(
                snapshot.selectedDate?.formatted(
                    .dateTime.weekday(.abbreviated).locale(appLocale())
                ) ?? ""
            )
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dayText: String {
        guard let date = snapshot.selectedDate else { return "•" }
        return "\(Calendar.current.component(.day, from: date))"
    }
}

private struct PreviewImage: View {
    let fileName: String?
    let previewImageData: Data?

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = previewImageData.flatMap(UIImage.init(data:))
                    ?? LockScreenImageStore(store: environment.appGroup).image(fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(Color.white.opacity(0.1))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PreviewDday: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 5) {
            Text("D-DAY")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(snapshot.ddayText?.isEmpty == false ? snapshot.ddayText! : "D-Day")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            if let title = snapshot.ddayTitle, !title.isEmpty {
                Text(title)
                    .font(.caption2.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
