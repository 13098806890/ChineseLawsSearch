//
//  PaywallView.swift
//  ChineseLawsSearch
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var pm: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing: String? = nil
    @State private var errorMsg:   String? = nil
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // MARK: Header
                    VStack(spacing: 8) {
                        Image(systemName: "scale.3d")
                            .font(.system(size: 52))
                            .foregroundStyle(AppColors.shared.searchHighlight)
                        Text("解锁完整功能")
                            .font(.title.bold())
                        Text("订阅后可无限使用法律顾问与高院公报全文，\n享受 AI 多专家协作分析与精准法条引用。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // MARK: Features
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow("法律顾问", "多专家并发分析，精准引用相关法条")
                        featureRow("高院公报全文", "指导案例、裁判文书、司法文件完整阅读")
                        featureRow("公报案例引用", "回答中自动关联同类指导案例与裁判规则")
                        featureRow("对话历史", "自动保存，iCloud 多设备同步")
                    }
                    .padding(.horizontal)

                    Divider()

                    // MARK: Plans
                    if pm.products.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView("加载中…").padding()
                            Button("重试") {
                                Task { await pm.loadProducts() }
                            }
                            .font(.footnote)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            planCard(
                                id: AgentProductID.proYearly,
                                badge: "推荐 · 省 35%",
                                icon: "crown.fill",
                                title: "年度订阅",
                                bullets: [
                                    "¥298/年，折合 ¥24.8/月",
                                    "每月 150 次法律顾问，每月 1 日重置",
                                    "无限访问高院公报全文",
                                    "随时取消"
                                ]
                            )
                            planCard(
                                id: AgentProductID.proMonthly,
                                badge: nil,
                                icon: "calendar",
                                title: "月度订阅",
                                bullets: [
                                    "¥38/月，按月续费",
                                    "每月 150 次法律顾问，每月 1 日重置",
                                    "无限访问高院公报全文",
                                    "随时取消"
                                ]
                            )
                        }
                        .padding(.horizontal)
                    }

                    if let msg = errorMsg {
                        Text(msg)
                            .font(.footnote).foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // MARK: Restore
                    Button {
                        Task {
                            isRestoring = true
                            await pm.restorePurchases()
                            isRestoring = false
                            if pm.hasPRO { dismiss() }
                        }
                    } label: {
                        if isRestoring { ProgressView() }
                        else { Text("恢复购买").font(.footnote).foregroundStyle(.secondary) }
                    }
                    .padding(.bottom, 4)

                    Text("订阅将在当前周期结束前 24 小时自动续费，费用从 Apple ID 账户中扣除。可随时在 App Store「订阅」中取消，取消后当前周期结束前仍可使用。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("订阅律疏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Plan card

    @ViewBuilder
    private func planCard(
        id: String,
        badge: String?,
        icon: String,
        title: String,
        bullets: [String]
    ) -> some View {
        let product     = pm.products.first { $0.id == id }
        let isHighlight = badge != nil
        let isBuying    = purchasing == id

        Button {
            guard let p = product else { return }
            Task {
                purchasing = id
                errorMsg   = nil
                do {
                    let bought = try await pm.purchase(p)
                    if bought { dismiss() }
                } catch {
                    errorMsg = "购买失败：\(error.localizedDescription)"
                }
                purchasing = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.shared.searchHighlight)
                    Text(title).font(.headline)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppColors.shared.searchHighlight.opacity(0.15))
                            .foregroundStyle(AppColors.shared.searchHighlight)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if isBuying {
                        ProgressView().scaleEffect(0.85)
                    } else if let p = product {
                        Text(p.displayPrice)
                            .font(.headline)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(AppColors.shared.searchHighlight)
                                .frame(width: 12, alignment: .center)
                                .padding(.top, 2)
                            Text(b)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHighlight
                          ? AppColors.shared.searchHighlight.opacity(0.08)
                          : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHighlight
                                    ? AppColors.shared.searchHighlight.opacity(0.4)
                                    : Color.clear,
                                    lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil || isRestoring || product == nil)
    }

    // MARK: - Feature row

    @ViewBuilder
    private func featureRow(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.shared.searchHighlight)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
