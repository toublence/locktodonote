import PhotosUI
import SwiftUI
import LockTodoNoteShared

/// The home tab: what is on the Lock Screen right now, and the fastest path to
/// changing it. Capture stays one tap away, as it was in the Flutter build.
struct LockScreenTabView: View {
    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var liveActivity: LiveActivityService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.palette) private var palette

    @State private var editingCard: Card?
    @State private var editingTodo: TodoEntry?
    @State private var isEditingDday = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoSelectionTemplate: LockScreenTemplate?
    @State private var errorMessage: String?
    @State private var captureMode: QuickAddMode = .todo
    @State private var captureText = ""
    @State private var captureRecurrence: TodoRecurrence = .none
    @State private var captureConfirmation: String?
    @State private var infoTemplate: LockScreenTemplate?
    @State private var showsCompletedTodos = false
    @State private var isTemplatePreviewExpanded = true
    @FocusState private var isCaptureFocused: Bool

    private var today: Date { Date() }
    private var template: LockScreenTemplate { settingsStore.settings.template }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 24 : 16) {
                templateSection
                quickCapture
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
            .padding(.bottom, horizontalSizeClass == .regular ? 36 : 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("home.scroll")
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .sheet(item: $editingCard) { card in
            MemoEditorSheet(card: card)
                .environment(\.palette, palette)
        }
        .sheet(item: $editingTodo) { entry in
            TodoEditorSheet(entry: entry)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $isEditingDday) {
            DdayEditorSheet()
                .environment(\.palette, palette)
        }
        .sheet(item: $infoTemplate) { template in
            ProTemplateInfoSheet(template: template) { draft in
                infoTemplate = nil
                environment.requestPaywall(
                    source: "lock_screen_template",
                    preview: draft
                )
            }
            .environment(\.palette, palette)
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onAppear {
            captureMode = settingsStore.settings.selectedContentSection == .memo ? .memo : .todo
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { errorMessage = nil }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                templateControl

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTemplatePreviewExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isTemplatePreviewExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.templateSection.toggle")
            }

            if isTemplatePreviewExpanded {
                DashboardPreviewCard(snapshot: dashboard.currentSnapshot())
                    .onAppear {
                        let snapshot = dashboard.currentSnapshot()
                        analytics.lockscreenPreviewSeen(
                            templateId: snapshot.lockScreenLayout,
                            todoCount: snapshot.todoItems.count
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            LiveActivityStatusRow(
                state: liveActivity.state,
                hasStartedBefore: environment.appGroup.defaults?.bool(
                    forKey: FlutterPreferenceKeys.liveActivityStarted
                ) ?? false,
                onStart: { await startLiveActivity() },
                onUpdate: { await dashboard.updateLiveActivity() }
            )

            if template.usesImage {
                ImageSlotCard(
                    fileName: settingsStore.settings.activeImageFileName,
                    photoItem: $photoItem
                )
            }

            if template.usesDday {
                DdaySummaryCard(
                    title: settingsStore.settings.ddayTitle,
                    targetDate: settingsStore.settings.ddayTargetDate,
                    text: dashboard.composer.ddayText(settingsStore.settings.ddayTargetDate)
                ) {
                    isEditingDday = true
                }
            }
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var templateControl: some View {
        HStack(spacing: 6) {
            ForEach(LockScreenTemplate.userFacingCases, id: \.self) { option in
                compactTemplateButton(option)
            }
        }
    }

    @ViewBuilder
    private func compactTemplateButton(_ option: LockScreenTemplate) -> some View {
        let isSelected = template.matchesUserFacingTemplate(option)
        let isLocked = isTemplateLocked(option)

        if option == .imageTodo, !isLocked {
            PhotosPicker(selection: $photoItem, matching: .images) {
                CompactTemplateLabel(
                    option: option,
                    isSelected: isSelected,
                    isLocked: false
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                photoSelectionTemplate = option.resolvedTemplate(
                    for: settingsStore.settings.selectedContentSection
                )
                selectTemplate(option)
            })
            .accessibilityLabel(option.displayName)
            .accessibilityIdentifier("template.\(option.rawValue)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            Button {
                selectTemplate(option)
            } label: {
                CompactTemplateLabel(
                    option: option,
                    isSelected: isSelected,
                    isLocked: isLocked
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.displayName)
            .accessibilityHint(
                isLocked
                    ? appString(localized: "template.lockedHint", defaultValue: "Requires Pro")
                    : ""
            )
            .accessibilityIdentifier("template.\(option.rawValue)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func isTemplateLocked(_ template: LockScreenTemplate) -> Bool {
        let resolved = template.resolvedTemplate(for: settingsStore.settings.selectedContentSection)
        guard let feature = resolved.proFeature else { return false }
        return !purchases.canUse(feature)
    }

    private func selectTemplate(_ template: LockScreenTemplate) {
        guard !isTemplateLocked(template) else {
            analytics.proTemplateTapped(template.rawValue)
            infoTemplate = template
            return
        }

        let resolved = template.resolvedTemplate(for: settingsStore.settings.selectedContentSection)
        settingsStore.settings.template = resolved
        if !resolved.supportsTodoAndMemo {
            setCaptureMode(.memo)
        }
        analytics.templateChanged(resolved.rawValue)
        dashboard.publish()
        if resolved.usesDday {
            isEditingDday = true
        }
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                appString(localized: "capture.type", defaultValue: "Capture type"),
                selection: captureModeBinding
            ) {
                Label(appString(localized: "home.todos", defaultValue: "Todo"), systemImage: "checklist")
                    .tag(QuickAddMode.todo)
                Label(appString(localized: "home.memos", defaultValue: "Memo"), systemImage: "square.and.pencil")
                    .tag(QuickAddMode.memo)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        captureItems
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                Spacer(minLength: 20)

                HStack(alignment: .bottom, spacing: 10) {
                    TextField(
                        appString(localized: "capture.prompt", defaultValue: "What would you like to add?"),
                        text: $captureText,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .frame(
                        minHeight: horizontalSizeClass == .regular ? 82 : 64,
                        alignment: .topLeading
                    )
                    .focused($isCaptureFocused)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("today.quickCapture")

                    Button(action: saveCapture) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(palette.accent, in: Circle())
                            .foregroundStyle(palette.onPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedCaptureText.isEmpty)
                    .opacity(trimmedCaptureText.isEmpty ? 0.45 : 1)
                    .accessibilityLabel(appString(localized: "common.save", defaultValue: "Save"))
                    .accessibilityIdentifier("today.quickCapture.save")
                }
                .padding(14)
                .background(
                    palette.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
                .padding(12)
            }
            .frame(
                height: horizontalSizeClass == .regular ? 360 : 300,
                alignment: .topLeading
            )
            .background(palette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let captureConfirmation {
                Label(captureConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.success)
                    .transition(.opacity)
            }

            if captureMode == .todo {
                HStack(spacing: 10) {
                    Text(
                        appString(localized: "quickAdd.repeat", defaultValue: "Show this todo")
                    )
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Picker("", selection: $captureRecurrence) {
                        ForEach(TodoRecurrence.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(appString(localized: "common.done", defaultValue: "Done")) {
                    saveCapture()
                    isCaptureFocused = false
                }
                .disabled(trimmedCaptureText.isEmpty)
            }
        }
        .onChange(of: isCaptureFocused) { focused in
            guard focused else { return }
            analytics.quickCaptureFocused(type: captureMode.rawValue)
        }
    }

    @ViewBuilder
    private var captureItems: some View {
        if captureMode == .todo {
            if pendingTodoItems.isEmpty &&
                (!settingsStore.settings.showCompletedTodos || completedTodoItems.isEmpty) {
                Text(appString(localized: "home.noTodos", defaultValue: "No todos for today"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ForEach(pendingTodoItems, id: \.compositeId) { entry in
                    TodoRowView(entry: entry) { isDone in
                        let saved = cardStore.setItemDone(
                            cardId: entry.card.id,
                            itemId: entry.item.id,
                            isDone: isDone
                        )
                        if saved, isDone {
                            analytics.todoCompleted(
                                taskCount: todoItems.count,
                                remainingCount: max(0, pendingTodoItems.count - 1),
                                templateId: template.rawValue
                            )
                        }
                        if !saved { reportSaveFailure(operation: "complete_todo") }
                    } onEdit: {
                        editingTodo = entry
                    } onDelete: {
                        if !cardStore.delete(id: entry.card.id) { reportSaveFailure(operation: "delete_todo") }
                    }
                }

                if settingsStore.settings.showCompletedTodos, !completedTodoItems.isEmpty {
                    DisclosureGroup(isExpanded: $showsCompletedTodos) {
                        ForEach(completedTodoItems, id: \.compositeId) { entry in
                            TodoRowView(entry: entry) { isDone in
                                if !cardStore.setItemDone(
                                    cardId: entry.card.id,
                                    itemId: entry.item.id,
                                    isDone: isDone
                                ) { reportSaveFailure(operation: "update_todo") }
                            } onEdit: {
                                editingTodo = entry
                            } onDelete: {
                                if !cardStore.delete(id: entry.card.id) { reportSaveFailure(operation: "delete_todo") }
                            }
                        }
                    } label: {
                        Text(
                            String(
                                format: appString(
                                    localized: "home.completedCount",
                                    defaultValue: "Completed %d"
                                ),
                                completedTodoItems.count
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        } else if memoCards.isEmpty {
            Text(appString(localized: "home.noMemos", defaultValue: "No memos for today"))
                .font(.subheadline)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
        } else {
            ForEach(memoCards) { card in
                MemoRowView(card: card, isPinned: card.isPinned) {
                    editingCard = card
                } onDelete: {
                    if !cardStore.delete(id: card.id) { reportSaveFailure(operation: "delete_memo") }
                }
            }
        }
    }

    private var todoItems: [TodoEntry] {
        cardStore.todoCards(on: today).flatMap { card in
            card.checklistItems.map { TodoEntry(card: card, item: $0) }
        }
    }

    private var pendingTodoItems: [TodoEntry] { todoItems.filter { !$0.item.isDone } }
    private var completedTodoItems: [TodoEntry] { todoItems.filter(\.item.isDone) }

    private var memoCards: [Card] {
        cardStore.memoCards(on: today)
    }

    private var trimmedCaptureText: String {
        captureText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var captureModeBinding: Binding<QuickAddMode> {
        Binding(
            get: { captureMode },
            set: { setCaptureMode($0) }
        )
    }

    // MARK: - Actions

    private func setCaptureMode(_ mode: QuickAddMode) {
        captureMode = mode
        settingsStore.settings.selectedContentSection = mode == .todo ? .todo : .memo
        dashboard.publish()
    }

    private func saveCapture() {
        guard !trimmedCaptureText.isEmpty else { return }

        switch captureMode {
        case .todo:
            let lines = trimmedCaptureText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            guard cardStore.addTodos(texts: lines, to: today, recurrence: captureRecurrence) else {
                reportSaveFailure(operation: "create_todo")
                return
            }
            let allTodos = cardStore.todoCards(on: today).flatMap(\.checklistItems)
            analytics.todoCreated(
                taskCount: allTodos.count,
                remainingCount: allTodos.filter { !$0.isDone }.count,
                hasMemo: !memoCards.isEmpty,
                templateId: template.rawValue,
                source: "inline"
            )
            if lines.count > 1 { analytics.multilineTodoImported(count: lines.count) }
            captureConfirmation = String(
                format: appString(localized: "capture.todosAdded", defaultValue: "%d todos added"),
                lines.count
            )
        case .memo:
            guard cardStore.addMemo(text: trimmedCaptureText, to: today) else {
                reportSaveFailure(operation: "create_memo")
                return
            }
            analytics.memoCreated(source: "inline", templateId: template.rawValue)
            captureConfirmation = appString(localized: "capture.memoAdded", defaultValue: "Memo added")
        }

        captureText = ""
    }

    private func reportSaveFailure(operation: String) {
        analytics.cardSaveFailed(operation: operation, source: "inline")
        errorMessage = appString(
            localized: "storage.writeFailed",
            defaultValue: "That change could not be saved. Your text is still here; please try again."
        )
    }

    private func startLiveActivity() async {
        let wasRunning = liveActivity.state.isRunning
        let requestId = UUID().uuidString
        analytics.liveActivityStartAttempt(
            requestId: requestId,
            source: "app",
            templateId: template.rawValue,
            reason: "user_start"
        )
        do {
            try await dashboard.startLiveActivity()
            let todos = todoItems
            analytics.liveActivityStarted(
                taskCount: todos.count,
                remainingCount: todos.filter { !$0.item.isDone }.count,
                hasMemo: !memoCards.isEmpty,
                templateId: template.rawValue,
                requestId: requestId
            )
            if wasRunning { analytics.liveActivityRestarted() }
            // The first successful Lock Screen card is the moment the app has
            // proven its value — the one place a paywall is earned.
            await environment.offerPaywallAfterFirstLockScreenSuccess()
        } catch let error as LiveActivityService.LiveActivityError {
            analytics.liveActivityStartFailed(
                reason: error.analyticsReason,
                templateId: template.rawValue,
                requestId: requestId
            )
            errorMessage = error.errorDescription
        } catch {
            analytics.liveActivityStartFailed(
                reason: "unknown",
                templateId: template.rawValue,
                requestId: requestId
            )
            errorMessage = error.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        let targetTemplate = photoSelectionTemplate ?? template
        defer {
            photoItem = nil
            photoSelectionTemplate = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = appString(localized: "image.loadFailed",
                defaultValue: "That photo could not be loaded."
            )
            return
        }
        do {
            let imageStore = LockScreenImageStore(store: environment.appGroup)
            let fileName = try imageStore.save(
                imageData: data,
                replacing: settingsStore.settings.activeImageFileName
            )
            switch targetTemplate {
            case .imageTodo: settingsStore.settings.imageTodoFileName = fileName
            default: settingsStore.settings.imageMemoFileName = fileName
            }
            settingsStore.settings.imageFileName = fileName
            dashboard.publish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TodoEntry: Identifiable {
    let card: Card
    let item: ChecklistItem

    /// The id the Lock Screen and its intents use.
    var compositeId: String { "\(card.id):\(item.id)" }
    var id: String { compositeId }
}

private struct CompactTemplateLabel: View {
    let option: LockScreenTemplate
    let isSelected: Bool
    let isLocked: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: isLocked ? "lock.fill" : option.symbolName)
                .font(.system(size: 15, weight: .semibold))
            Text(option.compactDisplayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .foregroundStyle(isSelected ? palette.onPrimary : palette.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(
            isSelected ? palette.accent : palette.surface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Cards

private struct LiveActivityStatusRow: View {
    let state: LiveActivityService.ActivityState
    let hasStartedBefore: Bool
    let onStart: () async -> Void
    let onUpdate: () async -> Void

    @Environment(\.palette) private var palette
    @State private var isWorking = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(at: context.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(detail(at: context.date))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)

                Button {
                    Task {
                        isWorking = true
                        if state.isRunning {
                            await onUpdate()
                        } else {
                            await onStart()
                        }
                        isWorking = false
                    }
                } label: {
                    if isWorking {
                        ProgressView()
                            .frame(minWidth: 72, minHeight: 36)
                    } else if state.isRunning {
                        Label(
                            appString(localized: "liveActivity.update", defaultValue: "Apply Changes"),
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 72, minHeight: 36)
                    } else {
                        Text(appString(localized: "liveActivity.startButton", defaultValue: "Start"))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(minWidth: 72, minHeight: 36)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(isUnsupported || isWorking)
            }
        }
    }

    private var isUnsupported: Bool {
        if case .unsupported = state { return true }
        return false
    }

    private var tint: Color {
        switch state {
        case .active: palette.success
        case .possiblyExpired, .ended, .missing: palette.warning
        case .notStarted, .dismissed: palette.textTertiary
        case .unsupported: palette.warning
        }
    }

    private func title(at now: Date) -> String {
        switch state {
        case .active(let startedAt):
            remainingSeconds(from: startedAt, at: now) <= 30 * 60
                ? appString(localized: "liveActivity.endingSoon", defaultValue: "Ending soon")
                : appString(localized: "liveActivity.live", defaultValue: "LIVE")
        case .possiblyExpired:
            appString(
                localized: "liveActivity.staleMessage",
                defaultValue: "Lock Screen card updates have stopped"
            )
        case .ended, .missing:
            appString(localized: "liveActivity.ended", defaultValue: "Live Activity ended")
        case .notStarted:
            hasStartedBefore
                ? appString(localized: "liveActivity.ended", defaultValue: "Live Activity ended")
                : appString(localized: "liveActivity.notConfigured", defaultValue: "No Lock Screen card yet")
        case .dismissed:
            appString(localized: "liveActivity.ended", defaultValue: "Live Activity ended")
        case .unsupported:
            appString(localized: "liveActivity.unavailable", defaultValue: "Unavailable")
        }
    }

    private func detail(at now: Date) -> String {
        switch state {
        case .active(let startedAt):
            remainingText(from: startedAt, at: now)
        case .possiblyExpired, .ended, .missing:
            appString(localized: "liveActivity.widgetContinues", defaultValue: "Today's card continues in Widget")
        case .notStarted:
            hasStartedBefore
                ? appString(localized: "liveActivity.widgetContinues",
                    defaultValue: "Today's card continues in Widget"
                )
                : appString(localized: "liveActivity.startDetail", defaultValue: "Start to see today without unlocking")
        case .dismissed:
            appString(localized: "liveActivity.startDetail", defaultValue: "Start to see today without unlocking")
        case .unsupported(let reason):
            reason == "disabled"
                ? appString(localized: "liveActivity.disabledDetail",
                    defaultValue: "Turn on Live Activities for LockTodoNote in Settings."
                )
                : appString(localized: "liveActivity.unsupportedDetail",
                    defaultValue: "This device cannot show Live Activities."
                )
        }
    }

    private func remainingSeconds(from startedAt: Date, at now: Date) -> TimeInterval {
        max(0, LiveActivityService.activityDuration - now.timeIntervalSince(startedAt))
    }

    private func remainingText(from startedAt: Date, at now: Date) -> String {
        let remaining = Int(remainingSeconds(from: startedAt, at: now))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return String(
                format: appString(localized: "liveActivity.hoursMinutesLeft", defaultValue: "%dh %dm left"),
                hours,
                minutes
            )
        }
        return String(
            format: appString(localized: "liveActivity.minutesLeft", defaultValue: "%dm left"),
            minutes
        )
    }
}

private struct TemplateSummaryCard: View {
    let template: LockScreenTemplate
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: template.symbolName)
                .font(.title2)
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(appString(localized: "home.currentTemplate", defaultValue: "Lock Screen template"))
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                Text(template.displayName)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(palette.premiumSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.premiumBorder, lineWidth: 1)
        )
    }
}

private struct ImageSlotCard: View {
    let fileName: String?
    @Binding var photoItem: PhotosPickerItem?

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        let appGroup = environment.appGroup
        PhotosPicker(selection: $photoItem, matching: .images) {
            ImageSlotLabel(fileName: fileName, appGroup: appGroup)
        }
        .buttonStyle(.plain)
    }
}

private struct ImageSlotLabel: View {
    let fileName: String?
    let appGroup: AppGroupStore

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            if let image = LockScreenImageStore(store: appGroup).image(fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.surfaceSoft)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(palette.textTertiary)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appString(localized: "home.image", defaultValue: "Lock Screen photo"))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(
                    fileName == nil
                        ? appString(localized: "home.imageEmpty", defaultValue: "Choose a photo")
                        : appString(localized: "home.imageChange", defaultValue: "Tap to change")
                )
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct DdaySummaryCard: View {
    let title: String?
    let targetDate: Date?
    let text: String?
    let onTap: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(text ?? "D-Day")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        title?.isEmpty == false
                            ? title!
                            : appString(localized: "dday.untitled", defaultValue: "Set a D-Day")
                    )
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    if let targetDate {
                        Text(appDateString(targetDate))
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TodoRowView: View {
    let entry: TodoEntry
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(!entry.item.isDone)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: entry.item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.item.isDone ? palette.success : palette.textTertiary)
                        .imageScale(.large)
                    Text(entry.item.text)
                        .foregroundStyle(entry.item.isDone ? palette.textTertiary : palette.textPrimary)
                        .strikethrough(entry.item.isDone)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if entry.item.recurrence != .none {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appString(localized: "common.edit", defaultValue: "Edit"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appString(localized: "common.delete", defaultValue: "Delete"))
        }
        .padding(.vertical, 10)
    }
}

private struct MemoRowView: View {
    let card: Card
    let isPinned: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(palette.textTertiary)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if !card.body.isEmpty, card.body != card.title {
                            Text(card.body)
                                .font(.subheadline)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(palette.accent)
                            .accessibilityLabel(
                                appString(localized: "home.pinnedMemo", defaultValue: "Shown on Lock Screen")
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appString(localized: "common.delete", defaultValue: "Delete"))
        }
        .padding(.vertical, 10)
    }
}

extension LockScreenTemplate {
    static let userFacingCases: [LockScreenTemplate] = [
        .calendarItems,
        .memoTodo,
        .dateTodo,
        .imageTodo,
        .ddayMemo,
    ]

    var supportsTodoAndMemo: Bool {
        switch self {
        case .calendarItems, .memoTodo, .dateMemo, .dateTodo, .imageMemo, .imageTodo: true
        case .ddayMemo: false
        }
    }

    func matchesUserFacingTemplate(_ option: LockScreenTemplate) -> Bool {
        switch (self, option) {
        case (.dateMemo, .dateTodo), (.dateTodo, .dateTodo),
             (.imageMemo, .imageTodo), (.imageTodo, .imageTodo): true
        default: self == option
        }
    }

    func resolvedTemplate(for section: ShortcutInsertPriority) -> LockScreenTemplate {
        switch self {
        case .dateMemo, .dateTodo:
            section == .memo ? .dateMemo : .dateTodo
        case .imageMemo, .imageTodo:
            section == .memo ? .imageMemo : .imageTodo
        default:
            self
        }
    }

    var displayName: String {
        switch self {
        case .calendarItems:
            appString(localized: "template.calendarItems", defaultValue: "Calendar + Todo · Memo")
        case .memoTodo: appString(localized: "template.memoTodo", defaultValue: "Memo + Todo")
        case .dateMemo, .dateTodo:
            appString(localized: "template.dateContent", defaultValue: "Date + Todo · Memo")
        case .imageMemo, .imageTodo:
            appString(localized: "template.imageContent", defaultValue: "Image + Todo · Memo")
        case .ddayMemo: appString(localized: "template.ddayMemo", defaultValue: "D-Day + Memo")
        }
    }

    var symbolName: String {
        switch self {
        case .calendarItems: "calendar"
        case .memoTodo: "rectangle.split.2x1"
        case .dateMemo, .dateTodo: "calendar.day.timeline.left"
        case .imageMemo, .imageTodo: "photo"
        case .ddayMemo: "calendar.badge.clock"
        }
    }

    var compactDisplayName: String {
        switch self {
        case .calendarItems:
            appString(localized: "template.short.calendar", defaultValue: "Calendar")
        case .memoTodo:
            appString(localized: "template.short.memoTodo", defaultValue: "Memo+Todo")
        case .dateMemo, .dateTodo:
            appString(localized: "template.short.date", defaultValue: "Date")
        case .imageMemo, .imageTodo:
            appString(localized: "template.short.image", defaultValue: "Image")
        case .ddayMemo:
            appString(localized: "template.short.dday", defaultValue: "D-Day")
        }
    }
}
