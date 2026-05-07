// LeaseContractExpert.swift — 租赁合同专家（含房屋租赁、融资租赁）

import Foundation

private let chLease: [Int]    = [35226]  // 第十四章 租赁合同
private let chFinLease: [Int] = [35259]  // 第十五章 融资租赁合同

let leaseContractExpert = SubExpert(
    name: "租赁合同专家",
    domain: "房屋租赁、租金、押金、提前解除租约、承租人权利、转租、房屋状态",
    requiredInfo: [
        RequiredInfo(field: "租赁物类型",
                     question: "租赁物是房屋还是其他物品（车辆/设备）？",
                     regexHint: "房屋|住宅|商铺|商场|车辆|设备|厂房"),
        RequiredInfo(field: "解除原因",
                     question: "是哪方要求解除/终止租赁？原因是什么（欠租/强拆/装修/出售）？",
                     regexHint: "解除|退租|驱逐|拆迁|欠租|不交租|强制|出售|转让|装修|维修"),
        RequiredInfo(field: "押金情况",
                     question: "是否有押金？押金金额？出租方是否退还？",
                     regexHint: "押金|保证金|退押|不退|扣押|租金"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chLease + chFinLease,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["租金", "押金", "提前解除", "转租", "租赁期限", "城镇房屋租赁",
                       "优先购买权", "买卖不破租赁"],
    answerTemplate: """
    你是租赁合同细分专家。基于以下法条，以第三方视角分析：
    1. 合同解除条件：法定解除情形（严重损坏/欠租/擅自转租）vs 约定解除
    2. 押金的性质与退还规则，出租方扣押金的合法限度
    3. 承租人的优先购买权（出租方出售时的告知义务）
    4. "买卖不破租赁"规则的适用范围
    5. 提前解除的违约责任计算
    引用民法典及城镇房屋租赁合同司法解释的具体条文。
    """
)
