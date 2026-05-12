//
//  PurchaseManager.swift
//  ChineseLawsSearch
//
//  StoreKit 2 购买管理 + 免费次数追踪。
//
//  Product IDs (App Store Connect 中配置):
//    com.doxie.chineseLawsAgent.lifetime   — 买断 ¥198
//    com.doxie.chineseLawsAgent.monthly    — 月订阅 ¥6
//    com.doxie.chineseLawsAgent.yearly     — 年订阅 ¥50
//
//  免费次数存在 iCloud KV Store，多设备共享同一配额。
//

import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Product IDs

enum AgentProductID {
    static let lifetime = "com.doxie.chineseLawsAgent.lifetime"
    static let monthly  = "com.doxie.chineseLawsAgent.monthly"
    static let yearly   = "com.doxie.chineseLawsAgent.yearly"

    static let all: [String] = [lifetime, monthly, yearly]
}

// MARK: - Access state

enum AgentAccess {
    case free(remaining: Int)   // 有免费次数剩余
    case paid                   // 买断或订阅有效
    case noAccess               // 免费用完且未购买
}

// MARK: - PurchaseManager

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    private let kv = NSUbiquitousKeyValueStore.default
    private let freeCountKey   = "agent_free_uses_remaining"
    private let freeTotal      = 20

    @Published private(set) var products:    [Product] = []
    @Published private(set) var isPurchased: Bool = false
    @Published private(set) var freeRemaining: Int = 0

    private var updateListenerTask: Task<Void, Never>?

    init() {
        freeRemaining = remainingFreeUses()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await refreshPurchaseStatus() }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.freeRemaining = self?.remainingFreeUses() ?? 0
            }
        }
        kv.synchronize()
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: - Access control

    var access: AgentAccess {
        if isPurchased { return .paid }
        let r = freeRemaining
        return r > 0 ? .free(remaining: r) : .noAccess
    }

    /// 调用一次 agent 之前检查；如果有权限则消耗一次免费次数并返回 true。
    func consumeIfAllowed() -> Bool {
        if isPurchased { return true }
        let r = remainingFreeUses()
        guard r > 0 else { return false }
        let newVal = r - 1
        kv.set(Int64(newVal), forKey: freeCountKey)
        kv.synchronize()
        freeRemaining = newVal
        return true
    }

    // MARK: - StoreKit: load products

    func loadProducts() async {
        guard let fetched = try? await Product.products(for: AgentProductID.all) else { return }
        // sort: lifetime first, then yearly, then monthly
        let order = [AgentProductID.lifetime, AgentProductID.yearly, AgentProductID.monthly]
        products = fetched.sorted {
            (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99)
        }
    }

    // MARK: - StoreKit: purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshPurchaseStatus()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - StoreKit: restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshPurchaseStatus()
    }

    // MARK: - Internal

    private func remainingFreeUses() -> Int {
        let stored = kv.object(forKey: freeCountKey)
        if stored == nil {
            // First time: initialise to freeTotal
            kv.set(Int64(freeTotal), forKey: freeCountKey)
            kv.synchronize()
            return freeTotal
        }
        return Int(kv.longLong(forKey: freeCountKey))
    }

    func refreshPurchaseStatus() async {
        var hasPaid = false
        for await result in Transaction.currentEntitlements {
            if let t = try? checkVerified(result),
               AgentProductID.all.contains(t.productID) {
                hasPaid = true
            }
        }
        isPurchased = hasPaid
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let t = try? checkVerified(result) {
                    await t.finish()
                    await self.refreshPurchaseStatus()
                }
            }
        }
    }
}

private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified: throw StoreError.failedVerification
    case .verified(let safe): return safe
    }
}

enum StoreError: Error { case failedVerification }
