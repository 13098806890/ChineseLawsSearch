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

    enum Tab { case browse, chat }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主内容区
            Group {
                if tab == .browse {
                    browseView
                } else {
                    chatView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部 Tab Bar
            Divider()
            HStack(spacing: 0) {
                tabButton(title: "法律浏览", icon: "books.vertical", tab: .browse)
                tabButton(title: "法律咨询", icon: "bubble.left.and.text.bubble.right", tab: .chat)
            }
            .frame(height: 56)
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Browse (原有逻辑)

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
            LegalChatView()
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

#Preview {
    ContentView()
}
