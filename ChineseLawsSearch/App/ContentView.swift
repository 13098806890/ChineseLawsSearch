//
//  ContentView.swift
//  ChineseLawsSearch
//

import SwiftUI
import UIKit

/// Identifies a navigation destination: which law, and which article to scroll to.
/// Each call to `init` creates a unique instance (via `id`), so navigation always
/// fires even when law + article are the same — e.g. tapping the same search result twice.
struct LawTarget: Identifiable, Hashable {
    let id: UUID = UUID()
    let law: LawMeta
    let scrollToArticle: Int?
    /// Non-nil when this was the entry point from another tab (chat/gazette → browse).
    /// Used by LawDetailView to show the custom "返回" back button instead of system back.
    let fromTab: ContentView.Tab?

    init(law: LawMeta, scrollToArticle: Int?, fromTab: ContentView.Tab? = nil) {
        self.law = law
        self.scrollToArticle = scrollToArticle
        self.fromTab = fromTab
    }

    static func == (lhs: LawTarget, rhs: LawTarget) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ContentView: View {
    @State private var tab: Tab = .browse
    /// Browse navigation path — supports multi-level cross-law navigation with native swipe-back.
    @State private var browseNavPath: [LawTarget] = []
    @State private var intraLawScrollArticle: Int? = nil   // same-law in-page scroll signal
    @State private var selectedGazetteDoc: GazetteDoc?
    @State private var selectedGazetteLaw: LawTarget?
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var showPaywall = false
    @State private var backStack: [BackItem] = []

    private var currentTarget: LawTarget? { browseNavPath.last }

    /// The tab we should return to when swiping back — covers both browse cross-tab and gazette cross-tab.
    private var effectiveFromTab: Tab? {
        if let ft = currentTarget?.fromTab { return ft }
        if gazetteNavigatedFromChat      { return .chat }
        if gazetteNavigatedFromBrowse    { return .browse }
        if gazetteNavigatedFromFavorites { return .favorites }
        return nil
    }
    private var canSwipeBack: Bool { effectiveFromTab != nil }

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
            // 所有 tab 同时存在于 View 树中，避免切换时销毁 ScrollView 状态
            // TabSwipeContainer 拥有 swipeBackOffset，手势回调不会导致 ContentView 重绘
            TabSwipeContainer(
                currentTab: tab,
                canSwipeBack: canSwipeBack,
                fromTab: effectiveFromTab,
                browseView: { browseView },
                gazetteView: { gazetteView },
                chatView: { chatView },
                favoritesView: { favoritesView },
                onGoBack: goBack
            )
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
            if shouldShowWelcome {
                Task { @MainActor in showWelcome = true }
            }
            restoreLastRead()
        }
        .onChange(of: currentTarget) {
            if let t = currentTarget {
                userStore.recordRead(lawId: t.law.id, articleNum: t.scrollToArticle)
                persistBackStack()
            }
        }
    }

    @ViewBuilder
    private var browseView: some View {
        if isCompact {
            NavigationStack(path: $browseNavPath) {
                TOCView(target: Binding(
                    get: { currentTarget },
                    set: { if let t = $0 { browseNavPath.append(t) } else { browseNavPath.removeAll() } }
                ))
                    .environmentObject(userStore)
                    .navigationDestination(for: LawTarget.self) { t in
                        LawDetailView(target: t,
                                      intraLawScrollArticle: $intraLawScrollArticle,
                                      navigate: navigate,
                                      navigateToGazette: navigateToGazette,
                                      canGoBack: t.fromTab != nil,
                                      showMenuButton: true,
                                      goBack: goBack,
                                      goToMenu: { tab = .browse; browseNavPath.removeAll(); backStack.removeAll(); persistBackStack() })
                            .environmentObject(userStore)
                    }
            }
        } else {
            NavigationSplitView {
                TOCView(target: Binding(
                    get: { currentTarget },
                    set: { if let t = $0 { browseNavPath = [t] } else { browseNavPath.removeAll() } }
                ))
                    .environmentObject(userStore)
            } detail: {
                if let t = currentTarget {
                    NavigationStack(path: Binding(
                        get: { browseNavPath.count > 1 ? Array(browseNavPath.dropFirst()) : [] },
                        set: { sub in
                            if sub.isEmpty { browseNavPath = browseNavPath.isEmpty ? [] : [browseNavPath[0]] }
                            else { browseNavPath = [browseNavPath[0]] + sub }
                        }
                    )) {
                        LawDetailView(target: t,
                                      intraLawScrollArticle: $intraLawScrollArticle,
                                      navigate: navigate,
                                      navigateToGazette: navigateToGazette,
                                      canGoBack: t.fromTab != nil,
                                      goBack: goBack,
                                      goToMenu: { browseNavPath.removeAll(); backStack.removeAll(); persistBackStack() })
                            .environmentObject(userStore)
                            .navigationDestination(for: LawTarget.self) { inner in
                                LawDetailView(target: inner,
                                              intraLawScrollArticle: $intraLawScrollArticle,
                                              navigate: navigate,
                                              navigateToGazette: navigateToGazette,
                                              canGoBack: false,
                                              showMenuButton: true,
                                              goBack: {},
                                              goToMenu: { browseNavPath.removeAll(); backStack.removeAll(); persistBackStack() })
                                    .environmentObject(userStore)
                            }
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
                                navigateToLaw: { selectedGazetteDoc = nil; selectedGazetteLaw = $0 },
                                onSelectDoc: selectGazetteDoc)
                        .navigationDestination(item: $selectedGazetteDoc) { doc in
                            GazetteDetailView(
                                doc: doc,
                                navigateBack: gazetteNavigatedFromBrowse    ? { tab = .browse;    gazetteNavigatedFromBrowse    = false }
                                            : gazetteNavigatedFromChat      ? { tab = .chat;      gazetteNavigatedFromChat      = false }
                                            : gazetteNavigatedFromFavorites ? { tab = .favorites; gazetteNavigatedFromFavorites = false }
                                            : nil,
                                backLabel: gazetteNavigatedFromChat ? "返回对话" : gazetteNavigatedFromFavorites ? "返回收藏" : "返回法条",
                                goToMenu: { selectedGazetteDoc = nil }
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
                                navigateToLaw: { selectedGazetteDoc = nil; selectedGazetteLaw = $0 },
                                onSelectDoc: selectGazetteDoc)
                } detail: {
                    if let lawTarget = selectedGazetteLaw {
                        LawDetailView(target: lawTarget, navigate: navigate,
                                      navigateToGazette: navigateToGazette)
                            .environmentObject(userStore)
                    } else if let doc = selectedGazetteDoc {
                        GazetteDetailView(
                            doc: doc,
                            navigateBack: gazetteNavigatedFromBrowse    ? { tab = .browse;    gazetteNavigatedFromBrowse    = false }
                                        : gazetteNavigatedFromChat      ? { tab = .chat;      gazetteNavigatedFromChat      = false }
                                        : gazetteNavigatedFromFavorites ? { tab = .favorites; gazetteNavigatedFromFavorites = false }
                                        : nil,
                            backLabel: gazetteNavigatedFromChat ? "返回对话" : gazetteNavigatedFromFavorites ? "返回收藏" : "返回法条",
                            goToMenu: { selectedGazetteDoc = nil }
                        )
                        .environmentObject(userStore)
                    } else {
                        GazetteWelcomeView()
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
                gazetteNavigatedFromBrowse    = false
                gazetteNavigatedFromChat      = false
                gazetteNavigatedFromFavorites = false
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
            showSettings = false
            showPaywall = false
            showWelcome = false
            let fromTab: Tab? = tab != .browse ? tab : nil
            if tab != .browse {
                backStack.append(BackItem(tab: tab, target: currentTarget))
                if backStack.count > 20 { backStack.removeFirst() }
            }
            intraLawScrollArticle = nil
            tab = .browse
            let newTarget = LawTarget(law: law, scrollToArticle: articleNum, fromTab: fromTab)
            if fromTab != nil {
                // Cross-tab: replace entire path so the cross-tab back button shows
                browseNavPath = [newTarget]
            } else {
                // Within browse (same or different law): push for native swipe-back
                browseNavPath.append(newTarget)
            }
        }
    }

    @State private var gazetteNavigatedFromBrowse    = false
    @State private var gazetteNavigatedFromChat      = false
    @State private var gazetteNavigatedFromFavorites = false

    func navigateToGazette(_ doc: GazetteDoc) {
        guard pm.canViewGazetteDetail else { showPaywall = true; return }
        gazetteNavigatedFromBrowse    = (tab == .browse)
        gazetteNavigatedFromChat      = (tab == .chat)
        gazetteNavigatedFromFavorites = (tab == .favorites)
        tab = .gongbao
        selectedGazetteLaw = nil
        selectedGazetteDoc = doc
    }

    /// Used by GazetteView's own list — gates access before setting selectedDoc.
    func selectGazetteDoc(_ doc: GazetteDoc) {
        guard pm.canViewGazetteDetail else { showPaywall = true; return }
        selectedGazetteLaw = nil
        selectedGazetteDoc = doc
    }

    /// 持久化当前 backStack 到 UserDefaults（browseNavPath 的 top 由 lastRead 记录）
    private func persistBackStack() {
        let items = backStack.map { item in
            PersistedBackItem(
                tab: item.tab == .browse ? "browse" : item.tab == .chat ? "chat" : item.tab == .gongbao ? "gongbao" : "favorites",
                lawId: item.target?.law.id,
                articleNum: item.target?.scrollToArticle
            )
        }
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

        browseNavPath = [LawTarget(law: law, scrollToArticle: last.articleNum)]
    }


    func goBack() {
        guard let fromTab = effectiveFromTab else { return }
        // Gazette cross-tab
        if gazetteNavigatedFromBrowse || gazetteNavigatedFromChat || gazetteNavigatedFromFavorites {
            gazetteNavigatedFromBrowse    = false
            gazetteNavigatedFromChat      = false
            gazetteNavigatedFromFavorites = false
            tab = fromTab
            return
        }
        // Browse cross-tab
        tab = fromTab
        browseNavPath.removeAll()
        if fromTab == .chat, chatVM.messages.isEmpty,
           chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let latest = historyStore.sessions.first {
            chatVM.loadSession(latest)
        }
        _ = backStack.popLast()
        persistBackStack()
    }
}

// MARK: - TabSwipeContainer

/// Extracted struct so @State swipeBackOffset changes only re-render this small
/// container, not ContentView.body. SwiftUI .offset() is a render transform —
/// it does NOT trigger layout on child views, so no tab re-lays-out at 60fps.
private struct TabSwipeContainer<Browse: View, Gazette: View, Chat: View, Fav: View>: View {
    let currentTab: ContentView.Tab
    let canSwipeBack: Bool
    let fromTab: ContentView.Tab?
    @ViewBuilder let browseView: () -> Browse
    @ViewBuilder let gazetteView: () -> Gazette
    @ViewBuilder let chatView: () -> Chat
    @ViewBuilder let favoritesView: () -> Fav
    let onGoBack: () -> Void

    @State private var swipeBackOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            ZStack {
                browseView()
                    .offset(x: offset(for: .browse, W: W))
                    .allowsHitTesting(currentTab == .browse && swipeBackOffset == 0)
                    .zIndex(currentTab == .browse ? 1 : 0)
                gazetteView()
                    .offset(x: offset(for: .gongbao, W: W))
                    .allowsHitTesting(currentTab == .gongbao && swipeBackOffset == 0)
                    .zIndex(currentTab == .gongbao ? 1 : 0)
                chatView()
                    .offset(x: offset(for: .chat, W: W))
                    .allowsHitTesting(currentTab == .chat && swipeBackOffset == 0)
                    .zIndex(currentTab == .chat ? 1 : 0)
                favoritesView()
                    .offset(x: offset(for: .favorites, W: W))
                    .allowsHitTesting(currentTab == .favorites && swipeBackOffset == 0)
                    .zIndex(currentTab == .favorites ? 1 : 0)
            }
            .overlay(alignment: .leading) {
                if canSwipeBack {
                    EdgePanGestureView(
                        onChanged: { tx in swipeBackOffset = tx },
                        onEnded: { tx, vx in
                            let threshold = W * 0.4
                            if tx > threshold || vx > 800 {
                                withAnimation(.easeOut(duration: 0.25)) { swipeBackOffset = W }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    onGoBack()
                                    swipeBackOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    swipeBackOffset = 0
                                }
                            }
                        }
                    )
                    .frame(width: 20)
                }
            }
            .onChange(of: canSwipeBack) { _, nowActive in
                if nowActive {
                    // Animate source tab sliding in from parallax start position
                    // (it starts at W, needs to land at -W*0.3)
                    withAnimation(.easeOut(duration: 0.25)) { _ = swipeBackOffset }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func offset(for t: ContentView.Tab, W: CGFloat) -> CGFloat {
        if t == currentTab { return canSwipeBack ? swipeBackOffset : 0 }
        if canSwipeBack, t == fromTab { return -W * 0.3 + swipeBackOffset * 0.3 }
        return W
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
                    if pm.hasPRO {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("已订阅", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("本订阅周期剩余 \(pm.proRemaining) 次 · 续订后自动重置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        switch pm.access {
                        case .free(let remaining):
                            HStack {
                                Label("免费剩余 \(remaining) 次", systemImage: "gift")
                                Spacer()
                                Button("订阅解锁") { showPaywall = true }
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.shared.searchHighlight)
                            }
                        case .noAccess, .pro:
                            HStack {
                                Label("免费次数已用完", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("订阅解锁") { showPaywall = true }
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.shared.searchHighlight)
                            }
                        }
                    }
                } header: {
                    Text("法律顾问")
                } footer: {
                    if pm.hasPRO {
                        Text("订阅版：每订阅周期 150 次法律顾问，续订后自动重置，无限访问高院公报全文。")
                    } else {
                        switch pm.access {
                        case .free(let remaining):
                            Text("每位新用户赠送 5 次免费体验，剩余 \(remaining) 次。订阅后每月 150 次。")
                        case .noAccess, .pro:
                            Text("免费体验已用完，订阅后每月 150 次法律顾问，同时解锁高院公报全文。")
                        }
                    }
                }

                Section {
                    Toggle("显示右侧条文索引", isOn: $userStore.showSideIndex)
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
                    Toggle("搜索时忽略条号匹配", isOn: $userStore.searchExcludeArtNum)
                    Picker("搜索结果上限", selection: $userStore.searchResultLimit) {
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                        Text("200 条").tag(200)
                    }
                } header: {
                    Text("搜索")
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
