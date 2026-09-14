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
                    Label(
                        bilingualString(
                            korean: "광고 없음 · 내 할 일은 나만의 것",
                            english: "No ads · Your tasks stay yours"
                        ),
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
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
                korean: "잠금화면에서 새 카드를 확인해보세요.",
                english: "Check your new card on the Lock Screen."
            ))
        }
        .onDisappear {
            if !didCompletePurchase {
                analytics.paywallDismissed(
                    source: source,
                    previewTemplate: preview?.template.rawValue
                )
            }
            if !isAwaitingApproval { environment.clearPendingProPreview() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview == nil
                ? appString(localized: "paywall.title", defaultValue: "Make your Lock Screen yours")
                : bilingualString(korean: "이 잠금화면을 계속 사용하세요", english: "Keep this Lock Screen")
            )
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text(
                preview == nil
                    ? appString(localized: "paywall.subtitle",
                        defaultValue: "Make your Lock Screen yours — photos, D-Day countdowns, and unlimited Shortcuts."
                    )
                    : bilingualString(
                        korean: "사진, D-Day, 메모와 할 일을\n나만의 잠금화면으로 만들어보세요.",
                        english: "Use photos, D-Day, notes, and todos\nto make your Lock Screen your own."
                    )
            )
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary)
        }
    }

    /// Ordered by how much each feature actually drives upgrades.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(
                icon: "photo",
                title: appString(localized: "paywall.benefit.image", defaultValue: "Photo templates"),
                detail: appString(localized: "paywall.benefit.imageDetail",
                    defaultValue: "Put a photo beside your todos or memo."
                )
            )
            BenefitRow(
                icon: "calendar.badge.clock",
                title: appString(localized: "paywall.benefit.dday", defaultValue: "D-Day countdown"),
                detail: appString(localized: "paywall.benefit.ddayDetail",
                    defaultValue: "Track the day that matters, right on the Lock Screen."
                )
            )
            BenefitRow(
                icon: "rectangle.split.2x1",
                title: appString(localized: "paywall.benefit.memoTodo", defaultValue: "Memo + Todo layout"),
                detail: appString(localized: "paywall.benefit.memoTodoDetail",
                    defaultValue: "See both at once, switchable from the Lock Screen."
                )
            )
            BenefitRow(
                icon: "bolt",
                title: appString(localized: "paywall.benefit.shortcuts", defaultValue: "Unlimited Shortcuts"),
                detail: appString(localized: "paywall.benefit.shortcutsDetail",
                    defaultValue: "Free is five captures a day. Pro has no limit."
                )
            )
            BenefitRow(
                icon: "paintpalette",
                title: appString(localized: "paywall.benefit.themes", defaultValue: "All accent themes"),
                detail: nil
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
        purchases.products.sorted { productRank($0) < productRank($1) }
    }

    private func productRank(_ product: Product) -> Int {
        if ProductIdentifiers.isYearly(product.id) { return 0 }
        if product.id == ProductIdentifiers.monthly { return 1 }
        return 2
    }

    /// Yearly first — the plan with the best value per month.
    private func selectDefaultProduct() {
        guard selectedProductId == nil else { return }
        guard let product = purchases.yearlyProduct ?? purchases.products.first else { return }
        selectedProductId = product.id
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
            if application.succeeded {
                if previewTemplate != nil {
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
                message = appString(localized: "purchase.applyFailed", defaultValue: "Pro was purchased, but the preview could not be applied. You can apply it again from Settings.")
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
            if application.succeeded {
                showingAppliedConfirmation = true
            } else {
                message = appString(
                    localized: "purchase.applyFailed",
                    defaultValue: "Pro was restored, but the preview could not be applied. Please try again."
                )
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
              purchases.isEligibleForFreeTrial(product),
              ProductIdentifiers.isYearly(product.id) else { return nil }
        return bilingualString(korean: "이후 연 \(product.displayPrice)", english: "Then \(product.displayPrice)/year")
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
