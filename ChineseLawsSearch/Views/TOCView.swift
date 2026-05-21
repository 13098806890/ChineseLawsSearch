//
//  TOCView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct TOCView: View {
    @Binding var target: LawTarget?

    private var selectedLawId: Int? { target?.law.id }

    @AppStorage("searchExcludeArtNum") private var excludeArtNum: Bool = true
    @AppStorage("searchResultLimit")   private var resultLimit: Int = 100
    @AppStorage("flkMode")             private var lawsExamMode: Bool = false

    @EnvironmentObject private var userStore: UserStore

    @State private var menu: DatabaseManager.LawMenu? = nil
    @State private var expandedGroups:    Set<String> = []
    @State private var expandedSubgroups: Set<String> = []

    @State private var searchQuery = ""
    @State private var titleResults:   [LawMeta]      = []
    @State private var articleResults: [SearchResult] = []
    @State private var titleSectionExpanded:      Bool = true
    @State private var lawArticleSectionExpanded: Bool = true
    @State private var interpSectionExpanded:     Bool = true
    @State private var isRunning = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        TOCListContent(
            target: $target,
            menu: menu,
            expandedGroups: $expandedGroups,
            expandedSubgroups: $expandedSubgroups,
            searchQuery: $searchQuery,
            titleResults: titleResults,
            articleResults: articleResults,
            titleSectionExpanded: $titleSectionExpanded,
            lawArticleSectionExpanded: $lawArticleSectionExpanded,
            interpSectionExpanded: $interpSectionExpanded,
            isRunning: isRunning
        )
        .navigationTitle(lawsExamMode ? "法考法规" : "法律法规")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索法律名称或条文内容")
        .onChange(of: searchQuery)   { _, q in runSearch(q) }
        .onChange(of: excludeArtNum) { _, _ in runSearch(searchQuery) }
        .onChange(of: resultLimit)   { _, _ in runSearch(searchQuery) }
        .onChange(of: lawsExamMode)  { _, _ in
            menu = lawsExamMode ? DatabaseManager.shared.loadLawsExamMenu() : DatabaseManager.shared.loadMenu()
            expandedGroups.removeAll()
            expandedSubgroups.removeAll()
            runSearch(searchQuery)
        }
        .task {
            menu = lawsExamMode ? DatabaseManager.shared.loadLawsExamMenu() : DatabaseManager.shared.loadMenu()
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Search logic

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard !q.isEmpty else {
            titleResults = []; articleResults = []; return
        }
        isRunning = true
        let excl  = excludeArtNum
        let limit = resultLimit
        let cats: [String] = []
        let flk   = lawsExamMode
        let variant = DatabaseManager.numberVariant(of: q)
        let db = DatabaseManager.shared
        searchTask = Task.detached(priority: .userInitiated) {
            var titles = db.searchByTitle(query: q, categories: cats, lawsExamOnly: flk)
            if let v = variant {
                let extra = db.searchByTitle(query: v, categories: cats, lawsExamOnly: flk)
                let seen  = Set(titles.map(\.id))
                titles += extra.filter { !seen.contains($0.id) }
            }
            var articles = db.searchContent(query: q, limit: limit, excludeArticleNumber: excl, categories: cats, lawsExamOnly: flk)
            if let v = variant {
                let extra = db.searchContent(query: v, limit: limit, excludeArticleNumber: excl, categories: cats, lawsExamOnly: flk)
                let seen  = Set(articles.map(\.id))
                articles += extra.filter { !seen.contains($0.id) }
            }
            guard !Task.isCancelled else { return }
            let t = titles; let a = articles
            await MainActor.run {
                titleResults   = t
                articleResults = a
                titleSectionExpanded      = true
                lawArticleSectionExpanded = true
                interpSectionExpanded     = true
                isRunning = false
            }
        }
    }
}

// MARK: - Inner list content (子视图，能正确读到 searchable 注入的 environment)

private struct TOCListContent: View {
    @Binding var target: LawTarget?
    let menu: DatabaseManager.LawMenu?
    @Binding var expandedGroups:    Set<String>
    @Binding var expandedSubgroups: Set<String>
    @Binding var searchQuery: String
    let titleResults:   [LawMeta]
    let articleResults: [SearchResult]
    @Binding var titleSectionExpanded:      Bool
    @Binding var lawArticleSectionExpanded: Bool
    @Binding var interpSectionExpanded:     Bool
    let isRunning: Bool

    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching)   private var isSearching

    private var selectedLawId: Int? { target?.law.id }
    private var lawArticleResults:  [SearchResult] { articleResults.filter { $0.lawCategory != "司法解释" } }
    private var interpArticleResults: [SearchResult] { articleResults.filter { $0.lawCategory == "司法解释" } }

    var body: some View {
        List {
            if searchQuery.isEmpty {
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
                                if isSearching { dismissSearch() }
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
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if titleResults.isEmpty && articleResults.isEmpty {
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
                if !titleResults.isEmpty {
                    Section {
                        if titleSectionExpanded {
                            ForEach(titleResults) { law in
                                Button {
                                    dismissSearch()
                                    target = LawTarget(law: law, scrollToArticle: nil)
                                } label: {
                                    highlightedText(law.title, query: searchQuery, baseFont: .subheadline)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    } header: {
                        collapsibleHeader(title: "法律名称", count: titleResults.count,
                                          expanded: $titleSectionExpanded)
                    }
                }
                if !lawArticleResults.isEmpty {
                    Section {
                        if lawArticleSectionExpanded {
                            ForEach(lawArticleResults) { result in articleResultRow(result) }
                        }
                    } header: {
                        collapsibleHeader(title: "法律法规条文", count: lawArticleResults.count,
                                          expanded: $lawArticleSectionExpanded)
                    }
                }
                if !interpArticleResults.isEmpty {
                    Section {
                        if interpSectionExpanded {
                            ForEach(interpArticleResults) { result in articleResultRow(result) }
                        }
                    } header: {
                        collapsibleHeader(title: "司法解释条文", count: interpArticleResults.count,
                                          expanded: $interpSectionExpanded)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded {
            if isSearching { dismissSearch() }
        })
    }

    @ViewBuilder
    func subgroupRows(groupLabel: String, sub: DatabaseManager.MenuSubgroup) -> some View {
        let subKey     = "\(groupLabel)/\(sub.label)"
        let isExpanded = expandedSubgroups.contains(subKey)
        let isAdminSub = sub.label.hasPrefix("行政法规/")
        let displayLabel = isAdminSub ? String(sub.label.dropFirst("行政法规/".count)) : sub.label

        Button {
            if isSearching { dismissSearch() }
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
            }
        }
    }

    @ViewBuilder
    func lawRow(_ menuLaw: DatabaseManager.MenuLaw) -> some View {
        let isSelected = selectedLawId == menuLaw.id
        Button {
            dismissSearch()
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
        .listRowInsets(EdgeInsets(top: 2, leading: 52, bottom: 2, trailing: 16))
    }

    @ViewBuilder
    private func articleResultRow(_ result: SearchResult) -> some View {
        Button {
            if let law = DatabaseManager.shared.lawMeta(id: result.lawId) {
                dismissSearch()
                target = LawTarget(law: law, scrollToArticle: result.nodeArticleNum)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                highlightedText(result.lawTitle, query: searchQuery, baseFont: .caption)
                    .foregroundStyle(.secondary)
                Text(result.articleNumber)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                highlightedText(result.content, query: searchQuery, baseFont: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private func collapsibleHeader(title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .frame(width: 14)
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
