//
//  LegalChatView.swift
//  ChineseLawsSearch
//

import SwiftUI
import UIKit
import Combine

// MARK: - Mode (kept for history compatibility, only expert used)

enum ChatMode: String, Codable {
    case expert = "专家"

    var icon: String { "person.3" }
}

// MARK: - View

struct LegalChatView: View {
    @ObservedObject var vm: LegalChatViewModel
    let historyStore: ChatHistoryStore
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void
    let navigateToGazette: (GazetteDoc) -> Void
    var showHistoryButton: Bool = true
    var showNewSessionButton: Bool = false
    var onOpenSettings: (() -> Void)? = nil
    /// Whether this view is currently the active tab (controls no-key alert timing)
    var isActive: Bool = true

    @ObservedObject private var tokenCounter = TokenCounter.shared
    @ObservedObject private var pm = PurchaseManager.shared
    @State private var showHistory = false
    @State private var showNoKeyAlert = false
    @State private var showPaywall = false
    @State private var exportItem: ExportItem? = nil
    @FocusState private var inputFocused: Bool
    @EnvironmentObject private var userStore: UserStore

    private var hasAPIKey: Bool { userStore.apiKeyConfigured }

    /// 是否允许使用 Agent：
    /// - .free  → 内置 Key，直接可用
    /// - .basic → 需自备 Key
    /// - .pro   → 内置 Key，有每周额度，额度为 0 时不可用
    /// - .noAccess → 不可用
    private var canUseAgent: Bool {
        switch pm.access {
        case .free:                       return true
        case .basic:                      return hasAPIKey
        case .pro(let remaining):         return remaining > 0
        case .noAccess:                   return false
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if vm.messages.isEmpty {
                        placeholderView
                    }
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg, showThinking: showThinking,
                                      navigate: navigate,
                                      navigateToGazette: navigateToGazette,
                                      onToggleStep: { vm.toggleStep(messageId: msg.id, stepId: $0) },
                                      onToggleSteps: { vm.toggleSteps(messageId: msg.id) },
                                      onToggleCitations: { vm.toggleCitations(messageId: msg.id) },
                                      onToggleGazetteCitations: { vm.toggleGazetteCitations(messageId: msg.id) })
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: vm.scrollToken) { _, _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture { inputFocused = false }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Thinking indicator sits above input bar, outside LazyVStack
                    if vm.isThinking {
                        thinkingIndicator
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    Divider()
                    // Network error retry banner
                    if vm.lastFailedQuestion != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("发送失败，问题已回填到输入框")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                vm.lastFailedQuestion = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08))
                    }
                    // Input bar
                    HStack(alignment: .center, spacing: 8) {
                        TextField({
                            if !canUseAgent {
                                switch pm.access {
                                case .basic:                  return "请在设置中配置 API Key…"
                                case .pro(let r) where r == 0: return "本周额度已用完，下周一恢复…"
                                default:                       return "购买后即可使用法律顾问…"
                                }
                            }
                            return vm.isAwaitingClarification ? "请回答专家的问题…" : "请输入您的法律问题…"
                        }(),
                                  text: $vm.inputText, axis: .vertical)
                            .lineLimit(1...5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appTertiaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .disabled(vm.isThinking || !canUseAgent)
                            .focused($inputFocused)
                            .onTapGesture {
                                if !canUseAgent {
                                    switch pm.access {
                                    case .basic:  onOpenSettings?()
                                    default:      showPaywall = true
                                    }
                                }
                            }
                        Button {
                            Task { await vm.send(historyStore: historyStore, gazetteNotes: userStore.gazetteNotes) }
                        } label: {
                            Image(systemName: vm.isThinking ? "stop.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isThinking
                                                 ? Color.appDisabled : AppColors.shared.searchHighlight)
                        }
                        .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isThinking)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Free uses hint / status bar
                    switch pm.access {
                    case .free(let remaining):
                        HStack(spacing: 4) {
                            Text("免费剩余 \(remaining) 次")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("·")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button { showPaywall = true } label: {
                                Text("解锁无限使用")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.shared.searchHighlight)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    case .basic:
                        if !hasAPIKey {
                            HStack(spacing: 4) {
                                Image(systemName: "key.slash").font(.caption2).foregroundStyle(.orange)
                                Text("请在设置中配置 API Key 以继续使用")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button { onOpenSettings?() } label: {
                                    Text("前往设置")
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.shared.searchHighlight)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        } else {
                            let isPro = pm.hasPRO
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill").font(.caption2).foregroundStyle(.secondary)
                                Text(isPro ? "畅用版 · 自备 Key 优先，无次数限制" : "基础版 · 自备 Key，无次数限制")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    case .pro(let remaining):
                        HStack(spacing: 4) {
                            Text("畅用版 · 本周剩余 \(remaining) 次")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    case .noAccess:
                        HStack(spacing: 4) {
                            Text("免费次数已用完")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("·")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button { showPaywall = true } label: {
                                Text("购买解锁")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.shared.searchHighlight)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    // Token counter — DEBUG 模式始终显示，便于测试
                    let totalPrompt     = vm.tokenBasePrompt     + tokenCounter.session.promptTokens
                    let totalCompletion = vm.tokenBaseCompletion + tokenCounter.session.completionTokens
                    let totalTokens     = totalPrompt + totalCompletion
                    #if DEBUG
                    if totalTokens > 0 {
                        HStack(spacing: 12) {
                            Spacer()
                            Label("\(formatTokens(totalPrompt))", systemImage: "arrow.up")
                            Label("\(formatTokens(totalCompletion))", systemImage: "arrow.down")
                            Text("共 \(formatTokens(totalTokens)) tokens")
                            let cost = Double(totalPrompt)     / 1_000_000 * 0.27
                                     + Double(totalCompletion) / 1_000_000 * 1.10
                            Text("≈ ¥\(String(format: cost < 0.01 ? "%.4f" : "%.3f", cost))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    } else {
                        Spacer().frame(height: 8)
                    }
                    #else
                    if case .basic = pm.access {
                        if totalTokens > 0 {
                            HStack(spacing: 12) {
                                Spacer()
                                Label("\(formatTokens(totalPrompt))", systemImage: "arrow.up")
                                Label("\(formatTokens(totalCompletion))", systemImage: "arrow.down")
                                Text("共 \(formatTokens(totalTokens)) tokens")
                                let cost = Double(totalPrompt)     / 1_000_000 * 0.27
                                         + Double(totalCompletion) / 1_000_000 * 1.10
                                Text("≈ ¥\(String(format: cost < 0.01 ? "%.4f" : "%.3f", cost))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                        } else {
                            Spacer().frame(height: 8)
                        }
                    } else {
                        Spacer().frame(height: 8)
                    }
                    #endif
                }
                .background(.bar)
            }
        }
        .navigationTitle("法律咨询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if showHistoryButton || showNewSessionButton {
                    HStack(spacing: 16) {
                        if !vm.messages.isEmpty {
                            Menu {
                                Button("纯文本") {
                                    exportItem = ExportItem(kind: .text(vm.exportMarkdown()))
                                }
                                Button("PDF 文件") {
                                    let text = vm.exportMarkdown()
                                    let url = ChatExportPDF.render(text: text)
                                    exportItem = ExportItem(kind: .pdf(url))
                                }
                            } label: {
                                Image(systemName: "paperplane")
                            }
                        }
                        if showHistoryButton {
                            Button { showHistory = true } label: {
                                Image(systemName: "clock")
                            }
                        }
                        Button { vm.newSession() } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(historyStore: historyStore, onSelect: { session in
                vm.loadSession(session)
                showHistory = false
            }, onNewSession: {
                vm.newSession()
            }, isThinking: vm.isThinking)
        }
        .sheet(isPresented: Binding(
            get: { showPaywall || vm.needsPaywall },
            set: { isPresented in
                if !isPresented {
                    showPaywall = false
                    vm.needsPaywall = false  // reset so paywall can trigger again next time
                }
            }
        )) {
            PaywallView(pm: pm)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.activityItem])
        }
        .alert("需要配置 API Key", isPresented: $showNoKeyAlert) {
            Button("前往设置") { onOpenSettings?() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("法律顾问功能需要 DeepSeek API Key 才能使用，请在设置中填入您的 Key。")
        }
        .alert("时间异常", isPresented: $vm.showTimeManipulationAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("检测到设备时间异常，请恢复正确时间后再使用。")
        }
        .onChange(of: isActive) { _, active in
            // 用户首次切到对话 Tab 且无权限时弹 Paywall，避免每次 onAppear 重复弹
            if active && vm.messages.isEmpty && !canUseAgent { showPaywall = true }
        }
    }

    // MARK: Placeholder

    private var placeholderView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 标题
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.shared.searchHighlight.opacity(0.7))
                    Text("律疏 · 法律顾问")
                        .font(.title2.bold())
                    Text("多领域专家协作分析，精准检索法条与公报案例，给出有依据的法律意见")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                // 三种问答模式
                VStack(alignment: .leading, spacing: 16) {
                    Text("三种提问方式")
                        .font(.headline)

                    modeCard(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "案情分析",
                        desc: "描述您遇到的具体纠纷：当事人关系、事件经过、时间节点。专家会追问关键细节，分析责任归属，给出维权建议。",
                        examples: [
                            "我和房东签了一年租约，还有四个月到期，房东突然要求我两周内搬走并拒绝退押金，我该怎么办？",
                        ]
                    )

                    modeCard(
                        icon: "lightbulb",
                        title: "法律咨询",
                        desc: "询问某类场景下的权利义务或法律规则。无需有具体纠纷，适合提前了解法律边界或评估潜在风险。",
                        examples: [
                            "劳动合同到期公司不续签，员工能拿到经济补偿吗？",
                        ]
                    )

                    modeCard(
                        icon: "doc.text.magnifyingglass",
                        title: "法条与公报案例检索",
                        desc: "查找特定主题的法律条文原文，或直接检索人民法院公报中的指导案例与裁判文书。问句中含「案例」「判决」「指导案例」「法院怎么判」等词时，系统会自动进入公报检索模式。",
                        examples: [
                            "合同欺诈的认定标准是什么？有没有相关指导案例？",
                            "有没有关于劳动者拒绝加班被解雇的公报案例？",
                            "房屋买卖合同无效的情形有哪些，司法实践中法院怎么判？",
                        ]
                    )
                }

                Divider()

                // 功能亮点
                VStack(alignment: .leading, spacing: 14) {
                    Text("功能亮点")
                        .font(.headline)

                    tipRow(icon: "book.closed",
                           title: "本地法规库，精准引用",
                           body: "内置 4000 余部法律法规、司法解释全文，回答时直接标注条文出处，不靠\"印象\"作答。点击引用法条可跳转原文查看。")

                    tipRow(icon: "newspaper",
                           title: "关联公报案例",
                           body: "自动检索人民法院公报指导案例与裁判文书，以卡片形式展示于回答末尾，点击直接查看完整文书，了解同类纠纷的实际裁判结果。")

                    tipRow(icon: "note.text",
                           title: "案例笔记辅助检索",
                           body: "在公报文书上添加个人笔记后，AI 咨询时会将笔记内容纳入检索，优先推荐您标注过的相关案例。")

                    tipRow(icon: "arrow.turn.down.right",
                           title: "多轮追问，深入分析",
                           body: "对答复中不清楚的地方直接追问，专家会沿用上下文继续分析，无需重复背景。")

                    tipRow(icon: "clock",
                           title: "历史记录与导出",
                           body: "对话自动保存，点击右上角时钟图标查看历史。可将对话导出为文本或 PDF 分享存档。")
                }

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func modeCard(icon: String, title: String, desc: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.shared.searchHighlight)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(desc)
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(examples, id: \.self) { ex in
                    Text(ex)
                        .font(.footnote)
                        .foregroundStyle(.secondary.opacity(0.85))
                        .italic()
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func tipRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppColors.shared.searchHighlight)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Thinking dots

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.appDisabled)
                    .frame(width: 8, height: 8)
                    .scaleEffect(vm.dotScale[i])
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: vm.dotScale[i]
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { vm.startDotAnimation() }
        .onDisappear { vm.stopDotAnimation() }
    }
}

// MARK: - Intent icon helper

private func intentIcon(_ intent: MessageIntent) -> String {
    switch intent {
    case .legalQuery: return "doc.text.magnifyingglass"
    case .followUp:   return "arrow.turn.down.right"
    case .offTopic:   return "bubble.left"
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void
    let navigateToGazette: (GazetteDoc) -> Void
    let onToggleStep: (UUID) -> Void
    let onToggleSteps: () -> Void
    let onToggleCitations: () -> Void
    let onToggleGazetteCitations: () -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.shared.searchHighlight)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                        }
                }
            } else {
                if message.isClarifying {
                    // Clarifying question bubble with distinct styling
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.shared.searchHighlight)
                            .padding(.top, 10)
                        Text(message.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColors.shared.searchHighlight.opacity(0.08))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppColors.shared.searchHighlight.opacity(0.3), lineWidth: 1)
                            )
                        Spacer(minLength: 32)
                    }
                } else {
                    if let idx = message.subQuestionIndex {
                        HStack(spacing: 6) {
                            Text("问题 \(idx)")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(AppColors.shared.searchHighlight)
                                .clipShape(Capsule())
                            Spacer()
                        }
                    }
                    if let intent = message.intent, intent != .offTopic {
                        HStack(spacing: 4) {
                            Image(systemName: intentIcon(intent))
                                .font(.caption2)
                            Text(intent.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.bottom, 2)
                    }
                    if showThinking && !message.thinkSteps.isEmpty {
                        HStack {
                            thinkingSection
                            Spacer(minLength: 0)
                        }
                    }
                    if !message.subQuestions.isEmpty {
                        subQuestionsView
                    }
                    if !message.text.isEmpty {
                        HStack {
                            Text(verbatim: message.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.appTertiaryBackground)
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = message.text
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                }
                            Spacer(minLength: 48)
                        }
                    }
                    if !message.citations.isEmpty {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { onToggleCitations() }
                        } label: {
                            Label(message.showCitations ? "收起参考法条" : "查看参考法条（\(message.citations.count)条）",
                                  systemImage: message.showCitations ? "chevron.up" : "book.closed")
                                .font(.caption)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                        .padding(.leading, 4)

                        if message.showCitations {
                            CitationList(citations: message.citations, navigate: navigate)
                        }
                    }

                    if !message.gazetteCitations.isEmpty {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { onToggleGazetteCitations() }
                        } label: {
                            Label(message.showGazetteCitations ? "收起公报案例" : "查看公报案例（\(message.gazetteCitations.count)条）",
                                  systemImage: message.showGazetteCitations ? "chevron.up" : "newspaper")
                                .font(.caption)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                        .padding(.leading, 4)

                        if message.showGazetteCitations {
                            GazetteCitationCards(citations: message.gazetteCitations,
                                                 navigateToGazette: navigateToGazette)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) { onToggleSteps() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(AppColors.shared.searchHighlight)
                    Text("思考过程")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.shared.searchHighlight)
                    Spacer()
                    Text("\(message.thinkSteps.count) 步")
                        .font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: message.showSteps ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(AppColors.shared.searchHighlight.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if message.showSteps {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(message.thinkSteps.enumerated()), id: \.element.id) { idx, step in
                        ThinkStepRow(step: step, index: idx, total: message.thinkSteps.count,
                                     isExpanded: step.isExpanded,
                                     onToggle: { withAnimation(.spring(duration: 0.2)) { onToggleStep(step.id) } },
                                     navigate: navigate)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.shared.searchHighlight.opacity(0.04))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10, topTrailingRadius: 0
                    )
                )
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(AppColors.shared.searchHighlight.opacity(0.18), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private var subQuestionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("问题已拆分为 \(message.subQuestions.count) 个子问题", systemImage: "list.number")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(AppColors.shared.searchHighlight)
            ForEach(message.subQuestions.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i+1)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(AppColors.shared.searchHighlight)
                        .clipShape(Circle())
                    Text(message.subQuestions[i])
                        .font(.subheadline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.shared.searchHighlight.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(AppColors.shared.searchHighlight.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4)
    }
}

// MARK: - Think Step Row

private struct ThinkStepRow: View {
    let step: ThinkStep
    let index: Int
    let total: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let navigate: (Int, Int?) -> Void

    private var stepIcon: String {
        switch step.name {
        case "拆分问题":     return "scissors"
        case "领域路由":     return "map"
        case "关键词提取":   return "text.magnifyingglass"
        case "别名扩展":     return "arrow.triangle.branch"
        case "检索条文":     return "doc.text.magnifyingglass"
        case "相关性过滤":   return "line.3.horizontal.decrease.circle"
        case "参考法条筛选": return "checkmark.seal"
        case "专家路由":     return "person.3"
        case "细分专家":     return "person.crop.rectangle.stack"
        case "专家检索":     return "doc.text.magnifyingglass"
        case "专家组综合":   return "text.badge.checkmark"
        default:             return "circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear.frame(width: 28, height: 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(step.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !step.articles.isEmpty {
                        Button {
                            onToggle()
                        } label: {
                            HStack(spacing: 3) {
                                Text("\(step.articles.count)条")
                                    .font(.caption2)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(AppColors.shared.searchHighlight)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppColors.shared.searchHighlight.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(step.content.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if isExpanded && !step.articles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(step.articles) { a in
                            Button {
                                navigate(a.lawId, a.articleNum)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text(a.lawTitle)
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(AppColors.shared.searchHighlight)
                                        Text(a.articleNumber)
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(a.tier)
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(a.tier == "司法解释"
                                                        ? Color.blue.opacity(0.1) : Color.appQuaternaryBackground)
                                            .clipShape(Capsule())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(verbatim: String(a.content.prefix(120)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appTertiaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appSeparator, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, index < total - 1 ? 12 : 4)
        }
        .padding(.top, index == 0 ? 10 : 0)
        .background(alignment: .topLeading) {
            // Left column drawn against the full row height determined by right side
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(AppColors.shared.searchHighlight.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: stepIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.shared.searchHighlight)
                }
                .padding(.top, index == 0 ? 10 : 0)
                if index < total - 1 {
                    Rectangle()
                        .fill(AppColors.shared.searchHighlight.opacity(0.2))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, index < total - 1 ? 12 : 4)
                }
            }
            .frame(maxWidth: 28, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Citation List

private struct CitationList: View {
    let citations: [RAGCitation]
    let navigate: (Int, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(citations) { c in
                Button {
                    navigate(c.lawId, c.articleNum)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(c.lawTitle)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                            Text(c.articleNumber)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(c.tier)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(c.tier == "司法解释"
                                            ? Color.blue.opacity(0.12) : Color.appQuaternaryBackground)
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(c.content)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(6).multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appSeparator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = c.content
                    } label: {
                        Label("复制条文", systemImage: "doc.on.doc")
                    }
                    Button {
                        UIPasteboard.general.string = "《\(c.lawTitle)》\(c.articleNumber)\n\(c.content)"
                    } label: {
                        Label("复制含标题", systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Gazette Citation Cards

private struct GazetteCitationCards: View {
    let citations: [GazetteCitation]
    let navigateToGazette: (GazetteDoc) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                    .font(.caption)
                    .foregroundStyle(AppColors.shared.searchHighlight)
                Text("相关公报案例")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            ForEach(citations) { cite in
                Button {
                    if let doc = DatabaseManager.shared.gazetteDoc(id: cite.docId) {
                        navigateToGazette(doc)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(sourceLabel(cite.source))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.appQuaternaryBackground)
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(cite.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !cite.rulingGist.isEmpty {
                            Text(cite.rulingGist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !cite.relevanceReason.isEmpty {
                            Text(cite.relevanceReason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appSeparator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "al":     return "指导案例"
        case "sfwj":   return "司法文件"
        case "cpwsxd": return "裁判文书"
        default:       return "公报"
        }
    }
}

// MARK: - History Sidebar (iPad split view)

struct ChatHistorySidebar: View {
    @ObservedObject var historyStore: ChatHistoryStore
    let vm: LegalChatViewModel

    var body: some View {
        Group {
            if historyStore.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("加载中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if historyStore.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("暂无历史记录")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding<UUID?>(
                    get: { vm.sessionId },
                    set: { id in
                        if let id, let session = historyStore.sessions.first(where: { $0.id == id }) {
                            vm.loadSession(session)
                        }
                    }
                )) {
                    ForEach(historyStore.sessions) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyStore.delete(id: session.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// MARK: - History Sheet

struct ChatHistorySheet: View {
    @ObservedObject var historyStore: ChatHistoryStore
    let onSelect: (ChatSession) -> Void
    let onNewSession: () -> Void
    var isThinking: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载中…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if historyStore.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("暂无历史记录")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(historyStore.sessions) { session in
                            SessionRowView(session: session)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(session) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        historyStore.delete(id: session.id)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onNewSession()
                        dismiss()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
