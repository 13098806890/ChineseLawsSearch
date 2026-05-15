//
//  GongbaoView.swift
//  ChineseLawsSearch
//
//  人民法院公报 — 指导案例 / 司法文件 / 裁判文书 浏览与搜索

import SwiftUI
import UIKit

// MARK: - 来源枚举

enum GazetteSource: String, CaseIterable, Identifiable {
    case guidingCase      = "al"
    case judicialDoc      = "sfwj"
    case selectedCase     = "cpwsxd"
    case interpretation   = "sfjs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .guidingCase:     return "指导案例"
        case .judicialDoc:   return "司法文件"
        case .selectedCase: return "裁判文书"
        case .interpretation:   return "司法解释"
        }
    }

    var icon: String {
        switch self {
        case .guidingCase:     return "lightbulb.circle"
        case .judicialDoc:   return "doc.plaintext"
        case .selectedCase: return "doc.text.magnifyingglass"
        case .interpretation:   return "text.book.closed"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .guidingCase:     return "案件名称、案例编号、关键词…"
        case .judicialDoc:   return "文件标题、关键词…"
        case .selectedCase: return "案件名称、摘要关键词…"
        case .interpretation:   return "标题、发文字号、关键词…"
        }
    }
}

// MARK: - 主视图（sidebar list，供 ContentView 包装进 SplitView / NavigationStack）

struct GazetteView: View {
    @Binding var selectedDoc: GazetteDoc?
    var navigate: (Int, Int?) -> Void = { _, _ in }
    var navigateToLaw: (LawTarget) -> Void = { _ in }
    /// Called when the user taps a doc row — ContentView gates access before setting selectedDoc.
    var onSelectDoc: (GazetteDoc) -> Void = { _ in }

    @State private var selectedSource: GazetteSource = .guidingCase
    @State private var searchText: String = ""
    @State private var docs: [GazetteDoc] = []
    @State private var sfjsDocs: [LawMeta] = []
    @State private var counts: [GazetteSource: Int] = [:]
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var hasLoaded = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    @State private var showIntro: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            sourcePickerBar
                .padding(.horizontal)
                .padding(.top, 8)

            searchBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            if isCompact && searchText.isEmpty {
                introBanner
            }

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedSource == .interpretation {
                sfjsList(docs: sfjsDocs)
            } else {
                docList(docs: docs)
            }
        }
        .navigationTitle("最高人民法院公报")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            scheduleReload(immediate: true)
        }
        .onDisappear { searchTask?.cancel() }
        .onChange(of: selectedSource) {
            // 切换来源时清空搜索词，然后统一触发一次 reload
            // Note: searchText = "" triggers onChange(of: searchText) → scheduleReload(),
            // which cancels the first scheduleReload call here via the Task mechanism.
            searchText = ""
            scheduleReload(immediate: true)
        }
        .onChange(of: searchText) { scheduleReload() }
    }

    // MARK: 介绍 Banner（compact 模式，可折叠）

    private var introBanner: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showIntro.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("关于最高人民法院公报")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showIntro ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)

            if showIntro {
                VStack(alignment: .leading, spacing: 10) {
                    bannerRow(icon: "star.circle.fill", color: .orange, title: "指导案例",
                              desc: "最高人民法院发布的典型案例，确立裁判规则，对同类案件具有参考指导效力。")
                    bannerRow(icon: "doc.text.fill", color: .blue, title: "裁判文书",
                              desc: "公报收录的重要判决，代表最高人民法院对法律适用的权威立场。")
                    bannerRow(icon: "book.closed.fill", color: .green, title: "司法解释",
                              desc: "就具体法律适用问题发布的解释性文件，与法律条文具有同等适用效力。")
                    bannerRow(icon: "megaphone.fill", color: .purple, title: "司法文件",
                              desc: "通知、规定、批复等规范性文件，对下级法院审判工作具有约束力。")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
            }
            Divider()
        }
    }

    private func bannerRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 来源选择栏

    private var sourcePickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(GazetteSource.allCases) { src in
                Button {
                    selectedSource = src
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: src.icon)
                            .font(.system(size: 10))
                        Text(src.displayName)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selectedSource == src
                            ? AppColors.shared.searchHighlight
                            : Color(.systemGray5)
                    )
                    .foregroundStyle(selectedSource == src ? .white : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer()
          }
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
    private func docList(docs: [GazetteDoc]) -> some View {
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
                        onSelectDoc(doc)
                    } label: {
                        GazetteDocRow(doc: doc)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onSelectDoc(doc)
                    } label: {
                        GazetteDocRow(doc: doc)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(doc)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: 防抖加载（300 ms）

    private func scheduleReload(immediate: Bool = false) {
        searchTask?.cancel()
        let delay: UInt64 = immediate ? 0 : 300_000_000
        let src = selectedSource
        let q = searchText
        searchTask = Task {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            await MainActor.run { isLoading = true }

            if src == .interpretation {
                async let sfjsResult = Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.searchByTitle(query: q.isEmpty ? "" : q, limit: 500,
                                                         categories: ["司法解释"])
                        .filter { $0.source == "gongbao" }
                }.value
                async let allCounts = Task.detached(priority: .userInitiated) {
                    var result: [GazetteSource: Int] = [:]
                    for source in GazetteSource.allCases where source != .interpretation {
                        result[source] = DatabaseManager.shared.gazetteCount(source: source.rawValue, query: q)
                    }
                    return result
                }.value
                let (sfjs, newCounts) = await (sfjsResult, allCounts)
                guard !Task.isCancelled else { return }
                var updatedCounts = newCounts
                updatedCounts[.interpretation] = sfjs.count
                await MainActor.run { sfjsDocs = sfjs; counts = updatedCounts; isLoading = false }
            } else {
                async let mainDocs = Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.gazetteDocs(source: src.rawValue, query: q)
                }.value
                async let allCounts = Task.detached(priority: .userInitiated) {
                    var result: [GazetteSource: Int] = [:]
                    for source in GazetteSource.allCases where source != .interpretation {
                        result[source] = DatabaseManager.shared.gazetteCount(source: source.rawValue, query: q)
                    }
                    result[.interpretation] = DatabaseManager.shared.searchByTitle(query: q, limit: 1000, categories: ["司法解释"])
                        .filter { $0.source == "gongbao" }.count
                    return result
                }.value
                let (result, newCounts) = await (mainDocs, allCounts)
                guard !Task.isCancelled else { return }
                await MainActor.run { docs = result; counts = newCounts; isLoading = false }
            }
        }
    }
}

// MARK: - 司法解释列表（GongbaoView 内部方法抽到扩展）
extension GazetteView {
    @ViewBuilder
    func sfjsList(docs: [LawMeta]) -> some View {
        if docs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: searchText.isEmpty ? "text.book.closed" : "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "暂无数据" : "无匹配结果")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(docs, id: \.id) { doc in
                Button {
                    if let law = DatabaseManager.shared.lawMeta(id: doc.id) {
                        navigateToLaw(LawTarget(law: law, scrollToArticle: nil))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if !doc.pubDate.isEmpty {
                                Text(doc.pubDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !doc.docNumber.isEmpty {
                                Text(doc.docNumber)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - 列表行

struct GazetteDocRow: View {
    let doc: GazetteDoc

    /// 去掉标题中与 case_number 重复的前缀（al 来源标题常以案号开头）
    private var cleanTitle: String {
        let cn = doc.caseNumber
        guard !cn.isEmpty, let range = doc.title.range(of: cn) else { return doc.title }
        let trimmed = doc.title.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .init(charactersIn: "　 ——-：:"))
        return trimmed.isEmpty ? doc.title : trimmed
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
                    HStack(spacing: 2) {
                        Image(systemName: "lightbulb")
                            .font(.caption2)
                        Text(doc.caseNumber)
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
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

struct GazetteDetailView: View {
    let doc: GazetteDoc
    var navigateBack: (() -> Void)? = nil
    var backLabel: String = "返回法条"
    @EnvironmentObject private var userStore: UserStore

    private var isFav: Bool { userStore.isGazetteFavorited(docId: doc.id) }
    @State private var showNoteSheet = false
    private var hasNote: Bool { !userStore.gazetteNote(docId: doc.id).isEmpty }

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

                // 笔记展示块
                let note = userStore.gazetteNote(docId: doc.id)
                if !note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("我的笔记")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

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

                // 用段落分割避免一次性渲染超大 Text；过滤孤立标点行，区分标题行与正文
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(doc.fullText.components(separatedBy: "\n").enumerated()), id: \.offset) { _, para in
                        let line = para.trimmingCharacters(in: .whitespaces)
                        // 跳过空行和孤立括号行（如单独的 "】" "】" "]"）
                        let isJunk = line.isEmpty || line.allSatisfy { "】】[]【【「」『』".contains($0) }
                        if !isJunk {
                            // 【标题】行用加粗样式
                            let isHeading = line.hasPrefix("【") || line.hasPrefix("【")
                            Text(line)
                                .font(isHeading ? .callout.weight(.semibold) : .callout)
                                .foregroundStyle(isHeading ? AppColors.shared.searchHighlight : .primary)
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
            if let back = navigateBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        back()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(backLabel)
                                .font(.body)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showNoteSheet = true
                    } label: {
                        Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                            .foregroundStyle(hasNote ? AppColors.shared.searchHighlight : .secondary)
                    }
                    Button {
                        if isFav {
                            userStore.removeGazetteFavorite(docId: doc.id)
                        } else {
                            userStore.addGazetteFavorite(
                                FavoriteGazetteDoc(
                                    docId: doc.id,
                                    source: doc.source,
                                    title: doc.title,
                                    rulingGist: doc.rulingGist,
                                    issue: doc.issue
                                )
                            )
                        }
                    } label: {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .foregroundStyle(isFav ? AppColors.shared.searchHighlight : .secondary)
                    }
                    Menu {
                        Button("纯文本") { shareAsText() }
                        Button("PDF 文件") { shareAsPDF() }
                    } label: {
                        Image(systemName: "paperplane")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            GazetteNoteSheet(doc: doc)
                .environmentObject(userStore)
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

    // MARK: 分享

    private func plainText() -> String {
        var parts: [String] = [doc.title]
        if !doc.caseNumber.isEmpty { parts.append("案号：\(doc.caseNumber)") }
        if !doc.issue.isEmpty { parts.append("期次：\(doc.issue)") }
        if !doc.rulingGist.isEmpty { parts.append("\n裁判要点：\n\(doc.rulingGist)") }
        if !doc.keywords.isEmpty { parts.append("\n关键词：\(doc.keywords)") }
        if !doc.fullText.isEmpty { parts.append("\n\(doc.fullText)") }
        return parts.joined(separator: "\n")
    }

    private func shareAsText() {
        let text = plainText()
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        present(av)
    }

    private func shareAsPDF() {
        let text = plainText()
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11)
            ]
            let margin: CGFloat = 40
            let maxWidth = pageRect.width - margin * 2

            // Title
            let titleStr = NSAttributedString(string: doc.title + "\n\n", attributes: titleAttrs)
            let bodyStr  = NSAttributedString(string: text.replacingOccurrences(of: doc.title + "\n", with: ""),
                                              attributes: bodyAttrs)
            let full = NSMutableAttributedString()
            full.append(titleStr)
            full.append(bodyStr)

            let framesetter = CTFramesetterCreateWithAttributedString(full)
            var charIndex = 0

            while charIndex < full.length {
                let frameRect = CGRect(x: margin, y: margin, width: maxWidth, height: pageRect.height - margin * 2)
                let path = CGPath(rect: frameRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(charIndex, 0), path, nil)
                let range = CTFrameGetVisibleStringRange(frame)
                if range.length == 0 { break }

                // Flip coordinate for CoreText
                let uiCtx = UIGraphicsGetCurrentContext()!
                uiCtx.saveGState()
                uiCtx.translateBy(x: 0, y: pageRect.height)
                uiCtx.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, uiCtx)
                uiCtx.restoreGState()

                charIndex += range.length
                if charIndex < full.length {
                    ctx.beginPage()
                }
            }
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(doc.title.prefix(30)).pdf")
        try? data.write(to: tmpURL)
        let av = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        present(av)
    }

    private func present(_ vc: UIActivityViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let popover = vc.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.safeAreaInsets.top + 44, width: 0, height: 0)
            popover.permittedArrowDirections = .up
        }
        top.present(vc, animated: true)
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            if !doc.caseNumber.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "lightbulb")
                    Text(doc.caseNumber)
                }
                .font(.caption)
                .foregroundStyle(.blue)
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

// MARK: - GazetteDoc: Hashable, Equatable

extension GazetteDoc: Hashable, Equatable {
    static func == (lhs: GazetteDoc, rhs: GazetteDoc) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 笔记 Sheet

struct GazetteNoteSheet: View {
    let doc: GazetteDoc
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("笔记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            userStore.setGazetteNote(docId: doc.id, text: text)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
        .onAppear { text = userStore.gazetteNote(docId: doc.id) }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 公报介绍视图

struct GazetteWelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(AppColors.shared.searchHighlight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("最高人民法院公报")
                            .font(.title2.bold())
                        Text("权威裁判规则与司法解释")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                infoBlock(
                    icon: "star.circle.fill", color: .orange,
                    title: "指导案例",
                    body: "最高人民法院发布的典型案例，确立裁判规则，对同类案件具有参考指导效力。检索时可按案由、关键词快速定位相关裁判要旨。"
                )

                infoBlock(
                    icon: "doc.text.fill", color: .blue,
                    title: "裁判文书",
                    body: "公报收录的重要二审、再审判决，代表最高人民法院对法律适用的权威立场，是研究疑难问题的第一手资料。"
                )

                infoBlock(
                    icon: "book.closed.fill", color: .green,
                    title: "司法解释",
                    body: "最高人民法院就具体法律适用问题发布的解释性文件，与法律条文具有同等适用效力，是司法实践中引用最频繁的规范依据。"
                )

                infoBlock(
                    icon: "megaphone.fill", color: .purple,
                    title: "司法文件",
                    body: "最高人民法院发布的通知、规定、批复等规范性文件，反映司法政策导向，对下级法院审判工作具有约束力。"
                )

                Text("点击左侧列表中的条目即可查看全文。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func infoBlock(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        GazetteView(selectedDoc: .constant(nil))
    }
}
