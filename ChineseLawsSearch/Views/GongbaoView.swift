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
}

// MARK: - 主视图

struct GongbaoView: View {
    @State private var selectedSource: GongbaoSource = .al
    @State private var searchText: String = ""
    @State private var selectedDoc: GongbaoDoc? = nil
    @State private var docs: [GongbaoDoc] = []
    @State private var isLoading = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        if isCompact {
            compactLayout
        } else {
            wideLayout
        }
    }

    // MARK: Compact（iPhone）

    private var compactLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 来源选择栏
                sourcePickerBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // 搜索框
                searchBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // 列表
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    docList(docs: docs)
                }
            }
            .navigationTitle("人民法院公报")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDoc) { doc in
                GongbaoDetailView(doc: doc)
            }
        }
        .onAppear { reload() }
        .onChange(of: selectedSource) { reload() }
        .onChange(of: searchText) { reload() }
    }

    // MARK: Wide（iPad / Mac）

    private var wideLayout: some View {
        NavigationSplitView {
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
        } detail: {
            if let doc = selectedDoc {
                GongbaoDetailView(doc: doc)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("选择条目")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reload() }
        .onChange(of: selectedSource) { reload() }
        .onChange(of: searchText) { reload() }
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
            TextField("搜索标题、摘要、关键词…", text: $searchText)
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

    // MARK: 数据加载

    private func reload() {
        isLoading = true
        let src = selectedSource.rawValue
        let q = searchText
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DatabaseManager.shared.gongbaoDocs(source: src, query: q)
            DispatchQueue.main.async {
                docs = result
                isLoading = false
            }
        }
    }
}

// MARK: - 列表行

struct GongbaoDocRow: View {
    let doc: GongbaoDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题
            Text(doc.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            // 案例号 + 期刊
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

            // 裁判摘要
            if !doc.rulingGist.isEmpty {
                Text(doc.rulingGist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 关键词
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
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                Text(doc.title)
                    .font(.title3.weight(.semibold))

                // 元数据行
                metaRow

                Divider()

                // 裁判摘要 / 裁判要点
                if !doc.rulingGist.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("裁判要点", systemImage: "text.quote")
                            .font(.headline)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                        Text(doc.rulingGist)
                            .font(.callout)
                    }
                    .padding()
                    .background(AppColors.shared.searchHighlight.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // 关键词
                if !doc.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关键词").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Text(doc.keywords).font(.footnote).foregroundStyle(AppColors.shared.searchHighlight)
                    }
                }

                Divider()

                // 全文
                Text(doc.fullText)
                    .font(.callout)
                    .textSelection(.enabled)
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

// MARK: - GongbaoDoc: Identifiable, Hashable, Equatable for NavigationLink/selection

extension GongbaoDoc: Hashable, Equatable {
    static func == (lhs: GongbaoDoc, rhs: GongbaoDoc) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    GongbaoView()
}
