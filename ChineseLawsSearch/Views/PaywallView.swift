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
                        Text("法律顾问")
                            .font(.title.bold())
                        Text("AI 多专家协作分析，精准引用相关法条，\n帮您梳理法律关系、明确维权路径。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // MARK: Features
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow("案情分析", "多专家并发分析，拆分复杂纠纷")
                        featureRow("法条检索", "精准引用相关条文，一键跳转原文")
                        featureRow("法律咨询", "知识问答，流式实时输出")
                        featureRow("对话历史", "自动保存，iCloud 多设备同步")
                    }
                    .padding(.horizontal)

                    Divider()

                    // MARK: Plans
                    if pm.products.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView("加载中…").padding()
                            // Allow manual retry in case StoreKit failed silently
                            Button("重试") {
                                Task { await pm.loadProducts() }
                            }
                            .font(.footnote)
                            .foregroundStyle(AppColors.shared.searchHighlight)
                        }
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {

                            // ── 畅用版 ──────────────────────────────────
                            Text("畅用版")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            planCard(
                                id: AgentProductID.proYearly,
                                badge: "推荐",
                                icon: "key.fill",
                                title: "畅用版 · 年度订阅",
                                bullets: [
                                    "内置 Key，无需自备，开箱即用",
                                    "每周 \(PurchaseManager.proWeeklyTotal) 次额度，每周一自动重置",
                                    "月均折合更优惠，按年续费"
                                ]
                            )
                            planCard(
                                id: AgentProductID.proMonthly,
                                badge: nil,
                                icon: "key.fill",
                                title: "畅用版 · 月度订阅",
                                bullets: [
                                    "内置 Key，无需自备，开箱即用",
                                    "每周 \(PurchaseManager.proWeeklyTotal) 次额度，每周一自动重置",
                                    "按月续费，随时取消"
                                ]
                            )

                            // ── 基础版 ──────────────────────────────────
                            Text("基础版")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)

                            planCard(
                                id: AgentProductID.basic,
                                badge: nil,
                                icon: "wrench.and.screwdriver",
                                title: "基础版 · 买断",
                                bullets: [
                                    "解锁 Agent 功能，一次付费永久可用",
                                    "需自备 DeepSeek API Key（注册即有免费额度）",
                                    "自备 Key 无次数限制"
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
                            if pm.hasBASIC || pm.hasPRO { dismiss() }
                        }
                    } label: {
                        if isRestoring { ProgressView() }
                        else { Text("恢复购买").font(.footnote).foregroundStyle(.secondary) }
                    }
                    .padding(.bottom, 4)

                    // App Store 自动续费披露（Guideline 3.1.2 要求）
                    Text("畅用版为自动续费订阅。订阅将在当前周期结束前 24 小时自动续费，费用从 Apple ID 账户中扣除。可随时在 App Store「订阅」中取消，取消后当前周期结束前仍可使用。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("解锁完整功能")
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
        let product    = pm.products.first { $0.id == id }
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
                // Title row
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
                // Bullets
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
