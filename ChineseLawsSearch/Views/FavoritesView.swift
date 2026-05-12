//
//  FavoritesView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct FavoritesView: View {
    let navigate: (Int, Int?) -> Void
    @EnvironmentObject private var userStore: UserStore

    var body: some View {
        NavigationStack {
            Group {
                if userStore.favorites.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(userStore.favorites) { fav in
                            Button {
                                navigate(fav.lawId, fav.articleNum)
                            } label: {
                                FavoriteRow(fav: fav)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    userStore.removeFavorite(lawId: fav.lawId, articleNum: fav.articleNum)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("暂无收藏")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("长按任意条文，选择「收藏」即可保存到这里。")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FavoriteRow

private struct FavoriteRow: View {
    let fav: FavoriteArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fav.lawTitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.shared.searchHighlight)
                    .lineLimit(1)
                Text(fav.articleNumber)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(fav.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}
