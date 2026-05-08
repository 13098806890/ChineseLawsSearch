//
//  Color+Adaptive.swift
//  ChineseLawsSearch
//
//  跨平台自适应颜色，取代 Color(.systemBackground) 等 UIKit 系义色。
//  在 iOS 上行为与原来一致；在 Mac Catalyst 上不会出现莫名灰色背景。
//

import SwiftUI

extension Color {
    /// 页面/容器背景：iOS 白色，Mac 透明（由窗口自身处理）
    static let appBackground       = Color.clear

    /// 次级容器背景（卡片、行、搜索框容器）
    static let appSecondaryBackground = Color.secondary.opacity(0.08)

    /// 输入框、气泡、浅色填充（≈ systemGray6）
    static let appTertiaryBackground  = Color.secondary.opacity(0.10)

    /// 略深填充（≈ systemGray5）
    static let appQuaternaryBackground = Color.secondary.opacity(0.15)

    /// 分割线 / 描边（≈ systemGray4）
    static let appSeparator        = Color.secondary.opacity(0.22)

    /// 禁用状态 / 占位图标（≈ systemGray3）
    static let appDisabled         = Color.secondary.opacity(0.38)

    /// 次要文字 / 图标（≈ systemGray）
    static let appSecondaryLabel: Color = .secondary
}
