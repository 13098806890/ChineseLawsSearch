//
//  GongbaoView.swift
//  ChineseLawsSearch
//
//  人民法院公报 — 指导案例 / 司法文件 / 裁判文书 浏览与搜索

import SwiftUI

// MARK: - 来源枚举

enum GongbaoSource: String, CaseIterable, Identifiable {
    case al     = "al"
    case sfwj   = "sfwj"
    case cpwsxd = "cpwsxd"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .al:     return "指导案例"
        case .sfwj:   return "司法文件"
        case .cpwsxd: return "裁判文书"
        }
    }

    var icon: String {
        switch self {
        case .al:     return "star.circle"
        case .sfwj:   return "doc.plaintext"
        case .cpwsxd: return "doc.text.magnifyingglass"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .al:     return "案件名称、案例编号、关键词…"
        case .sfwj:   return "文件标题、关键词…"
        case .cpwsxd: return "案件名称、摘要关键词…"
        }
    }
}

// MARK: - 主视图（sidebar list，供 ContentView 包装进 SplitView / NavigationStack）

struct GongbaoView: View {
    @Binding var selectedDoc: GongbaoDoc?

    @State private var selectedSource: GongbaoSource = .al
    @State private var searchText: String = ""
    @State private var docs: [GongbaoDoc] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            sourcePickerBar
                .padding(.horizontal)
                .padding(.top, 8)

            searchBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                docList(docs: docs)
            }
        }
        .navigationTitle("人民法院公报")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { scheduleReload() }
        .onChange(of: selectedSource) {
            // 切换来源时清空搜索词，然后统一触发一次 reload
            searchText = ""
            scheduleReload(immediate: true)
        }
        .onChange(of: searchText) { scheduleReload() }
    }

    // MARK: 来源选择栏

    private var sourcePickerBar: some View {
        HStack(spacing: 8) {
            ForEach(GongbaoSource.allCases) { src in
                Button {
                    selectedSource = src
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: src.icon)
                            .font(.caption)
                        Text(src.displayName)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        selectedSource == src
                            ? AppColors.shared.searchHighlight
                            : Color(.systemGray5)
                    )
                    .foregroundStyle(selectedSource == src ? .white : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: 搜索框

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(selectedSource.searchPlaceholder, text: $searchText)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 列表

    @ViewBuilder
    private func docList(docs: [GongbaoDoc]) -> some View {
        if docs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "暂无数据" : "无匹配结果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !searchText.isEmpty {
                    Text("换个关键词试试")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(docs, selection: isCompact ? nil : $selectedDoc) { doc in
                if isCompact {
                    Button {
                        selectedDoc = doc
                    } label: {
                        GongbaoDocRow(doc: doc)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    GongbaoDocRow(doc: doc)
                        .tag(doc)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: 防抖加载（300 ms）

    private func scheduleReload(immediate: Bool = false) {
        searchTask?.cancel()
        let delay: UInt64 = immediate ? 0 : 300_000_000 // 300ms
        let src = selectedSource.rawValue
        let q = searchText
        searchTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { isLoading = true }
            let result = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.gongbaoDocs(source: src, query: q)
            }.value
            await MainActor.run {
                docs = result
                isLoading = false
            }
        }
    }
}

// MARK: - 列表行

struct GongbaoDocRow: View {
    let doc: GongbaoDoc

    /// 去掉标题中与 case_number 重复的前缀（al 来源标题常以案号开头）
    private var cleanTitle: String {
        let cn = doc.caseNumber
        guard !cn.isEmpty, doc.title.hasPrefix(cn) else { return doc.title }
        return doc.title.drop(while: { _ in false })  // 保留原，下面处理
            .replacingOccurrences(of: cn, with: "", range: doc.title.range(of: cn))
            .trimmingCharacters(in: .init(charactersIn: "　 ——-：:"))
            .isEmpty ? doc.title :
            doc.title
                .replacingOccurrences(of: cn, with: "", range: doc.title.range(of: cn))
                .trimmingCharacters(in: .init(charactersIn: "　 ——-：:"))
    }

    /// sfwj 通常 ruling_gist 为空，用全文前 80 字作为预览
    private var preview: String {
        if !doc.rulingGist.isEmpty { return doc.rulingGist }
        let text = doc.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let limit = text.index(text.startIndex, offsetBy: min(80, text.count))
        return String(text[..<limit]) + (text.count > 80 ? "…" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cleanTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 8) {
                if !doc.caseNumber.isEmpty {
                    Label(doc.caseNumber, systemImage: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if !doc.issue.isEmpty {
                    Text(doc.issue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !doc.keywords.isEmpty {
                Text(doc.keywords)
                    .font(.caption2)
                    .foregroundStyle(AppColors.shared.searchHighlight.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 详情视图

struct GongbaoDetailView: View {
    let doc: GongbaoDoc

    private var cleanTitle: String {
        let cn = doc.caseNumber
        guard !cn.isEmpty, let r = doc.title.range(of: cn) else { return doc.title }
        let trimmed = doc.title.replacingCharacters(in: r, with: "")
            .trimmingCharacters(in: .init(charactersIn: "　 ——-：:"))
        return trimmed.isEmpty ? doc.title : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(cleanTitle)
                    .font(.title3.weight(.semibold))

                metaRow

                Divider()

                if !doc.rulingGist.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.bubble")
                                .foregroundStyle(AppColors.shared.searchHighlight)
                            Text("裁判要点")
                                .font(.headline)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                        Text(doc.rulingGist)
                            .font(.callout)
                    }
                    .padding()
                    .background(AppColors.shared.searchHighlight.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if !doc.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关键词").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Text(doc.keywords).font(.footnote).foregroundStyle(AppColors.shared.searchHighlight)
                    }
                }

                Divider()

                // 用段落分割避免一次性渲染超大 Text
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(doc.fullText.components(separatedBy: "\n").enumerated()), id: \.offset) { _, para in
                        let line = para.trimmingCharacters(in: .whitespaces)
                        if !line.isEmpty {
                            Text(line)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(sourceLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !doc.url.isEmpty, let url = URL(string: doc.url) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
    }

    private var sourceLabel: String {
        switch doc.source {
        case "al":     return "指导案例"
        case "sfwj":   return "司法文件"
        case "cpwsxd": return "裁判文书"
        default:       return "公报"
        }
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            if !doc.caseNumber.isEmpty {
                Label(doc.caseNumber, systemImage: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !doc.issue.isEmpty {
                Label(doc.issue, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - GongbaoDoc: Hashable, Equatable

extension GongbaoDoc: Hashable, Equatable {
    static func == (lhs: GongbaoDoc, rhs: GongbaoDoc) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    NavigationStack {
        GongbaoView(selectedDoc: .constant(nil))
    }
}
