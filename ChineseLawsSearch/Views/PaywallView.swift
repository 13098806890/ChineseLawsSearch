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
                    // Header
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

                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow("案情分析", "多专家并发分析，拆分复杂纠纷")
                        featureRow("法条检索", "精准引用相关条文，一键跳转原文")
                        featureRow("法律咨询", "知识问答，流式实时输出")
                        featureRow("对话历史", "自动保存，iCloud 多设备同步")
                    }
                    .padding(.horizontal)

                    Divider()

                    // Products
                    if pm.products.isEmpty {
                        ProgressView("加载中…")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(pm.products, id: \.id) { product in
                                productRow(product)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let msg = errorMsg {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Restore
                    Button {
                        Task {
                            isRestoring = true
                            await pm.restorePurchases()
                            isRestoring = false
                            if pm.isPurchased { dismiss() }
                        }
                    } label: {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("恢复购买")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 8)
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

    @ViewBuilder
    private func productRow(_ product: Product) -> some View {
        let isLifetime = product.id == AgentProductID.lifetime
        let isBuying   = purchasing == product.id

        Button {
            Task {
                purchasing = product.id
                errorMsg   = nil
                do {
                    let bought = try await pm.purchase(product)
                    if bought { dismiss() }
                } catch {
                    errorMsg = "购买失败：\(error.localizedDescription)"
                }
                purchasing = nil
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(productLabel(product))
                            .font(.headline)
                        if isLifetime {
                            Text("推荐")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(AppColors.shared.searchHighlight.opacity(0.15))
                                .foregroundStyle(AppColors.shared.searchHighlight)
                                .clipShape(Capsule())
                        }
                    }
                    Text(productSub(product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBuying {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundStyle(AppColors.shared.searchHighlight)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLifetime ? AppColors.shared.searchHighlight.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isLifetime ? AppColors.shared.searchHighlight.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil || isRestoring)
    }

    private func productLabel(_ p: Product) -> String {
        switch p.id {
        case AgentProductID.lifetime: return "买断永久"
        case AgentProductID.monthly:  return "月度订阅"
        case AgentProductID.yearly:   return "年度订阅"
        default: return p.displayName
        }
    }

    private func productSub(_ p: Product) -> String {
        switch p.id {
        case AgentProductID.lifetime: return "一次付费，永久使用，含所有未来更新"
        case AgentProductID.monthly:  return "按月续费，随时取消"
        case AgentProductID.yearly:   return "按年续费，相比月付省约 30%"
        default: return ""
        }
    }
}
