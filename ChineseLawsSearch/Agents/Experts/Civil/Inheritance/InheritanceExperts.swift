// InheritanceExperts.swift — 继承编专家

import Foundation

// 继承编章节 IDs
private let chInhGeneral: [Int]  = [35685]  // 第一章 一般规定
private let chLegal: [Int]       = [35693]  // 第二章 法定继承
private let chTestament: [Int]   = [35701]  // 第三章 遗嘱继承和遗赠
private let chEstate: [Int]      = [35714]  // 第四章 遗产的处理

let intestateInheritanceExpert = SubExpert(
    name: "法定继承专家",
    domain: "法定继承顺序、继承份额、丧失继承权、代位继承、转继承",
    requiredInfo: [
        RequiredInfo(field: "继承人构成",
                     question: "死亡者的法定继承人有哪些（配偶/父母/子女/兄弟姐妹/祖父母）？",
                     regexHint: "配偶|妻子|丈夫|父母|子女|儿子|女儿|兄弟|姐妹|祖父母|外祖父母"),
        RequiredInfo(field: "遗产范围",
                     question: "遗产主要包括什么（房产/存款/股权/债务）？",
                     regexHint: "房产|房屋|存款|银行卡|股权|股票|债务|债权|保险|车辆"),
        RequiredInfo(field: "特殊情形",
                     question: "是否有继承人丧失继承权/放弃继承/先于被继承人死亡等情形？",
                     regexHint: "放弃|丧失|先死|代位|转继承|虐待|遗弃|伪造遗嘱|继承纠纷"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chInhGeneral + chLegal + chEstate,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["法定继承", "继承顺序", "第一顺序继承人", "代位继承", "丧失继承权",
                       "遗产清偿债务", "遗产分割协议", "继承编司法解释"],
    answerTemplate: """
    你是法定继承细分专家。基于以下法条，以第三方视角分析：
    1. 继承顺序：第一顺序（配偶/父母/子女）优先，第二顺序（兄弟姐妹/祖父母）在无第一顺序时继承
    2. 各继承人的法定份额（同顺序一般均等，可协议调整）
    3. 代位继承：继承人先于被继承人死亡时，由其直系晚辈血亲代位
    4. 丧失继承权的情形（故意杀害被继承人/遗弃/伪造遗嘱等）
    5. 遗产债务的清偿：以遗产实际价值为限清偿，超出部分不负责任
    引用继承编司法解释（一）的具体条文，给出遗产分割协议建议。
    """
)

let testamentaryInheritanceExpert = SubExpert(
    name: "遗嘱继承专家",
    domain: "遗嘱形式、遗嘱效力、遗嘱撤销变更、遗赠、必留份、遗嘱信托",
    requiredInfo: [
        RequiredInfo(field: "遗嘱形式",
                     question: "遗嘱是什么形式（自书/代书/打印/录音录像/公证/口头）？",
                     regexHint: "自书|代书|打印|录音|录像|公证|口头|遗嘱"),
        RequiredInfo(field: "遗嘱内容争议",
                     question: "遗嘱内容是否完整清晰？是否存在多份遗嘱？",
                     regexHint: "多份|前后|矛盾|不清楚|缺少|见证人|签字|日期"),
        RequiredInfo(field: "特留份",
                     question: "是否有缺乏劳动能力又无生活来源的继承人（应受特留份保护）？",
                     regexHint: "残疾|无劳动能力|无收入|老人|未成年|特留份|必留份"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chInhGeneral + chTestament + chEstate,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["遗嘱效力", "公证遗嘱", "自书遗嘱形式要件", "遗嘱撤销",
                       "必留份", "遗赠扶养协议", "打印遗嘱要件"],
    answerTemplate: """
    你是遗嘱继承细分专家。基于以下法条，以第三方视角分析：
    1. 遗嘱形式要件审查：各类遗嘱的成立要件（自书须全文手写/签名/日期；打印须见证人2人+签名）
    2. 多份遗嘱并存时：以最后一份有效遗嘱为准（公证遗嘱不再优先）
    3. 遗嘱撤销：明示撤销vs以后遗嘱推定撤销
    4. 必留份制度：遗嘱不得剥夺缺乏劳动能力且无生活来源的法定继承人的遗产份额
    5. 遗赠扶养协议：优先于遗嘱和法定继承执行
    引用继承编司法解释（一）的具体条文，指出遗嘱无效的常见情形。
    """
)
