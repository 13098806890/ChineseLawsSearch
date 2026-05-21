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

    /// Debug only: set true to simulate active PRO subscription without a real purchase.
    #if DEBUG
    static var debugSimulatePRO: Bool = false
    #endif

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
    /// Cached period start from last refreshPurchaseStatus; used by consumeIfAllowed (sync).
    private var cachedPeriodStart: Date? = nil

    private var updateListenerTask: Task<Void, Never>?
    /// True once the first refreshPurchaseStatus() completes. Avoids false paywall on cold launch.
    @Published private(set) var isReady: Bool = false

    init() {
        freeRemaining = remainingFreeUses()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await refreshPurchaseStatus() }
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: - Access control

    var access: AgentAccess {
        #if DEBUG
        if Self.debugSimulatePRO { return .pro(remaining: proRemaining) }
        #endif
        let free = freeRemaining
        if free > 0 { return .free(remaining: free) }
        if hasPRO   { return .pro(remaining: proRemaining) }
        return .noAccess
    }

    var canViewGazetteDetail: Bool {
        #if DEBUG
        if Self.debugSimulatePRO { return true }
        #endif
        return hasPRO
    }

    /// 调用 Agent 前调用；有权限则消耗计数并返回 true。
    /// 追问传 isFollowUp=true 不消耗次数。
    func consumeIfAllowed(isFollowUp: Bool = false) -> Bool {
        lastConsumedPath = .none
        if isFollowUp { return true }
        // 如果 StoreKit 尚未完成第一次查询，等同于 pro 状态不可知：
        // 已知有免费次数则直接消耗；否则先放行一次（isReady 为 false），
        // 实际上此情形在 UI 禁用了按钮，这里作为安全兜底。
        if !isReady {
            let free = remainingFreeUses()
            if free > 0 {
                let newVal = free - 1
                ud.set(newVal, forKey: freeCountKey)
                freeRemaining = newVal
                lastConsumedPath = .free
                return true
            }
            // StoreKit 未就绪且无免费次数：暂时放行，后续刷新后 hasPRO 会更新
            return true
        }
        #if DEBUG
        if Self.debugSimulatePRO {
            guard let ps = cachedPeriodStart else { return false }
            var quota = loadProQuota(periodStart: ps)
            if quota.count > 0 {
                quota.count -= 1
                saveProQuota(quota)
                proRemaining = quota.count
                lastConsumedPath = .pro
                return true
            }
            return false
        }
        #endif
        // 已订阅：优先消耗订阅配额，免费次数保留
        if hasPRO {
            guard let ps = cachedPeriodStart else { return false }
            var quota = loadProQuota(periodStart: ps)
            if quota.count > 0 {
                quota.count -= 1
                saveProQuota(quota)
                proRemaining = quota.count
                lastConsumedPath = .pro
                return true
            }
            return false
        }
        // 未订阅：消耗免费次数
        let free = remainingFreeUses()
        if free > 0 {
            let newVal = free - 1
            ud.set(newVal, forKey: freeCountKey)
            freeRemaining = newVal
            lastConsumedPath = .free
            return true
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
            guard let ps = cachedPeriodStart else { break }
            var quota = loadProQuota(periodStart: ps)
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

    func restorePurchases() async throws {
        try await AppStore.sync()
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
        /// ISO8601 date string of the start of the current subscription period.
        /// Quota resets when the period changes (renewal or new purchase).
        var periodStart: String
        // Legacy field — ignored on read but kept for backward decode compatibility
        var month: String?
    }

    /// Returns the active subscription's current period start date, or nil if not subscribed.
    /// Uses Transaction.currentEntitlements so this is always based on real receipt data.
    private func currentPeriodStart() async -> Date? {
        #if DEBUG
        if Self.debugSimulatePRO { return Date() }
        #endif
        var latestPurchaseDate: Date? = nil
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result),
                  AgentProductID.proIDs.contains(t.productID) else { continue }
            // purchaseDate is the start of the current billing period for auto-renewing subscriptions
            if latestPurchaseDate == nil || t.purchaseDate > latestPurchaseDate! {
                latestPurchaseDate = t.purchaseDate
            }
        }
        return latestPurchaseDate
    }

    private func loadProQuota(periodStart: Date) -> ProQuota {
        let periodKey = Self.isoDateString(periodStart)
        if let data = KeychainHelper.loadLocalData(forKey: proQuotaKeychainKey),
           let quota = try? JSONDecoder().decode(ProQuota.self, from: data),
           quota.periodStart == periodKey {
            return quota
        }
        // New billing period — reset to full quota
        let fresh = ProQuota(count: Self.proMonthlyTotal, periodStart: periodKey)
        saveProQuota(fresh)
        return fresh
    }

    private func saveProQuota(_ quota: ProQuota) {
        guard let data = try? JSONEncoder().encode(quota) else { return }
        KeychainHelper.saveLocalData(data, forKey: proQuotaKeychainKey)
    }

    private static func isoDateString(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.string(from: date)
    }

    func refreshPurchaseStatus() async {
        var pro = false
        var periodStart: Date? = nil
        #if DEBUG
        if Self.debugSimulatePRO { pro = true; periodStart = Date() }
        #else
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result) else { continue }
            if AgentProductID.proIDs.contains(t.productID) {
                pro = true
                if periodStart == nil || t.purchaseDate > periodStart! {
                    periodStart = t.purchaseDate
                }
            }
        }
        #endif
        hasPRO        = pro
        freeRemaining = remainingFreeUses()
        if pro, let ps = periodStart {
            cachedPeriodStart = ps
            proRemaining = loadProQuota(periodStart: ps).count
        } else {
            cachedPeriodStart = nil
            proRemaining = 0
        }
        isReady = true
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
