//
//  SearchView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct SearchView: View {
    @Binding var isPresented: Bool
    let onSelect: (LawMeta, Int?) -> Void   // (law, articleNum?)

    @State private var query = ""
    @State private var titleResults:   [LawMeta]      = []
    @State private var articleResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var showOptions = true
    @State private var excludeArticleNum = true
    @State private var resultLimit = 50
    @State private var includeLaws = true
    @State private var includeInterp = true
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var titleSectionExpanded   = true
    @State private var articleSectionExpanded = true

    @AppStorage("flkMode") private var lawsExamMode: Bool = false

    @EnvironmentObject private var userStore: UserStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showOptions {
                    optionsPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                List {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "输入关键词",
                            systemImage: "text.magnifyingglass",
                            description: Text("搜索法律名称或条文内容")
                        )
                        .listRowBackground(Color.clear)
                    } else if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if titleResults.isEmpty && articleResults.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    } else {
                        if !titleResults.isEmpty {
                            Button {
                                withAnimation { titleSectionExpanded.toggle() }
                            } label: {
                                HStack {
                                    Text("法律名称")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    Text("(\(titleResults.count))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: titleSectionExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.appSecondaryBackground)

                            if titleSectionExpanded {
                                ForEach(titleResults) { law in
                                    Button {
                                        select(law: law, articleNum: nil)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            highlightedText(law.title, query: query)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Text(law.category)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !articleResults.isEmpty {
                            Button {
                                withAnimation { articleSectionExpanded.toggle() }
                            } label: {
                                HStack {
                                    Text("条文内容")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    Text("(前 \(articleResults.count) 条)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: articleSectionExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.appSecondaryBackground)

                            if articleSectionExpanded {
                                ForEach(articleResults) { result in
                                    Button {
                                        if let law = DatabaseManager.shared.lawMeta(id: result.lawId) {
                                            select(law: law, articleNum: result.nodeArticleNum)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.lawTitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            highlightedText(result.content, query: query)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                                .lineLimit(4)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showOptions.toggle() }
                    } label: {
                        Image(systemName: showOptions
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索法律名称或条文内容")
            .onChange(of: query)             { _, q in runSearch(q) }
            .onChange(of: excludeArticleNum) { _, _ in runSearch(query) }
            .onChange(of: resultLimit)       { _, _ in runSearch(query) }
            .onChange(of: includeLaws)       { _, _ in runSearch(query) }
            .onChange(of: includeInterp)     { _, _ in runSearch(query) }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private func select(law: LawMeta, articleNum: Int?) {
        onSelect(law, articleNum)
        isPresented = false
    }

    // MARK: - 选项面板

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("忽略条号匹配（搜「第十条」不会仅因编号命中）", isOn: $excludeArticleNum)
                .font(.subheadline)
            HStack {
                Text("结果上限")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $resultLimit) {
                    Text("50条").tag(50)
                    Text("100条").tag(100)
                    Text("200条").tag(200)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Divider()
            HStack(spacing: 12) {
                Text("范围")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("法律法规", isOn: $includeLaws)
                    .font(.subheadline)
                    .toggleStyle(.button)
                Toggle("司法解释", isOn: $includeInterp)
                    .font(.subheadline)
                    .toggleStyle(.button)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appSecondaryBackground)
    }

    // MARK: - 搜索

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard !q.isEmpty else {
            titleResults   = []
            articleResults = []
            return
        }
        isSearching = true
        let excl  = excludeArticleNum
        let limit = resultLimit
        let cats  = lawsExamMode ? [] : userStore.searchCategories
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

            guard !Task.isCancelled else { return }
            var articles = db.searchContent(
                query: q, limit: limit, excludeArticleNumber: excl, categories: cats, lawsExamOnly: flk)
            if let v = variant {
                let extra = db.searchContent(
                    query: v, limit: limit, excludeArticleNumber: excl, categories: cats, lawsExamOnly: flk)
                let seen = Set(articles.map(\.id))
                articles += extra.filter { !seen.contains($0.id) }
            }
            articles = Array(articles.prefix(limit))

            guard !Task.isCancelled else { return }
            let finalTitles   = titles
            let finalArticles = articles
            await MainActor.run {
                titleResults   = finalTitles
                articleResults = finalArticles
                isSearching    = false
            }
        }
    }
}
