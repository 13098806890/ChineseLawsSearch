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
    @State private var showOptions = false
    @State private var excludeArticleNum = false
    @State private var resultLimit = 50

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
                            Section("法律名称") {
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
                            Section("条文内容（前 \(articleResults.count) 条）") {
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
                                            Text(result.articleNumber)
                                                .font(.subheadline).bold()
                                                .foregroundStyle(.primary)
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
        }
    }

    private func select(law: LawMeta, articleNum: Int?) {
        onSelect(law, articleNum)
        isPresented = false
    }

    // MARK: - 高亮关键词

    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }
        // 同时高亮原词和数字变体
        let keywords = [query, DatabaseManager.numberVariant(of: query)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        // 找出所有匹配区间（不区分大小写）
        var ranges: [Range<String.Index>] = []
        for kw in keywords {
            var searchFrom = text.startIndex
            while searchFrom < text.endIndex,
                  let r = text.range(of: kw, options: .caseInsensitive, range: searchFrom..<text.endIndex) {
                ranges.append(r)
                searchFrom = r.upperBound
            }
        }
        guard !ranges.isEmpty else { return Text(text) }

        // 合并重叠区间，按位置排序后拼成 Text
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in sorted {
            if let last = merged.last, last.upperBound >= r.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }

        var result = Text("")
        var cur = text.startIndex
        for r in merged {
            if cur < r.lowerBound {
                result = result + Text(String(text[cur..<r.lowerBound]))
            }
            result = result + Text(String(text[r]))
                .foregroundColor(AppColors.shared.searchHighlight)
                .bold()
            cur = r.upperBound
        }
        if cur < text.endIndex {
            result = result + Text(String(text[cur...]))
        }
        return result
    }

    // MARK: - 选项面板

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("屏蔽「第X条」编号匹配（仅搜正文）", isOn: $excludeArticleNum)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - 搜索

    private func runSearch(_ q: String) {
        guard !q.isEmpty else {
            titleResults   = []
            articleResults = []
            return
        }
        isSearching = true
        let excl    = excludeArticleNum
        let limit   = resultLimit
        let variant = DatabaseManager.numberVariant(of: q)

        Task.detached(priority: .userInitiated) {
            var titles = DatabaseManager.shared.searchByTitle(query: q)
            if let v = variant {
                let extra = DatabaseManager.shared.searchByTitle(query: v)
                let seen  = Set(titles.map(\.id))
                titles += extra.filter { !seen.contains($0.id) }
            }

            var articles = DatabaseManager.shared.searchContent(
                query: q, limit: limit, excludeArticleNumber: excl)
            if let v = variant {
                let extra = DatabaseManager.shared.searchContent(
                    query: v, limit: limit, excludeArticleNumber: excl)
                let seen = Set(articles.map(\.id))
                articles += extra.filter { !seen.contains($0.id) }
            }

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
