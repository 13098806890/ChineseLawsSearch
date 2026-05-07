// SaleContractExpert.swift — 买卖合同专家（含商品房买卖）

import Foundation

private let chSale: [Int] = [35111]  // 第九章 买卖合同

let saleContractExpert = SubExpert(
    name: "买卖合同专家",
    domain: "货物买卖、商品房买卖、二手房、标的物交付、所有权转移、检验期、质量瑕疵",
    requiredInfo: [
        RequiredInfo(field: "标的物类型",
                     question: "买卖标的物是什么（房屋/车辆/货物/二手商品/其他）？",
                     regexHint: "房屋|房产|商品房|二手房|车辆|汽车|货物|商品|物品"),
        RequiredInfo(field: "交付状态",
                     question: "标的物是否已交付？交付时是否存在质量问题？",
                     regexHint: "交付|已交|未交|质量|瑕疵|损坏|不符|验收|拒收"),
        RequiredInfo(field: "价款支付",
                     question: "买方是否已支付价款？尾款情况？",
                     regexHint: "付款|支付|价款|定金|首付|尾款|未付|拖欠"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chSale,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["所有权转移", "标的物瑕疵", "检验期", "拒绝受领", "买卖合同解除",
                       "商品房买卖", "预售合同"],
    answerTemplate: """
    你是买卖合同细分专家。基于以下法条，以第三方视角分析：
    1. 所有权转移时间点（交付/登记）及风险负担转移规则
    2. 标的物质量瑕疵的认定与处理（修理/更换/减价/解除合同）
    3. 检验期与异议期的计算，逾期未检验的后果
    4. 卖方的交付义务与买方的付款义务，违约形态认定
    5. 若为商品房买卖：预售合同效力、逾期交房、面积误差处理
    引用具体条文和司法解释，给出争议解决路径。
    """
)
