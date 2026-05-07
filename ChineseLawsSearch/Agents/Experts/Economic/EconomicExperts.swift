//
//  EconomicExperts.swift
//  ChineseLawsSearch
//

import Foundation

let consumerExpert = SubExpert(
    name: "消费者权益专家",
    domain: "假冒伪劣、退款、三倍赔偿、平台责任、欺诈",
    requiredInfo: [
        RequiredInfo(field: "购买渠道", question: "在哪里购买的（线上平台/实体店/直播带货）？",
                     regexHint: "淘宝|京东|拼多多|抖音|快手|微商|实体店|超市|直播|网购"),
        RequiredInfo(field: "问题类型", question: "商品/服务问题是什么（假货/虚假宣传/拒绝退款/过期食品）？",
                     regexHint: "假货|假冒|伪劣|不合格|虚假宣传|拒绝退款|过期|变质|食品安全"),
        RequiredInfo(field: "金额损失", question: "购买金额是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千)"#),
    ],
    lawTitles: ["中华人民共和国消费者权益保护法", "中华人民共和国食品安全法",
                "中华人民共和国产品质量法", "中华人民共和国电子商务法"],
    chapterIdHints: [],
    ftsDomains: ["经济法", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["三倍赔偿", "退一赔三", "退一赔十", "平台责任", "欺诈消费者"],
    answerTemplate: "你是消费者权益保护细分专家。基于以下法条，分析：\n1. 消费者可以主张的具体权利（退货/退款/赔偿）\n2. 惩罚性赔偿倍数（三倍/十倍）及适用条件\n3. 平台连带责任的适用场景\n4. 投诉路径（12315/市场监管局/法院）\n明确给出赔偿金额计算和维权步骤。"
)

let productExpert = SubExpert(
    name: "产品质量专家",
    domain: "产品缺陷、侵权赔偿、召回、生产者销售者责任",
    requiredInfo: [
        RequiredInfo(field: "产品类型", question: "是什么产品（食品/药品/家电/车辆/儿童用品）？",
                     regexHint: "食品|药品|家电|车辆|汽车|儿童|玩具|工业品|医疗器械"),
        RequiredInfo(field: "损害后果", question: "产品缺陷造成了什么损害（人身伤害/财产损失）？",
                     regexHint: "受伤|烫伤|中毒|财产损失|损坏|死亡|伤残"),
    ],
    lawTitles: ["中华人民共和国产品质量法", "中华人民共和国消费者权益保护法"],
    chapterIdHints: [],
    ftsDomains: ["经济法"],
    ftsCategories: ["法律"],
    ftsKeywordsExtra: ["产品缺陷", "产品责任", "生产者责任", "缺陷产品召回"],
    answerTemplate: "你是产品质量法细分专家。基于以下法条，分析：\n1. 产品缺陷的认定标准\n2. 生产者与销售者的责任划分\n3. 受害方可以主张的赔偿项目\n4. 举证责任（产品缺陷的证明方式）\n明确说明追责路径。"
)

let ecommerceExpert = SubExpert(
    name: "电子商务专家",
    domain: "网络交易、平台责任、刷单、大数据杀熟",
    requiredInfo: [
        RequiredInfo(field: "纠纷类型", question: "电子商务纠纷类型（假货/大数据杀熟/平台封号）？",
                     regexHint: "假货|刷单|大数据杀熟|差别定价|封号|扣押保证金"),
        RequiredInfo(field: "平台名称", question: "涉及哪个电商平台？",
                     regexHint: "淘宝|京东|拼多多|抖音|快手|小红书|亚马逊"),
    ],
    lawTitles: ["中华人民共和国电子商务法", "中华人民共和国消费者权益保护法"],
    chapterIdHints: [],
    ftsDomains: ["经济法"],
    ftsCategories: ["法律"],
    ftsKeywordsExtra: ["电子商务平台", "平台责任", "搭售", "大数据杀熟", "用户评价"],
    answerTemplate: "你是电子商务法细分专家。基于以下法条，分析：\n1. 电商平台的法律责任（知道或应当知道侵权行为的连带责任）\n2. 大数据杀熟的法律认定\n3. 消费者维权路径（申请退款/投诉平台/仲裁/诉讼）\n4. 平台封号/扣押保证金的合法性审查\n给出具体的操作建议。"
)

let companyExpert = SubExpert(
    name: "公司商事专家",
    domain: "公司设立、股东权利、公司决议、对外担保、破产",
    requiredInfo: [
        RequiredInfo(field: "公司类型", question: "是有限责任公司还是股份公司？",
                     regexHint: "有限责任公司|股份公司|合伙企业|个人独资"),
        RequiredInfo(field: "纠纷类型", question: "纠纷类型（股东纠纷/公司决议效力/对外担保/破产清算）？",
                     regexHint: "股东纠纷|股权|分红|决议|担保|破产|清算|注册|设立"),
    ],
    lawTitles: ["中华人民共和国公司法"],
    chapterIdHints: [],
    ftsDomains: ["经济法", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["股东权利", "公司决议", "股权转让", "公司担保", "破产清算"],
    answerTemplate: "你是公司商事法细分专家。基于以下法条，分析：\n1. 股东权利的法律依据\n2. 公司决议的效力及瑕疵认定\n3. 公司对外担保的法律规范\n4. 股东/高管的赔偿责任\n引用公司法条文，给出操作建议。"
)

let allEconomicExperts: [SubExpert] = [
    consumerExpert, productExpert, ecommerceExpert, companyExpert,
]
