//
//  CivilExperts.swift
//  ChineseLawsSearch
//

import Foundation

// 民法典合同编 chapter hints
private let civilContractGeneral = [34971, 34978, 35012, 35020, 35047, 35056, 35071, 35092]
private let civilSale  = [35111]
private let civilLease = [35226]
private let civilLoan  = [35186]

let contractExpert = SubExpert(
    name: "合同法专家",
    domain: "合同纠纷、违约责任、合同解除、合同效力",
    requiredInfo: [
        RequiredInfo(field: "合同类型", question: "合同是哪种类型（买卖/租赁/服务/借款/建设工程/其他）？",
                     regexHint: "买卖|租赁|服务|借款|贷款|雇佣|劳务|承揽|运输|建设工程"),
        RequiredInfo(field: "合同金额", question: "合同标的金额大概是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千|亿)"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: civilContractGeneral + civilSale + civilLease + civilLoan,
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["违约责任", "合同解除", "继续履行", "损害赔偿"],
    answerTemplate: "你是合同法细分专家。基于以下法条，从法律角度分析各方的权利义务：\n1. 合同效力认定\n2. 违约责任（继续履行/损害赔偿/定金罚则），由你基于事实判断哪方违约\n3. 救济路径\n引用具体条文编号，使用第三方视角（\"当事人\"而非\"您\"）。"
)

let propertyExpert = SubExpert(
    name: "物权专家",
    domain: "不动产所有权、用益物权、担保物权、物权登记",
    requiredInfo: [
        RequiredInfo(field: "物权类型", question: "涉及的是哪种物权（所有权/使用权/抵押/宅基地）？",
                     regexHint: "所有权|使用权|抵押|质押|留置|地役权|宅基地|建设用地|居住权"),
        RequiredInfo(field: "标的物",   question: "争议的财产是什么（房产/土地/车辆/动产）？",
                     regexHint: "房产|房屋|土地|宅基地|车辆|动产|股权"),
        RequiredInfo(field: "是否登记", question: "该财产是否已办理权属登记/过户？",
                     regexHint: "登记|过户|产权证|不动产证|已登记|未登记"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["物权登记", "善意取得", "不动产", "抵押权实现"],
    answerTemplate: "你是物权法细分专家。基于以下法条，分析：\n1. 当事人的物权归属及法律依据\n2. 物权是否受到侵害及侵害方式（由你判断）\n3. 物权人可以行使哪些请求权（返还/排除妨害/损害赔偿）\n使用第三方视角，引用具体条文，指明登记要求。"
)

let tortExpert = SubExpert(
    name: "侵权责任专家",
    domain: "侵权损害赔偿、过错责任、无过错责任、共同侵权",
    requiredInfo: [
        RequiredInfo(field: "侵权类型", question: "属于哪种侵权情形（人身伤害/财产损失/名誉/产品责任/交通事故）？",
                     regexHint: "人身伤害|受伤|死亡|财产损失|名誉|隐私|产品|交通事故|医疗|动物咬伤"),
        RequiredInfo(field: "损害后果", question: "造成了什么具体损害（伤亡情况/财产损失金额/精神损害）？",
                     regexHint: #"受伤|死亡|残疾|财产损失|\d+元|精神损害"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["侵权责任", "损害赔偿", "精神损害", "无过错责任"],
    answerTemplate: "你是侵权责任法细分专家。基于以下法条，从法律角度分析：\n1. 适用归责原则（过错/无过错/公平责任），并判断各方过错\n2. 侵权构成要件是否满足\n3. 赔偿范围（医疗费/误工费/残疾赔偿金/死亡赔偿金/精神损害赔偿）\n4. 诉讼时效\n使用第三方视角，引用具体条文，给出赔偿项目清单。"
)

let marriageExpert = SubExpert(
    name: "婚姻家庭专家",
    domain: "离婚、抚养权、财产分割、婚姻效力、家庭暴力",
    requiredInfo: [
        RequiredInfo(field: "婚姻状况", question: "当前婚姻状态（已婚/离婚中/未婚同居/再婚）？",
                     regexHint: "已婚|离婚|结婚|同居|未婚|再婚|分居"),
        RequiredInfo(field: "纠纷类型", question: "主要纠纷是什么（离婚/子女抚养权/财产分割/家庭暴力）？",
                     regexHint: "离婚|抚养|监护|财产分割|家庭暴力|出轨|婚前财产|共同财产|彩礼"),
        RequiredInfo(field: "子女情况", question: "有无未成年子女？子女年龄？",
                     regexHint: #"\d+岁|孩子|子女|小孩|儿子|女儿|未成年|抚养"#),
        RequiredInfo(field: "财产情况", question: "主要财产有哪些（房产/存款/股权）？",
                     regexHint: #"房产|房屋|存款|股权|婚前|婚后|共同财产|\d+万"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["离婚协议", "夫妻共同财产", "子女抚养费", "彩礼返还", "家庭暴力"],
    answerTemplate: "你是婚姻家庭法细分专家。基于以下法条，分析：\n1. 离婚条件是否具备（协议离婚/诉讼离婚）\n2. 子女抚养权归属原则\n3. 夫妻共同财产分割原则（有过错方少分由你判断/婚前财产不分）\n4. 家庭暴力的法律后果\n使用第三方视角，明确给出各方权利义务。"
)

let inheritanceExpert = SubExpert(
    name: "继承专家",
    domain: "法定继承、遗嘱继承、遗产分配、继承放弃",
    requiredInfo: [
        RequiredInfo(field: "遗嘱情况",   question: "死者是否留有遗嘱？遗嘱形式（书面/公证/口头）？",
                     regexHint: "遗嘱|公证|立遗嘱|无遗嘱|口头遗嘱|书面遗嘱"),
        RequiredInfo(field: "继承人情况", question: "继承人有哪些（配偶/子女/父母/兄弟姐妹）？",
                     regexHint: "配偶|子女|父母|兄弟|姐妹|孙子|外孙|继承人"),
        RequiredInfo(field: "遗产情况",   question: "主要遗产是什么（房产/存款/债务/股权）？",
                     regexHint: "房产|存款|债务|股权|遗产|财产"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["法定继承", "遗嘱继承", "继承顺序", "遗产债务", "遗嘱效力"],
    answerTemplate: "你是继承法细分专家。基于以下法条，分析：\n1. 遗嘱是否有效（形式要件/内容要件）\n2. 法定继承的顺序和份额\n3. 必留份（特留份）制度的适用\n4. 继承债务的处理\n明确列出继承顺序和份额计算方式。"
)

let personalityExpert = SubExpert(
    name: "人格权专家",
    domain: "名誉权、隐私权、肖像权、姓名权、网络侵权",
    requiredInfo: [
        RequiredInfo(field: "人格权类型", question: "侵害的是哪种人格权（名誉/隐私/肖像/姓名）？",
                     regexHint: "名誉|隐私|肖像|姓名|荣誉|诽谤|侮辱|泄露"),
        RequiredInfo(field: "侵权行为",   question: "侵权方具体做了什么（网络发布/散布谣言/未授权使用照片）？",
                     regexHint: "发布|散布|传播|谣言|未经授权|使用照片|泄露隐私|侮辱|诽谤"),
        RequiredInfo(field: "损害后果",   question: "造成了什么后果（名誉受损/精神痛苦/经济损失）？",
                     regexHint: #"名誉受损|精神|抑郁|失业|经济损失|\d+元"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["名誉权", "隐私权", "肖像权", "网络侵权", "删除侵权内容"],
    answerTemplate: "你是人格权法细分专家。基于以下法条，分析：\n1. 哪种人格权受到侵害及法律依据\n2. 受害方可以主张的救济（删除/更正/赔礼道歉/损害赔偿）\n3. 平台责任（通知-删除规则）\n4. 如何证明损害及举证责任\n明确说明维权步骤。"
)

let allCivilExperts: [SubExpert] = [
    contractExpert, propertyExpert, tortExpert,
    marriageExpert, inheritanceExpert, personalityExpert,
]
