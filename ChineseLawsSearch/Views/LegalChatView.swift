//
//  LegalChatView.swift
//  ChineseLawsSearch
//

import SwiftUI
import Combine

// MARK: - Mode (kept for history compatibility, only expert used)

enum ChatMode: String, CaseIterable, Codable {
    case expert = "专家"

    var icon: String { "person.3" }
}

// MARK: - View

struct LegalChatView: View {
    @ObservedObject var vm: LegalChatViewModel
    let historyStore: ChatHistoryStore
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void
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
    @FocusState private var inputFocused: Bool
    @EnvironmentObject private var userStore: UserStore

    private var hasAPIKey: Bool { userStore.apiKeyConfigured }

    /// 用户有自己的 Key，或者还有免费次数/已购买
    private var canUseAgent: Bool {
        if hasAPIKey { return true }
        switch pm.access {
        case .paid, .free: return true
        case .noAccess: return false
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if vm.messages.isEmpty {
                        placeholderView
                            .onAppear {
                                // 无 key 且免费次数用完时弹 paywall
                                if isActive && !canUseAgent { showPaywall = true }
                            }
                    }
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg, showThinking: showThinking,
                                      navigate: navigate,
                                      onToggleStep: { vm.toggleStep(messageId: msg.id, stepId: $0) },
                                      onToggleSteps: { vm.toggleSteps(messageId: msg.id) },
                                      onToggleCitations: { vm.toggleCitations(messageId: msg.id) })
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
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(vm.isAwaitingClarification ? "请回答专家的问题…" : "请输入您的法律问题…",
                                  text: $vm.inputText, axis: .vertical)
                            .lineLimit(1...5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appTertiaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .disabled(vm.isThinking || !canUseAgent)
                            .focused($inputFocused)
                            .onTapGesture {
                                if !canUseAgent { showPaywall = true }
                            }
                        Button {
                            Task { await vm.send(historyStore: historyStore) }
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

                    // Free uses hint
                    if !hasAPIKey {
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
                        case .paid:
                            EmptyView()
                        }
                    }

                    // Token counter — show base (from loaded history) + current session
                    let totalPrompt     = vm.tokenBasePrompt     + tokenCounter.session.promptTokens
                    let totalCompletion = vm.tokenBaseCompletion + tokenCounter.session.completionTokens
                    let totalTokens     = totalPrompt + totalCompletion
                    if totalTokens > 0 {
                        HStack(spacing: 12) {
                            Spacer()
                            Label("\(formatTokens(totalPrompt))", systemImage: "arrow.up")
                            Label("\(formatTokens(totalCompletion))", systemImage: "arrow.down")
                            Text("共 \(formatTokens(totalTokens)) tokens")
                            let cost = Double(totalPrompt)     / 1_000_000 * 1.0
                                     + Double(totalCompletion) / 1_000_000 * 2.0
                            Text("≈ ¥\(String(format: cost < 0.01 ? "%.4f" : "%.3f", cost))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                }
                .background(.bar)
            }
        }
        .navigationTitle("法律咨询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showHistoryButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showHistory = true } label: {
                            Image(systemName: "clock")
                        }
                        Button { vm.newSession() } label: {
                            Image(systemName: "plus.circle")
                        }
                        .disabled(vm.isThinking)
                    }
                }
            }
            if !showHistoryButton && showNewSessionButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.newSession() } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(vm.isThinking)
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(historyStore: historyStore, onSelect: { session in
                vm.loadSession(session)
                showHistory = false
            }, onNewSession: {
                vm.newSession()
            })
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(pm: pm)
        }
        .alert("需要配置 API Key", isPresented: $showNoKeyAlert) {
            Button("前往设置") { onOpenSettings?() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("法律顾问功能需要 DeepSeek API Key 才能使用，请在设置中填入您的 Key。")
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
                    Text("由多位细分领域专家协作，自动检索相关法条，给出有依据的法律意见")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                // 三种问答模式
                VStack(alignment: .leading, spacing: 16) {
                    Text("支持三种问答模式")
                        .font(.headline)

                    modeCard(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "案情分析",
                        desc: "描述您亲历的具体纠纷，专家会追问缺失事实，分析责任归属并给出维权建议。",
                        example: "我和房东签了一年租约，还有四个月到期，房东突然要求我两周内搬走，并拒绝退押金，我该怎么办？"
                    )

                    modeCard(
                        icon: "lightbulb",
                        title: "法律咨询",
                        desc: "询问某类情景下的权利义务，无需有具体案情，适合提前了解法律规则。",
                        example: "劳动合同到期公司不续签，员工能拿到经济补偿吗？"
                    )

                    modeCard(
                        icon: "doc.text.magnifyingglass",
                        title: "法条检索",
                        desc: "查询某个法律概念的定义、某罪的构成要件，或某主题的相关条文原文。",
                        example: "交通肇事罪的构成要件是什么？"
                    )
                }

                Divider()

                // 使用提示
                VStack(alignment: .leading, spacing: 14) {
                    Text("使用提示")
                        .font(.headline)

                    tipRow(icon: "text.alignleft",
                           title: "案情越详细，分析越准确",
                           body: "说明当事人关系、事件经过、时间节点，专家能据此精准检索法条、给出针对性意见。")

                    tipRow(icon: "arrow.turn.down.right",
                           title: "在同一会话里追问",
                           body: "对答复中不清楚的地方直接追问，无需重复背景，专家会沿用上下文继续分析。")

                    tipRow(icon: "plus.circle",
                           title: "新案情开新会话",
                           body: "遇到完全不同的纠纷，点击右上角「+」新建对话，避免不同案情互相干扰。")
                }

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func modeCard(icon: String, title: String, desc: String, example: String) -> some View {
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
            Text("示例：\(example)")
                .font(.footnote)
                .foregroundStyle(.secondary.opacity(0.85))
                .italic()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
    let onToggleStep: (UUID) -> Void
    let onToggleSteps: () -> Void
    let onToggleCitations: () -> Void

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
            }
        }
        .padding(.horizontal, 4)
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
                        historyRow(session)
                            .tag(session.id)
                    }
                    .onDelete { offsets in
                        offsets.forEach { historyStore.delete(id: historyStore.sessions[$0].id) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(_ session: ChatSession) -> some View {
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
                if session.totalPromptTokens + session.totalCompletionTokens > 0 {
                    Text("·")
                    Text("\(formatTokens(session.totalPromptTokens + session.totalCompletionTokens)) tokens")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - History Sheet

struct ChatHistorySheet: View {
    @ObservedObject var historyStore: ChatHistoryStore
    let onSelect: (ChatSession) -> Void
    let onNewSession: () -> Void
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
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(session.mode == "专家" ? "专家" : "快速",
                                          systemImage: session.mode == "专家" ? "person.3" : "bolt")
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
                                    if session.totalPromptTokens + session.totalCompletionTokens > 0 {
                                        Text("·")
                                        Text("\(formatTokens(session.totalPromptTokens + session.totalCompletionTokens)) tokens")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(session) }
                        }
                        .onDelete { offsets in
                            offsets.forEach { idx in
                                historyStore.delete(id: historyStore.sessions[idx].id)
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

final class LegalChatViewModel: ObservableObject {
    @Published var messages:  [ChatMessage] = []
    @Published var inputText  = ""
    @Published var isThinking = false
    @Published var dotScale   = [1.0, 1.0, 1.0]
    @Published var scrollToken = 0
    @Published var mode: ChatMode = .expert
    @Published var lastFailedQuestion: String? = nil  // set on network error, cleared on retry

    // Follow-up state (expert mode)
    var isAwaitingClarification = false
    var followUpRound = 0
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
    @AppStorage("maxFollowUpRounds") var maxFollowUpRounds: Int = 3

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
    func newSession() {
        messages = []
        inputText = ""
        isThinking = false
        isAwaitingClarification = false
        followUpRound = 0
        pendingFacts = [:]
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
                return step
            }
            msg.citations   = pm.citations.map {
                RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                            articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                            category: $0.category, content: $0.content)
            }
            msg.subQuestions = pm.subQuestions
            return msg
        }
        // 恢复专家追问上下文
        isAwaitingClarification = session.isAwaitingClarification
        followUpRound           = session.followUpRound
        pendingFacts            = session.pendingFacts
        lastSelectedExperts     = resolveExperts(names: session.selectedExpertNames)
        conversationHistory     = buildConversationHistory()
        tokenBasePrompt         = session.totalPromptTokens
        tokenBaseCompletion     = session.totalCompletionTokens
        TokenCounter.shared.reset()
    }

    @MainActor
    func send(historyStore: ChatHistoryStore) async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }

        // Access control: consume a free use (no-op if user has own key or is paid)
        let userKey = KeychainHelper.load(forKey: "deepseek_api_key") ?? ""
        let needsQuota = userKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if needsQuota && !PurchaseManager.shared.consumeIfAllowed() { return }

        let currentSessionId = sessionId  // capture before any await
        lastFailedQuestion = nil
        inputText = ""
        messages.append(ChatMessage(role: .user, text: q))

        isThinking = true
        defer {
            // Guarantee isThinking is always cleared regardless of exit path
            if self.sessionId == currentSessionId { self.isThinking = false }
        }

        do {
            if isAwaitingClarification { followUpRound += 1 }

            // ── Intent classification (Mod 1: single LLM call for intent + mode) ─
            let intent: MessageIntent
            let preMode: QueryMode?
            if isAwaitingClarification {
                intent = .followUp
                preMode = lastQueryMode   // carry over mode from the turn that triggered clarification
            } else {
                let classified = await LegalExpertService.shared.classifyIntentAndMode(
                    message: q, history: conversationHistory)
                intent = classified.0
                preMode = classified.1
            }

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
            // Remove the empty assistant bubble if present
            if let last = messages.last, last.role == .assistant, last.text.isEmpty {
                messages.removeLast()
            }
            // Remove the user message and restore to input box for retry
            if let last = messages.last, last.role == .user {
                messages.removeLast()
            }
            inputText = q
            lastFailedQuestion = q
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
        case .offTopic: citations = []  // never reached

        case .followUp:
            if lastSelectedExperts.isEmpty {
                // No prior case context — treat as fresh legal query (Mod 6: use preMode)
                let (c, mode) = try await LegalExpertService.shared.askLegalQuery(
                    question: q,
                    conversationHistory: conversationHistory,
                    knownFacts: pendingFacts,
                    followUpRound: 0,
                    maxFollowUpRounds: 0,
                    preClassifiedMode: preMode ?? .legalAdvisory
                ) { [weak self] event in
                    Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
                }
                if mode == .caseAnalysis { isAwaitingClarification = false }
                citations = c
            } else {
                let (c, updatedExperts) = try await LegalExpertService.shared.askFollowUp(
                    question: q,
                    lastExperts: lastSelectedExperts,
                    conversationHistory: conversationHistory,
                    knownFacts: pendingFacts
                ) { [weak self] event in
                    Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
                }
                lastSelectedExperts = updatedExperts
                citations = c
            }

        case .legalQuery:
            // Reset clarification state for fresh queries
            if !isAwaitingClarification {
                lastSelectedExperts = []
                pendingFacts = [:]
                followUpRound = 0
            }
            let maxRounds = isAwaitingClarification ? 0 : UserDefaults.standard.integer(forKey: "maxFollowUpRounds")
            // Mod 6: pass preMode to skip redundant classifyQueryMode call
            let (c, mode) = try await LegalExpertService.shared.askLegalQuery(
                question: q,
                conversationHistory: conversationHistory,
                knownFacts: pendingFacts,
                followUpRound: followUpRound,
                maxFollowUpRounds: maxRounds,
                preClassifiedMode: preMode
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
            }
            // Only case analysis supports multi-turn clarification
            if mode != .caseAnalysis { isAwaitingClarification = false }
            lastQueryMode = mode
            citations = c
        }

        if replyIdx < messages.count { messages[replyIdx].citations = citations }

        if lastFailedQuestion == nil && sessionId == currentSessionId {
            let assistantText = messages.last(where: { $0.role == .assistant })?.text ?? ""
            conversationHistory.append((user: q, assistant: assistantText))
            autoSave(historyStore: historyStore)
        }
    }

    @MainActor
    private func handleEvent(_ event: RAGEvent, replyIdx: Int) {
        guard replyIdx < messages.count else { return }
        switch event {
        case .thinkStep(let name, let content):
            messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content))
        case .thinkStepWithArticles(let name, let content, let articles):
            messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content, articles: articles))
        case .subQuestions(let qs):
            messages[replyIdx].subQuestions = qs
        case .token(let t):
            messages[replyIdx].text += t
            isThinking = false
            scrollToken += 1
        case .clarifyingQuestion(let text):
            messages[replyIdx].text = text
            messages[replyIdx].isClarifying = true
            isThinking = false
            isAwaitingClarification = true
            scrollToken += 1
        case .expertsSelected(let experts):
            lastSelectedExperts = experts
        }
    }

    @MainActor
    private func autoSave(historyStore: ChatHistoryStore) {
        guard !messages.isEmpty else { return }
        let title = messages.first(where: { $0.role == .user })?.text
            .prefix(40)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "新对话"
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
                            }
                        )
                    },
                    citations: msg.citations.map {
                        PersistedCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                                          articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                                          category: $0.category, content: $0.content)
                    },
                    subQuestions: msg.subQuestions,
                    isClarifying: msg.isClarifying
                )
            },
            selectedExpertNames: lastSelectedExperts.map { $0.name },
            pendingFacts: pendingFacts,
            isAwaitingClarification: isAwaitingClarification,
            followUpRound: followUpRound,
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
        while i < messages.count - 1 {
            if messages[i].role == .user && messages[i+1].role == .assistant {
                pairs.append((user: messages[i].text, assistant: messages[i+1].text))
                i += 2
            } else { i += 1 }
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
}
