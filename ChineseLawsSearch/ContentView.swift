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
    @State private var backStack: [BackItem] = []

    @StateObject private var userStore    = UserStore()
    @StateObject private var chatVM       = LegalChatViewModel()
    @StateObject private var historyStore = ChatHistoryStore()

    enum Tab { case browse, chat }

    struct BackItem {
        let tab: Tab
        let target: LawTarget?
    }

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                browseView
                    .opacity(tab == .browse ? 1 : 0)
                    .allowsHitTesting(tab == .browse)
                chatView
                    .opacity(tab == .chat ? 1 : 0)
                    .allowsHitTesting(tab == .chat)
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
                    .foregroundStyle(Color.appSecondaryLabel)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56)
            .background(
                Color.appBackground.ignoresSafeArea(edges: .bottom)
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(userStore)
        }
        .onAppear {
            restoreLastRead()
        }
        .onChange(of: target) { newTarget in
            // 记录当前阅读位置（target 变化时同步，包含从 TOC 直接点击的情况）
            if let t = newTarget {
                userStore.recordRead(lawId: t.law.id, articleNum: t.scrollToArticle)
            }
            // 同步持久化 backStack
            persistBackStack()
        }
    }

    // MARK: Browse

    @ViewBuilder
    private var browseView: some View {
        if isCompact {
            NavigationStack {
                TOCView(selectedLaw: $selectedLaw, target: $target)
                    .navigationDestination(item: $target) { t in
                        LawDetailView(target: t, navigate: navigate,
                                      canGoBack: !backStack.isEmpty, goBack: goBack)
                            .environmentObject(userStore)
                    }
            }
        } else {
            NavigationSplitView {
                TOCView(selectedLaw: $selectedLaw, target: $target)
            } detail: {
                if let t = target {
                    NavigationStack {
                        LawDetailView(target: t, navigate: navigate,
                                      canGoBack: !backStack.isEmpty, goBack: goBack)
                            .environmentObject(userStore)
                    }
                    .id(t)
                } else {
                    Text("选择一部法律")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Chat

    private var chatView: some View {
        Group {
            if isCompact {
                NavigationStack {
                    LegalChatView(vm: chatVM, historyStore: historyStore,
                                  showThinking: userStore.showThinking, navigate: navigate)                }
            } else {
                NavigationSplitView {
                    ChatHistorySidebar(historyStore: historyStore, vm: chatVM) {
                        chatVM.newSession()
                    }
                } detail: {
                    NavigationStack {
                        LegalChatView(vm: chatVM, historyStore: historyStore,
                                      showThinking: userStore.showThinking, navigate: navigate,
                                      showHistoryButton: false)
                    }
                }
            }
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
            .foregroundStyle(tab == t ? AppColors.shared.searchHighlight : Color.appSecondaryLabel)
            .frame(maxWidth: .infinity)
        }
    }

    func navigate(to lawId: Int, articleNum: Int?) {
        if let law = DatabaseManager.shared.lawMeta(id: lawId) {
            backStack.append(BackItem(tab: tab, target: target))
            tab = .browse
            selectedLaw = law
            target = LawTarget(law: law, scrollToArticle: articleNum)
            persistBackStack()
        }
    }

    /// 持久化当前 backStack + target 到 UserDefaults
    private func persistBackStack() {
        var items = backStack.map { item in
            PersistedBackItem(
                tab: item.tab == .browse ? "browse" : "chat",
                lawId: item.target?.law.id,
                articleNum: item.target?.scrollToArticle
            )
        }
        // 末尾追加当前 target 作为「当前层」标记，tab 固定 browse
        // （target 本身已由 lastReadLawId/lastReadArticleNum 记录，这里只存 stack）
        userStore.saveBackStack(items)
    }

    /// 启动时恢复上次阅读位置和跳转链路
    private func restoreLastRead() {
        guard let last = userStore.lastRead else { return }
        guard let law = DatabaseManager.shared.lawMeta(id: last.lawId) else { return }

        // 恢复 backStack
        let persistedItems = userStore.loadBackStack()
        backStack = persistedItems.compactMap { item -> BackItem? in
            let t: Tab = item.tab == "browse" ? .browse : .chat
            if let lid = item.lawId, let meta = DatabaseManager.shared.lawMeta(id: lid) {
                return BackItem(tab: t, target: LawTarget(law: meta, scrollToArticle: item.articleNum))
            } else {
                return BackItem(tab: t, target: nil)
            }
        }

        // 直接设置 target，不走 navigate（避免把 target 自己压入 backStack）
        selectedLaw = law
        target = LawTarget(law: law, scrollToArticle: last.articleNum)
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        tab = prev.tab
        target = prev.target
        selectedLaw = prev.target?.law
        persistBackStack()
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @EnvironmentObject private var userStore: UserStore
    @Environment(\.dismiss) private var dismiss
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
                Section("法律浏览") {
                    Toggle("显示右侧条文索引", isOn: $userStore.showSideIndex)
                }

                Section("对话") {
                    Toggle("显示思考过程", isOn: $userStore.showThinking)
                    Stepper("专家最多追问 \(userStore.maxFollowUpRounds) 轮",
                            value: $userStore.maxFollowUpRounds, in: 0...5)
                    let label = userStore.maxCitations == 0 ? "参考法条：不限数量" : "参考法条最多 \(userStore.maxCitations) 条"
                    Stepper(label, value: $userStore.maxCitations, in: 0...200, step: 10)
                    Stepper("每专家上下文法条 \(userStore.maxContextArticles) 条",
                            value: $userStore.maxContextArticles, in: 5...1000, step: 5)
                }

                Section {
                    Picker("模型", selection: $userStore.selectedProviderId) {
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
                if let provider = LLMProviderRegistry.provider(id: userStore.selectedProviderId),
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
        switch userStore.selectedProviderId {
        case "groq":    return "Groq 免费，无需绑卡，国内可直连。使用 Llama 3.3 70B 模型，中文能力较好。"
        case "gemini":  return "Gemini Flash 免费额度：每天 100 万 tokens。部分地区需要 VPN 申请 Key。"
        case "deepseek": return "DeepSeek 按量计费，价格较低。需要在账户中充值。"
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
