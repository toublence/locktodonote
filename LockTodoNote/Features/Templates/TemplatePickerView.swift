import SwiftUI
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
            ProTemplateInfoSheet(template: template) {
                infoTemplate = nil
                environment.requestPaywall(source: "lock_screen_template")
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
            analytics.proInfoSheetViewed(template.rawValue)
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
    let onUpgrade: () -> Void

    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(template.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 12)

                DashboardPreviewCard(snapshot: previewSnapshot)

                Text(template.proDescription)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 24)

                Spacer()

                Button(action: onUpgrade) {
                    Text(appString(localized: "template.usePro", defaultValue: "Use with Pro"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
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
        .onAppear { analytics.proPreviewViewed(template.rawValue) }
    }

    private var previewSnapshot: DashboardSnapshot {
        var snapshot = dashboard.currentSnapshot()
        snapshot.lockScreenLayout = template.rawValue
        return snapshot
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
        case .calendarItems, .dateMemo, .dateTodo:
            ""
        }
    }
}
