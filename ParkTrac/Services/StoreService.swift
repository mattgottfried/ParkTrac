import StoreKit
import Observation

@Observable
final class StoreService {
    static let shared = StoreService()

    static let removeAdsProductID = "com.mattgottfried.parktrac.removeads"

    private(set) var isAdFree: Bool = false
    private(set) var adsReady: Bool = false
    private(set) var removeAdsProduct: Product?
    private(set) var isPurchasing: Bool = false
    private(set) var purchaseError: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        isAdFree = UserDefaults.standard.bool(forKey: "isAdFree")
        transactionListener = listenForTransactions()
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.removeAdsProductID])
            removeAdsProduct = products.first
        } catch {
            // Products unavailable in simulator — silent
        }
    }

    // MARK: - Purchase

    func purchase() async {
        if removeAdsProduct == nil { await loadProducts() }
        guard let product = removeAdsProduct else {
            purchaseError = "Product unavailable. Make sure you're connected to the internet."
            return
        }
        isPurchasing = true
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    setAdFree(true)
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        isPurchasing = false
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        var hasActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.removeAdsProductID,
               transaction.revocationDate == nil {
                hasActiveEntitlement = true
                break
            }
        }
        setAdFree(hasActiveEntitlement)
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == Self.removeAdsProductID {
                    await transaction.finish()
                    self?.setAdFree(true)
                }
            }
        }
    }

    func markAdsReady() {
        adsReady = true
    }

    // MARK: - Persist

    private func setAdFree(_ value: Bool) {
        isAdFree = value
        UserDefaults.standard.set(value, forKey: "isAdFree")
    }
}
