//
//  WelcomeView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct WelcomeView: View {
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

                // 功能分区
                Group {
                    featureSection(
                        icon: "doc.text",
                        iconColor: .blue,
                        title: "法律浏览",
                        items: [
                            ("按领域目录浏览", "法律、行政法规、司法解释按部门法分类，逐层展开查阅。"),
                            ("全文搜索", "在搜索栏输入关键词，可同时搜索法律名称与条文内容。两个字以上即可搜索。"),
                            ("跳转关联条文", "法律顾问的引用条文可直接点击跳转，右上角返回按钮可回到对话。"),
                        ]
                    )

                    featureSection(
                        icon: "message",
                        iconColor: .green,
                        title: "法律顾问",
                        items: [
                            ("直接描述您的问题", "用日常语言描述纠纷或问题即可，无需使用法律术语。系统会自动将问题规范化并检索相关法条。"),
                            ("多专家协作分析", "系统自动识别问题类型：法条查询直接检索作答；具体纠纷案情调用多位细分专家（合同、侵权、劳动、刑事等）协同研判，给出综合分析。"),
                            ("追问与深入分析", "回答后可继续追问，系统可能反问补充案情，以便给出更精准的意见。"),
                            ("历史记录", "点击右上角时钟图标查看历史对话，可随时切换或继续之前的咨询。"),
                        ]
                    )

                    featureSection(
                        icon: "gearshape",
                        iconColor: .gray,
                        title: "设置",
                        items: [
                            ("选择 AI 模型", "支持 Groq（免费）、Gemini（免费额度）、DeepSeek（按量计费）。在设置中填入 API Key 即可使用。"),
                            ("分析模式", "节省 / 标准 / 详细三档，控制追问轮次与检索深度。"),
                            ("搜索偏好", "可设置仅搜标题、搜索结果数量上限等。"),
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
