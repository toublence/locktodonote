import SwiftUI
import PhotosUI
import LockTodoNoteShared

/// Template chooser. Tapping a Pro template does not jump straight to the
/// paywall — it explains what that template does first, which is both fairer
/// and measurably better at converting than an abrupt wall.
struct TemplatePickerView: View {
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @Environment(\.palette) private var palette

    @State private var infoTemplate: LockScreenTemplate?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(LockScreenTemplate.userFacingCases, id: \.self) { template in
                    TemplateCard(
                        template: template,
                        isSelected: settingsStore.settings.template.matchesUserFacingTemplate(template),
                        isLocked: isLocked(template)
                    ) {
                        select(template)
                    }
                }
            }
            .padding(20)
        }
        .background(palette.background)
        .navigationTitle(appString(localized: "template.title", defaultValue: "Lock Screen template"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
    }

    private func isLocked(_ template: LockScreenTemplate) -> Bool {
        let resolved = template.resolvedTemplate(for: settingsStore.settings.selectedContentSection)
        guard let feature = resolved.proFeature else { return false }
        return !purchases.canUse(feature)
    }

    private func select(_ template: LockScreenTemplate) {
        guard !isLocked(template) else {
            analytics.proTemplateTapped(template.rawValue)
            infoTemplate = template
            return
        }
        let resolved = template.resolvedTemplate(for: settingsStore.settings.selectedContentSection)
        settingsStore.settings.template = resolved
        analytics.templateChanged(resolved.rawValue)
        dashboard.publish()
    }
}

private struct TemplateCard: View {
    let template: LockScreenTemplate
    let isSelected: Bool
    let isLocked: Bool
    let onTap: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isLocked ? "lock.fill" : template.symbolName)
                        .font(.title3)
                        .foregroundStyle(isLocked ? palette.textTertiary : palette.accent)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
                Text(template.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                if template.requiresPro {
                    Text(appString(localized: "template.pro", defaultValue: "Pro"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(palette.accentSoft, in: Capsule())
                        .foregroundStyle(palette.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            isLocked
                ? appString(localized: "template.lockedHint", defaultValue: "Requires Pro")
                : ""
        )
    }
}

/// Explains one Pro template before asking for money.
struct ProTemplateInfoSheet: View {
    let template: LockScreenTemplate
    let onUpgrade: (ProPreviewDraft) -> Void

    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var previewTitle = bilingualString(korean: "여행", english: "Trip")
    @State private var previewMemo = bilingualString(
        korean: "여권과 충전기 챙기기",
        english: "Pack your passport and charger"
    )
    @State private var previewDate = Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImageData: Data?
    @State private var didLogPreview = false
    @State private var didInteract = false
    @State private var photoError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(template.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 12)

                DashboardPreviewCard(
                    snapshot: previewSnapshot,
                    previewImageData: previewImageData
                )
                .onAppear {
                    guard !didLogPreview else { return }
                    didLogPreview = true
                    analytics.proPreviewViewed(template.rawValue)
                }

                if template == .imageMemo || template == .imageTodo {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            bilingualString(korean: "사진 선택", english: "Choose a photo"),
                            systemImage: "photo.on.rectangle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: photoItem) { item in
                        guard let item else { return }
                        Task {
                            do {
                                guard let data = try await item.loadTransferable(type: Data.self) else {
                                    throw PhotoPreviewError.emptyData
                                }
                                previewImageData = data
                                trackInteraction()
                            } catch {
                                photoError = appString(
                                    localized: "image.loadFailed",
                                    defaultValue: "That photo could not be loaded. Please choose another one."
                                )
                            }
                        }
                    }
                }

                if template == .ddayMemo {
                    VStack(spacing: 12) {
                        TextField(
                            bilingualString(korean: "제목", english: "Title"),
                            text: $previewTitle
                        )
                        DatePicker(
                            bilingualString(korean: "날짜", english: "Date"),
                            selection: $previewDate,
                            displayedComponents: .date
                        )
                        TextField(
                            bilingualString(korean: "메모", english: "Memo"),
                            text: $previewMemo,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: previewTitle) { _ in trackInteraction() }
                    .onChange(of: previewMemo) { _ in trackInteraction() }
                    .onChange(of: previewDate) { _ in trackInteraction() }
                }

                VStack(spacing: 3) {
                    Text(bilingualString(korean: "미리보기입니다.", english: "This is a preview."))
                    Text(bilingualString(
                        korean: "Pro 구매 후 잠금화면에 적용됩니다.",
                        english: "It will be applied to your Lock Screen after purchasing Pro."
                    ))
                }
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)

                Text(template.proDescription)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 24)

                Spacer()

                Button { onUpgrade(previewDraft) } label: {
                    VStack(spacing: 2) {
                        Text(template.proCTA)
                            .font(.headline)
                        Text(appString(localized: "template.includedInPro", defaultValue: "Included with LockTodoNote Pro"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(palette.onPrimary)

                Button(appString(localized: "common.notNow", defaultValue: "Not now")) { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, 8)
            }
            .padding(20)
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(appString(localized: "common.close", defaultValue: "Close"))
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            environment.isProInfoPresented = true
            analytics.proInfoSheetViewed(template.rawValue)
        }
        .onDisappear { environment.isProInfoPresented = false }
        .alert(
            photoError ?? "",
            isPresented: Binding(
                get: { photoError != nil },
                set: { if !$0 { photoError = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { photoError = nil }
        }
    }

    private var previewSnapshot: DashboardSnapshot {
        var snapshot = dashboard.currentSnapshot()
        snapshot.lockScreenLayout = template.rawValue
        if template == .ddayMemo {
            snapshot.selectedDate = previewDate
            snapshot.selectedDateText = appDateString(previewDate)
            snapshot.ddayTargetDate = previewDate
            snapshot.ddayTitle = previewTitle.isEmpty
                ? bilingualString(korean: "제목을 입력하세요", english: "Enter a title")
                : previewTitle
            snapshot.ddayText = dashboard.composer.ddayText(previewDate)
            let memo = previewMemo.isEmpty
                ? bilingualString(korean: "메모를 입력하세요", english: "Enter a memo")
                : previewMemo
            snapshot.ddayMemo = memo
            snapshot.memoItems = [DashboardMemoItem(id: "preview-dday", title: memo, bodyPreview: memo)]
            snapshot.memoTitle = memo
            snapshot.memoText = memo
        }
        if (template == .memoTodo || template == .imageTodo), snapshot.todoItems.isEmpty {
            snapshot.todoItems = [
                DashboardTodoItem(
                    id: "preview-todo",
                    text: bilingualString(korean: "할 일 미리보기", english: "Todo preview"),
                    isDone: false
                )
            ]
            snapshot.totalCount = 1
            snapshot.doneCount = 0
        }
        if (template == .memoTodo || template == .imageMemo), snapshot.memoItems.isEmpty {
            let placeholder = bilingualString(korean: "메모 미리보기", english: "Memo preview")
            snapshot.memoItems = [
                DashboardMemoItem(id: "preview-memo", title: placeholder, bodyPreview: placeholder)
            ]
            snapshot.memoTitle = placeholder
            snapshot.memoText = placeholder
        }
        return snapshot
    }

    private var previewDraft: ProPreviewDraft {
        ProPreviewDraft(
            template: template,
            snapshot: previewSnapshot,
            imageData: previewImageData,
            ddayTitle: template == .ddayMemo ? previewTitle : nil,
            ddayDate: template == .ddayMemo ? previewDate : nil,
            ddayMemo: template == .ddayMemo ? previewMemo : nil
        )
    }

    private func trackInteraction() {
        guard !didInteract else { return }
        didInteract = true
        analytics.proPreviewInteracted(template.rawValue)
    }
}

extension LockScreenTemplate: @retroactive Identifiable {
    public var id: String { rawValue }

    var proDescription: String {
        switch self {
        case .memoTodo:
            appString(localized: "template.memoTodo.description",
                defaultValue: "Keep a memo and your todos on one card, and switch between them without unlocking."
            )
        case .imageMemo:
            appString(localized: "template.imageMemo.description",
                defaultValue: "Pair a photo with your memo so the Lock Screen feels like yours."
            )
        case .imageTodo:
            appString(localized: "template.imageTodo.description",
                defaultValue: "Pair a photo with today's todos."
            )
        case .ddayMemo:
            appString(localized: "template.ddayMemo.description",
                defaultValue: "Count down to the day that matters, with a note beside it."
            )
        case .dateMemo, .dateTodo:
            appString(localized: "template.date.description",
                defaultValue: "Show a selected date with its todos or memo on the Lock Screen."
            )
        case .calendarItems:
            ""
        }
    }

    var proCTA: String {
        switch self {
        case .ddayMemo:
            appString(localized: "template.useDday", defaultValue: "Use D-Day card")
        case .imageMemo, .imageTodo:
            appString(localized: "template.useImage", defaultValue: "Use image card")
        case .memoTodo:
            appString(localized: "template.useMemoTodo", defaultValue: "Use Memo + Todo card")
        case .calendarItems, .dateMemo, .dateTodo:
            appString(localized: "template.usePro", defaultValue: "Use this card")
        }
    }
}

private enum PhotoPreviewError: Error {
    case emptyData
}
