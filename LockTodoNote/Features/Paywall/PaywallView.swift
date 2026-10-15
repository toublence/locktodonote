import StoreKit
import SwiftUI
import LockTodoNoteShared

/// The paywall.
///
/// Yearly is preselected and carries the savings badge because it is the plan
/// worth steering toward; the close button is always visible and every price is
/// shown in full, so nothing here depends on the user missing something.
struct PaywallView: View {
    let source: String

    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedProductId: String?
    @State private var message: String?
    @State private var isRestoring = false
    @State private var didLogPaywallSeen = false
    @State private var didCompletePurchase = false
    @State private var showingAppliedConfirmation = false
    @State private var isAwaitingApproval = false
    @State private var showsLifetime = false
    @State private var hasAppliedPreview = false

    private var preview: ProPreviewDraft? { environment.pendingProPreview }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let preview {
                        DashboardPreviewCard(
                            snapshot: preview.snapshot,
                            height: 190,
                            previewImageData: preview.imageData
                        )
                    }
                    if AdPolicy.isEnabled {
                        Label(
                            bilingualString(korean: "Pro에서는 광고 없이 사용", english: "Ad-free with Pro"),
                            systemImage: "hand.raised.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    }
                    benefits
                    productList
                    footer
                }
                .padding(20)
                .frame(maxWidth: sizeClass == .regular ? 560 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .background(palette.background)
            .safeAreaInset(edge: .bottom) { purchaseBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(appString(localized: "common.close", defaultValue: "Close"))
                    .accessibilityIdentifier("paywall.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(appString(localized: "paywall.restore", defaultValue: "Restore")) {
                        Task { await restore() }
                    }
                    .disabled(isRestoring || purchases.isPurchasing)
                }
            }
        }
        .task {
            if !didLogPaywallSeen {
                didLogPaywallSeen = true
                analytics.paywallSeen(source: source)
            }
            if purchases.products.isEmpty { await purchases.loadProducts() }
            selectDefaultProduct()
        }
        .alert(
            message ?? "",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { message = nil }
        }
        .alert(
            bilingualString(korean: "Pro가 적용되었습니다.", english: "Pro has been applied."),
            isPresented: $showingAppliedConfirmation
        ) {
            Button(appString(localized: "common.done", defaultValue: "Done")) { dismiss() }
        } message: {
            Text(bilingualString(
                korean: hasAppliedPreview ? "잠금화면에서 새 카드를 확인해보세요." : "이제 Pro 기능을 사용할 수 있습니다.",
                english: hasAppliedPreview ? "Check your new card on the Lock Screen." : "Your Pro features are ready to use."
            ))
        }
        .accessibilityIdentifier("paywall.root")
        .onDisappear {
            if !didCompletePurchase {
                environment.recordPaywallDismissal()
                analytics.paywallDismissed(
                    source: source,
                    previewTemplate: preview?.template.rawValue
                )
            }
            if !isAwaitingApproval && !didCompletePurchase { environment.clearPendingProPreview() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(purchaseContext.title)
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text(purchaseContext.detail)
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary)
        }
    }

    private var purchaseContext: (title: String, detail: String, icon: String) {
        if source == "smart_lock_screen" {
            return (
                bilingualString(korean: "시간에 맞춰 잠금화면을 전환하세요", english: "Let your Lock Screen follow your day"),
                bilingualString(korean: "아침·업무·저녁마다 저장 구성과 표시할 할 일·메모를 자동으로 전환하세요. Live Activity의 백그라운드 갱신은 iOS 실행 허용에 따라 지연될 수 있습니다.", english: "Switch saved layouts and selected tasks or notes by time of day. Live Activity background updates depend on iOS execution and may be delayed."),
                "clock.arrow.2.circlepath"
            )
        }
        if source == "smart_repeat" {
            return (
                bilingualString(korean: "복잡한 반복도 한 번만 설정하세요", english: "Set complex repeats once"),
                bilingualString(
                    korean: "월·수·금, 매월 마지막 금요일, 격주 화요일, 매 3일 간격까지 Pro로 관리하세요.",
                    english: "Schedule selected weekdays, the last Friday of each month, alternate Tuesdays and every three days with Pro."
                ),
                "repeat"
            )
        }
        if source == "apple_reminders_sync" {
            return (
                bilingualString(korean: "할 일을 두 번 입력하지 마세요", english: "Enter your tasks just once"),
                bilingualString(
                    korean: "Apple 미리알림의 할 일을 잠금화면으로 가져오고, 완료 상태를 원본에도 반영하세요.",
                    english: "Bring Apple Reminders to your Lock Screen and sync completion back to the original."
                ),
                "checklist"
            )
        }
        if source == "theme_color" {
            return (
                appString(localized: "paywall.benefit.themes", defaultValue: "All accent themes"),
                bilingualString(korean: "원하는 색상으로 잠금화면과 앱을 꾸미세요.", english: "Use your preferred accent across the app and Lock Screen."),
                "paintpalette"
            )
        }
        if source == "layout_profile_limit" {
            return (
                bilingualString(korean: "업무와 개인 구성을 저장하고 바로 바꾸세요", english: "Save layouts and switch between work and life"),
                bilingualString(korean: "여러 잠금화면 구성을 다시 만들 필요 없이 사용하세요.", english: "Keep multiple Lock Screen layouts ready without recreating them."),
                "rectangle.stack"
            )
        }
        if source == "shortcut_limit_reached" {
            return (
                bilingualString(korean: "하루 입력 제한 없이 빠르게 기록하세요", english: "Capture without a daily limit"),
                appString(localized: "paywall.benefit.shortcutsDetail", defaultValue: "Free is five captures a day. Pro has no limit."),
                "bolt"
            )
        }
        if let template = preview?.template {
            if template.usesImage {
                return (
                    bilingualString(korean: "내 사진과 기록을 잠금화면에 표시하세요", english: "Keep your photo and notes on the Lock Screen"),
                    appString(localized: "paywall.benefit.imageDetail", defaultValue: "Put a photo beside your todos or memo."),
                    "photo"
                )
            }
            if template.usesDday {
                return (
                    bilingualString(korean: "중요한 날과 기억할 내용을 함께 확인하세요", english: "Keep the day that matters in view"),
                    appString(localized: "paywall.benefit.ddayDetail", defaultValue: "Track the day that matters, right on the Lock Screen."),
                    "calendar.badge.clock"
                )
            }
            return (template.displayName, template.proDescription, template.symbolName)
        }
        return (
            appString(localized: "paywall.title", defaultValue: "Make your Lock Screen yours"),
            appString(localized: "paywall.subtitle", defaultValue: "Photos, D-Day countdowns, and unlimited Shortcuts."),
            "sparkles"
        )
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(
                icon: purchaseContext.icon,
                title: purchaseContext.title,
                detail: purchaseContext.detail
            )
            BenefitRow(
                icon: "rectangle.stack",
                title: bilingualString(korean: "여러 잠금화면 구성 저장", english: "Multiple saved layouts"),
                detail: bilingualString(korean: "무료는 1개, Pro는 여러 구성을 저장하고 전환합니다.", english: "Free saves one layout. Pro saves and switches between multiple layouts.")
            )
            if source != "smart_lock_screen" {
                BenefitRow(
                    icon: "clock.arrow.2.circlepath",
                    title: "Smart Lock Screen",
                    detail: bilingualString(korean: "요일과 시간대에 따라 저장 구성과 표시 항목 전환", english: "Switch saved layouts and selected content by weekday and time")
                )
            }
            if source != "smart_repeat" {
                BenefitRow(
                    icon: "repeat",
                    title: "Smart Repeat",
                    detail: bilingualString(korean: "요일 조합·매월 마지막 요일·격주·N일 간격 반복", english: "Selected weekdays, last weekday of the month, alternate weeks and N-day intervals")
                )
            }
            if source != "apple_reminders_sync" {
                BenefitRow(
                    icon: "checklist",
                    title: bilingualString(korean: "Apple 미리알림 연동", english: "Apple Reminders sync"),
                    detail: bilingualString(
                        korean: "할 일을 다시 입력하지 않고 잠금화면에서 확인하고 완료하세요.",
                        english: "See and complete existing reminders without entering tasks twice."
                    )
                )
            }
            BenefitRow(
                icon: "bolt",
                title: appString(localized: "paywall.benefit.shortcuts", defaultValue: "Unlimited Shortcuts"),
                detail: appString(localized: "paywall.benefit.shortcutsDetail",
                    defaultValue: "Free is five captures a day. Pro has no limit."
                )
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.premiumSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.premiumBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var productList: some View {
        if purchases.isLoadingProducts {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if purchases.productLoadFailed {
            VStack(spacing: 12) {
                Text(
                    appString(localized: "paywall.loadFailed",
                        defaultValue: "Prices could not be loaded. Check your connection and try again."
                    )
                )
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)

                Button(appString(localized: "common.retry", defaultValue: "Try again")) {
                    Task {
                        await purchases.loadProducts()
                        selectDefaultProduct()
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(displayProducts, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isSelected: selectedProductId == product.id,
                        badge: badge(for: product),
                        trialText: trialText(for: product),
                        savingsText: savingsText(for: product)
                    ) {
                        guard selectedProductId != product.id else { return }
                        selectedProductId = product.id
                        logPlanSelected(product, isDefault: false)
                    }
                }
                if let product = purchases.lifetimeProduct {
                    DisclosureGroup(isExpanded: $showsLifetime) {
                        ProductCard(
                            product: product,
                            isSelected: selectedProductId == product.id,
                            badge: nil, trialText: nil, savingsText: nil
                        ) {
                            guard selectedProductId != product.id else { return }
                            selectedProductId = product.id
                            logPlanSelected(product, isDefault: false)
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(bilingualString(korean: "평생 이용권 보기", english: "See lifetime access"))
                            .font(.subheadline)
                    }
                    .onChange(of: showsLifetime) { expanded in
                        if !expanded && selectedProductId == product.id {
                            selectedProductId = nil
                            selectDefaultProduct()
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                appString(localized: "paywall.renewalNote",
                    defaultValue: "Subscriptions renew automatically until cancelled. Manage them in Settings."
                )
            )
            .font(.caption)
            .foregroundStyle(palette.textTertiary)

            HStack(spacing: 16) {
                Link(
                    appString(localized: "settings.terms", defaultValue: "Terms of Use"),
                    destination: LegalLinks.termsOfUse
                )
                Link(
                    appString(localized: "settings.privacy", defaultValue: "Privacy Policy"),
                    destination: LegalLinks.privacyPolicy
                )
            }
            .font(.caption)
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if purchases.isPurchasing {
                        ProgressView().tint(palette.onPrimary)
                    } else {
                        VStack(spacing: 2) {
                            Text(ctaTitle)
                                .font(.headline)
                            if let ctaDetail {
                                Text(ctaDetail).font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(palette.onPrimary)
            .disabled(selectedProduct == nil || purchases.isPurchasing)
            .opacity(selectedProduct == nil ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    // MARK: - Actions

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedProductId }
    }

    private var displayProducts: [Product] {
        // Keep both legacy annual IDs valid for restoration, but sell one annual choice.
        [purchases.yearlyProduct, purchases.monthlyProduct].compactMap { $0 }
    }

    /// Yearly first — the plan with the best value per month.
    private func selectDefaultProduct() {
        guard selectedProductId == nil else { return }
        guard let product = purchases.yearlyProduct ?? purchases.products.first else { return }
        selectedProductId = product.id
        showsLifetime = product.id == ProductIdentifiers.lifetime
        logPlanSelected(product, isDefault: true)
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        let attemptId = UUID().uuidString
        let isTrial = purchases.isEligibleForFreeTrial(product)
        let previewTemplate = preview?.template.rawValue
        if isTrial {
            analytics.trialCTATapped(
                productId: product.id,
                source: source,
                previewTemplate: previewTemplate
            )
        }
        analytics.purchaseStarted(
            productId: product.id,
            source: source,
            price: product.price,
            currency: product.priceFormatStyle.currencyCode,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
        switch await purchases.purchase(product) {
        case .success:
            analytics.isPremium = purchases.isPro
            analytics.purchaseCompleted(
                productId: product.id,
                source: source,
                price: product.price,
                currency: product.priceFormatStyle.currencyCode,
                isTrial: isTrial,
                previewTemplate: previewTemplate,
                attemptId: attemptId
            )
            didCompletePurchase = true
            let application = await environment.applyPendingProValue()
            hasAppliedPreview = application.valueApplied
            if application.succeeded {
                if application.valueApplied && previewTemplate != nil {
                    analytics.purchaseValueApplied(
                        productId: product.id,
                        source: source,
                        price: product.price,
                        currency: product.priceFormatStyle.currencyCode,
                        isTrial: isTrial,
                        previewTemplate: previewTemplate,
                        attemptId: attemptId
                    )
                }
                showingAppliedConfirmation = true
            } else {
                message = application.recoveryMessage
            }
        case .cancelled:
            analytics.purchaseCancelled(
                productId: product.id, source: source, price: product.price,
                currency: product.priceFormatStyle.currencyCode, isTrial: isTrial,
                previewTemplate: previewTemplate, attemptId: attemptId
            )
        case .pending:
            isAwaitingApproval = true
            environment.registerPendingPurchase(
                productId: product.id,
                source: source,
                price: product.price,
                currency: product.priceFormatStyle.currencyCode,
                isTrial: isTrial,
                previewTemplate: previewTemplate,
                attemptId: attemptId
            )
            analytics.purchasePending(
                productId: product.id,
                source: source,
                attemptId: attemptId,
                previewTemplate: previewTemplate
            )
            message = appString(localized: "purchase.pending",
                defaultValue: "Your purchase is waiting for approval."
            )
        case .failed(let detail):
            analytics.purchaseFailed(
                productId: product.id, source: source, price: product.price,
                currency: product.priceFormatStyle.currencyCode, isTrial: isTrial,
                previewTemplate: previewTemplate, attemptId: attemptId
            )
            message = detail
        }
    }

    private func restore() async {
        isRestoring = true
        let outcome = await purchases.restore()
        isRestoring = false
        analytics.restoreCompleted(result: restoreResult(outcome))
        switch outcome {
        case .restored:
            analytics.isPremium = purchases.isPro
            didCompletePurchase = true
            let application = await environment.applyPendingProValue()
            hasAppliedPreview = application.valueApplied
            if application.succeeded {
                showingAppliedConfirmation = true
            } else {
                message = application.recoveryMessage
            }
        case .noPurchases:
            message = appString(localized: "restore.empty",
                defaultValue: "No previous purchase was found for this Apple Account."
            )
        case .failed:
            message = appString(localized: "restore.failed",
                defaultValue: "Purchases could not be restored. Please try again."
            )
        }
    }

    private func restoreResult(_ outcome: PurchaseService.RestoreOutcome) -> String {
        switch outcome {
        case .restored: "restored"
        case .noPurchases: "no_purchases"
        case .failed: "fail"
        }
    }

    private func badge(for product: Product) -> String? {
        guard ProductIdentifiers.isYearly(product.id) else { return nil }
        return appString(localized: "paywall.bestValue", defaultValue: "Best Value")
    }

    private func trialText(for product: Product) -> String? {
        guard purchases.isEligibleForFreeTrial(product),
              let period = purchases.freeTrial(for: product) else { return nil }
        if ProductIdentifiers.isYearly(product.id), period.unit == .day {
            return bilingualString(
                korean: "\(period.value)일간 무료 체험",
                english: "\(period.value)-day free trial"
            )
        }
        let unit: String
        switch period.unit {
        case .day: unit = appString(localized: "period.day", defaultValue: "day")
        case .week: unit = appString(localized: "period.week", defaultValue: "week")
        case .month: unit = appString(localized: "period.month", defaultValue: "month")
        case .year: unit = appString(localized: "period.year", defaultValue: "year")
        @unknown default: return nil
        }
        return String(
            format: appString(localized: "paywall.freeTrial", defaultValue: "%d-%@ free trial"),
            period.value,
            unit
        )
    }

    private func savingsText(for product: Product) -> String? {
        guard ProductIdentifiers.isYearly(product.id),
              let percent = purchases.yearlySavingsPercent else { return nil }
        return bilingualString(korean: "\(percent)% 절약", english: "Save \(percent)%")
    }

    private func logPlanSelected(_ product: Product, isDefault: Bool) {
        analytics.planSelected(
            productId: product.id,
            source: source,
            price: product.price,
            currency: product.priceFormatStyle.currencyCode,
            isTrial: purchases.isEligibleForFreeTrial(product),
            isDefault: isDefault,
            previewTemplate: preview?.template.rawValue
        )
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return "" }
        if purchases.isEligibleForFreeTrial(product),
           let period = purchases.freeTrial(for: product) {
            return bilingualString(
                korean: "\(period.value)\(periodUnit(period.unit)) 무료로 시작",
                english: "Start \(period.value)-\(periodUnit(period.unit)) free trial"
            )
        }
        switch ProductIdentifiers.Kind(productId: product.id) {
        case .yearly:
            return bilingualString(korean: "연 \(product.displayPrice)로 시작", english: "Start for \(product.displayPrice)/year")
        case .monthly:
            return bilingualString(korean: "월 \(product.displayPrice)로 시작", english: "Start for \(product.displayPrice)/month")
        case .lifetime:
            return bilingualString(korean: "\(product.displayPrice) 한 번 결제", english: "\(product.displayPrice) one-time purchase")
        case nil:
            return product.displayPrice
        }
    }

    private var ctaDetail: String? {
        guard let product = selectedProduct,
              purchases.isEligibleForFreeTrial(product) else { return nil }
        if ProductIdentifiers.isYearly(product.id) {
            return bilingualString(korean: "이후 연 \(product.displayPrice)", english: "Then \(product.displayPrice)/year")
        }
        if product.id == ProductIdentifiers.monthly {
            return bilingualString(korean: "이후 월 \(product.displayPrice)", english: "Then \(product.displayPrice)/month")
        }
        return nil
    }

    private func periodUnit(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return bilingualString(korean: "일", english: "day")
        case .week: return bilingualString(korean: "주", english: "week")
        case .month: return bilingualString(korean: "개월", english: "month")
        case .year: return bilingualString(korean: "년", english: "year")
        @unknown default: return ""
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let trialText: String?
    let savingsText: String?
    let onTap: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? palette.accent : palette.textTertiary)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(palette.accent, in: Capsule())
                                .foregroundStyle(palette.onPrimary)
                        }
                    }
                    if let trialText {
                        Text(trialText)
                            .font(.caption)
                            .foregroundStyle(palette.success)
                    }
                    if let savingsText {
                        Text(savingsText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.accent)
                    }
                    if let perMonth {
                        Text(perMonth)
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? palette.accentSoft : palette.surface)
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
    }

    private var title: String {
        switch ProductIdentifiers.Kind(productId: product.id) {
        case .monthly: appString(localized: "product.monthly", defaultValue: "Monthly")
        case .yearly: appString(localized: "product.yearly", defaultValue: "Yearly")
        case .lifetime: appString(localized: "product.lifetime", defaultValue: "Lifetime")
        case nil: product.displayName
        }
    }

    /// Only meaningful for the yearly plan, where the monthly equivalent is the
    /// number people actually compare.
    private var perMonth: String? {
        guard ProductIdentifiers.isYearly(product.id) else { return nil }
        let monthly = product.price / 12
        let formatted = monthly.formatted(product.priceFormatStyle)
        return String(
            format: appString(localized: "product.perMonth", defaultValue: "%@ per month"),
            formatted
        )
    }
}
