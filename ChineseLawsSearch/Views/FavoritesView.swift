//
//  FavoritesView.swift
//  ChineseLawsSearch
//

import SwiftUI

// MARK: - 分类 Tab

private enum FavTab: String, CaseIterable, Identifiable {
    case laws    = "laws"
    case guidingCase  = "al"
    case selectedCase = "cpwsxd"
    case judicialDoc  = "sfwj"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .laws:    return "法条"
        case .guidingCase:      return "指导案例"
        case .selectedCase:  return "裁判文书"
        case .judicialDoc:    return "司法文件"
        }
    }

    var icon: String {
        switch self {
        case .laws:    return "text.book.closed"
        case .guidingCase:      return "star.circle"
        case .selectedCase:  return "doc.text.magnifyingglass"
        case .judicialDoc:    return "doc.plaintext"
        }
    }
}

// MARK: - FavoritesView

struct FavoritesView: View {
    let navigate: (Int, Int?) -> Void
    let navigateToGazette: (GazetteDoc) -> Void

    @EnvironmentObject private var userStore: UserStore
    @State private var selectedTab: FavTab = .laws

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Divider()

                tabContent
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Tab 选择栏

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FavTab.allCases) { tab in
                    let count = badgeCount(tab)
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.displayName)
                                .font(.subheadline)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        selectedTab == tab
                                            ? Color.white.opacity(0.3)
                                            : AppColors.shared.searchHighlight.opacity(0.15)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab
                                ? AppColors.shared.searchHighlight
                                : Color(.systemGray5)
                        )
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func badgeCount(_ tab: FavTab) -> Int {
        switch tab {
        case .laws:   return userStore.favorites.count
        case .guidingCase:     return userStore.favoriteGazetteDocs.filter { $0.source == "al" }.count
        case .selectedCase: return userStore.favoriteGazetteDocs.filter { $0.source == "cpwsxd" }.count
        case .judicialDoc:   return userStore.favoriteGazetteDocs.filter { $0.source == "sfwj" }.count
        }
    }

    // MARK: Tab 内容

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .laws:
            lawsList
        case .guidingCase, .selectedCase, .judicialDoc:
            gazetteList(source: selectedTab.rawValue)
        }
    }

    // MARK: 法条列表

    private var lawsList: some View {
        Group {
            if userStore.favorites.isEmpty {
                emptyState(icon: "star", message: "暂无收藏法条", hint: "长按任意条文，选择「收藏」即可保存到这里。")
            } else {
                List {
                    ForEach(userStore.favorites) { fav in
                        Button {
                            navigate(fav.lawId, fav.articleNum)
                        } label: {
                            FavoriteRow(fav: fav)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                userStore.removeFavorite(lawId: fav.lawId, articleNum: fav.articleNum)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: 公报文书列表

    private func gazetteList(source: String) -> some View {
        let items = userStore.favoriteGazetteDocs.filter { $0.source == source }
        return Group {
            if items.isEmpty {
                emptyState(icon: "star", message: "暂无收藏", hint: "在公报文书详情页点击星标图标即可收藏。")
            } else {
                List {
                    ForEach(items) { fav in
                        Button {
                            // 从DB加载完整文档后导航
                            if let doc = DatabaseManager.shared.gazetteDoc(id: fav.docId) {
                                navigateToGazette(doc)
                            }
                        } label: {
                            GazetteFavoriteRow(fav: fav)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                userStore.removeGazetteFavorite(docId: fav.docId)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: 空状态

    private func emptyState(icon: String, message: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 法条行

private struct FavoriteRow: View {
    let fav: FavoriteArticle
    @State private var lawTitle: String = ""
    @State private var articleNumber: String = ""
    @State private var content: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(lawTitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.shared.searchHighlight)
                    .lineLimit(1)
                Text(articleNumber)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .task(id: fav.id) {
            let db = DatabaseManager.shared
            if let node = db.nodes(lawId: fav.lawId).first(where: { $0.articleNum == fav.articleNum }) {
                lawTitle      = db.lawMeta(id: fav.lawId)?.title ?? ""
                articleNumber = node.title
                content       = node.content
            } else {
                lawTitle      = fav.lawTitle ?? ""
                articleNumber = fav.articleNumber ?? ""
                content       = fav.content ?? ""
            }
        }
    }
}

// MARK: - 公报文书行

private struct GazetteFavoriteRow: View {
    let fav: FavoriteGazetteDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(fav.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                if !fav.issue.isEmpty {
                    Text(fav.issue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !fav.rulingGist.isEmpty {
                Text(fav.rulingGist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
