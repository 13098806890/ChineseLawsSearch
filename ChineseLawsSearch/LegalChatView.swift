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
    @ObservedObject var historyStore: ChatHistoryStore
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void
    var showHistoryButton: Bool = true

    @ObservedObject private var tokenCounter = TokenCounter.shared
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.messages.isEmpty {
                            placeholderView
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg, showThinking: showThinking,
                                          navigate: navigate,
                                          onToggleStep: { vm.toggleStep(messageId: msg.id, stepId: $0) },
                                          onToggleSteps: { vm.toggleSteps(messageId: msg.id) },
                                          onToggleCitations: { vm.toggleCitations(messageId: msg.id) })
                                .id(msg.id)
                        }
                        if vm.isThinking {
                            thinkingIndicator
                                .id("thinking")
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
                .onChange(of: vm.isThinking) { _, thinking in
                    if thinking {
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
            }
            #if os(iOS)
            .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
            #endif

            // Input bar
            HStack(alignment: .bottom, spacing: 8) {
                TextField(vm.isAwaitingClarification ? "请回答专家的问题…" : "请输入您的法律问题…",
                          text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.appTertiaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .disabled(vm.isThinking)
                    .focused($inputFocused)
                    #if os(iOS)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("完成") { inputFocused = false }
                        }
                    }
                    #endif

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
            .padding(.vertical, 10)
            .background(.bar)

            // Token counter
            if tokenCounter.session.total > 0 {
                HStack(spacing: 12) {
                    Spacer()
                    Label("\(formatTokens(tokenCounter.session.promptTokens))", systemImage: "arrow.up")
                    Label("\(formatTokens(tokenCounter.session.completionTokens))", systemImage: "arrow.down")
                    Text("共 \(formatTokens(tokenCounter.session.total)) tokens")
                    let cost = Double(tokenCounter.session.promptTokens) / 1_000_000 * 1.0
                           + Double(tokenCounter.session.completionTokens) / 1_000_000 * 2.0
                    Text("≈ ¥\(String(format: cost < 0.01 ? "%.4f" : "%.3f", cost))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .background(.bar)
            }
        }
        .navigationTitle("法律咨询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showHistoryButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        vm.newSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(vm.isThinking)
                }
            }
            if showHistoryButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock")
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(historyStore: historyStore) { session in
                vm.loadSession(session)
                showHistory = false
            }
        }
    }

    // MARK: Placeholder

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private var placeholderView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 标题
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.shared.searchHighlight.opacity(0.7))
                    Text("中国法律顾问")
                        .font(.title2.bold())
                    Text("多位细分领域专家协作分析，给出更深入的法律意见")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                // 使用指引
                VStack(alignment: .leading, spacing: 16) {
                    Text("如何获得最佳效果")
                        .font(.headline)

                    tipRow(icon: "doc.text",
                           title: "详细描述案情",
                           body: "说明当事人关系、事件经过、时间节点和损失金额，专家能据此准确检索相关法条并给出针对性分析。")

                    tipRow(icon: "questionmark.circle",
                           title: "回答专家追问",
                           body: "专家可能会追问缺失的关键信息（如签订合同的形式、是否有书面证据），如实补充有助于提升分析质量。")

                    tipRow(icon: "arrow.turn.down.right",
                           title: "在同一会话里继续追问",
                           body: "对答复中不清楚的地方直接追问，专家会沿用已有案情上下文，无需重复描述背景。")

                    tipRow(icon: "plus.bubble",
                           title: "新案情开新会话",
                           body: "遇到完全不同的纠纷，点击「+」新建对话，避免不同案情互相干扰。")
                }

                Divider()

                // 示例
                VStack(alignment: .leading, spacing: 10) {
                    Text("示例描述方式")
                        .font(.headline)
                    Text("""
我与某公司于2023年5月签订了一份书面劳动合同，约定月薪8000元。今年3月公司以"经营困难"为由单方面将我工资降至5000元，我未同意。现公司以旷工为由将我辞退，未支付任何补偿。请问我有哪些法律救济途径？
""")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.appSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
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
        .background(Color.appTertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { vm.startDotAnimation() }
        .onDisappear { vm.stopDotAnimation() }
    }
}

// MARK: - Intent icon helper

private func intentIcon(_ intent: MessageIntent) -> String {
    switch intent {
    case .caseNarration: return "doc.text.magnifyingglass"
    case .followUp:      return "arrow.turn.down.right"
    case .general:       return "book"
    case .offTopic:      return "bubble.left"
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
                            .padding(.top, 2)
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
                    if let intent = message.intent, intent != .caseNarration {
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
    let onNewSession: () -> Void

    var body: some View {
        Group {
            if historyStore.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("暂无历史记录")
                        .foregroundStyle(.secondary)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onNewSession() } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    private func historyRow(_ session: ChatSession) -> some View {
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
            Text("\(session.messages.count / 2) 轮对话")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("暂无历史记录")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(historyStore.sessions) { session in
                            Button {
                                onSelect(session)
                            } label: {
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
                                    Text("\(session.messages.count / 2) 轮对话")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ViewModel

final class LegalChatViewModel: ObservableObject {
    @Published var messages:  [ChatMessage] = []
    @Published var inputText  = ""
    @Published var isThinking = false
    @Published var dotScale   = [1.0, 1.0, 1.0]
    @Published var scrollToken = 0
    @Published var mode: ChatMode = .expert

    // Follow-up state (expert mode)
    var isAwaitingClarification = false
    var followUpRound = 0
    var pendingFacts: [String: String] = [:]
    var conversationHistory: [(user: String, assistant: String)] = []

    // Intent routing state
    var lastSelectedExperts: [SubExpert] = []   // cached for follow_up reuse

    // Session identity for history
    var sessionId = UUID()
    var sessionCreatedAt = Date()

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
        sessionId = UUID()
        sessionCreatedAt = Date()
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
                isClarifying: false
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
        TokenCounter.shared.reset()
    }

    @MainActor
    func send(historyStore: ChatHistoryStore) async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        let currentSessionId = sessionId  // capture before any await
        inputText = ""
        messages.append(ChatMessage(role: .user, text: q))

        isThinking = true

        do {
            if isAwaitingClarification { followUpRound += 1 }

            // ── Intent classification ──────────────────────────────────────────
            let intent: MessageIntent
            if isAwaitingClarification {
                // Mid-clarification reply is always a follow-up in the current flow
                intent = .followUp
            } else {
                intent = await LegalExpertService.shared.classifyIntent(
                    message: q, history: conversationHistory)
            }

            // ── Route by intent ────────────────────────────────────────────────
            switch intent {

            // ── Off-topic: hardcoded reply, zero LLM calls ─────────────────────
            case .offTopic:
                var reply = ChatMessage(role: .assistant,
                                        text: "您好！我是中国法律顾问助手，专门解答中国法律问题。\n请描述您遇到的法律问题或纠纷，例如合同纠纷、劳动争议、侵权责任等，我将为您提供专业分析。")
                reply.intent = .offTopic
                messages.append(reply)

            // ── General / Follow-up / Case: append reply slot then run pipeline ─
            case .general, .followUp, .caseNarration:
                var replyMsg = ChatMessage(role: .assistant)
                replyMsg.intent = intent
                messages.append(replyMsg)
                let replyIdx = messages.count - 1

                let citations: [RAGCitation]

                switch intent {
                case .offTopic: citations = []  // never reached

                case .general:
                    citations = try await LegalExpertService.shared.askGeneral(
                        question: q
                    ) { [weak self] event in
                        Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
                    }

                case .followUp:
                    // Guard: follow_up requires an active case context (experts already selected).
                    // If no case has been analysed yet in this session, treat as general instead.
                    if lastSelectedExperts.isEmpty {
                        citations = try await LegalExpertService.shared.askGeneral(
                            question: q
                        ) { [weak self] event in
                            Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
                        }
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

                case .caseNarration:
                    // Reset clarification state for a fresh case
                    isAwaitingClarification = false
                    followUpRound = 0
                    pendingFacts = [:]
                    lastSelectedExperts = []
                    citations = try await runCasePipeline(
                        q: q, replyIdx: replyIdx, isAwaitingClarification: false)
                }

                await MainActor.run {
                    if replyIdx < messages.count { messages[replyIdx].citations = citations }
                }
            }

        } catch {
            await MainActor.run {
                if let last = messages.last, last.role == .assistant, last.text.isEmpty {
                    messages[messages.count - 1].text = error.localizedDescription
                }
            }
        }

        let capturedStore = historyStore
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionId == currentSessionId else { return }
            self.isThinking = false
            let assistantText = self.messages.last(where: { $0.role == .assistant })?.text ?? ""
            self.conversationHistory.append((user: q, assistant: assistantText))
            self.autoSave(historyStore: capturedStore)
        }
    }

    /// Runs the full case pipeline (decompose → askSingle or multi-question).
    /// Returns citations for single-question path; multi-question path sets them directly.
    @MainActor
    private func runCasePipeline(q: String, replyIdx: Int,
                                  isAwaitingClarification: Bool) async throws -> [RAGCitation] {
        let decomposed = await LegalExpertService.shared.decomposeWithFacts(question: q)

        if decomposed.questions.count >= 2 {
            let preamble = decomposed.preamble
            let subQs    = decomposed.questions

            await MainActor.run {
                var header = ChatMessage(role: .assistant)
                header.subQuestions = subQs
                messages.insert(header, at: replyIdx)
                // shift replyIdx — original slot is now one further
            }

            var replyIndices: [Int] = []
            await MainActor.run {
                // Remove the placeholder at replyIdx (was empty) and add N slots
                messages.remove(at: replyIdx + 1)
                for i in 0..<subQs.count {
                    var msg = ChatMessage(role: .assistant)
                    msg.subQuestionIndex = i + 1
                    messages.append(msg)
                    replyIndices.append(messages.count - 1)
                }
            }

            try await withThrowingTaskGroup(of: (Int, [RAGCitation]).self) { group in
                for (i, subQ) in subQs.enumerated() {
                    let idx = replyIndices[i]
                    group.addTask { [weak self] in
                        guard let self else { return (idx, []) }
                        let citations = try await LegalExpertService.shared.askSingle(
                            question: subQ,
                            factContext: preamble,
                            conversationHistory: self.conversationHistory,
                            knownFacts: self.pendingFacts,
                            followUpRound: 0,
                            maxFollowUpRounds: 0
                        ) { event in
                            Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: idx) }
                        }
                        return (idx, citations)
                    }
                }
                for try await (idx, citations) in group {
                    await MainActor.run {
                        if idx < messages.count { messages[idx].citations = citations }
                    }
                }
            }
            return []
        } else {
            // Single question
            let citations = try await LegalExpertService.shared.askSingle(
                question: q,
                factContext: decomposed.preamble,
                conversationHistory: conversationHistory,
                knownFacts: pendingFacts,
                followUpRound: followUpRound,
                maxFollowUpRounds: maxFollowUpRounds
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleEvent(event, replyIdx: replyIdx) }
            }
            return citations
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
                    subQuestions: msg.subQuestions
                )
            },
            selectedExpertNames: lastSelectedExperts.map { $0.name },
            pendingFacts: pendingFacts,
            isAwaitingClarification: isAwaitingClarification,
            followUpRound: followUpRound,
            totalPromptTokens: TokenCounter.shared.session.promptTokens,
            totalCompletionTokens: TokenCounter.shared.session.completionTokens
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
