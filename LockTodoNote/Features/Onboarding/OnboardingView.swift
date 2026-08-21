import SwiftUI
import LockTodoNoteShared

/// Onboarding exists to get one card onto the Lock Screen — that is the moment
/// the product makes sense. Every step is measured against that, and the user
/// can leave at any point without losing what they entered.
struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var liveActivity: LiveActivityService
    @Environment(\.palette) private var palette

    let onFinish: () -> Void

    @State private var step: Step = .intro
    @State private var todoText = ""
    @State private var startError: String?
    @State private var isStarting = false
    @State private var activationSucceeded = false
    @FocusState private var isTodoFieldFocused: Bool

    enum Step: Int, CaseIterable {
        case intro
        case firstTodo
        case activate

        var analyticsName: String {
            switch self {
            case .intro: "intro"
            case .firstTodo: "first_todo"
            case .activate: "activate"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(palette.background)
        .onAppear {
            analytics.onboardingStart()
            analytics.onboardingStepViewed(step: step.analyticsName, index: step.rawValue + 1)
        }
        .onChange(of: step) { newStep in
            analytics.onboardingStepViewed(step: newStep.analyticsName, index: newStep.rawValue + 1)
        }
        .alert(
            startError ?? "",
            isPresented: Binding(
                get: { startError != nil },
                set: { if !$0 { startError = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { startError = nil }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? palette.accent : palette.border)
                        .frame(width: item == step ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            Spacer()
            Button(appString(localized: "onboarding.skip", defaultValue: "Skip")) {
                analytics.onboardingComplete(skipped: true)
                onFinish()
            }
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("onboarding.skip")
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            StepShell(
                symbol: "lock.iphone",
                title: appString(localized: "onboarding.intro.title",
                    defaultValue: "Your day, on your Lock Screen"
                ),
                message: appString(localized: "onboarding.intro.message",
                    defaultValue: "See today's todos and memos without unlocking, and check them off right there."
                )
            ) {
                DashboardPreviewCard(snapshot: dashboard.currentSnapshot())
                    .padding(.horizontal, 24)
            }

        case .firstTodo:
            StepShell(
                symbol: "checklist",
                title: appString(localized: "onboarding.firstTodo.title",
                    defaultValue: "What's one thing for today?"
                ),
                message: appString(localized: "onboarding.firstTodo.message",
                    defaultValue: "Start with something small. You can add more later."
                )
            ) {
                TextField(
                    appString(localized: "onboarding.firstTodo.placeholder", defaultValue: "e.g. Call the clinic"),
                    text: $todoText
                )
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($isTodoFieldFocused)
                .accessibilityIdentifier("onboarding.todoField")
                .onSubmit(advance)
                .padding(.horizontal, 24)
                // Asking a question and then making the user tap to answer it
                // is a step that should not exist.
                .task { isTodoFieldFocused = true }
            }

        case .activate:
            StepShell(
                symbol: activationSucceeded ? "checkmark.circle.fill" : "sparkles",
                title: activationSucceeded
                    ? appString(localized: "onboarding.done.title", defaultValue: "You're set")
                    : appString(localized: "onboarding.activate.title",
                        defaultValue: "Put it on your Lock Screen"
                    ),
                message: activationSucceeded
                    ? appString(localized: "onboarding.done.message",
                        defaultValue: "Lock your phone to see today's card."
                    )
                    : appString(localized: "onboarding.activate.message",
                        defaultValue: "Start the real Live Activity now. You can restart it any time."
                    )
            ) {
                DashboardPreviewCard(snapshot: dashboard.currentSnapshot())
                    .padding(.horizontal, 24)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                Group {
                    if isStarting {
                        ProgressView().tint(palette.onPrimary)
                    } else {
                        Text(primaryTitle).font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(palette.onPrimary)
            .disabled(isPrimaryDisabled)
            .opacity(isPrimaryDisabled ? 0.5 : 1)
            .accessibilityIdentifier("onboarding.primary")

            if step == .activate && !activationSucceeded {
                Button(appString(localized: "onboarding.later", defaultValue: "Maybe later")) {
                    analytics.onboardingComplete(skipped: false)
                    onFinish()
                }
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
    }

    private var primaryTitle: String {
        switch step {
        case .intro: appString(localized: "onboarding.start", defaultValue: "Get started")
        case .firstTodo: appString(localized: "common.next", defaultValue: "Next")
        case .activate:
            activationSucceeded
                ? appString(localized: "onboarding.finish", defaultValue: "Done")
                : appString(localized: "liveActivity.start", defaultValue: "Show on Lock Screen")
        }
    }

    private var isPrimaryDisabled: Bool {
        if isStarting { return true }
        if step == .firstTodo {
            return todoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    // MARK: - Flow

    private func advance() {
        switch step {
        case .intro:
            step = .firstTodo
        case .firstTodo:
            saveFirstTodo()
            step = .activate
        case .activate:
            if activationSucceeded {
                analytics.onboardingComplete(skipped: false)
                onFinish()
            } else {
                Task { await activate() }
            }
        }
    }

    private func saveFirstTodo() {
        let trimmed = todoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cardStore.addTodo(text: trimmed, to: Date())
        analytics.todoCreated(
            taskCount: 1,
            remainingCount: 1,
            hasMemo: false,
            templateId: LockScreenTemplate.default.rawValue,
            source: "onboarding"
        )
        analytics.lockscreenPreviewSeen(templateId: LockScreenTemplate.default.rawValue, todoCount: 1)
    }

    private func activate() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await dashboard.startLiveActivity()
            let todos = cardStore.todoCards(on: Date()).flatMap(\.checklistItems)
            analytics.liveActivityStarted(
                taskCount: todos.count,
                remainingCount: todos.filter { !$0.isDone }.count,
                hasMemo: cardStore.pinnedMemo != nil,
                templateId: LockScreenTemplate.default.rawValue,
                source: "onboarding"
            )
            analytics.lockscreenSetupConfirmed(visible: true, todoCount: todos.count)
            activationSucceeded = true
        } catch let error as LiveActivityService.LiveActivityError {
            analytics.liveActivityStartFailed(
                reason: error.analyticsReason,
                templateId: LockScreenTemplate.default.rawValue
            )
            startError = error.errorDescription
        } catch {
            startError = error.localizedDescription
        }
    }
}

// MARK: - Pieces

private struct StepShell<Extra: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var extra: Extra

    @Environment(\.palette) private var palette

    init(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 32)
            extra
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }
}
