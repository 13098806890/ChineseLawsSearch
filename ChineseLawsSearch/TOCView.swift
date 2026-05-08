//
//  TOCView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct TOCView: View {
    @Binding var selectedLaw: LawMeta?
    @Binding var target: LawTarget?

    @State private var menu: DatabaseManager.LawMenu? = nil
    @State private var expandedGroups:    Set<String> = []
    @State private var expandedSubgroups: Set<String> = []
    @State private var showSearch = false
    @State private var pendingTarget: LawTarget? = nil

    var body: some View {
        List {
            if let menu {
                ForEach(menu.groups, id: \.label) { group in
                    let totalCount = group.subgroups.reduce(0) { $0 + $1.laws.count }
                    let isExpanded = expandedGroups.contains(group.label)

                    Section {
                        if isExpanded {
                            ForEach(group.subgroups, id: \.label) { sub in
                                subgroupRows(groupLabel: group.label, sub: sub)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded { expandedGroups.remove(group.label) }
                                else          { expandedGroups.insert(group.label) }
                            }
                        } label: {
                            HStack {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(group.label)
                                    .font(.subheadline).bold()
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(totalCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("中国法律法规")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(isPresented: $showSearch) { law, articleNum in
                pendingTarget = LawTarget(law: law, scrollToArticle: articleNum)
            }
        }
        .onChange(of: showSearch) { _, isShowing in
            if !isShowing, let t = pendingTarget {
                selectedLaw = t.law
                target = t
                pendingTarget = nil
            }
        }
        .onChange(of: selectedLaw) { old, law in
            // 只在用户点目录行时同步 target（搜索已直接设置 target，不需要再覆盖）
            guard let law, target?.law.id != law.id else { return }
            target = LawTarget(law: law, scrollToArticle: nil)
        }
        .task {
            menu = DatabaseManager.shared.loadMenu()
        }
    }

    // MARK: - Subgroup rows

    @ViewBuilder
    func subgroupRows(groupLabel: String, sub: DatabaseManager.MenuSubgroup) -> some View {
        let subKey     = "\(groupLabel)/\(sub.label)"
        let isExpanded = expandedSubgroups.contains(subKey)
        let isAdminSub = sub.label.hasPrefix("行政法规/")
        let displayLabel = isAdminSub ? String(sub.label.dropFirst("行政法规/".count)) : sub.label

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { expandedSubgroups.remove(subKey) }
                else          { expandedSubgroups.insert(subKey) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isAdminSub
                      ? (isExpanded ? "tag.fill" : "tag")
                      : (isExpanded ? "folder.fill" : "folder"))
                    .font(.subheadline)
                    .foregroundStyle(isAdminSub ? AppColors.shared.tagIcon : AppColors.shared.folderIcon)
                Text(displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(sub.laws.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 32, bottom: 4, trailing: 16))

        if isExpanded {
            ForEach(sub.laws, id: \.id) { menuLaw in
                lawRow(menuLaw)
                    .listRowInsets(EdgeInsets(top: 4, leading: 52, bottom: 4, trailing: 16))
            }
        }
    }

    // MARK: - Law row
    // 点击时按 id 查 DB 取完整 LawMeta

    @ViewBuilder
    func lawRow(_ menuLaw: DatabaseManager.MenuLaw) -> some View {
        let isSelected = selectedLaw?.id == menuLaw.id
        Button {
            let law = DatabaseManager.shared.lawMeta(id: menuLaw.id)
            if let law {
                selectedLaw = law
                let newTarget = LawTarget(law: law, scrollToArticle: nil)
                if target == newTarget {
                    // 强制触发：先清空再赋值
                    target = nil
                    DispatchQueue.main.async { target = newTarget }
                } else {
                    target = newTarget
                }
            }
        } label: {
            Text(menuLaw.title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? AppColors.shared.folderIcon : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isSelected ? AppColors.shared.folderIcon.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
