//
//  LegalChatView.swift
//  ChineseLawsSearch
//

import SwiftUI
import Combine

struct LegalChatView: View {
    @ObservedObject var vm: LegalChatViewModel
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.messages.isEmpty {
                            placeholderView
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg, showThinking: showThinking, navigate: navigate)
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

            // 输入栏（无分割线）
            HStack(alignment: .bottom, spacing: 8) {
                TextField("请输入您的法律问题…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .disabled(vm.isThinking)

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isThinking ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isThinking
                                         ? Color(.systemGray3) : AppColors.shared.searchHighlight)
                }
                .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isThinking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .navigationTitle("法律咨询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("模式", selection: $vm.mode) {
                    ForEach(ChatMode.allCases, id: \.self) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .disabled(vm.isThinking)
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: vm.mode == .expert ? "person.3" : "scale.3d")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.shared.searchHighlight.opacity(0.6))
            Text("您好，我是中国法律助手")
                .font(.headline)
            Text(vm.mode == .expert
                 ? "专家模式：召集 17 位细分专家协作分析，回答更深入，速度稍慢。"
                 : "快速模式：关键词检索 + 相关性过滤，适合快速查询。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(.systemGray3))
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
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { vm.startDotAnimation() }
        .onDisappear { vm.stopDotAnimation() }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let showThinking: Bool
    let navigate: (Int, Int?) -> Void

    @State private var showSteps    = true   // 默认展开
    @State private var showCitations = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            // 用户气泡
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
                // 思考步骤折叠区
                if showThinking && !message.thinkSteps.isEmpty {
                    thinkingSection
                }

                // 子问题列表
                if !message.subQuestions.isEmpty {
                    subQuestionsView
                }

                // 正文气泡
                if !message.text.isEmpty {
                    HStack {
                        Text(message.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Spacer(minLength: 48)
                    }
                }

                // 参考法条
                if !message.citations.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showCitations.toggle() }
                    } label: {
                        Label(showCitations ? "收起参考法条" : "查看参考法条（\(message.citations.count)条）",
                              systemImage: showCitations ? "chevron.up" : "book.closed")
                            .font(.caption)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                    }
                    .padding(.leading, 4)

                    if showCitations {
                        CitationList(citations: message.citations, navigate: navigate)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 折叠头
            Button {
                withAnimation(.spring(duration: 0.25)) { showSteps.toggle() }
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: showSteps ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.shared.searchHighlight.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: showSteps ? 10 : 10))
            }

            if showSteps {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(message.thinkSteps.enumerated()), id: \.element.id) { idx, step in
                        ThinkStepRow(step: step, index: idx, total: message.thinkSteps.count)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .background(AppColors.shared.searchHighlight.opacity(0.04))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10, topTrailingRadius: 0
                    )
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.shared.searchHighlight.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 4)
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
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.shared.searchHighlight.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.shared.searchHighlight.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Think Step Row (时间线样式)

private struct ThinkStepRow: View {
    let step: ThinkStep
    let index: Int
    let total: Int

    private var stepIcon: String {
        switch step.name {
        case "拆分问题":   return "scissors"
        case "领域路由":   return "map"
        case "关键词提取": return "text.magnifyingglass"
        case "别名扩展":   return "arrow.triangle.branch"
        case "检索条文":   return "doc.text.magnifyingglass"
        case "相关性过滤": return "line.3.horizontal.decrease.circle"
        case "参考法条筛选": return "checkmark.seal"
        // Expert mode steps
        case "专家路由":   return "person.3"
        case "细分专家":   return "person.crop.rectangle.stack"
        case "专家检索":   return "doc.text.magnifyingglass"
        case "专家组综合": return "text.badge.checkmark"
        default:           return "circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 时间线轴
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(AppColors.shared.searchHighlight.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: stepIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.shared.searchHighlight)
                }
                if index < total - 1 {
                    Rectangle()
                        .fill(AppColors.shared.searchHighlight.opacity(0.2))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(step.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                // 按换行分段渲染，每行一个段落
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(step.content.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, index < total - 1 ? 12 : 4)
        }
        .padding(.top, index == 0 ? 10 : 0)
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
                                            ? Color.blue.opacity(0.12)
                                            : Color(.systemGray5))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(c.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - ViewModel

enum ChatMode: String, CaseIterable {
    case rag    = "快速"
    case expert = "专家"

    var icon: String {
        switch self {
        case .rag:    return "bolt"
        case .expert: return "person.3"
        }
    }
}

final class LegalChatViewModel: ObservableObject {
    @Published var messages:    [ChatMessage] = []
    @Published var inputText    = ""
    @Published var isThinking   = false
    @Published var dotScale     = [1.0, 1.0, 1.0]
    @Published var scrollToken  = 0   // increment to trigger scroll
    @Published var mode: ChatMode = .rag

    private var dotTask: Task<Void, Never>?

    @MainActor
    func send() async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, text: q))

        isThinking = true
        var replyMsg = ChatMessage(role: .assistant)
        messages.append(replyMsg)
        let replyIdx = messages.count - 1

        do {
            let service: (String, @escaping (RAGEvent) -> Void) async throws -> [RAGCitation]
            switch mode {
            case .rag:    service = LegalRAGService.shared.ask
            case .expert: service = LegalExpertService.shared.ask
            }

            let citations = try await service(q) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .thinkStep(let name, let content):
                        self.messages[replyIdx].thinkSteps.append(ThinkStep(name: name, content: content))
                        self.isThinking = false
                    case .subQuestions(let qs):
                        self.messages[replyIdx].subQuestions = qs
                    case .token(let t):
                        self.messages[replyIdx].text += t
                        self.isThinking = false
                        self.scrollToken += 1
                    }
                }
            }
            await MainActor.run {
                messages[replyIdx].citations = citations
            }
        } catch {
            await MainActor.run {
                if messages[replyIdx].text.isEmpty {
                    messages[replyIdx].text = error.localizedDescription
                }
            }
        }
        await MainActor.run { isThinking = false }
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
