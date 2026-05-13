//
//  ContentView.swift
//  ChineseLawsSearch
//

import SwiftUI

/// Identifies a navigation destination: which law, and which article to scroll to.
/// Each call to `init` creates a unique instance (via `id`), so navigation always
/// fires even when law + article are the same — e.g. tapping the same search result twice.
struct LawTarget: Identifiable, Hashable {
    let id: UUID = UUID()
    let law: LawMeta
    let scrollToArticle: Int?

    init(law: LawMeta, scrollToArticle: Int?) {
        self.law = law
        self.scrollToArticle = scrollToArticle
    }

    static func == (lhs: LawTarget, rhs: LawTarget) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ContentView: View {
    @State private var tab: Tab = .browse
    @State private var target: LawTarget?
    @State private var selectedGongbaoDoc: GongbaoDoc?
    @State private var selectedGongbaoSfjs: GongbaoSfjs?
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var backStack: [BackItem] = []

    @StateObject private var userStore    = UserStore()
    @StateObject private var chatVM       = LegalChatViewModel()
    @StateObject private var historyStore = ChatHistoryStore()

    enum Tab { case browse, chat, favorites, gongbao }

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
                favoritesView
                    .opacity(tab == .favorites ? 1 : 0)
                    .allowsHitTesting(tab == .favorites)
                gongbaoView
                    .opacity(tab == .gongbao ? 1 : 0)
                    .allowsHitTesting(tab == .gongbao)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 0) {
                tabButton(title: "法律浏览", icon: "doc.text", tab: .browse)
                tabButton(title: "高院公报", icon: "newspaper", tab: .gongbao)
                tabButton(title: "法律咨询", icon: "message", tab: .chat)
                tabButton(title: "收藏", icon: "star", tab: .favorites)
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
            .ignoresSafeArea(.keyboard)
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
                            Button("完成") {
                                showWelcome = false
                                restoreLastRead()
                            }
                        }
                    }
            }
        }
        .onAppear {
            let isFirstLaunch = !userStore.hasLaunchedBefore
            if isFirstLaunch {
                userStore.hasLaunchedBefore = true
            }
            let shouldShowWelcome = userStore.showWelcomeOnLaunch || isFirstLaunch
            if isCompact && shouldShowWelcome {
                DispatchQueue.main.async { showWelcome = true }
            }
            restoreLastRead()
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
                TOCView(target: $target)
                    .navigationDestination(item: $target) { t in
                        LawDetailView(target: t, navigate: navigate,
                                      navigateToGongbao: navigateToGongbao,
                                      canGoBack: !backStack.isEmpty, goBack: goBack)
                            .environmentObject(userStore)
                    }
            }
        } else {
            NavigationSplitView {
                TOCView(target: $target)
            } detail: {
                if let t = target {
                    NavigationStack {
                        LawDetailView(target: t, navigate: navigate,
                                      navigateToGongbao: navigateToGongbao,
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
                                  navigateToGongbao: navigateToGongbao,
                                  onOpenSettings: { showSettings = true },
                                  isActive: tab == .chat)
                        .environmentObject(userStore)
                }
            } else {
                NavigationSplitView {
                    ChatHistorySidebar(historyStore: historyStore, vm: chatVM)
                } detail: {
                    NavigationStack {
                        LegalChatView(vm: chatVM, historyStore: historyStore,
                                      showThinking: userStore.showThinking, navigate: navigate,
                                      navigateToGongbao: navigateToGongbao,
                                      showHistoryButton: false, showNewSessionButton: true,
                                      onOpenSettings: { showSettings = true },
                                      isActive: tab == .chat)
                            .environmentObject(userStore)
                    }
                }
            }
        }
    }

    // MARK: Favorites

    private var favoritesView: some View {
        FavoritesView(navigate: navigate, navigateToGongbao: navigateToGongbao)
            .environmentObject(userStore)
    }

    // MARK: Gongbao

    private var gongbaoView: some View {
        Group {
            if isCompact {
                NavigationStack {
                    GongbaoView(selectedDoc: $selectedGongbaoDoc, selectedSfjs: $selectedGongbaoSfjs)
                        .navigationDestination(item: $selectedGongbaoDoc) { doc in
                            GongbaoDetailView(
                                doc: doc,
                                navigateBack: gongbaoNavigatedFromBrowse ? { tab = .browse; gongbaoNavigatedFromBrowse = false }
                                            : gongbaoNavigatedFromChat   ? { tab = .chat;   gongbaoNavigatedFromChat   = false }
                                            : nil,
                                backLabel: gongbaoNavigatedFromChat ? "返回对话" : "返回法条"
                            )
                            .environmentObject(userStore)
                        }
                        .navigationDestination(item: $selectedGongbaoSfjs) { doc in
                            GongbaoSfjsDetailView(doc: doc)
                        }
                }
            } else {
                NavigationSplitView {
                    GongbaoView(selectedDoc: $selectedGongbaoDoc, selectedSfjs: $selectedGongbaoSfjs)
                } detail: {
                    if let doc = selectedGongbaoDoc {
                        GongbaoDetailView(
                            doc: doc,
                            navigateBack: gongbaoNavigatedFromBrowse ? { tab = .browse; gongbaoNavigatedFromBrowse = false }
                                        : gongbaoNavigatedFromChat   ? { tab = .chat;   gongbaoNavigatedFromChat   = false }
                                        : nil,
                            backLabel: gongbaoNavigatedFromChat ? "返回对话" : "返回法条"
                        )
                        .environmentObject(userStore)
                    } else if let doc = selectedGongbaoSfjs {
                        GongbaoSfjsDetailView(doc: doc)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "newspaper")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("选择条目")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if backStack.count > 20 { backStack.removeFirst() }
            tab = .browse
            target = LawTarget(law: law, scrollToArticle: articleNum)
        }
    }

    @State private var gongbaoNavigatedFromBrowse = false
    @State private var gongbaoNavigatedFromChat   = false

    func navigateToGongbao(_ doc: GongbaoDoc) {
        gongbaoNavigatedFromBrowse = (tab == .browse)
        gongbaoNavigatedFromChat   = (tab == .chat)
        tab = .gongbao
        selectedGongbaoDoc = doc
    }

    /// 持久化当前 backStack + target 到 UserDefaults
    private func persistBackStack() {
        let items = backStack.map { item in
            PersistedBackItem(
                tab: item.tab == .browse ? "browse" : item.tab == .chat ? "chat" : item.tab == .gongbao ? "gongbao" : "favorites",
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

        let persistedItems = userStore.loadBackStack()
        backStack = persistedItems.compactMap { item -> BackItem? in
            let t: Tab = item.tab == "browse" ? .browse : item.tab == "chat" ? .chat : item.tab == "gongbao" ? .gongbao : .favorites
            if let lid = item.lawId, let meta = DatabaseManager.shared.lawMeta(id: lid) {
                return BackItem(tab: t, target: LawTarget(law: meta, scrollToArticle: item.articleNum))
            } else {
                return BackItem(tab: t, target: nil)
            }
        }

        target = LawTarget(law: law, scrollToArticle: last.articleNum)
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        tab = prev.tab
        target = prev.target
        // Only restore latest session if chat is blank — don't clobber an active conversation
        if prev.tab == .chat, chatVM.messages.isEmpty, let latest = historyStore.sessions.first {
            chatVM.loadSession(latest)
        }
        persistBackStack()
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @EnvironmentObject private var userStore: UserStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pm = PurchaseManager.shared
    @State private var showPaywall = false
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
    @State private var testStatus: TestStatus = .idle

    enum TestStatus {
        case idle, testing, success, failure(String)
        var isLoading: Bool { if case .testing = self { return true }; return false }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Agent 解锁状态
                Section {
                    switch pm.access {
                    case .pro(let remaining):
                        VStack(alignment: .leading, spacing: 4) {
                            Label("畅用版已激活", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("本周剩余 \(remaining) 次 · 每周一自动重置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    case .basic:
                        VStack(alignment: .leading, spacing: 4) {
                            Label(pm.hasPRO ? "畅用版已激活 · 自备 Key 优先" : "基础版已激活",
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            if pm.hasPRO {
                                Text("您的 API Key 优先使用，不消耗每周额度")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    case .free(let remaining):
                        HStack {
                            Label("免费剩余 \(remaining) 次", systemImage: "gift")
                            Spacer()
                            Button("解锁无限使用") { showPaywall = true }
                                .font(.footnote)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                    case .noAccess:
                        HStack {
                            Label("免费次数已用完", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("购买解锁") { showPaywall = true }
                                .font(.footnote)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                    }
                } header: {
                    Text("法律顾问")
                } footer: {
                    switch pm.access {
                    case .pro:
                        Text("畅用版：内置 Key 已为您配置，每周 \(PurchaseManager.proWeeklyTotal) 次额度，每周一重置。")
                    case .basic:
                        Text(userStore.apiKeyConfigured
                             ? "基础版：使用您自己的 API Key，无次数限制。"
                             : "基础版已激活。请在下方配置 DeepSeek API Key 以开始使用。")
                    case .free(let remaining):
                        Text("每位用户免费赠送 5 次体验，剩余 \(remaining) 次。\n畅用版包含内置 Key 每周 \(PurchaseManager.proWeeklyTotal) 次；基础版需自备 Key 但无次数限制。")
                    case .noAccess:
                        Text("免费体验已用完。\n· 畅用版：内置 Key，每周 \(PurchaseManager.proWeeklyTotal) 次，无需配置\n· 基础版：需自备 DeepSeek API Key，无次数限制")
                    }
                }

                Section {
                    Toggle("显示右侧条文索引", isOn: $userStore.showSideIndex)
                    Toggle("每次启动显示使用说明", isOn: $userStore.showWelcomeOnLaunch)
                    Button("查看使用说明") { showWelcome = true }
                    Picker("条文字号", selection: $userStore.articleFontSize) {
                        Text("小").tag("small")
                        Text("中").tag("medium")
                        Text("大").tag("large")
                        Text("超大").tag("xlarge")
                    }
                } header: {
                    Text("法律浏览")
                }

                Section {
                    Toggle("仅搜索法律标题", isOn: $userStore.searchTitleOnly)
                    Toggle("搜索时忽略条号匹配", isOn: $userStore.searchExcludeArtNum)
                    Picker("搜索结果上限", selection: $userStore.searchResultLimit) {
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                        Text("200 条").tag(200)
                    }
                    Toggle("法律法规", isOn: $userStore.searchIncludeLaws)
                    Toggle("司法解释", isOn: $userStore.searchIncludeInterp)
                } header: {
                    Text("搜索")
                } footer: {
                    if !userStore.searchIncludeLaws && !userStore.searchIncludeInterp {
                        Text("两项均关闭时，搜索将覆盖全部类型。")
                    }
                }

                Section {
                    Toggle("显示思考过程", isOn: $userStore.showThinking)

                    if case .basic = pm.access {
                        Picker("分析模式", selection: $userStore.chatQualityMode) {
                            Text("节省").tag("economy")
                            Text("标准").tag("standard")
                            Text("详细").tag("detailed")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: userStore.chatQualityMode) {
                            userStore.applyQualityMode(userStore.chatQualityMode)
                        }
                    }
                } header: {
                    Text("对话")
                } footer: {
                    if case .basic = pm.access {
                        switch userStore.chatQualityMode {
                        case "economy":
                            Text("节省模式：追问 1 轮，上下文法条 15 条，参考法条 5 条。回答更简洁，消耗 token 最少。")
                        case "detailed":
                            Text("详细模式：追问 5 轮，法条上下文与引用数量不设上限。分析最全面，消耗 token 最多。")
                        default:
                            Text("标准模式：追问 3 轮，上下文法条 40 条，参考法条 80 条。兼顾质量与成本。")
                        }
                    } else {
                        Text("畅用版使用标准分析模式。")
                    }
                }

                // AI 模型与 API Key — 始终显示（pro+自备Key 优先走自备Key，不消耗额度）
                Section {
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
                            switch testStatus {
                            case .testing:
                                ProgressView().scaleEffect(0.8)
                            case .success:
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failure:
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            case .idle:
                                EmptyView()
                            }
                        }
                        Button {
                            Task { await saveKeyWithTest(provider: provider) }
                        } label: {
                            if testStatus.isLoading {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("验证中…")
                                }
                            } else {
                                Text("验证并保存")
                            }
                        }
                        .disabled((savedKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus.isLoading)
                        if case .failure(let msg) = testStatus {
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red).font(.footnote)
                        }
                        if !currentKey.isEmpty {
                            Button(role: .destructive) {
                                showDeleteKeyConfirm = true
                            } label: {
                                Label { Text("删除已保存的 Key") } icon: {
                                    Image(systemName: "trash")
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                            .confirmationDialog("确认删除 API Key？", isPresented: $showDeleteKeyConfirm, titleVisibility: .visible) {
                                Button("删除", role: .destructive) {
                                    KeychainHelper.delete(forKey: provider.keychainKey)
                                    savedKeys[provider.id] = ""
                                    userStore.refreshAPIKeyState()
                                    testStatus = .idle
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
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                Section {
                    Text("律疏 \(version).\(build)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(pm: pm)
            }
        }
    }

    @MainActor
    private func saveKeyWithTest(provider: any LLMProvider) async {
        let trimmed = (savedKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        testStatus = .testing
        KeychainHelper.save(trimmed, forKey: provider.keychainKey)
        do {
            _ = try await provider.chat(
                messages: [["role": "user", "content": "hi"]],
                temperature: 0
            )
            testStatus = .success
            userStore.refreshAPIKeyState()
            savedFeedback = provider.id
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .success = testStatus { testStatus = .idle }
        } catch LLMError.apiKeyMissing {
            KeychainHelper.delete(forKey: provider.keychainKey)
            userStore.refreshAPIKeyState()
            testStatus = .failure("Key 未配置")
        } catch LLMError.apiKeyInvalid {
            KeychainHelper.delete(forKey: provider.keychainKey)
            userStore.refreshAPIKeyState()
            testStatus = .failure("Key 无效，请检查后重试")
        } catch {
            // Network error — keep key saved (could be temporary)
            testStatus = .failure("网络错误，Key 已保存")
            userStore.refreshAPIKeyState()
            savedFeedback = provider.id
        }
    }
}

#Preview {
    ContentView()
}
