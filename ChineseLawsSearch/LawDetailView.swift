//
//  LawDetailView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct LawDetailView: View {
    let target: LawTarget
    let navigate: (Int, Int?) -> Void

    @State private var nodes: [LawNode] = []
    @State private var outgoingMap: [Int: [OutgoingRef]] = [:]
    @State private var incomingMap: [Int: [IncomingRef]] = [:]
    @State private var highlightedArticle: Int? = nil
    @State private var scrollPosition: Int? = nil

    var law: LawMeta { target.law }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 元数据
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
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
                .id(-1)

                Divider()

                ForEach(nodes) { node in
                    NodeRowView(
                        node: node,
                        outgoing: node.articleNum.flatMap { outgoingMap[$0] } ?? [],
                        incoming: node.articleNum.flatMap { incomingMap[$0] } ?? [],
                        highlighted: node.articleNum != nil && node.articleNum == highlightedArticle,
                        navigate: navigate
                    )
                    .id(node.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .task(id: target) {
            let lawId = law.id
            highlightedArticle = nil
            scrollPosition = -1  // 先跳回顶部

            async let nodesTask = Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.nodes(lawId: lawId)
            }.value
            async let ogTask = Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.outgoingRefsForLaw(lawId: lawId)
            }.value
            async let icTask = Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.incomingRefsForLaw(lawId: lawId)
            }.value
            let (loadedNodes, ogList, icList) = await (nodesTask, ogTask, icTask)
            nodes = loadedNodes
            outgoingMap = Dictionary(grouping: ogList, by: \.fromArticleNum)
            incomingMap = Dictionary(grouping: icList, by: \.toArticleNum)

            if let artNum = target.scrollToArticle {
                // 找到目标条文对应的 node.id
                if let targetNode = loadedNodes.first(where: { $0.articleNum == artNum }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollPosition = targetNode.id
                        withAnimation(.easeIn(duration: 0.2)) {
                            highlightedArticle = artNum
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.6)) {
                                highlightedArticle = nil
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(law.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    .background(Color(.systemGroupedBackground))
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
                HStack(spacing: 4) {
                    ForEach(Array(incoming.enumerated()), id: \.element.id) { i, ref in
                        IncomingRefBadge(index: i + 1, ref: ref, navigate: navigate)
                    }
                }
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
            Text("[\(index)]")
                .font(.caption2)
                .foregroundStyle(AppColors.shared.incomingRef)
        }
        .contextMenu {
            Text("被《\(ref.fromLawTitle)》\(ref.fromArticleLabel)引用")
            Divider()
            Button("跳转到引用处") {
                navigate(ref.fromLawId, ref.fromArticleNum)
            }
        }
    }
}
