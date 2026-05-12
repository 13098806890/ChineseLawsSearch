//
//  LawDetailView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct LawDetailView: View {
    let target: LawTarget
    let navigate: (Int, Int?) -> Void
    var canGoBack: Bool = false
    var goBack: () -> Void = {}

    @EnvironmentObject private var userStore: UserStore

    @State private var nodes: [LawNode] = []
    @State private var outgoingMap: [Int: [OutgoingRef]] = [:]
    @State private var incomingMap: [Int: [IncomingRef]] = [:]
    @State private var highlightedArticle: Int? = nil
    @State private var scrollPosition: Int? = nil
    @State private var isSearching = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool

    var law: LawMeta { target.law }

    // 过滤后的节点：搜索模式下只保留含关键词的 article
    private var displayedNodes: [LawNode] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard isSearching && !q.isEmpty else { return nodes }
        return nodes.filter { node in
            node.type == "article" && node.content.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !isSearching {
                    VStack(alignment: .leading, spacing: 8) {
                        if !law.issuingOrg.isEmpty {
                            MetaRow(label: "发布机关", value: law.issuingOrg)
                        }
                        if !law.docNumber.isEmpty {
                            MetaRow(label: "发文字号", value: law.docNumber)
                        }
                        if !law.pubDate.isEmpty {
                            MetaRow(label: "发布日期", value: law.pubDate)
                        }
                        if !law.effectiveDate.isEmpty {
                            MetaRow(label: "实施日期", value: law.effectiveDate)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .id(-1)

                    Divider()
                }

                ForEach(displayedNodes) { node in
                    NodeRowView(
                        node: node,
                        outgoing: node.articleNum.flatMap { outgoingMap[$0] } ?? [],
                        incoming: node.articleNum.flatMap { incomingMap[$0] } ?? [],
                        highlighted: node.articleNum != nil && node.articleNum == highlightedArticle,
                        navigate: navigate
                    )
                    .id(node.id)
                }

                if isSearching && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && displayedNodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("未找到「\(searchQuery)」相关条文")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            // 始终渲染，用 frame(height:) 控制占位，避免视图增删导致 ScrollView 重布局卡顿和内容重叠
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索本法条文…", text: $searchQuery)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                Divider()
            }
            .background(.bar)
            .frame(height: isSearching ? nil : 0, alignment: .top)
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)
            .clipped()
        }
        .overlay(alignment: .trailing) {
            if !nodes.isEmpty && !isSearching && userStore.showSideIndex {
                SideIndexBar(nodes: nodes) { nodeId, articleNum in
                    scrollPosition = nodeId
                    if let a = articleNum {
                        withAnimation(.easeIn(duration: 0.2)) { highlightedArticle = a }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation(.easeOut(duration: 0.6)) { highlightedArticle = nil }
                        }
                    }
                }
            }
        }
        .task(id: target) {
            let lawId = law.id
            highlightedArticle = nil
            scrollPosition = -1

            async let nodesTask = DatabaseManager.shared.nodes(lawId: lawId)
            async let ogTask    = DatabaseManager.shared.outgoingRefsForLaw(lawId: lawId)
            async let icTask    = DatabaseManager.shared.incomingRefsForLaw(lawId: lawId)
            let (loadedNodes, ogList, icList) = await (nodesTask, ogTask, icTask)
            nodes = loadedNodes
            outgoingMap = Dictionary(grouping: ogList, by: \.fromArticleNum)
            incomingMap = Dictionary(grouping: icList, by: \.toArticleNum)

            if let artNum = target.scrollToArticle,
               let targetNode = loadedNodes.first(where: { $0.articleNum == artNum }) {
                try? await Task.sleep(for: .milliseconds(50))
                scrollPosition = targetNode.id
                withAnimation(.easeIn(duration: 0.2)) {
                    highlightedArticle = artNum
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.6)) {
                    highlightedArticle = nil
                }
            }
        }
        .onChange(of: isSearching) { _, searching in
            if searching {
                searchFocused = true
                scrollPosition = nil
            } else {
                scrollPosition = nil
            }
        }
        .navigationTitle(law.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canGoBack {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("返回")
                                .font(.body)
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSearching {
                    Button("完成") {
                        isSearching = false
                        searchQuery = ""
                        searchFocused = false
                    }
                } else {
                    Button {
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }
}

// MARK: - MetaRow

struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - NodeRowView

struct NodeRowView: View {
    let node: LawNode
    let outgoing: [OutgoingRef]
    let incoming: [IncomingRef]
    let highlighted: Bool
    let navigate: (Int, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch node.type {
            case "part":
                Text(node.content)
                    .font(.title2).bold()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .padding(.horizontal)
            case "chapter":
                Text(node.content)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                    .background(Color.appSecondaryBackground)
            case "section":
                Text(node.content)
                    .font(.subheadline).bold()
                    .padding(.vertical, 8)
                    .padding(.horizontal)
            default: // article
                ArticleView(
                    content: node.content,
                    outgoing: outgoing,
                    incoming: incoming,
                    navigate: navigate
                )
                Divider().padding(.leading).opacity(0.4)
            }
        }
        .background(highlighted ? AppColors.shared.articleHighlight.opacity(0.15) : Color.clear)
        .clipped()
    }
}

// MARK: - ArticleView

struct ArticleView: View {
    let content: String
    let outgoing: [OutgoingRef]
    let incoming: [IncomingRef]
    let navigate: (Int, Int?) -> Void

    // 把单段文字里的 rawText 替换成超链接
    func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for ref in outgoing {
            var searchFrom = result.startIndex
            while let range = result[searchFrom...].range(of: ref.rawText) {
                result[range].link = URL(string: "lawlink://\(ref.toLawId)/\(ref.toArticleNum)")
                result[range].foregroundColor = AppColors.shared.outgoingRef
                searchFrom = range.upperBound
            }
        }
        return result
    }

    var paragraphs: [String] {
        content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { i, para in
                Text(attributed(para))
                    .font(.body)
                    .padding(.top, i == 0 ? 0 : 2)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "lawlink",
                              let host = url.host, let lawId = Int(host),
                              let artStr = url.pathComponents.dropFirst().first,
                              let artNum = Int(artStr) else { return .discarded }
                        navigate(lawId, artNum)
                        return .handled
                    })
            }

            if !incoming.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(incoming.enumerated()), id: \.element.id) { i, ref in
                        IncomingRefBadge(index: i + 1, ref: ref, navigate: navigate)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
    }
}

// MARK: - IncomingRefBadge

struct IncomingRefBadge: View {
    let index: Int
    let ref: IncomingRef
    let navigate: (Int, Int?) -> Void

    var body: some View {
        Button {
            navigate(ref.fromLawId, ref.fromArticleNum)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("[\(index)]")
                    .font(.caption2)
                    .foregroundStyle(AppColors.shared.incomingRef)
                Text("《\(ref.fromLawTitle)》\(ref.fromArticleLabel)")
                    .font(.caption2)
                    .foregroundStyle(AppColors.shared.incomingRef.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SideIndexBar

struct SideIndexBar: View {
    let nodes: [LawNode]
    let onSelect: (Int, Int?) -> Void

    // 只取 article 节点，按 globalOrder 排好（预计算，不在手势事件中重算）
    private let articles: [LawNode]
    private let precomputedSamples: [(label: String, idx: Int)]

    init(nodes: [LawNode], onSelect: @escaping (Int, Int?) -> Void) {
        self.nodes = nodes
        self.onSelect = onSelect
        let arts = nodes.filter { $0.type == "article" }
            .sorted { $0.globalOrder < $1.globalOrder }
        self.articles = arts
        // Pre-sample with a generous max; body will slice to visible count
        let maxSamples = min(120, arts.count)
        var samples: [(String, Int)] = []
        if maxSamples > 0 {
            for i in 0..<maxSamples {
                let idx = i * (arts.count - 1) / max(1, maxSamples - 1)
                let node = arts[min(idx, arts.count - 1)]
                let label = node.articleNum.map { "\($0)" } ?? "\(idx + 1)"
                samples.append((label, idx))
            }
        }
        self.precomputedSamples = samples
    }

    private func samples(maxCount: Int) -> [(label: String, idx: Int)] {
        guard !precomputedSamples.isEmpty else { return [] }
        let count = min(maxCount, precomputedSamples.count)
        guard count > 0 else { return [] }
        let step = max(1, precomputedSamples.count / count)
        return stride(from: 0, to: precomputedSamples.count, by: step)
            .prefix(count)
            .map { precomputedSamples[$0] }
    }

    // 按触摸 Y 跳到离触摸点最近的那个标注数字对应的 article
    private func jump(locationY: CGFloat, firstCenter: CGFloat, rowH: CGFloat,
                      items: [(offset: Int, element: (label: String, idx: Int))]) {
        guard !items.isEmpty else { return }
        let nearest = items.min(by: { a, b in
            let yA = firstCenter + CGFloat(a.offset) * rowH * 2
            let yB = firstCenter + CGFloat(b.offset) * rowH * 2
            return abs(yA - locationY) < abs(yB - locationY)
        })!
        let node = articles[nearest.element.idx]
        onSelect(node.id, node.articleNum)
    }

    var body: some View {
        GeometryReader { geo in
            let rowH: CGFloat = 18
            let padding: CGFloat = 4
            let available = geo.size.height - padding * 2
            let maxLabels = max(2, Int(available / (rowH * 2)))
            let items = samples(maxCount: maxLabels)

            // 标签列实际高度：n个标签 + (n-1)个点，每行都是 rowH
            let labelCount = items.count
            let dotCount = max(0, labelCount - 1)
            let listHeight = CGFloat(labelCount + dotCount) * rowH
            // 标签列在 GeometryReader 中的起始 Y（居中）
            let listTop = (geo.size.height - listHeight) / 2

            // 第一个标签中心 Y
            let firstCenter = listTop + rowH / 2

            ZStack(alignment: .center) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                jump(locationY: v.location.y, firstCenter: firstCenter,
                                     rowH: rowH, items: Array(items.enumerated()))
                            }
                    )

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        if i > 0 {
                            Text("·")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .frame(height: rowH)
                                .allowsHitTesting(false)
                        }
                        Text(item.label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppColors.shared.folderIcon)
                            .lineLimit(1)
                            .frame(height: rowH)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: 36)
            .padding(.vertical, padding)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 36)
        .padding(.trailing, 4)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
