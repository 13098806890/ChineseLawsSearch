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

// MARK: - 收藏条文

struct FavoriteArticle: Codable, Identifiable, Equatable {
    let id: UUID
    let lawId: Int
    let lawTitle: String
    let articleNum: Int      // 条号（数字）
    let articleNumber: String // 显示用，如"第一百二十三条"
    let content: String
    let savedAt: Date

    init(lawId: Int, lawTitle: String, articleNum: Int, articleNumber: String, content: String) {
        self.id            = UUID()
        self.lawId         = lawId
        self.lawTitle      = lawTitle
        self.articleNum    = articleNum
        self.articleNumber = articleNumber
        self.content       = content
        self.savedAt       = Date()
    }
}

// MARK: - 收藏公报文书

struct FavoriteGongbaoDoc: Codable, Identifiable {
    let id: UUID
    let docId: Int
    let source: String     // "al" | "cpwsxd" | "sfwj"
    let title: String
    let rulingGist: String
    let issue: String
    let savedAt: Date

    init(docId: Int, source: String, title: String, rulingGist: String, issue: String) {
        self.id         = UUID()
        self.docId      = docId
        self.source     = source
        self.title      = title
        self.rulingGist = rulingGist
        self.issue      = issue
        self.savedAt    = Date()
    }
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
        PurchaseManager.shared.notifyKeyChanged()
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

    @AppStorage("showSideIndex")         var showSideIndex: Bool = true
    @AppStorage("searchExcludeArtNum")   var searchExcludeArtNum: Bool = true
    @AppStorage("searchTitleOnly")       var searchTitleOnly: Bool = false
    @AppStorage("searchResultLimit")     var searchResultLimit: Int = 100
    /// 法考模式：只检索法考法律
    @AppStorage("flkMode") var flkMode: Bool = false

    /// 搜索范围过滤：是否包含法律法规（法律/宪法/行政法规/修正案/法律解释/监察法规）
    @AppStorage("searchIncludeLaws")     var searchIncludeLaws: Bool = true
    /// 搜索范围过滤：是否包含司法解释
    @AppStorage("searchIncludeInterp")   var searchIncludeInterp: Bool = true

    /// 当前搜索范围对应的 category 列表（供 DatabaseManager 过滤）
    var searchCategories: [String] {
        var cats: [String] = []
        if searchIncludeLaws  { cats += ["法律", "宪法", "行政法规", "修正案", "法律解释", "监察法规"] }
        if searchIncludeInterp { cats += ["司法解释"] }
        // 如果全部取消，兜底返回所有类型避免搜索结果空白
        return cats.isEmpty ? ["法律", "宪法", "行政法规", "修正案", "法律解释", "监察法规", "司法解释"] : cats
    }

    /// true = 每次启动显示使用说明；false = 恢复上次阅读记录（默认）
    @AppStorage("showWelcomeOnLaunch") var showWelcomeOnLaunch: Bool = false
    /// 标记是否已经完成过首次启动（首次安装时为 false）
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    /// 条文字号：small / medium / large / xlarge，默认 medium
    @AppStorage("articleFontSize") var articleFontSize: String = "medium"

    // MARK: - 对话偏好

    @AppStorage("showThinking") var showThinking: Bool = true

    /// 对话质量模式："economy" | "standard" | "detailed"
    @AppStorage("chatQualityMode") var chatQualityMode: String = "standard"

    /// 实际生效的质量模式：基础版（自备Key）尊重用户设置，其余锁定标准
    private var effectiveQualityMode: String {
        switch PurchaseManager.shared.access {
        case .basic: return chatQualityMode
        default:     return "standard"
        }
    }

    struct QualitySettings {
        let maxFollowUpRounds: Int
        let maxContextArticles: Int
        let maxCitations: Int
    }

    private var effectiveQualitySettings: QualitySettings {
        switch effectiveQualityMode {
        case "economy":  return QualitySettings(maxFollowUpRounds: 1,  maxContextArticles: 15, maxCitations: 5)
        case "detailed": return QualitySettings(maxFollowUpRounds: 5,  maxContextArticles: 0,  maxCitations: 0)
        default:         return QualitySettings(maxFollowUpRounds: 3,  maxContextArticles: 40, maxCitations: 80)
        }
    }

    var maxFollowUpRounds:  Int { effectiveQualitySettings.maxFollowUpRounds }
    var maxContextArticles: Int { effectiveQualitySettings.maxContextArticles }
    var maxCitations:       Int { effectiveQualitySettings.maxCitations }

    func applyQualityMode(_ mode: String) {
        chatQualityMode = mode
        // maxContextArticles / maxCitations / maxFollowUpRounds 由计算属性实时计算，无需额外写入
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
            self?.loadFavorites()
            self?.loadGongbaoFavorites()
            self?.loadGongbaoNotes()
        }
        kv.synchronize()
        loadFavorites()
        loadGongbaoFavorites()
        loadGongbaoNotes()
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

    // MARK: - 收藏条文

    private static let favoritesKey = "favoriteArticles"

    @Published private(set) var favorites: [FavoriteArticle] = []

    private func loadFavorites() {
        guard let data = kv.data(forKey: Self.favoritesKey),
              let items = try? JSONDecoder().decode([FavoriteArticle].self, from: data)
        else { return }
        favorites = items
    }

    func isFavorited(lawId: Int, articleNum: Int) -> Bool {
        favorites.contains { $0.lawId == lawId && $0.articleNum == articleNum }
    }

    func addFavorite(_ article: FavoriteArticle) {
        guard !isFavorited(lawId: article.lawId, articleNum: article.articleNum) else { return }
        favorites.insert(article, at: 0)
        persistFavorites()
    }

    func removeFavorite(lawId: Int, articleNum: Int) {
        favorites.removeAll { $0.lawId == lawId && $0.articleNum == articleNum }
        persistFavorites()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persistFavorites()
    }

    private func persistFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        kv.set(data, forKey: Self.favoritesKey)
        kv.synchronize()
    }

    // MARK: - 收藏公报文书

    private static let gongbaoFavoritesKey = "favoriteGongbaoDocs"

    @Published private(set) var favoriteGongbaoDocs: [FavoriteGongbaoDoc] = []

    private func loadGongbaoFavorites() {
        guard let data = kv.data(forKey: Self.gongbaoFavoritesKey),
              let items = try? JSONDecoder().decode([FavoriteGongbaoDoc].self, from: data)
        else { return }
        favoriteGongbaoDocs = items
    }

    func isGongbaoFavorited(docId: Int) -> Bool {
        favoriteGongbaoDocs.contains { $0.docId == docId }
    }

    func addGongbaoFavorite(_ doc: FavoriteGongbaoDoc) {
        guard !isGongbaoFavorited(docId: doc.docId) else { return }
        favoriteGongbaoDocs.insert(doc, at: 0)
        persistGongbaoFavorites()
    }

    func removeGongbaoFavorite(docId: Int) {
        favoriteGongbaoDocs.removeAll { $0.docId == docId }
        persistGongbaoFavorites()
    }

    func removeGongbaoFavorites(at offsets: IndexSet) {
        favoriteGongbaoDocs.remove(atOffsets: offsets)
        persistGongbaoFavorites()
    }

    private func persistGongbaoFavorites() {
        guard let data = try? JSONEncoder().encode(favoriteGongbaoDocs) else { return }
        kv.set(data, forKey: Self.gongbaoFavoritesKey)
        kv.synchronize()
    }

    // MARK: - 公报笔记

    private static let gongbaoNotesKey = "gongbaoNotes"
    @Published private(set) var gongbaoNotes: [String: String] = [:]

    private func loadGongbaoNotes() {
        guard let data = kv.data(forKey: Self.gongbaoNotesKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        gongbaoNotes = dict
    }

    func gongbaoNote(docId: Int) -> String {
        gongbaoNotes["\(docId)"] ?? ""
    }

    func setGongbaoNote(docId: Int, text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gongbaoNotes.removeValue(forKey: "\(docId)")
        } else {
            gongbaoNotes["\(docId)"] = text
        }
        persistGongbaoNotes_()
    }

    private func persistGongbaoNotes_() {
        guard let data = try? JSONEncoder().encode(gongbaoNotes) else { return }
        kv.set(data, forKey: Self.gongbaoNotesKey)
        kv.synchronize()
    }
}
