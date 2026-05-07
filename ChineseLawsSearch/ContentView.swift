//
//  ContentView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct LawTarget: Equatable, Hashable {
    let law: LawMeta
    let scrollToArticle: Int?
}

struct ContentView: View {
    @State private var tab: Tab = .browse
    @State private var selectedLaw: LawMeta?
    @State private var target: LawTarget?
    @State private var showSettings = false
    @AppStorage("showThinking") private var showThinking = true

    @StateObject private var chatVM = LegalChatViewModel()
    @StateObject private var historyStore = ChatHistoryStore()

    enum Tab { case browse, chat }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if tab == .browse {
                    browseView
                } else {
                    chatView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 0) {
                tabButton(title: "法律浏览", icon: "books.vertical", tab: .browse)
                tabButton(title: "法律咨询", icon: "bubble.left.and.text.bubble.right", tab: .chat)
                Button {
                    showSettings = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                        Text("设置")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color(.systemGray))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56)
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showThinking: $showThinking)
        }
    }

    // MARK: Browse

    @ViewBuilder
    private var browseView: some View {
        if isPhone {
            NavigationStack {
                TOCView(selectedLaw: $selectedLaw, target: $target)
                    .navigationDestination(item: $target) { t in
                        LawDetailView(target: t, navigate: navigate)
                    }
            }
        } else {
            NavigationSplitView {
                TOCView(selectedLaw: $selectedLaw, target: $target)
            } detail: {
                if let t = target {
                    NavigationStack {
                        LawDetailView(target: t, navigate: navigate)
                    }
                    .id(t.law.id)
                } else {
                    Text("选择一部法律")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Chat

    private var chatView: some View {
        NavigationStack {
            LegalChatView(vm: chatVM, historyStore: historyStore, showThinking: showThinking, navigate: navigate)
        }
    }

    // MARK: Tab button

    private func tabButton(title: String, icon: String, tab t: Tab) -> some View {
        Button {
            tab = t
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(tab == t ? AppColors.shared.searchHighlight : Color(.systemGray))
            .frame(maxWidth: .infinity)
        }
    }

    func navigate(to lawId: Int, articleNum: Int?) {
        if let law = DatabaseManager.shared.lawMeta(id: lawId) {
            tab = .browse
            selectedLaw = law
            target = LawTarget(law: law, scrollToArticle: articleNum)
        }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @Binding var showThinking: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("maxFollowUpRounds") private var maxFollowUpRounds: Int = 3

    @AppStorage("selected_llm_provider") private var selectedProviderId = "gemini"
    @State private var savedKeys: [String: String] = {
        var d: [String: String] = [:]
        for p in LLMProviderRegistry.all where !p.keychainKey.isEmpty {
            d[p.id] = KeychainHelper.load(forKey: p.keychainKey) ?? ""
        }
        return d
    }()
    @State private var savedFeedback: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("对话") {
                    Toggle("显示思考过程", isOn: $showThinking)
                    Stepper("专家最多追问 \(maxFollowUpRounds) 轮",
                            value: $maxFollowUpRounds, in: 0...5)
                }

                Section {
                    Picker("模型", selection: $selectedProviderId) {
                        ForEach(LLMProviderRegistry.all, id: \.id) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("模型选择")
                } footer: {
                    Text(footerText)
                }

                // 当前选中 provider 的 Key 输入（Ollama 不需要）
                if let provider = LLMProviderRegistry.provider(id: selectedProviderId),
                   !provider.keychainKey.isEmpty {
                    Section {
                        HStack {
                            SecureField("粘贴 API Key…", text: Binding(
                                get: { savedKeys[provider.id] ?? "" },
                                set: { savedKeys[provider.id] = $0 }
                            ))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            if savedFeedback == provider.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Button("保存 Key") { saveKey(for: provider) }
                            .disabled((savedKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let url = provider.keyURL {
                            Link("前往 \(provider.displayName) 获取 API Key →", destination: url)
                                .font(.footnote)
                        }
                    } header: {
                        Text("\(provider.displayName) API Key")
                    } footer: {
                        Text("Key 加密存储在系统 Keychain 中。")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var footerText: String {
        switch selectedProviderId {
        case "groq":    return "Groq 免费，无需绑卡，国内可直连。使用 Llama 3.3 70B 模型，中文能力较好。"
        case "gemini":  return "Gemini Flash 免费额度：每天 100 万 tokens。部分地区需要 VPN 申请 Key。"
        case "deepseek": return "DeepSeek 按量计费，价格较低。需要在账户中充值。"
        case "ollama":  return "本地运行，需先在 Mac 上启动 Ollama（ollama serve）。"
        default:        return ""
        }
    }

    private func saveKey(for provider: any LLMProvider) {
        let trimmed = (savedKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(forKey: provider.keychainKey)
        } else {
            KeychainHelper.save(trimmed, forKey: provider.keychainKey)
        }
        savedFeedback = provider.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFeedback = nil }
    }
}

#Preview {
    ContentView()
}
