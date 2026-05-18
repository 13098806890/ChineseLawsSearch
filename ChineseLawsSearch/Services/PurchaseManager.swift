//
//  PurchaseManager.swift
//  ChineseLawsSearch
//
//  StoreKit 2 购买管理 + 免费次数 + 月度配额追踪。
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
//    .free(remaining)       — 新用户 5 次免费体验
//    .pro(remaining: Int)   — 订阅用户，本月剩余次数
//    .noAccess              — 免费用完且未订阅
//
//  安全设计：
//    - 免费次数存 UserDefaults（5 次损失可接受）
//    - 月度配额（count + month）序列化为单条 JSON，存设备本地 Keychain
//      (.thisDeviceOnly, 不同步 iCloud，防止明文篡改)
//    - paymentEnabled 由编译条件控制，Release 包强制走真实逻辑
//    - 时间篡改检测在 LegalChatViewModel 中通过 iCloud KV 的 lastSendTime 实现
//    - 追问回答不消耗次数
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
    // MARK: - 编译条件控制
    // ---------------------------------------------------------------

    static let proMonthlyTotal: Int = 150

    private let freeTotal: Int = 5

    // MARK: - Storage keys
    private let ud = UserDefaults.standard
    private let freeCountKey    = "agent_free_uses_remaining"
    private let freeInitedKey   = "agent_free_inited"
    // Keychain key — stores JSON {"count": Int, "month": "YYYY-MM"} atomically
    private let proQuotaKeychainKey = "agent_pro_quota_v1"

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
        proRemaining  = loadProQuota().count
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await refreshPurchaseStatus() }
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: - Access control

    var access: AgentAccess {
        let free = freeRemaining
        if free > 0 { return .free(remaining: free) }
        if hasPRO   { return .pro(remaining: proRemaining) }
        return .noAccess
    }

    var canViewGazetteDetail: Bool {
        switch access {
        case .pro: return true
        case .free, .noAccess: return false
        }
    }

    /// 调用 Agent 前调用；有权限则消耗计数并返回 true。
    /// 追问传 isFollowUp=true 不消耗次数。
    func consumeIfAllowed(isFollowUp: Bool = false) -> Bool {
        lastConsumedPath = .none
        if isFollowUp {
            switch access {
            case .free, .pro: return true
            case .noAccess:   return false
            }
        }
        // 优先消耗免费次数
        let free = remainingFreeUses()
        if free > 0 {
            let newVal = free - 1
            ud.set(newVal, forKey: freeCountKey)
            freeRemaining = newVal
            lastConsumedPath = .free
            return true
        }
        // 消耗订阅月度配额
        if hasPRO {
            var quota = loadProQuota()
            if quota.count > 0 {
                quota.count -= 1
                saveProQuota(quota)
                proRemaining = quota.count
                lastConsumedPath = .pro
                return true
            }
            return false   // 本月配额已用完
        }
        return false
    }

    /// 网络失败等不可控错误时退还已消耗的计数。
    func refundIfNeeded() {
        switch lastConsumedPath {
        case .free:
            let restored = min(ud.integer(forKey: freeCountKey) + 1, freeTotal)
            ud.set(restored, forKey: freeCountKey)
            freeRemaining = restored
        case .pro:
            var quota = loadProQuota()
            quota.count = min(quota.count + 1, Self.proMonthlyTotal)
            saveProQuota(quota)
            proRemaining = quota.count
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

    // MARK: - Internal: free uses (UserDefaults — low value, acceptable risk)

    private func remainingFreeUses() -> Int {
        if !ud.bool(forKey: freeInitedKey) {
            ud.set(freeTotal, forKey: freeCountKey)
            ud.set(true, forKey: freeInitedKey)
        }
        return ud.integer(forKey: freeCountKey)
    }

    // MARK: - Internal: pro quota (Keychain — atomic JSON blob)

    private struct ProQuota: Codable {
        var count: Int
        var month: String   // "YYYY-MM"
    }

    private func loadProQuota() -> ProQuota {
        let currentMonth = Self.currentMonthString()
        if let data = KeychainHelper.loadLocalData(forKey: proQuotaKeychainKey),
           let quota = try? JSONDecoder().decode(ProQuota.self, from: data),
           quota.month == currentMonth {
            return quota
        }
        // New month (or first launch) — reset to full quota
        let fresh = ProQuota(count: Self.proMonthlyTotal, month: currentMonth)
        saveProQuota(fresh)
        return fresh
    }

    private func saveProQuota(_ quota: ProQuota) {
        guard let data = try? JSONEncoder().encode(quota) else { return }
        KeychainHelper.saveLocalData(data, forKey: proQuotaKeychainKey)
    }

    private static func currentMonthString() -> String {
        let cal = Calendar.current
        let now = Date()
        return String(format: "%04d-%02d",
                      cal.component(.year,  from: now),
                      cal.component(.month, from: now))
    }

    func refreshPurchaseStatus() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result) else { continue }
            if AgentProductID.proIDs.contains(t.productID) { pro = true }
        }
        hasPRO        = pro
        freeRemaining = remainingFreeUses()
        proRemaining  = loadProQuota().count
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

private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified: throw StoreError.failedVerification
    case .verified(let safe): return safe
    }
}

enum StoreError: Error { case failedVerification }
