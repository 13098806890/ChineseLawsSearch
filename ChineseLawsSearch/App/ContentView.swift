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
    @State private var selectedGazetteDoc: GazetteDoc?
    @State private var selectedGazetteLaw: LawTarget?
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var showPaywall = false
    @State private var backStack: [BackItem] = []

    @StateObject private var userStore    = UserStore()
    @StateObject private var chatVM       = LegalChatViewModel()
    @StateObject private var historyStore = ChatHistoryStore()
    @ObservedObject private var pm = PurchaseManager.shared

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
                gazetteView
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(pm: pm)
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
                Task { @MainActor in showWelcome = true }
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
                    .environmentObject(userStore)
                    .navigationDestination(item: $target) { t in
                        LawDetailView(target: t, navigate: navigate,
                                      navigateToGazette: navigateToGazette,
                                      canGoBack: !backStack.isEmpty, goBack: goBack)
                            .environmentObject(userStore)
                    }
            }
        } else {
            NavigationSplitView {
                TOCView(target: $target)
                    .environmentObject(userStore)
            } detail: {
                if let t = target {
                    NavigationStack {
                        LawDetailView(target: t, navigate: navigate,
                                      navigateToGazette: navigateToGazette,
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
                                  navigateToGazette: navigateToGazette,
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
                                      navigateToGazette: navigateToGazette,
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
        FavoritesView(navigate: navigate, navigateToGazette: navigateToGazette)
            .environmentObject(userStore)
    }

    // MARK: Gazette

    private var gazetteView: some View {
        Group {
            if isCompact {
                NavigationStack {
                    GazetteView(selectedDoc: $selectedGazetteDoc,
                                navigate: navigate,
                                navigateToLaw: { selectedGazetteDoc = nil; selectedGazetteLaw = $0 })
                        .navigationDestination(item: $selectedGazetteDoc) { doc in
                            GazetteDetailView(
                                doc: doc,
                                navigateBack: gazetteNavigatedFromBrowse ? { tab = .browse; gazetteNavigatedFromBrowse = false }
                                            : gazetteNavigatedFromChat   ? { tab = .chat;   gazetteNavigatedFromChat   = false }
                                            : nil,
                                backLabel: gazetteNavigatedFromChat ? "返回对话" : "返回法条"
                            )
                            .environmentObject(userStore)
                        }
                        .navigationDestination(item: $selectedGazetteLaw) { lawTarget in
                            LawDetailView(target: lawTarget, navigate: navigate,
                                          navigateToGazette: navigateToGazette)
                                .environmentObject(userStore)
                        }
                }
            } else {
                NavigationSplitView {
                    GazetteView(selectedDoc: $selectedGazetteDoc,
                                navigate: navigate,
                                navigateToLaw: { selectedGazetteDoc = nil; selectedGazetteLaw = $0 })
                } detail: {
                    if let lawTarget = selectedGazetteLaw {
                        LawDetailView(target: lawTarget, navigate: navigate,
                                      navigateToGazette: navigateToGazette)
                            .environmentObject(userStore)
                    } else if let doc = selectedGazetteDoc {
                        GazetteDetailView(
                            doc: doc,
                            navigateBack: gazetteNavigatedFromBrowse ? { tab = .browse; gazetteNavigatedFromBrowse = false }
                                        : gazetteNavigatedFromChat   ? { tab = .chat;   gazetteNavigatedFromChat   = false }
                                        : nil,
                            backLabel: gazetteNavigatedFromChat ? "返回对话" : "返回法条"
                        )
                        .environmentObject(userStore)
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
            // Clear gazette navigation flags when manually switching to/from gazette tab
            if t == .gongbao {
                gazetteNavigatedFromBrowse = false
                gazetteNavigatedFromChat   = false
            }
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

    @State private var gazetteNavigatedFromBrowse = false
    @State private var gazetteNavigatedFromChat   = false

    func navigateToGazette(_ doc: GazetteDoc) {
        guard pm.canViewGazetteDetail else { showPaywall = true; return }
        gazetteNavigatedFromBrowse = (tab == .browse)
        gazetteNavigatedFromChat   = (tab == .chat)
        tab = .gongbao
        selectedGazetteLaw = nil
        selectedGazetteDoc = doc
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
        // Only restore latest session if chat is blank and no unsent text — don't clobber active conversation
        if prev.tab == .chat, chatVM.messages.isEmpty,
           chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let latest = historyStore.sessions.first {
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
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Agent 解锁状态
                Section {
                    switch pm.access {
                    case .pro:
                        VStack(alignment: .leading, spacing: 4) {
                            Label("已订阅 · 无限使用", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
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
                            Button("订阅解锁") { showPaywall = true }
                                .font(.footnote)
                                .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                    }
                } header: {
                    Text("法律顾问")
                } footer: {
                    switch pm.access {
                    case .pro:
                        Text("订阅版：无限使用法律顾问与高院公报全文。")
                    case .free(let remaining):
                        Text("每位新用户赠送 5 次免费体验，剩余 \(remaining) 次。订阅后可无限使用。")
                    case .noAccess:
                        Text("免费体验已用完，订阅后即可无限使用法律顾问与高院公报全文。")
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
                } header: {
                    Text("对话")
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
}

#Preview {
    ContentView()
}
