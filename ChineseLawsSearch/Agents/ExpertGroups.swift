//
//  ExpertGroups.swift
//  ChineseLawsSearch
//

import Foundation

let allExpertGroups: [String: ExpertGroup] = [
    "民法专家组": ExpertGroup(
        name: "民法专家组",
        description: "处理民事法律问题：合同、物权、侵权、婚姻家庭、继承、人格权",
        subExperts: allCivilExperts,
        routingKeywords: ["合同","违约","租赁","买卖","借款","物权","所有权","抵押",
                          "侵权","赔偿","离婚","抚养","继承","遗产","遗嘱",
                          "名誉","隐私","肖像","人格权","民法典"]
    ),
    "刑法专家组": ExpertGroup(
        name: "刑法专家组",
        description: "处理刑事犯罪问题：财产犯罪、人身伤害、经济犯罪、职务犯罪",
        subExperts: allCriminalExperts,
        routingKeywords: ["犯罪","刑事","坐牢","判刑","立案","报案","刑法",
                          "盗窃","诈骗","抢劫","故意伤害","故意杀人","贪污","受贿",
                          "交通肇事","肇事逃逸","醉驾","危险驾驶","构成要件","量刑","罪名"]
    ),
    "劳动法专家组": ExpertGroup(
        name: "劳动法专家组",
        description: "处理劳动关系问题：劳动合同、工资、工伤、劳动争议",
        subExperts: allLaborExperts,
        routingKeywords: ["劳动","工资","加班费","辞退","解雇","工伤","职业病",
                          "劳动合同","经济补偿","仲裁","试用期","社保","五险一金","拖欠工资"]
    ),
    "行政法专家组": ExpertGroup(
        name: "行政法专家组",
        description: "处理行政机关与公民的法律关系：行政处罚、许可、复议",
        subExperts: [adminProcedureExpert],
        routingKeywords: ["行政","政府","处罚","吊销","罚款","许可证","审批",
                          "拆迁","征收","行政复议","行政诉讼","工商"]
    ),
    "经济法专家组": ExpertGroup(
        name: "经济法专家组",
        description: "处理市场监管、消费者权益、公司商事法律问题",
        subExperts: allEconomicExperts,
        routingKeywords: ["消费者","购物","假货","退款","维权","质量","产品缺陷",
                          "网购","电商","平台","公司","股东","破产","食品安全"]
    ),
    "诉讼专家组": ExpertGroup(
        name: "诉讼专家组",
        description: "处理诉讼程序、管辖、证据、仲裁等程序性问题",
        subExperts: allProcedureExperts,
        routingKeywords: ["诉讼","起诉","法院","仲裁","管辖","证据","上诉",
                          "执行","保全","查封","冻结","程序","时效","去哪告"]
    ),
]
