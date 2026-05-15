//
//  PurchaseManager.swift
//  ChineseLawsSearch
//
//  StoreKit 2 购买管理 + 免费次数追踪。
//
//  两种订阅套餐（App Store Connect 中配置）：
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │ 套餐          Product ID                      类型    建议价格   │
//  │ ─────────────────────────────────────────────────────────────── │
//  │ 订阅版月订阅   com.doxie.laws.pro.monthly      月订阅   ¥38/月   │
//  │ 订阅版年订阅   com.doxie.laws.pro.yearly       年订阅   ¥298/年  │
//  │   包含内置 Key，每月 150 次，每月 1 日自动重置                    │
//  └──────────────────────────────────────────────────────────────────┘
//
//  权限模型：
//    .free(remaining)       — 新用户 5 次免费体验，可用法律顾问和公报内容
//    .pro(remaining: Int)   — 订阅用户，本月剩余次数（满 150 次/月）
//    .noAccess              — 免费用完且未订阅，法律顾问和公报内容均锁定
//
//  免费体验次数和月度配额均存于 UserDefaults（本地）。
//  追问回答不消耗次数。
//

import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Product IDs

enum AgentProductID {
    static let proMonthly  = "com.doxie.laws.pro.monthly"
    static let proYearly   = "com.doxie.laws.pro.yearly"

    static let all: [String] = [proMonthly, proYearly]
    static let proIDs: Set<String> = [proMonthly, proYearly]
}

// MARK: - Access state

enum AgentAccess {
    /// 免费体验次数尚有剩余
    case free(remaining: Int)
    /// 订阅用户，本月剩余次数
    case pro(remaining: Int)
    /// 无权限（免费用完且未订阅）
    case noAccess
}

// MARK: - PurchaseManager

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // ---------------------------------------------------------------
    // MARK: - 调试开关（上线前务必确认所有开关状态）
    //
    // paymentEnabled = false → 完全绕过付费，mockAccess 生效
    //
    // mockAccess：paymentEnabled = false 时模拟的权限状态
    //   .free(remaining: 5)   → 模拟有免费次数
    //   .pro(remaining: 150)  → 模拟订阅用户
    //   .noAccess             → 模拟未订阅且免费用完
    // ---------------------------------------------------------------
    static let paymentEnabled: Bool      = false
    #if DEBUG
    static let mockAccess: AgentAccess   = .pro(remaining: 150)
    #else
    static let mockAccess: AgentAccess   = .noAccess
    #endif
    static let proMonthlyTotal: Int      = 150   // 订阅用户每月额度

    private let freeTotal: Int           = 5

    // MARK: - UserDefaults keys
    private let ud = UserDefaults.standard
    private let freeCountKey    = "agent_free_uses_remaining"
    private let freeInitedKey   = "agent_free_inited"
    private let proCountKey     = "agent_pro_uses_remaining"
    private let proMonthKey     = "agent_pro_quota_month"   // "YYYY-MM"

    // MARK: - Published state
    @Published private(set) var products:      [Product] = []
    @Published private(set) var hasPRO:        Bool = false
    @Published private(set) var freeRemaining: Int  = 0
    @Published private(set) var proRemaining:  Int  = 0

    private enum ConsumedPath { case free, pro, none }
    private var lastConsumedPath: ConsumedPath = .none

    private var updateListenerTask: Task<Void, Never>?

    init() {
        freeRemaining = remainingFreeUses()
        proRemaining  = remainingProUses()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await refreshPurchaseStatus() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Access control

    var access: AgentAccess {
        if !Self.paymentEnabled { return Self.mockAccess }
        let free = freeRemaining
        if free > 0 { return .free(remaining: free) }
        if hasPRO   { return .pro(remaining: proRemaining) }
        return .noAccess
    }

    /// 是否有权限查看公报详情（免费期或订阅中）
    var canViewGazetteDetail: Bool {
        switch access {
        case .free, .pro: return true
        case .noAccess:   return false
        }
    }

    /// 调用 Agent 前调用；有权限则消耗计数并返回 true（追问传 isFollowUp=true 不消耗）
    func consumeIfAllowed(isFollowUp: Bool = false) -> Bool {
        lastConsumedPath = .none
        if !Self.paymentEnabled {
            switch Self.mockAccess {
            case .noAccess: return false
            default:        return true
            }
        }
        if isFollowUp {
            switch access {
            case .free, .pro: return true
            case .noAccess:   return false
            }
        }
        let free = remainingFreeUses()
        if free > 0 {
            let newVal = free - 1
            ud.set(newVal, forKey: freeCountKey)
            freeRemaining = max(0, newVal)
            lastConsumedPath = .free
            return true
        }
        if hasPRO {
            let pro = remainingProUses()
            if pro > 0 {
                let newVal = pro - 1
                ud.set(newVal, forKey: proCountKey)
                proRemaining = max(0, newVal)
                lastConsumedPath = .pro
                return true
            }
            // 月度配额用完
            return false
        }
        return false
    }

    /// 网络失败等不可控错误时退还已消耗的计数。
    func refundIfNeeded() {
        if !Self.paymentEnabled { return }
        switch lastConsumedPath {
        case .free:
            let current  = ud.integer(forKey: freeCountKey)
            let restored = min(current + 1, freeTotal)
            ud.set(restored, forKey: freeCountKey)
            freeRemaining = restored
        case .pro:
            let current  = ud.integer(forKey: proCountKey)
            let restored = min(current + 1, Self.proMonthlyTotal)
            ud.set(restored, forKey: proCountKey)
            proRemaining = restored
        case .none:
            break
        }
        lastConsumedPath = .none
    }

    // MARK: - StoreKit: load products

    func loadProducts() async {
        guard let fetched = try? await Product.products(for: AgentProductID.all) else { return }
        let order = [AgentProductID.proYearly, AgentProductID.proMonthly]
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
        if !ud.bool(forKey: freeInitedKey) {
            ud.set(freeTotal, forKey: freeCountKey)
            ud.set(true, forKey: freeInitedKey)
        }
        return ud.integer(forKey: freeCountKey)
    }

    private func remainingProUses() -> Int {
        let currentMonth = Self.currentMonthString()
        if ud.string(forKey: proMonthKey) != currentMonth {
            ud.set(Self.proMonthlyTotal, forKey: proCountKey)
            ud.set(currentMonth, forKey: proMonthKey)
        }
        return ud.integer(forKey: proCountKey)
    }

    private static func currentMonthString() -> String {
        let cal = Calendar.current
        let now = Date()
        let y   = cal.component(.year, from: now)
        let m   = cal.component(.month, from: now)
        return String(format: "%04d-%02d", y, m)
    }

    func refreshPurchaseStatus() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result) else { continue }
            if AgentProductID.proIDs.contains(t.productID) { pro = true }
        }
        hasPRO        = pro
        freeRemaining = remainingFreeUses()
        proRemaining  = remainingProUses()
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
