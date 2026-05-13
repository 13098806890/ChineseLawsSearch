//
//  WelcomeView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct WelcomeView: View {
    private let appBlue = AppColors.shared.searchHighlight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // 标题区
                VStack(alignment: .leading, spacing: 6) {
                    Text("律疏")
                        .font(.largeTitle.bold())
                    Text("中国法律法规检索与咨询")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Divider()

                Group {
                    featureSection(
                        icon: "doc.text",
                        iconColor: appBlue,
                        title: "法律浏览",
                        items: [
                            ("目录浏览",
                             "按宪法、民商法、刑法、行政法等部门法分类，逐层展开查阅法律、行政法规与司法解释。"),
                            ("全文搜索",
                             "在搜索栏输入关键词，可同时搜索法律名称与条文内容，三个字以上即可精准匹配。搜索结果中命中词语会高亮显示。"),
                            ("收藏条文",
                             "长按任意条文，选择「收藏」保存到底部「收藏」栏，随时快速回查，数据 iCloud 多设备同步。"),
                            ("跳转关联条文",
                             "法律顾问引用的条文可直接点击跳转原文，右上角返回按钮可回到对话。"),
                        ]
                    )

                    featureSection(
                        icon: "message",
                        iconColor: appBlue,
                        title: "法律顾问",
                        items: [
                            ("直接描述您的问题",
                             "用日常语言描述纠纷或问题即可，无需使用法律术语，系统会自动理解并检索相关法条。"),
                            ("多专家协作分析",
                             "针对具体纠纷，系统自动调用合同、侵权、劳动、刑事等细分领域专家协同研判，精准引用法条，给出综合分析意见。"),
                            ("追问与深入分析",
                             "回答后可继续追问；专家可能反问补充案情，案情越完整，分析越精准。"),
                            ("历史记录与导出",
                             "对话自动保存，点击右上角时钟图标查看历史。点击导出按钮可将对话导出为 Markdown 文本分享或存档。"),
                        ]
                    )

                    featureSection(
                        icon: "star",
                        iconColor: appBlue,
                        title: "收藏",
                        items: [
                            ("保存常用条文",
                             "在法律浏览中长按任意条文选择「收藏」，即可保存到收藏栏，方便日后快速查阅。"),
                            ("iCloud 同步",
                             "收藏数据通过 iCloud 在您的所有设备间自动同步。"),
                        ]
                    )

                    featureSection(
                        icon: "gearshape",
                        iconColor: appBlue,
                        title: "设置",
                        items: [
                            ("法律顾问套餐",
                             "「畅用版」订阅后无需任何配置即可使用，内置 API Key，每周 80 次额度，每周一自动重置。\n「基础版」买断后需在设置中填入您自己的 DeepSeek API Key，无次数限制。"),
                            ("自备 API Key",
                             "在设置中填入 DeepSeek API Key 后，无论何种套餐均优先使用您自己的 Key，畅用版用户可实现无限制使用。"),
                            ("分析模式",
                             "节省 / 标准 / 详细三档，控制追问轮次与检索深度，按需平衡质量与速度。"),
                            ("搜索偏好",
                             "可设置仅搜标题、结果数量上限、条文字号等。"),
                        ]
                    )
                }

                Divider()

                // 数据说明
                VStack(alignment: .leading, spacing: 6) {
                    Label("数据说明", systemImage: "info.circle")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    Text("收录现行有效的法律、行政法规、司法解释及宪法，数据来源于全国人大、国务院、最高人民法院等官方渠道。法律内容仅供参考，不构成正式法律意见，具体案件建议咨询执业律师。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func featureSection(icon: String, iconColor: Color,
                                title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.0) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(iconColor.opacity(0.18))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.subheadline.bold())
                            Text(item.1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.leading, 4)
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}
