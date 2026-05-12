//
//  PurchaseManager.swift
//  ChineseLawsSearch
//
//  StoreKit 2 购买管理 + 免费次数 + 每周配额追踪。
//
//  两种付费套餐（App Store Connect 中配置）：
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │ 套餐         Product ID                      类型     建议价格  │
//  │ ─────────────────────────────────────────────────────────────── │
//  │ 基础版       com.doxie.laws.basic             买断     ¥18      │
//  │   解锁 Agent 功能，需用户自备 DeepSeek API Key                  │
//  │                                                                  │
//  │ 畅用版月订阅  com.doxie.laws.pro.monthly      月订阅   ¥12/月   │
//  │ 畅用版年订阅  com.doxie.laws.pro.yearly       年订阅   ¥68/年   │
//  │   包含内置 Key，每周 80 次额度，无需自备 Key                    │
//  └─────────────────────────────────────────────────────────────────┘
//
//  权限优先级（hasBASIC + hasPRO 同时持有时）：
//    1. 用户自备 Key（basic 或 pro+key）→ 走自备 Key，标准/详细/节省模式均可
//    2. 无自备 Key + hasPRO → 走内置 Key，每周额度，锁定标准模式
//    3. hasBASIC 无 Key → 提示配置 Key
//
//  免费体验次数存于 UserDefaults（本地），防止 iCloud 不可用时无限重置。
//  每周额度存于 iCloud KV Store，多设备共享同一配额。
//

import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Product IDs

enum AgentProductID {
    /// 基础版买断：解锁 Agent，需自备 Key
    static let basic       = "com.doxie.laws.basic"
    /// 畅用版：包含内置 Key + 每周额度
    static let proMonthly  = "com.doxie.laws.pro.monthly"
    static let proYearly   = "com.doxie.laws.pro.yearly"

    static let all: [String] = [basic, proMonthly, proYearly]

    /// 畅用版 product ID 集合，用于判断是否有内置 Key 权限
    static let proIDs: Set<String> = [proMonthly, proYearly]
}

// MARK: - Access state

enum AgentAccess {
    /// 免费体验次数尚有剩余（使用内置 Key）
    case free(remaining: Int)
    /// 基础版：已购买，需自备 Key，无次数限制
    case basic
    /// 畅用版：已购买，使用内置 Key，每周 weeklyRemaining 次
    case pro(weeklyRemaining: Int)
    /// 无权限（免费用完且未购买）
    case noAccess
}

// MARK: - PurchaseManager

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // ---------------------------------------------------------------
    // MARK: - 调试开关（上线前务必确认）
    // paymentEnabled = false → 完全绕过付费，所有人直接获得 .pro 权限
    // freeTotal 改为 0 → 免费次数用完，强制展示 Paywall（测试购买流程）
    // ---------------------------------------------------------------
    // MARK: - 调试开关（上线前务必确认所有开关状态）
    //
    // paymentEnabled = false → 完全绕过付费，mockAccess 生效
    // freeTotal 改为 0      → 免费次数用完，强制展示 Paywall
    //
    // mockAccess：paymentEnabled = false 时模拟的权限状态，用于测试各个套餐的 UI 表现
    //   .free(remaining: 5)   → 模拟有免费次数
    //   .basic                → 模拟基础版买断（需自备 Key）
    //   .pro(weeklyRemaining: 80) → 模拟畅用版有额度
    //   .pro(weeklyRemaining: 0)  → 模拟畅用版额度用完
    //   .noAccess             → 模拟未购买且免费用完
    // ---------------------------------------------------------------
    static let paymentEnabled: Bool      = true    // false = 本地调试，mockAccess 生效
    #if DEBUG
    static let mockAccess:     AgentAccess = .basic  // 仅 paymentEnabled=false 时有效
    #else
    static let mockAccess:     AgentAccess = .noAccess
    #endif
    private let freeTotal: Int           = 5       // 免费体验次数

    /// 畅用版每周额度上限（每天约 11 次，月均成本 ¥4.5，利润率 ~46%）
    static let proWeeklyTotal = 80

    // MARK: - iCloud KV keys（周额度，双写 UserDefaults 作 fallback）
    private let kv = NSUbiquitousKeyValueStore.default
    private let weekUsedKey      = "agent_pro_week_used"
    private let weekStartKey     = "agent_pro_week_start"   // TimeInterval
    // UserDefaults fallback keys（iCloud 不可用时使用）
    private let weekUsedUDKey    = "agent_pro_week_used_local"
    private let weekStartUDKey   = "agent_pro_week_start_local"

    // MARK: - UserDefaults keys（免费次数本地存储，防 iCloud 不可用重置）
    private let ud = UserDefaults.standard
    private let freeCountKey    = "agent_free_uses_remaining"
    private let freeInitedKey   = "agent_free_inited"

    // MARK: - Published state
    @Published private(set) var products:       [Product] = []
    @Published private(set) var hasBASIC:       Bool = false   // 基础版买断
    @Published private(set) var hasPRO:         Bool = false   // 畅用版（月/年订阅有效）
    @Published private(set) var freeRemaining:  Int  = 0
    @Published private(set) var weeklyRemaining: Int = 0

    private var updateListenerTask: Task<Void, Never>?

    init() {
        freeRemaining   = remainingFreeUses()
        weeklyRemaining = remainingWeeklyUses()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await refreshPurchaseStatus() }
        // iCloud 变更只影响周额度（免费次数已改为本地 UserDefaults）
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.weeklyRemaining = self?.remainingWeeklyUses() ?? 0
            }
        }
        kv.synchronize()
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: - Access control

    /// 缓存 Key 状态，避免每次访问 access/quality 属性都同步读 Keychain。
    /// 通过 notifyKeyChanged() 刷新（在 refreshAPIKeyState 和保存/删除 Key 时调用）。
    private(set) var hasUserKey: Bool = {
        !(KeychainHelper.load(forKey: "deepseek_api_key") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }()

    /// 供外部（View层）主动刷新 Key 状态后通知 access 更新
    func notifyKeyChanged() {
        hasUserKey = !(KeychainHelper.load(forKey: "deepseek_api_key") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        freeRemaining = remainingFreeUses()   // @Published，触发依赖 pm.access 的 View 重渲染
    }

    var access: AgentAccess {
        if !Self.paymentEnabled { return Self.mockAccess }
        // 免费次数优先（不论买没买，只要还有就先用内置 Key）
        let free = freeRemaining
        if free > 0 { return .free(remaining: free) }
        // 已购买任一套餐 + 自备 Key → 走 basic（不消耗内置 Key 额度）
        if (hasBASIC || hasPRO) && hasUserKey { return .basic }
        // 畅用版（无自备 Key）→ 走内置 Key 周额度
        if hasPRO { return .pro(weeklyRemaining: weeklyRemaining) }
        // 仅基础版无 Key → 提示配置 Key（返回 .basic，View 层判断 hasAPIKey）
        if hasBASIC { return .basic }
        return .noAccess
    }

    /// 调用 Agent 前调用；有权限则消耗计数并返回 true。
    func consumeIfAllowed() -> Bool {
        if !Self.paymentEnabled {
            switch Self.mockAccess {
            case .noAccess:                return false
            case .pro(let r) where r == 0: return false
            default:                       return true
            }
        }
        let free = remainingFreeUses()
        if free > 0 {
            let newVal = free - 1
            ud.set(newVal, forKey: freeCountKey)
            freeRemaining = max(0, newVal)
            return true
        }
        // 自备 Key（basic 或 pro+key）→ 不消耗内置额度
        if (hasBASIC || hasPRO) && hasUserKey { return true }
        // 畅用版内置 Key → 消耗周额度（同时写 iCloud + UserDefaults 防 fallback 虚高）
        if hasPRO {
            let used = currentWeekUsed()
            guard used < Self.proWeeklyTotal else { return false }
            let newUsed = used + 1
            kv.set(Int64(newUsed), forKey: weekUsedKey)
            kv.synchronize()
            ud.set(newUsed, forKey: weekUsedUDKey)
            weeklyRemaining = Self.proWeeklyTotal - newUsed
            return true
        }
        return false
    }

    /// 网络失败等不可控错误时退还已消耗的计数。
    /// 只退还真正从计数中扣除的路径（免费次数 / 畅用版周额度），自备 Key 路径无需退还。
    func refundIfNeeded() {
        if !Self.paymentEnabled { return }
        // 如果还有免费次数在本次调用前被消耗（即调用前 freeRemaining 比现在少一次），则退还
        let currentFree = ud.integer(forKey: freeCountKey)
        let initializedFree = ud.bool(forKey: freeInitedKey)
        // 仅在当次调用扣了免费次数的情况下退还（freeRemaining 被减少过）
        // 判断依据：消耗路径上 freeRemaining = max(0, free-1)，所以如果上一次消耗是免费路径
        // 此时 currentFree < freeTotal 且 (hasBASIC||hasPRO) 都不成立（否则走自备Key路径）
        if initializedFree && currentFree < freeTotal {
            let restored = currentFree + 1
            ud.set(restored, forKey: freeCountKey)
            freeRemaining = restored
            return
        }
        // 畅用版周额度退还
        if hasPRO && !hasUserKey {
            let used = currentWeekUsed()
            guard used > 0 else { return }
            let newUsed = used - 1
            kv.set(Int64(newUsed), forKey: weekUsedKey)
            kv.synchronize()
            ud.set(newUsed, forKey: weekUsedUDKey)
            weeklyRemaining = Self.proWeeklyTotal - newUsed
        }
    }

    // MARK: - StoreKit: load products

    func loadProducts() async {
        guard let fetched = try? await Product.products(for: AgentProductID.all) else { return }
        // 展示顺序：基础版 → 畅用版年 → 畅用版月
        let order = [AgentProductID.basic, AgentProductID.proYearly, AgentProductID.proMonthly]
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
        // 使用 UserDefaults（本地），避免 iCloud 不可用时无限重置
        if !ud.bool(forKey: freeInitedKey) {
            ud.set(freeTotal, forKey: freeCountKey)
            ud.set(true, forKey: freeInitedKey)
        }
        return ud.integer(forKey: freeCountKey)
    }

    /// 当前自然周已用次数（周一 00:00 重置）。iCloud 不可用时 fallback 到 UserDefaults。
    private func currentWeekUsed() -> Int {
        let weekStart = currentWeekStart().timeIntervalSince1970

        // 用 synchronize 返回值判断 iCloud 是否可用（true = 有数据同步能力）
        // 同时读两处，以防 iCloud 刚恢复但尚未写入 weekStartKey
        let kvStart = kv.double(forKey: weekStartKey)   // 0.0 if not set or unavailable
        let udStart = ud.double(forKey: weekStartUDKey)
        // 取最新的（较大的）作为参考，防止 iCloud 延迟同步导致误重置
        let storedStart = max(kvStart, udStart)

        if storedStart < weekStart - 1 {
            // 新的一周，重置（同时写两处保持同步）
            kv.set(weekStart, forKey: weekStartKey)
            kv.set(Int64(0), forKey: weekUsedKey)
            kv.synchronize()
            ud.set(weekStart, forKey: weekStartUDKey)
            ud.set(0, forKey: weekUsedUDKey)
            return 0
        }
        let kvUsed = Int(kv.longLong(forKey: weekUsedKey))
        let udUsed = ud.integer(forKey: weekUsedUDKey)
        // 取两者最大值，防止某端同步延迟导致额度虚高
        return max(kvUsed, udUsed)
    }

    private func remainingWeeklyUses() -> Int {
        max(0, Self.proWeeklyTotal - currentWeekUsed())
    }

    /// 本周一 00:00 的 Date（用户本地时区）
    private func currentWeekStart() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2   // 周一
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    func refreshPurchaseStatus() async {
        var basic = false
        var pro   = false
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result) else { continue }
            if t.productID == AgentProductID.basic              { basic = true }
            if AgentProductID.proIDs.contains(t.productID)     { pro   = true }
        }
        let wasProBefore = hasPRO
        hasBASIC = basic
        hasPRO   = pro
        // 重新订阅（之前没有 Pro，现在有了）→ 重置本周用量，让用户拿到完整额度
        if pro && !wasProBefore {
            kv.set(currentWeekStart().timeIntervalSince1970, forKey: weekStartKey)
            kv.set(Int64(0), forKey: weekUsedKey)
            kv.synchronize()
        }
        weeklyRemaining = remainingWeeklyUses()
        freeRemaining   = remainingFreeUses()
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
