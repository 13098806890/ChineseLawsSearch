//
//  TOCView.swift
//  ChineseLawsSearch
//

import SwiftUI

// MARK: - Highlight helper

private func highlighted(_ text: String, query: String,
                          baseFont: Font = .caption,
                          highlightColor: Color = AppColors.shared.searchHighlight) -> Text {
    guard !query.isEmpty else { return Text(text).font(baseFont) }
    var attr = AttributedString(text)
    let lower = text.lowercased()
    let lowerQ = query.lowercased()
    var searchFrom = lower.startIndex
    while let range = lower.range(of: lowerQ, range: searchFrom..<lower.endIndex) {
        if let attrRange = Range(range, in: attr) {
            attr[attrRange].font = baseFont.bold()
            attr[attrRange].foregroundColor = UIColor(highlightColor)
        }
        searchFrom = range.upperBound
    }
    return Text(attr).font(baseFont)
}

struct TOCView: View {
    @Binding var target: LawTarget?

    private var selectedLawId: Int? { target?.law.id }

    @AppStorage("searchExcludeArtNum") private var excludeArtNum: Bool = true
    @AppStorage("searchTitleOnly")     private var titleOnly: Bool = false
    @AppStorage("searchResultLimit")   private var resultLimit: Int = 100
    @AppStorage("searchIncludeLaws")   private var includeLaws: Bool = true
    @AppStorage("searchIncludeInterp") private var includeInterp: Bool = true

    private var searchCategories: [String] {
        var cats: [String] = []
        if includeLaws  { cats += ["法律", "宪法", "行政法规", "修正案", "法律解释", "监察法规"] }
        if includeInterp { cats += ["司法解释"] }
        return cats.isEmpty ? ["法律", "宪法", "行政法规", "修正案", "法律解释", "监察法规", "司法解释"] : cats
    }

    @State private var menu: DatabaseManager.LawMenu? = nil
    @State private var expandedGroups:    Set<String> = []
    @State private var expandedSubgroups: Set<String> = []

    @State private var searchQuery = ""
    @State private var titleResults:   [LawMeta]      = []
    @State private var articleResults: [SearchResult] = []
    @State private var isRunning = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        List {
            if searchQuery.isEmpty {
                // 目录浏览
                if let menu {
                    ForEach(menu.groups, id: \.label) { group in
                        let totalCount = group.subgroups.reduce(0) { $0 + $1.laws.count }
                        let isExpanded = expandedGroups.contains(group.label)

                        Section {
                            if isExpanded {
                                ForEach(group.subgroups, id: \.label) { sub in
                                    subgroupRows(groupLabel: group.label, sub: sub)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isExpanded { expandedGroups.remove(group.label) }
                                    else          { expandedGroups.insert(group.label) }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(group.label)
                                        .font(.subheadline).bold()
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(totalCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if isRunning {
                // 搜索中
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if titleResults.isEmpty && articleResults.isEmpty {
                // 无结果
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("未找到「\(searchQuery)」相关内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("请尝试其他关键词，建议使用 3 个字以上")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                // 搜索结果
                if !titleResults.isEmpty {
                    Section("法律名称") {
                        ForEach(titleResults) { law in
                            Button {
                                target = LawTarget(law: law, scrollToArticle: nil)
                            } label: {
                                highlighted(law.title, query: searchQuery,
                                            baseFont: .subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !articleResults.isEmpty {
                    Section("条文内容") {
                        ForEach(articleResults) { result in
                            Button {
                                if let law = DatabaseManager.shared.lawMeta(id: result.lawId) {
                                    target = LawTarget(law: law, scrollToArticle: result.nodeArticleNum)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    highlighted(result.lawTitle, query: searchQuery,
                                                baseFont: .caption)
                                        .foregroundStyle(.secondary)
                                    Text(result.articleNumber)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                    highlighted(result.content, query: searchQuery,
                                                baseFont: .caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("法律法规")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: titleOnly ? "搜索法律名称" : "搜索法律名称或条文内容")
        .onChange(of: searchQuery)    { _, q in runSearch(q) }
        .onChange(of: excludeArtNum)  { _, _ in runSearch(searchQuery) }
        .onChange(of: titleOnly)      { _, _ in runSearch(searchQuery) }
        .onChange(of: resultLimit)    { _, _ in runSearch(searchQuery) }
        .onChange(of: includeLaws)    { _, _ in runSearch(searchQuery) }
        .onChange(of: includeInterp)  { _, _ in runSearch(searchQuery) }
        .task {
            menu = DatabaseManager.shared.loadMenu()
        }
    }

    // MARK: - Search logic

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard !q.isEmpty else {
            titleResults = []; articleResults = []; return
        }
        isRunning = true
        let excl      = excludeArtNum
        let limit     = resultLimit
        let onlyTitle = titleOnly
        let cats      = searchCategories
        let variant   = DatabaseManager.numberVariant(of: q)
        let db = DatabaseManager.shared
        searchTask = Task.detached(priority: .userInitiated) {
            var titles = db.searchByTitle(query: q, categories: cats)
            if let v = variant {
                let extra = db.searchByTitle(query: v, categories: cats)
                let seen  = Set(titles.map(\.id))
                titles += extra.filter { !seen.contains($0.id) }
            }
            var articles: [SearchResult] = []
            if !onlyTitle {
                articles = db.searchContent(query: q, limit: limit, excludeArticleNumber: excl, categories: cats)
                if let v = variant {
                    let extra = db.searchContent(query: v, limit: limit, excludeArticleNumber: excl, categories: cats)
                    let seen  = Set(articles.map(\.id))
                    articles += extra.filter { !seen.contains($0.id) }
                }
            }
            guard !Task.isCancelled else { return }
            let finalTitles   = titles
            let finalArticles = articles
            await MainActor.run {
                titleResults   = finalTitles
                articleResults = finalArticles
                isRunning      = false
            }
        }
    }

    // MARK: - Browse subviews

    @ViewBuilder
    func subgroupRows(groupLabel: String, sub: DatabaseManager.MenuSubgroup) -> some View {
        let subKey     = "\(groupLabel)/\(sub.label)"
        let isExpanded = expandedSubgroups.contains(subKey)
        let isAdminSub = sub.label.hasPrefix("行政法规/")
        let displayLabel = isAdminSub ? String(sub.label.dropFirst("行政法规/".count)) : sub.label

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { expandedSubgroups.remove(subKey) }
                else          { expandedSubgroups.insert(subKey) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.shared.folderIcon)
                Text(displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(sub.laws.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 32, bottom: 4, trailing: 16))

        if isExpanded {
            ForEach(sub.laws, id: \.id) { menuLaw in
                lawRow(menuLaw)
                    .listRowInsets(EdgeInsets(top: 4, leading: 52, bottom: 4, trailing: 16))
            }
        }
    }

    @ViewBuilder
    func lawRow(_ menuLaw: DatabaseManager.MenuLaw) -> some View {
        let isSelected = selectedLawId == menuLaw.id
        Button {
            if let law = DatabaseManager.shared.lawMeta(id: menuLaw.id) {
                target = LawTarget(law: law, scrollToArticle: nil)
            }
        } label: {
            Text(menuLaw.title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? AppColors.shared.folderIcon : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isSelected ? AppColors.shared.folderIcon.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
