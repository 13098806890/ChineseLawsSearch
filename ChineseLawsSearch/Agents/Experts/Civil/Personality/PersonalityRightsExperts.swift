// PersonalityRightsExpert.swift — 人格权专家（分章建立专家）

import Foundation

// 人格权编各章 IDs
private let chPersonalityGeneral: [Int] = [35537]  // 第一章 一般规定
private let chLifeHealth: [Int]         = [35551]  // 第二章 生命权、身体权和健康权
private let chName: [Int]               = [35562]  // 第三章 姓名权和名称权
private let chPortrait: [Int]           = [35569]  // 第四章 肖像权
private let chReputation: [Int]         = [35576]  // 第五章 名誉权和荣誉权
private let chPrivacy: [Int]            = [35585]  // 第六章 隐私权和个人信息保护

let reputationPrivacyExpert = SubExpert(
    name: "名誉隐私权专家",
    domain: "名誉权、荣誉权、隐私权、个人信息保护、网络侵权、肖像权、姓名权",
    requiredInfo: [
        RequiredInfo(field: "权利类型",
                     question: "受侵害的是哪种人格权（名誉/隐私/肖像/姓名/个人信息）？",
                     regexHint: "名誉|荣誉|诽谤|侮辱|隐私|个人信息|肖像|照片|姓名|冒用"),
        RequiredInfo(field: "侵权行为",
                     question: "对方具体做了什么（网络发帖/散布谣言/泄露信息/未授权使用照片）？",
                     regexHint: "发帖|发布|散布|传播|泄露|公开|使用|冒用|盗用|截图"),
        RequiredInfo(field: "侵权平台",
                     question: "侵权行为发生在哪个平台（微博/微信/抖音/论坛/线下）？平台是否已处理？",
                     regexHint: "微博|微信|抖音|快手|小红书|B站|论坛|贴吧|平台|通知"),
    ],
    lawTitles: [
        "中华人民共和国民法典",
        "中华人民共和国个人信息保护法",
        "最高人民法院关于审理使用人脸识别技术处理个人信息相关民事案件适用法律若干问题的规定",
    ],
    chapterIdHints: chPersonalityGeneral + chLifeHealth + chName + chPortrait + chReputation + chPrivacy + [14044, 4905],
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["名誉权", "隐私权", "肖像权", "个人信息", "通知删除", "网络侵权",
                       "精神损害赔偿", "平台责任", "删除权", "个人信息保护法",
                       "人脸识别", "知情同意原则", "信息删除权", "名誉侵权构成要件", "侮辱诽谤区别"],
    answerTemplate: """
    你是人格权细分专家。基于以下法条，以第三方视角分析：
    1. 名誉权侵权要件：降低社会评价的陈述/行为+故意/过失+确有对象+造成损害，侮辱（直接贬损）vs诽谤（捏造事实）
    2. 隐私权保护范围：私密空间/信息/活动，合理期待隐私权的判断标准
    3. 个人信息保护（援引个人信息保护法）：处理须合法依据（同意/合同/法定职责等），侵权须证明损害
    4. 人脸识别专项（援引4905号解释）：非必要收集人脸信息违法；公共场所不得将人脸识别作为唯一身份验证手段
    5. 网络平台通知-删除规则：向平台发出侵权通知→平台必须及时处理，否则承担连带责任
    6. 救济手段：责令删除/赔礼道歉/精神损害赔偿；公证固定网络侵权证据的方法
    """
)

let lifeHealthRightsExpert = SubExpert(
    name: "生命健康权专家",
    domain: "生命权、身体权、健康权侵害、身体伤害赔偿、性骚扰、强制医疗",
    requiredInfo: [
        RequiredInfo(field: "侵害方式",
                     question: "身体权/健康权如何受到侵害（殴打/性骚扰/强制检查/过度医疗）？",
                     regexHint: "殴打|打伤|伤害|性骚扰|猥亵|强制|强迫|体检|医疗|侵害身体"),
        RequiredInfo(field: "损害程度",
                     question: "造成了什么程度的损害（轻伤/重伤/残疾/精神创伤）？",
                     regexHint: "轻伤|重伤|骨折|残疾|伤残|后遗症|精神|心理|住院"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chPersonalityGeneral + chLifeHealth,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["身体权", "健康权", "人身损害赔偿", "性骚扰", "禁止性规定",
                       "医疗权利", "人格尊严"],
    answerTemplate: """
    你是生命健康权细分专家。基于以下法条，以第三方视角分析：
    1. 生命权/身体权/健康权各自的保护范围和侵害认定
    2. 性骚扰的法律定义和受害者维权路径
    3. 侵害身体权的赔偿范围（医疗费/误工费/残疾赔偿/死亡赔偿/精神损害抚慰金）
    4. 紧急救助豁免：自愿紧急救助他人的免责规定
    引用人身损害赔偿司法解释的赔偿项目计算标准。
    """
)
