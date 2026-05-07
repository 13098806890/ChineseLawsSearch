// TrafficAccidentExpert.swift — 机动车交通事故责任专家

import Foundation

private let chTraffic: [Int] = [35783]  // 第五章 机动车交通事故责任

let trafficAccidentExpert = SubExpert(
    name: "交通事故责任专家",
    domain: "机动车交通事故、保险理赔、交强险、商业险、逃逸、行人责任",
    requiredInfo: [
        RequiredInfo(field: "事故当事人类型",
                     question: "事故涉及哪些主体（机动车/非机动车/行人/货车/电动车）？",
                     regexHint: "机动车|非机动车|行人|货车|电动车|摩托车|自行车|三轮车"),
        RequiredInfo(field: "责任认定",
                     question: "交警是否出具了事故责任认定书？责任比例是多少？",
                     regexHint: "责任认定|全责|主责|同责|次责|无责|认定书|逃逸"),
        RequiredInfo(field: "保险情况",
                     question: "肇事车辆是否投保了交强险和商业险？保险公司是否参与理赔？",
                     regexHint: "交强险|商业险|保险|理赔|投保|未投保|脱保|无牌"),
        RequiredInfo(field: "损害后果",
                     question: "伤亡情况及医疗费用大概多少？是否构成伤残？",
                     regexHint: #"受伤|死亡|残疾|伤残|医疗费|\d+级|鉴定"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chTraffic,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["交强险", "商业三者险", "无证驾驶", "醉酒驾车", "逃逸",
                       "机动车所有人与驾驶人不一致", "道路交通事故损害赔偿"],
    answerTemplate: """
    你是交通事故责任细分专家。基于以下法条，以第三方视角分析：
    1. 责任主体认定：登记车主、实际驾驶人、借车人的责任分担
    2. 无证/醉驾/逃逸对保险责任的影响（交强险垫付后追偿）
    3. 赔偿顺序：交强险优先 → 商业险 → 侵权人自行赔偿
    4. 赔偿项目：医疗费/误工费/护理费/残疾赔偿金/死亡赔偿金/精神损害抚慰金
    5. 行人/非机动车的过错对赔偿比例的影响
    引用道路交通事故损害赔偿司法解释及机动车交通事故责任强制保险条例的具体规定。
    """
)
