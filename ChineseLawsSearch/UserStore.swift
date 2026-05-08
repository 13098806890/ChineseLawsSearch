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

    // MARK: - 阅读记录（当前 target）

    /// 上次打开的法律 ID（0 = 无记录）
    @AppStorage("lastReadLawId")      var lastReadLawId: Int  = 0
    /// 上次阅读的条文编号（-1 = 无特定条文）
    @AppStorage("lastReadArticleNum") var lastReadArticleNum: Int = -1

    // MARK: - 跳转链路（backStack）

    private static let backStackKey = "lastBackStack"

    /// 保存 backStack 到 UserDefaults
    func saveBackStack(_ items: [PersistedBackItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.backStackKey)
    }

    /// 读取上次 backStack，无则返回空数组
    func loadBackStack() -> [PersistedBackItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.backStackKey),
              let items = try? JSONDecoder().decode([PersistedBackItem].self, from: data)
        else { return [] }
        return items
    }

    /// 清除 backStack（新开浏览时调用）
    func clearBackStack() {
        UserDefaults.standard.removeObject(forKey: Self.backStackKey)
    }

    // MARK: - 法律浏览偏好

    @AppStorage("showSideIndex") var showSideIndex: Bool = true

    // MARK: - 对话偏好

    @AppStorage("showThinking")         var showThinking: Bool = true
    @AppStorage("maxFollowUpRounds")    var maxFollowUpRounds: Int = 3
    @AppStorage("maxCitations")         var maxCitations: Int  = 0
    @AppStorage("maxContextArticles")   var maxContextArticles: Int = 20

    // MARK: - 模型选择

    @AppStorage("selected_llm_provider") var selectedProviderId: String = "gemini"

    // MARK: - 阅读记录操作

    /// 记录当前打开的法律和条文
    func recordRead(lawId: Int, articleNum: Int?) {
        lastReadLawId      = lawId
        lastReadArticleNum = articleNum ?? -1
    }

    /// 返回上次阅读位置，无记录时返回 nil
    var lastRead: (lawId: Int, articleNum: Int?)? {
        guard lastReadLawId > 0 else { return nil }
        let article = lastReadArticleNum >= 0 ? lastReadArticleNum : nil
        return (lastReadLawId, article)
    }
}
