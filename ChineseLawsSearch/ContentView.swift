//
//  ContentView.swift
//  ChineseLawsSearch
//
//  Created by Xie, Dongze on 2026/4/29.
//

import SwiftUI

// 描述一个导航目标：哪部法律、滚动到哪条（nil = 不滚动）
struct LawTarget: Equatable, Hashable {
    let law: LawMeta
    let scrollToArticle: Int?
}

struct ContentView: View {
    @State private var selectedLaw: LawMeta?
    @State private var target: LawTarget?

    var body: some View {
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

    func navigate(to lawId: Int, articleNum: Int?) {
        if let law = DatabaseManager.shared.lawMeta(id: lawId) {
            selectedLaw = law
            target = LawTarget(law: law, scrollToArticle: articleNum)
        }
    }
}

#Preview {
    ContentView()
}
