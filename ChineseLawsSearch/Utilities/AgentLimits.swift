//
//  AgentLimits.swift
//  ChineseLawsSearch
//
//  Reads AgentLimits.plist. -1 means unlimited.
//

import Foundation

enum AgentLimits {
    private static let values: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "AgentLimits", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else { return [:] }
        return dict
    }()

    private static func int(_ key: String, default d: Int) -> Int {
        (values[key] as? Int) ?? d
    }

    // Word count limits (-1 = unlimited)
    static let coordinatorAnswerSoftLimit   = int("coordinatorAnswerSoftLimitChars",   default: 800)
    static let gazetteRulingGistMax         = int("gazetteRulingGistMaxChars",          default: -1)

    // Count limits
    static let statuteArticlesPerLawMax     = int("statuteArticlesPerLawMax",           default: 5)
    static let statuteArticlesTotalMax      = int("statuteArticlesTotalMax",            default: 10)
    static let routingMaxExperts            = int("routingMaxExperts",                  default: 4)
    static let decompositionMaxSubQuestions = int("decompositionMaxSubQuestions",       default: 4)
    static let expertGazetteCandidatesMax   = int("expertGazetteCandidatesMax",         default: 4)
    static let expertGazetteCandidatesTypical = int("expertGazetteCandidatesTypical",   default: 3)

    // Helpers for prompt interpolation
    static var coordinatorAnswerSoftLimitText: String {
        coordinatorAnswerSoftLimit == -1 ? "" : "；复杂案情可超过\(coordinatorAnswerSoftLimit)字"
    }
}
