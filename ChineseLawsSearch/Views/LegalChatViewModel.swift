//
//  LegalChatViewModel.swift
//  ChineseLawsSearch
//

import SwiftUI
import Combine

final class LegalChatViewModel: ObservableObject {
    @Published var messages:  [ChatMessage] = []
    @Published var inputText  = ""
    /// 正在思考中的 session ID 集合；用 sessionId 查询当前 session 是否在思考
    @Published private var thinkingSessions: Set<UUID> = []
    /// 当前 session 是否正在思考
    var isThinking: Bool { thinkingSessions.contains(sessionId) }
    @Published var dotScale   = [1.0, 1.0, 1.0]
    @Published var scrollToken = 0
    /// 从 chat 跳转到法条/案例前记录的可见消息 ID，返回时用于恢复滚动位置
    @Published var restoreScrollId: UUID? = nil
    @Published var mode: ChatMode = .expert
    @Published var lastFailedQuestion: String? = nil  // set on network error, cleared on retry
    @Published var lastFailedIcon: String = "wifi.exclamationmark"
    @Published var errorMessage: String? = nil         // shown as alert; cleared after dismissal
    @Published var showTimeManipulationAlert = false
    @Published var needsPaywall = false  // consumeIfAllowed 拦截时触发，View 层弹 Paywall

    // 切换 session 时的中断确认
    @Published var showAbortAlert = false
    var pendingSwitchAction: (() -> Void)?   // 用户确认后执行的切换动作

    private let kv = NSUbiquitousKeyValueStore.default
    private let lastSendTimeKey = "lastChatSendTime"

    // Follow-up state (expert mode)
    private(set) var isAwaitingClarification = false  // no longer set; kept for session persistence compat
    private var followUpRound = 0                      // no longer set; kept for session persistence compat
    var pendingFacts: [String: String] = [:]
    var conversationHistory: [(user: String, assistant: String)] = []

    // Intent routing state
    var lastSelectedExperts: [SubExpert] = []   // cached for follow_up reuse
    var lastQueryMode: QueryMode? = nil          // mode used by the last legalQuery turn

    // Session identity for history
    var sessionId = UUID()
    var sessionCreatedAt = Date()
    // Token base from persisted session (new tokens are added on top)
    var tokenBasePrompt: Int = 0
    var tokenBaseCompletion: Int = 0

    private var dotTask: Task<Void, Never>?
    var sendTask: Task<Void, Never>?

    deinit {
        dotTask?.cancel()
        sendTask?.cancel()
    }

    @MainActor
    func toggleStep(messageId: UUID, stepId: UUID) {
        guard let mi = messages.firstIndex(where: { $0.id == messageId }),
              let si = messages[mi].thinkSteps.firstIndex(where: { $0.id == stepId })
        else { return }
        messages[mi].thinkSteps[si].isExpanded.toggle()
    }

    @MainActor
    func toggleSteps(messageId: UUID) {
        guard let mi = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[mi].showSteps.toggle()
    }

    @MainActor
    func toggleCitations(messageId: UUID) {
        guard let mi = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[mi].showCitations.toggle()
    }

    @MainActor
    func toggleGazetteCitations(messageId: UUID) {
        guard let mi = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[mi].showGazetteCitations.toggle()
    }

    /// agent 运行中时拦截切换：弹 alert 让用户确认；否则直接执行。
    @MainActor
    func requestSwitch(historyStore: ChatHistoryStore, action: @escaping () -> Void) {
        if isThinking {
            pendingSwitchAction = action
            showAbortAlert = true
        } else {
            autoSavePublic(historyStore: historyStore)
            action()
        }
    }

    /// 用户确认中断后调用：取消当前任务并执行切换。
    @MainActor
    func confirmAbortAndSwitch(historyStore: ChatHistoryStore) {
        sendTask?.cancel()
        sendTask = nil
        thinkingSessions.remove(sessionId)
        autoSavePublic(historyStore: historyStore)
        pendingSwitchAction?()
        pendingSwitchAction = nil
        showAbortAlert = false
    }

    @MainActor
    func newSession() {
        messages = []
        inputText = ""
        // sessionId 切换后 isThinking 计算属性自动变 false，旧 session 的 thinkingSessions 条目保留直到任务完成
        isAwaitingClarification = false  // kept for legacy session compat        pendingFacts = [:]
        conversationHistory = []
        lastSelectedExperts = []
        lastQueryMode = nil
        sessionId = UUID()
        sessionCreatedAt = Date()
        tokenBasePrompt = 0
        tokenBaseCompletion = 0
        TokenCounter.shared.reset()
    }

    @MainActor
    func loadSession(_ session: ChatSession) {
        sessionId = session.id
        sessionCreatedAt = session.createdAt
        mode = ChatMode(rawValue: session.mode) ?? .expert
        messages = session.messages.map { pm in
            var msg = ChatMessage(
                role: pm.role == "user" ? .user : .assistant,
                text: pm.text,
                isClarifying: pm.isClarifying
            )
            msg.thinkSteps = pm.thinkSteps.map { ts in
                var step = ThinkStep(name: ts.name, content: ts.content)
                step.articles = ts.articles.map {
                    RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                                articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                                category: $0.category, content: $0.content)
                }
                step.gazetteCitations = ts.gazetteCitations
                return step
            }
            msg.citations   = pm.citations.map {
                RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                            articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                            category: $0.category, content: $0.content)
            }
            msg.subQuestions = pm.subQuestions
            msg.gazetteCitations = pm.gazetteCitations
            return msg
        }
        // 恢复专家追问上下文
        isAwaitingClarification = session.isAwaitingClarification
        followUpRound           = session.followUpRound
        pendingFacts            = session.pendingFacts
        lastSelectedExperts     = resolveExperts(names: session.selectedExpertNames)
        lastQueryMode           = session.lastQueryMode.flatMap { QueryMode(rawValue: $0) }
        conversationHistory     = buildConversationHistory()
        tokenBasePrompt         = session.totalPromptTokens
        tokenBaseCompletion     = session.totalCompletionTokens
        TokenCounter.shared.reset()
        // Scroll to top of the newly loaded session
        restoreScrollId = messages.first?.id
    }

    @MainActor
    func send(historyStore: ChatHistoryStore, gazetteNotes: [String: String] = [:]) async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.count >= 2, !isThinking else { return }

        let currentSessionId = sessionId  // capture before any await
        thinkingSessions.insert(currentSessionId)  // 立即标记，防止并发双触发

        // 准入检查：
        // - 免费次数 > 0 → 消耗一次，用内置 key
        // - 免费用完 + 已购买 + 有 key → 直接放行
        // - 其他 → 拦截（canUseAgent 已 disabled，此处兜底）
        if !PurchaseManager.shared.consumeIfAllowed(isFollowUp: false) {
            thinkingSessions.remove(currentSessionId)
            needsPaywall = true
            return
        }

        // 时间篡改检测：当前时间不得早于上次发送时间
        let now = Date().timeIntervalSince1970
        let lastSend = kv.double(forKey: lastSendTimeKey)
        if lastSend > 0 && now < lastSend - 1 {
            showTimeManipulationAlert = true
            return
        }
        kv.set(now, forKey: lastSendTimeKey)

        LegalExpertService.shared.gazetteNotes = gazetteNotes

        lastFailedQuestion = nil
        inputText = ""
        messages.append(ChatMessage(role: .user, text: q))
        // 立即保存用户消息，确保切换对话时不丢失
        autoSave(historyStore: historyStore)

        defer {
            // 无论哪条路径退出，都清除该 session 的 thinking 状态
            thinkingSessions.remove(currentSessionId)
        }

        do {
            // ── Intent classification ──────────────────────────────────────────
            let classified = await LegalExpertService.shared.classifyIntentAndMode(
                message: q, history: conversationHistory)
            let intent = classified.0
            let preMode = classified.1

            // ── Route by intent ────────────────────────────────────────────────
            switch intent {

            // ── Off-topic: hardcoded reply, zero LLM calls ─────────────────────
            case .offTopic:
                var reply = ChatMessage(role: .assistant, text: """
我是律疏法律顾问，由多位细分领域专家协作，自动检索相关法条，给出有依据的法律意见。

支持三种问答模式：

【案情分析】描述您亲历的具体纠纷，专家会分析责任归属并给出维权建议。
示例：我和房东签了一年租约，还有四个月到期，房东突然要求我两周内搬走，并拒绝退押金，我该怎么办？

【法律咨询】询问某类情景下的权利义务，适合提前了解法律规则。
示例：劳动合同到期公司不续签，员工能拿到经济补偿吗？

【法条检索】查询某个法律概念的定义、某罪的构成要件，或某主题的相关条文原文。
示例：交通肇事罪的构成要件是什么？

请直接描述您的法律问题，无需指定模式，我会自动判断并为您解答。
""")
                reply.intent = .offTopic
                messages.append(reply)

            // ── Legal query / Follow-up: run pipeline ──────────────────────────
            case .legalQuery, .followUp:
                try await handleLLMIntent(intent, question: q, preMode: preMode,
                                          historyStore: historyStore,
                                          currentSessionId: currentSessionId)
                return
            }

            // Off-topic path: update history and save
            conversationHistory.append((user: q, assistant: messages.last?.text ?? ""))
            autoSave(historyStore: historyStore)

        } catch {
            // Refund the quota consumed at the top of send() — the request never completed
            PurchaseManager.shared.refundIfNeeded()
            // Remove any partial/empty assistant bubble added during streaming (no citations = incomplete)
            if let last = messages.last, last.role == .assistant,
               last.citations.isEmpty && last.gazetteCitations.isEmpty {
                messages.removeLast()
            }
            // Remove the user message and restore to input box for retry
            if let last = messages.last, last.role == .user {
                messages.removeLast()
            }
            inputText = q
            lastFailedQuestion = q
            lastFailedIcon = {
                switch error as? LLMError {
                case .apiKeyMissing:       return "key.slash"
                case .apiKeyInvalid:       return "key.slash"
                case .insufficientBalance: return "creditcard.trianglebadge.exclamationmark"
                case .rateLimited:         return "clock.badge.exclamationmark"
                case .serverError:         return "exclamationmark.icloud"
                case .none:
                    if (error as? URLError) != nil { return "wifi.exclamationmark" }
                    return "exclamationmark.triangle"
                }
            }()
            errorMessage = (error as? LLMError)?.errorDescription
                ?? (error as? URLError).map { "网络错误：\($0.localizedDescription)" }
                ?? error.localizedDescription
            // Reset multi-turn state so next send starts fresh
            conversationHistory.removeAll()
            isAwaitingClarification = false
            followUpRound = 0
            // 保存已有内容（如有部分回复已展示，保留历史）；否则删除提前写入的空 session
            if !messages.isEmpty {
                autoSave(historyStore: historyStore)
            } else {
                historyStore.delete(id: sessionId)
            }
        }
    }

    /// Handles all intent paths that require an LLM call + reply slot.
    @MainActor
    private func handleLLMIntent(_ intent: MessageIntent, question q: String,
                                  preMode: QueryMode?,
                                  historyStore: ChatHistoryStore,
                                  currentSessionId: UUID) async throws {
        var replyMsg = ChatMessage(role: .assistant)
        replyMsg.intent = intent
        messages.append(replyMsg)
        let replyIdx = messages.count - 1

        let citations: [RAGCitation]

        switch intent {
        case .offTopic:
            fatalError("handleLLMIntent called with .offTopic — should never happen")

        case .followUp:
            if lastSelectedExperts.isEmpty {
                // No prior case context — treat as fresh legal query (Mod 6: use preMode)
                let (c, mode) = try await LegalExpertService.shared.askLegalQuery(
                    question: q,
                    conversationHistory: conversationHistory,
                    knownFacts: pendingFacts,
                    preClassifiedMode: preMode ?? .legalAdvisory
                ) { [weak self] event in
                    self?.handleEvent(event, replyIdx: replyIdx, sessionId: currentSessionId)
                }
                _ = mode
                citations = c
            } else {
                let (c, updatedExperts) = try await LegalExpertService.shared.askFollowUp(
                    question: q,
                    lastExperts: lastSelectedExperts,
                    conversationHistory: conversationHistory,
                    knownFacts: pendingFacts
                ) { [weak self] event in
                    self?.handleEvent(event, replyIdx: replyIdx, sessionId: currentSessionId)
                }
                lastSelectedExperts = updatedExperts
                citations = c
            }

        case .legalQuery:
            // Reset state for fresh queries
            lastSelectedExperts = []
            pendingFacts = [:]
            let (c, mode) = try await LegalExpertService.shared.askLegalQuery(
                question: q,
                conversationHistory: conversationHistory,
                knownFacts: pendingFacts,
                preClassifiedMode: preMode
            ) { [weak self] event in
                self?.handleEvent(event, replyIdx: replyIdx, sessionId: currentSessionId)
            }
            lastQueryMode = mode
            citations = c
        }

        if replyIdx < messages.count {
            // 补全 citations：扫描正文里 《...》第X条，把数据库能查到但 RAG 未返回的条文追加进去
            let answerText = messages[replyIdx].text
            let extra = Self.extractCitationsFromText(answerText, existing: citations)
            messages[replyIdx].citations = citations + extra
        }

        if lastFailedQuestion == nil && sessionId == currentSessionId {
            let assistantText = messages.last(where: { $0.role == .assistant })?.text ?? ""
            conversationHistory.append((user: q, assistant: assistantText))
            autoSave(historyStore: historyStore)
        }
    }

    @MainActor
    private func handleEvent(_ event: RAGEvent, replyIdx: Int, sessionId: UUID) {
        // 如果用户已新建会话，丢弃旧任务的事件，防止写入新会话
        guard sessionId == self.sessionId else { return }
        guard replyIdx < messages.count else { return }
        switch event {
        case .thinkStep(let name, let content):
            messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content))
        case .thinkStepWithArticles(let name, let content, let articles):
            messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content, articles: articles))
        case .thinkStepWithGazette(let name, let content, let gazetteCitations):
            messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content, gazetteCitations: gazetteCitations))
        case .subQuestions(let qs):
            messages[replyIdx].subQuestions = qs
        case .token(let t):
            messages[replyIdx].text += t
            thinkingSessions.remove(sessionId)  // 收到第一个 token，停止 spinner
            scrollToken += 1
        case .clarifyingQuestion(let text):
            messages[replyIdx].text = text
            messages[replyIdx].isClarifying = true
            thinkingSessions.remove(sessionId)  // 收到追问，停止 spinner
            isAwaitingClarification = true
            scrollToken += 1
        case .expertsSelected(let experts):
            lastSelectedExperts = experts
        case .gazetteCitations(let cites):
            messages[replyIdx].gazetteCitations = cites
        }
    }

    @MainActor
    func autoSavePublic(historyStore: ChatHistoryStore) {
        autoSave(historyStore: historyStore)
    }

    @MainActor
    private func autoSave(historyStore: ChatHistoryStore) {
        guard !messages.isEmpty else { return }
        let rawTitle = messages.first(where: { $0.role == .user })?.text
            .prefix(40)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "新对话" : rawTitle
        let session = ChatSession(
            id: sessionId,
            title: String(title),
            mode: mode.rawValue,
            createdAt: sessionCreatedAt,
            updatedAt: Date(),
            messages: messages.map { msg in
                PersistedMessage(
                    role: msg.role == .user ? "user" : "assistant",
                    text: msg.text,
                    thinkSteps: msg.thinkSteps.map { ts in
                        PersistedThinkStep(
                            name: ts.name, content: ts.content,
                            articles: ts.articles.map {
                                PersistedCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                                                  articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                                                  category: $0.category, content: $0.content)
                            },
                            gazetteCitations: ts.gazetteCitations
                        )
                    },
                    citations: msg.citations.map {
                        PersistedCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                                          articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                                          category: $0.category, content: $0.content)
                    },
                    subQuestions: msg.subQuestions,
                    isClarifying: msg.isClarifying,
                    gazetteCitations: msg.gazetteCitations
                )
            },
            selectedExpertNames: lastSelectedExperts.map { $0.name },
            pendingFacts: pendingFacts,
            isAwaitingClarification: isAwaitingClarification,
            followUpRound: followUpRound,
            lastQueryMode: lastQueryMode?.rawValue,
            totalPromptTokens: tokenBasePrompt + TokenCounter.shared.session.promptTokens,
            totalCompletionTokens: tokenBaseCompletion + TokenCounter.shared.session.completionTokens
        )
        historyStore.save(session)
    }

    private func resolveExperts(names: [String]) -> [SubExpert] {
        let allExperts = allExpertGroups.values.flatMap { $0.subExperts }
        let nameMap = Dictionary(allExperts.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return names.compactMap { nameMap[$0] }
    }

    private func buildConversationHistory() -> [(user: String, assistant: String)] {
        var pairs: [(user: String, assistant: String)] = []
        var i = 0
        while i < messages.count {
            guard messages[i].role == .user else { i += 1; continue }
            let userText = messages[i].text
            // Find the next assistant message (not necessarily adjacent)
            var j = i + 1
            while j < messages.count && messages[j].role != .assistant { j += 1 }
            if j < messages.count {
                pairs.append((user: userText, assistant: messages[j].text))
                i = j + 1
            } else {
                break
            }
        }
        return pairs
    }

    @MainActor
    func startDotAnimation() {
        dotTask = Task { @MainActor in
            while !Task.isCancelled {
                for i in 0..<3 {
                    dotScale[i] = 1.4
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    dotScale[i] = 1.0
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    @MainActor
    func stopDotAnimation() {
        dotTask?.cancel()
        dotTask = nil
    }

    @MainActor
    func exportMarkdown() -> String {
        var lines: [String] = ["法律咨询记录\n"]
        for msg in messages {
            switch msg.role {
            case .user:
                lines.append("您：\(msg.text)\n")
            case .assistant:
                if !msg.text.isEmpty {
                    lines.append("律疏：\(msg.text)\n")
                }
                if !msg.citations.isEmpty {
                    lines.append("参考法条：\n")
                    for c in msg.citations {
                        lines.append("《\(c.lawTitle)》\(c.articleNumber)：\(c.content)\n")
                    }
                }
                if !msg.gazetteCitations.isEmpty {
                    lines.append("相关公报案例：\n")
                    for (i, c) in msg.gazetteCitations.enumerated() {
                        let sourceLabel: String
                        switch c.source {
                        case "al":     sourceLabel = "指导案例"
                        case "sfwj":   sourceLabel = "司法文件"
                        case "cpwsxd": sourceLabel = "裁判文书"
                        default:       sourceLabel = c.source
                        }
                        var entry = "\(i + 1). 《\(c.title)》（\(sourceLabel)）"
                        if !c.rulingGist.isEmpty { entry += "\n   裁判要点：\(c.rulingGist)" }
                        if let doc = DatabaseManager.shared.gazetteDoc(id: c.docId), !doc.fullText.isEmpty {
                            entry += "\n   正文：\(doc.fullText)"
                        }
                        lines.append(entry + "\n")
                    }
                }
            }
        }
        lines.append("\n---\n免责声明：以上内容由 AI 自动生成，仅供参考，不构成正式法律意见。具体案件建议咨询执业律师。")
        return lines.joined(separator: "\n")
    }

    // MARK: - Answer text citation extraction
    /// queries the DB for each, and returns the additional RAGCitations found.
    static func extractCitationsFromText(_ text: String, existing: [RAGCitation]) -> [RAGCitation] {
        let re = ArticleRefPattern.regex
        let existingKeys = Set(existing.map { "\($0.lawId)||\($0.articleNumber)" })
        var result: [RAGCitation] = []
        var seenKeys = Set<String>()
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let title  = ns.substring(with: m.range(at: 1))
            let artNum = ns.substring(with: m.range(at: 2))
            guard let article = DatabaseManager.shared.articleByRef(
                lawTitleFragment: title, articleNumber: artNum) else { continue }
            let key = "\(article.lawId)||\(article.articleNumber)"
            guard !existingKeys.contains(key), seenKeys.insert(key).inserted else { continue }
            result.append(RAGCitation(
                lawId: article.lawId, lawTitle: article.lawTitle,
                articleNumber: article.articleNumber, articleNum: article.articleNum,
                category: article.category, content: article.content))
        }
        return result
    }
}

// MARK: - Export helpers

struct ExportItem: Identifiable {
    enum Kind { case text(String); case pdf(URL?) }
    let id = UUID()
    let kind: Kind
    var activityItem: Any {
        switch kind {
        case .text(let s):    return s
        case .pdf(let url):   return url as Any
        }
    }
}

enum ChatExportPDF {
    static func render(text: String) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            let margin: CGFloat = 44
            let maxWidth = pageRect.width - margin * 2
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
            var charIndex = 0
            ctx.beginPage()
            while charIndex < attrStr.length {
                let frameRect = CGRect(x: margin, y: margin, width: maxWidth, height: pageRect.height - margin * 2)
                let path = CGPath(rect: frameRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(charIndex, 0), path, nil)
                let range = CTFrameGetVisibleStringRange(frame)
                let uiCtx = UIGraphicsGetCurrentContext()!
                uiCtx.saveGState()
                uiCtx.translateBy(x: 0, y: pageRect.height)
                uiCtx.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, uiCtx)
                uiCtx.restoreGState()
                charIndex += range.length
                if charIndex < attrStr.length { ctx.beginPage() }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("法律咨询记录.pdf")
        try? data.write(to: url)
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss?() }
        return vc
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {
        // Required on iPad/Mac: provide a source for the popover anchor.
        // Without this, UIActivityViewController crashes on iPad.
        if let popover = uvc.popoverPresentationController {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
    }
}

// MARK: - SessionRowView (shared by Sidebar + Sheet)

struct SessionRowView: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("专家", systemImage: "person.3")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AppColors.shared.searchHighlight)
                    .clipShape(Capsule())
                Spacer()
                Text(session.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(session.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text("\(session.messages.count / 2) 轮对话")
                let totalP = session.totalPromptTokens
                let totalC = session.totalCompletionTokens
                if totalP + totalC > 0 {
                    Text("·")
                    Text("\(formatTokens(totalP + totalC)) tokens")
                    let cost = Double(totalP) / 1_000_000 * 0.27
                             + Double(totalC) / 1_000_000 * 1.10
                    Text("≈ ¥\(String(format: cost < 0.01 ? "%.4f" : "%.3f", cost))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
