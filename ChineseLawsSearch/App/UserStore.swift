//
//  UserStore.swift
//  ChineseLawsSearch
//
//  统一管理用户偏好与阅读记录，底层使用 UserDefaults（通过 @AppStorage）。
//  用 @StateObject 注入 ContentView，子视图通过 @EnvironmentObject 访问。
//

import SwiftUI
import Combine

// MARK: - 持久化跳转栈条目

struct PersistedBackItem: Codable {
    let tab: String          // "browse" | "chat"
    let lawId: Int?          // nil 表示该层没有打开的法律
    let articleNum: Int?
}

final class UserStore: ObservableObject {

    private let kv = NSUbiquitousKeyValueStore.default

    // MARK: - API Key 状态（供跨视图响应）

    @Published var apiKeyConfigured: Bool = {
        let k = KeychainHelper.load(forKey: "deepseek_api_key") ?? ""
        return !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }()

    func refreshAPIKeyState() {
        let k = KeychainHelper.load(forKey: "deepseek_api_key") ?? ""
        apiKeyConfigured = !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 阅读记录（当前 target）

    var lastReadLawId: Int {
        get { Int(kv.longLong(forKey: "lastReadLawId")) }
        set { kv.set(Int64(newValue), forKey: "lastReadLawId"); kv.synchronize() }
    }
    var lastReadArticleNum: Int {
        get { Int(kv.longLong(forKey: "lastReadArticleNum")) }
        set { kv.set(Int64(newValue), forKey: "lastReadArticleNum"); kv.synchronize() }
    }

    // MARK: - 跳转链路（backStack）

    private static let backStackKey = "lastBackStack"

    func saveBackStack(_ items: [PersistedBackItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        kv.set(data, forKey: Self.backStackKey)
        kv.synchronize()
    }

    func loadBackStack() -> [PersistedBackItem] {
        guard let data = kv.data(forKey: Self.backStackKey),
              let items = try? JSONDecoder().decode([PersistedBackItem].self, from: data)
        else { return [] }
        return items
    }

    func clearBackStack() {
        kv.removeObject(forKey: Self.backStackKey)
        kv.synchronize()
    }

    // MARK: - 法律浏览偏好

    @AppStorage("showSideIndex")       var showSideIndex: Bool = true
    @AppStorage("searchExcludeArtNum") var searchExcludeArtNum: Bool = true
    @AppStorage("searchTitleOnly")     var searchTitleOnly: Bool = false
    @AppStorage("searchResultLimit")   var searchResultLimit: Int = 100
    /// true = 每次启动显示使用说明；false = 恢复上次阅读记录（默认）
    @AppStorage("showWelcomeOnLaunch") var showWelcomeOnLaunch: Bool = false
    /// 标记是否已经完成过首次启动（首次安装时为 false）
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false

    // MARK: - 对话偏好

    @AppStorage("showThinking") var showThinking: Bool = true

    /// 对话质量模式："economy" | "standard" | "detailed"
    @AppStorage("chatQualityMode") var chatQualityMode: String = "standard"

    /// 追问最多轮次（由 chatQualityMode 驱动）
    var maxFollowUpRounds: Int {
        switch chatQualityMode {
        case "economy":  return 1
        case "detailed": return 5
        default:         return 3
        }
    }
    var maxContextArticles: Int {
        switch chatQualityMode {
        case "economy":  return 15
        case "detailed": return 0
        default:         return 40
        }
    }
    var maxCitations: Int {
        switch chatQualityMode {
        case "economy":  return 5
        case "detailed": return 0
        default:         return 80
        }
    }

    func applyQualityMode(_ mode: String) {
        chatQualityMode = mode
        switch mode {
        case "economy":
            UserDefaults.standard.set(1,  forKey: "maxFollowUpRounds")
            UserDefaults.standard.set(15, forKey: "maxContextArticles")
            UserDefaults.standard.set(5,  forKey: "maxCitations")
        case "detailed":
            UserDefaults.standard.set(5,  forKey: "maxFollowUpRounds")
            UserDefaults.standard.set(0,  forKey: "maxContextArticles")
            UserDefaults.standard.set(0,  forKey: "maxCitations")
        default:
            UserDefaults.standard.set(3,  forKey: "maxFollowUpRounds")
            UserDefaults.standard.set(40, forKey: "maxContextArticles")
            UserDefaults.standard.set(80, forKey: "maxCitations")
        }
    }

    // MARK: - 模型选择

    @AppStorage("selected_llm_provider") var selectedProviderId: String = "deepseek"

    // MARK: - iCloud KV 变更监听

    private var kvObserver: NSObjectProtocol?

    init() {
        kvObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
        kv.synchronize()
    }

    deinit {
        if let obs = kvObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - 阅读记录操作

    func recordRead(lawId: Int, articleNum: Int?) {
        lastReadLawId      = lawId
        lastReadArticleNum = articleNum ?? -1
    }

    var lastRead: (lawId: Int, articleNum: Int?)? {
        guard lastReadLawId > 0 else { return nil }
        let article = lastReadArticleNum >= 0 ? lastReadArticleNum : nil
        return (lastReadLawId, article)
    }
}
