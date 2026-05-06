//
//  LegalChatView.swift
//  ChineseLawsSearch
//

import SwiftUI
import Combine

struct LegalChatView: View {
    @StateObject private var vm = LegalChatViewModel()
    @FocusState  private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.messages.isEmpty {
                            placeholderView
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg)
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
                .onChange(of: vm.messages.count) { _, _ in
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

            Divider()

            // 输入栏
            HStack(alignment: .bottom, spacing: 8) {
                TextField("请输入您的法律问题…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .focused($inputFocused)
                    .disabled(vm.isThinking)

                Button {
                    inputFocused = false
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
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "scale.3d")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.shared.searchHighlight.opacity(0.6))
            Text("您好，我是中国法律助手")
                .font(.headline)
            Text("请描述您的法律问题，我会根据现行法律法规为您解答。")
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
    @State private var showCitations = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            HStack {
                if message.role == .user { Spacer(minLength: 48) }
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user
                                ? AppColors.shared.searchHighlight
                                : Color(.systemGray6))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if message.role == .assistant { Spacer(minLength: 48) }
            }

            if message.role == .assistant && !message.citations.isEmpty {
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
                    CitationList(citations: message.citations)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Citation List

private struct CitationList: View {
    let citations: [RAGCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(citations) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(c.lawTitle)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                        Text(c.articleNumber)
                            .font(.caption).fontWeight(.semibold)
                        Spacer()
                        Text(c.tier)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(c.tier == "司法解释"
                                        ? Color.blue.opacity(0.12)
                                        : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    Text(c.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
                .padding(10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - ViewModel

final class LegalChatViewModel: ObservableObject {
    @Published var messages:   [ChatMessage] = []
    @Published var inputText   = ""
    @Published var isThinking  = false
    @Published var dotScale    = [1.0, 1.0, 1.0]

    private var dotTask: Task<Void, Never>?

    @MainActor
    func send() async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, text: q))

        isThinking = true
        var replyMsg = ChatMessage(role: .assistant, text: "")
        messages.append(replyMsg)
        let replyIdx = messages.count - 1

        do {
            let citations = try await LegalRAGService.shared.ask(question: q) { [weak self] token in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.messages[replyIdx].text += token
                    self.isThinking = false
                }
            }
            await MainActor.run { messages[replyIdx].citations = citations }
        } catch {
            await MainActor.run {
                if messages[replyIdx].text.isEmpty {
                    messages[replyIdx].text = "暂时无法连接到模型，请确认 Ollama 已在本地运行（http://localhost:11434）。"
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
