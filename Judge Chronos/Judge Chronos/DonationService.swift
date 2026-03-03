import Foundation
import StoreKit

@MainActor
final class DonationService: ObservableObject {
    static let shared = DonationService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseMessage: String?

    let donationProductIds = ["tip.small", "tip.medium", "tip.large"]
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: donationProductIds)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            purchaseMessage = "Could not load donations."
            products = []
        }
    }

    func purchase(productId: String) async {
        guard let product = products.first(where: { $0.id == productId }) else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchaseMessage = "Thank you for your support."
            case .userCancelled:
                purchaseMessage = "Purchase cancelled."
            case .pending:
                purchaseMessage = "Purchase is pending approval."
            @unknown default:
                purchaseMessage = "Unknown purchase result."
            }
        } catch {
            purchaseMessage = "Purchase failed. Please try again."
        }
    }

    func clearMessage() {
        purchaseMessage = nil
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await update in Transaction.updates {
                do {
                    let transaction = try checkVerified(update)
                    await transaction.finish()
                } catch {
                    continue
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw DonationError.verificationFailed
        }
    }
}

enum DonationError: Error {
    case verificationFailed
}

