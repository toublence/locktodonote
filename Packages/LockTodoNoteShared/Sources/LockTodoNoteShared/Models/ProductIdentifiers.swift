import Foundation

/// App Store product identifiers.
///
/// `yealy` is a typo that shipped and is now the live identifier — correcting
/// it would orphan every existing subscriber. The corrected spelling is queried
/// alongside it because the Flutter build did the same, so whichever one App
/// Store Connect actually holds will resolve.
public enum ProductIdentifiers {
    public static let monthly = "com.namslab.glancecard.monthly"
    public static let yearlyLegacy = "com.namslab.glancecard.yealy"
    public static let yearlyCorrected = "com.namslab.glancecard.yearly"
    public static let lifetime = "com.namslab.glancecard.lifetime"

    public static let yearlyValues: Set<String> = [yearlyLegacy, yearlyCorrected]

    /// Query order also drives paywall ordering.
    public static let all: [String] = [monthly, yearlyLegacy, yearlyCorrected, lifetime]
    public static let allSet = Set(all)

    public static func isYearly(_ id: String) -> Bool { yearlyValues.contains(id) }
    public static func isSupported(_ id: String) -> Bool { allSet.contains(id) }

    /// Lifetime outranks yearly outranks monthly when several are held.
    public static func priority(_ id: String) -> Int {
        if id == lifetime { return 3 }
        if isYearly(id) { return 2 }
        if id == monthly { return 1 }
        return 0
    }

    public enum Kind: Sendable {
        case monthly
        case yearly
        case lifetime

        public init?(productId: String) {
            if productId == ProductIdentifiers.monthly { self = .monthly }
            else if ProductIdentifiers.isYearly(productId) { self = .yearly }
            else if productId == ProductIdentifiers.lifetime { self = .lifetime }
            else { return nil }
        }
    }
}

/// The Pro state the app trusts. Derived from StoreKit, never from a local flag
/// alone — a cached `isPro` is a fallback for offline launches only.
public struct Entitlement: Equatable, Sendable {
    public var isPro: Bool
    public var productId: String?
    public var purchasedAt: Date?
    public var expirationDate: Date?
    public var source: String

    /// One-time 24-hour preview. Unlocks Pro templates but not themes,
    /// customization, or unlimited Shortcuts.
    public var temporaryTrialActive: Bool

    public static let none = Entitlement(
        isPro: false,
        productId: nil,
        purchasedAt: nil,
        expirationDate: nil,
        source: "",
        temporaryTrialActive: false
    )

    public init(
        isPro: Bool,
        productId: String?,
        purchasedAt: Date?,
        expirationDate: Date?,
        source: String,
        temporaryTrialActive: Bool = false
    ) {
        self.isPro = isPro
        self.productId = productId
        self.purchasedAt = purchasedAt
        self.expirationDate = expirationDate
        self.source = source
        self.temporaryTrialActive = temporaryTrialActive
    }

    public var kind: ProductIdentifiers.Kind? {
        productId.flatMap(ProductIdentifiers.Kind.init(productId:))
    }

    public func canUse(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        if temporaryTrialActive { return feature.unlockedByTemporaryTrial }
        return false
    }

    // MARK: - Local cache (offline fallback)

    public init(cachedJSON: String?) {
        guard
            let cachedJSON,
            let data = cachedJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            self = .none
            return
        }
        let productId = object["productId"] as? String
        let expiration = FlutterDate.parse(object["expirationDate"] as? String)
        let expired = expiration.map { $0 <= Date() } ?? false
        let supported = productId.map(ProductIdentifiers.isSupported) ?? false
        self.init(
            isPro: (object["isPro"] as? Bool ?? false) && supported && !expired,
            productId: productId,
            purchasedAt: FlutterDate.parse(object["purchasedAt"] as? String),
            expirationDate: expiration,
            source: object["source"] as? String ?? ""
        )
    }

    public var cachedJSON: String? {
        var object: [String: Any] = ["isPro": isPro, "source": source]
        if let productId { object["productId"] = productId }
        if let purchasedAt { object["purchasedAt"] = FlutterDate.utcString(from: purchasedAt) }
        if let expirationDate { object["expirationDate"] = FlutterDate.utcString(from: expirationDate) }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
