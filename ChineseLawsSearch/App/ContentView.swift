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
    @State private var showWelcome = false
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
                tabButton(title: "法律浏览", icon: "doc.text", tab: .browse)
                tabButton(title: "法律咨询", icon: "message", tab: .chat)
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
            .background(.bar)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(userStore)
        }
        .sheet(isPresented: $showWelcome) {
            NavigationStack {
                WelcomeView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showWelcome = false }
                        }
                    }
            }
        }
        .onAppear {
            let isFirstLaunch = !userStore.hasLaunchedBefore
            let shouldShowWelcome = userStore.showWelcomeOnLaunch || isFirstLaunch
            if isCompact && shouldShowWelcome {
                showWelcome = true
            } else {
                restoreLastRead()
            }
            if isFirstLaunch {
                userStore.hasLaunchedBefore = true
            }
        }
        .onChange(of: target) {
            if let t = target {
                userStore.recordRead(lawId: t.law.id, articleNum: t.scrollToArticle)
                persistBackStack()
            }
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
                    WelcomeView()
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
                                  showThinking: userStore.showThinking, navigate: navigate,
                                  onOpenSettings: { showSettings = true })                }
            } else {
                NavigationSplitView {
                    ChatHistorySidebar(historyStore: historyStore, vm: chatVM)
                } detail: {
                    NavigationStack {
                        LegalChatView(vm: chatVM, historyStore: historyStore,
                                      showThinking: userStore.showThinking, navigate: navigate,
                                      showHistoryButton: false, showNewSessionButton: true,
                                      onOpenSettings: { showSettings = true })
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
        let items = backStack.map { item in
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
    @State private var showWelcome = false
    @State private var showDeleteKeyConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("法律浏览") {
                    Toggle("显示右侧条文索引", isOn: $userStore.showSideIndex)
                    Toggle("仅搜索法律标题", isOn: $userStore.searchTitleOnly)
                    Toggle("搜索时忽略条号匹配", isOn: $userStore.searchExcludeArtNum)
                    Picker("搜索结果上限", selection: $userStore.searchResultLimit) {
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                        Text("200 条").tag(200)
                    }
                    Toggle("每次启动显示使用说明", isOn: $userStore.showWelcomeOnLaunch)
                    Button("查看使用说明") { showWelcome = true }
                }

                Section {
                    Toggle("显示思考过程", isOn: $userStore.showThinking)

                    Picker("分析模式", selection: $userStore.chatQualityMode) {
                        Text("节省").tag("economy")
                        Text("标准").tag("standard")
                        Text("详细").tag("detailed")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: userStore.chatQualityMode) {
                        userStore.applyQualityMode(userStore.chatQualityMode)
                    }
                } header: {
                    Text("对话")
                } footer: {
                    switch userStore.chatQualityMode {
                    case "economy":
                        Text("节省模式：追问 1 轮，上下文法条 15 条，参考法条 5 条。回答更简洁，消耗 token 最少。")
                    case "detailed":
                        Text("详细模式：追问 5 轮，法条上下文与引用数量不设上限。分析最全面，消耗 token 最多。")
                    default:
                        Text("标准模式：追问 3 轮，上下文法条 40 条，参考法条 80 条。兼顾质量与成本。")
                    }
                }

                Section {
                    // 目前仅支持 DeepSeek（国内直连），其他 provider 代码保留但不在 UI 展示
                    let deepseek = LLMProviderRegistry.provider(id: "deepseek")!
                    HStack {
                        Label(deepseek.displayName, systemImage: "cpu")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.shared.searchHighlight)
                            .font(.footnote.bold())
                    }
                } header: {
                    Text("AI 模型")
                } footer: {
                    Text("当前使用 DeepSeek，需在下方填入您的 API Key。DeepSeek 新用户注册即有免费额度，价格低廉，国内可直连。")
                }

                // DeepSeek API Key 输入
                let provider = LLMProviderRegistry.provider(id: "deepseek")!
                let currentKey = KeychainHelper.load(forKey: provider.keychainKey) ?? ""
                Section {
                    HStack {
                        SecureField("粘贴 DeepSeek API Key…", text: Binding(
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
                    if !currentKey.isEmpty {
                        Button(role: .destructive) {
                            showDeleteKeyConfirm = true
                        } label: {
                            Label("删除已保存的 Key", systemImage: "trash")
                        }
                        .confirmationDialog("确认删除 API Key？", isPresented: $showDeleteKeyConfirm, titleVisibility: .visible) {
                            Button("删除", role: .destructive) {
                                KeychainHelper.delete(forKey: provider.keychainKey)
                                savedKeys[provider.id] = ""
                            }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("删除后法律顾问功能将无法使用，需重新填入 Key。")
                        }
                    }
                    if let url = provider.keyURL {
                        Link("前往 DeepSeek 获取 API Key →", destination: url)
                            .font(.footnote)
                    }
                } header: {
                    Text("DeepSeek API Key")
                } footer: {
                    Text(currentKey.isEmpty
                         ? "尚未配置 API Key，法律顾问功能暂不可用。"
                         : "Key 加密存储在系统 Keychain 中，不会上传至任何服务器。")
                        .font(.caption)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showWelcome) {
                NavigationStack {
                    WelcomeView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showWelcome = false }
                            }
                        }
                }
            }
        }
    }

    private var footerText: String { "" }

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
