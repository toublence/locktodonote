import Foundation
import StoreKit
import LockTodoNoteShared

/// Owns Pro state, backed by StoreKit 2.
///
/// `Transaction.currentEntitlements` is the source of truth. The cached value
/// only carries the app through a launch with no network; it is replaced as
/// soon as StoreKit answers. This is what lets an existing subscriber install
/// the SwiftUI build and keep Pro without doing anything.
@MainActor
final class PurchaseService: ObservableObject, EntitlementProviding {
    @Published private(set) var entitlement: Entitlement
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadFailed = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var introOfferEligibleProductIds: Set<String> = []

    private let defaults: UserDefaults?
    private var updatesTask: Task<Void, Never>?
    var onEntitlementChanged: ((Entitlement, StoreKit.Transaction?) -> Void)?

    var isPro: Bool { entitlement.isPro }

    init(store: AppGroupStore = AppGroupStore()) {
        let defaults = store.defaults
        self.defaults = defaults
        var cached = Entitlement(
            cachedJSON: defaults?.string(forKey: FlutterPreferenceKeys.purchaseState)
        )
        cached.temporaryTrialActive = Self.isTrialActive(defaults: defaults)
        self.entitlement = cached

        // A purchase can complete while the app is backgrounded, or an
        // interrupted one can resume; without this listener it would never be
        // acknowledged and StoreKit would keep retrying it.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var best: StoreKit.Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard
                ProductIdentifiers.isSupported(transaction.productID),
                transaction.revocationDate == nil,
                transaction.expirationDate.map({ $0 > Date() }) ?? true
            else { continue }
            if let current = best,
               ProductIdentifiers.priority(current.productID)
                >= ProductIdentifiers.priority(transaction.productID) {
                continue
            }
            best = transaction
        }
        apply(best)
    }

    private func apply(_ transaction: StoreKit.Transaction?) {
        var updated = Entitlement(
            isPro: transaction != nil,
            productId: transaction?.productID,
            purchasedAt: transaction?.purchaseDate,
            expirationDate: transaction?.expirationDate,
            source: "storekit2_verified"
        )
        updated.temporaryTrialActive = Self.isTrialActive(defaults: defaults)
        entitlement = updated

        if updated.isPro, let json = updated.cachedJSON {
            defaults?.set(json, forKey: FlutterPreferenceKeys.purchaseState)
        } else {
            defaults?.removeObject(forKey: FlutterPreferenceKeys.purchaseState)
        }
        onEntitlementChanged?(updated, transaction)
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        productLoadFailed = false
        do {
            let loaded = try await Product.products(for: ProductIdentifiers.allSet)
            products = loaded.sorted {
                let lhs = ProductIdentifiers.all.firstIndex(of: $0.id) ?? .max
                let rhs = ProductIdentifiers.all.firstIndex(of: $1.id) ?? .max
                return lhs < rhs
            }
            var eligibleIds: Set<String> = []
            for product in products where freeTrial(for: product) != nil {
                if await product.subscription?.isEligibleForIntroOffer == true {
                    eligibleIds.insert(product.id)
                }
            }
            introOfferEligibleProductIds = eligibleIds
            productLoadFailed = products.isEmpty
        } catch {
            products = []
            introOfferEligibleProductIds = []
            productLoadFailed = true
        }
        isLoadingProducts = false
    }

    /// Whichever yearly identifier the store actually returned.
    var yearlyProduct: Product? {
        products.first { ProductIdentifiers.isYearly($0.id) }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == ProductIdentifiers.monthly }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == ProductIdentifiers.lifetime }
    }

    /// Percentage saved by paying yearly instead of twelve monthly charges.
    var yearlySavingsPercent: Int? {
        guard
            let yearly = yearlyProduct,
            let monthly = monthlyProduct,
            monthly.price > 0
        else { return nil }
        let perMonth = yearly.price / 12
        guard perMonth < monthly.price else { return nil }
        let ratio = (1 - perMonth / monthly.price) * 100
        let percent = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return percent > 0 ? percent : nil
    }

    /// Introductory free trial attached to a subscription, if one is configured.
    func freeTrial(for product: Product) -> Product.SubscriptionPeriod? {
        guard
            let offer = product.subscription?.introductoryOffer,
            offer.paymentMode == .freeTrial
        else { return nil }
        return offer.period
    }

    func isEligibleForFreeTrial(_ product: Product) -> Bool {
        introOfferEligibleProductIds.contains(product.id)
    }

    // MARK: - Purchase

    enum PurchaseOutcome: Equatable {
        case success
        case cancelled
        /// Awaiting approval, e.g. Ask to Buy.
        case pending
        case failed(String)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !isPurchasing else { return .failed("purchase_in_progress") }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed(
                        appString(localized: "purchase.unverified",
                            defaultValue: "This purchase could not be verified."
                        )
                    )
                }
                await transaction.finish()
                await refreshEntitlement()
                // Match the Flutter build: StoreKit's entitlement sequence can
                // lag just behind a verified purchase update. Keep the verified
                // transaction as the immediate fallback so a paid customer is
                // never dismissed back into a locked app.
                if !entitlement.isPro {
                    apply(transaction)
                }
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("unknown_result")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum RestoreOutcome: Equatable {
        case restored
        case noPurchases
        case failed
    }

    /// Restores by syncing with the App Store, then re-reading entitlements.
    /// A sync failure stays distinct from an account with no purchases, as it
    /// did in the Flutter build.
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            return .failed
        }
        await refreshEntitlement()
        return entitlement.isPro ? .restored : .noPurchases
    }

    // MARK: - Temporary trial

    var canStartTemporaryTrial: Bool {
        !entitlement.isPro
            && !(defaults?.bool(forKey: FlutterPreferenceKeys.temporaryProTrialClaimed) ?? false)
            && !Self.isTrialActive(defaults: defaults)
    }

    func startTemporaryTrial() {
        guard canStartTemporaryTrial else { return }
        activateTrial()
    }

    /// Installing the widget earns its own 24 hours, even if the paywall
    /// preview was already used.
    func grantWidgetInstallTrial() {
        guard !entitlement.isPro else { return }
        activateTrial()
    }

    private func activateTrial() {
        let expiry = Date().addingTimeInterval(24 * 60 * 60)
        defaults?.set(FlutterDate.utcString(from: expiry), forKey: FlutterPreferenceKeys.temporaryProTrialExpiresAt)
        defaults?.set(true, forKey: FlutterPreferenceKeys.temporaryProTrialClaimed)
        entitlement.temporaryTrialActive = true
    }

    func refreshTrialState() {
        entitlement.temporaryTrialActive = Self.isTrialActive(defaults: defaults)
    }

    private static func isTrialActive(defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        if let stored = defaults.string(forKey: FlutterPreferenceKeys.temporaryProTrialExpiresAt),
           let expiry = FlutterDate.parse(stored),
           expiry > Date() {
            return true
        }
        // Pre-expiry-date builds stored only the day the trial was taken.
        let legacyDay = defaults.string(forKey: FlutterPreferenceKeys.legacyTemporaryProDay)
        return legacyDay == FlutterDate.dateKey(Date())
    }

    func canUse(_ feature: ProFeature) -> Bool {
        entitlement.canUse(feature)
    }
}
