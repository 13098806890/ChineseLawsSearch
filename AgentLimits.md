# AgentLimits.plist — Prompt 参数说明

`ChineseLawsSearch/AgentLimits.plist` 集中管理所有 LLM prompt 中的数值限制。修改后重新编译即生效，无需改代码。

`-1` 表示不限制。

---

## 字数限制

| Key | 默认值 | 说明 |
|-----|------:|------|
| `coordinatorAnswerSoftLimitChars` | -1 | Coordinator 回答的参考字数上限。设为正整数时，prompt 里会追加"复杂案情可超过 N 字"的软性提示；-1 则完全不提字数，让模型自行判断长度。 |
| `gazetteRulingGistMaxChars` | -1 | 从公报文书正文提取 `ruling_gist`（裁判要旨）时的截断字数。-1 = 完整提取，不截断。仅影响数据库构建阶段（`build_gongbao_db.py`），不影响 iOS 运行时。 |

---

## 数量限制

| Key | 默认值 | 说明 |
|-----|------:|------|
| `statuteArticlesPerLawMax` | 5 | **法条检索模式（statute）**：专家在 identify 阶段，每部法律最多列出的条文数。防止单部法律占满 context。 |
| `statuteArticlesTotalMax` | 10 | **法条检索模式（statute）**：所有法律条文的总数上限。超出时按相关性截取前 N 条。 |
| `routingMaxExperts` | 4 | **路由阶段**：`characterizeAndRoute` 最多选中的细分专家数。问题涉及多个法律关系时控制并发 agent 数量，避免 context 过长和 API 费用过高。 |
| `decompositionMaxSubQuestions` | 4 | **问题拆分（decompose）**：复杂问题最多拆分为几个子问题并行处理。每个子问题独立跑一次完整 pipeline，设太大会显著增加延迟和费用。 |
| `expertGazetteCandidatesTypical` | 3 | **专家路由提示**：prompt 中"通常选 1-N 个"的 N 值，引导模型在简单问题时少选专家。 |
| `expertGazetteCandidatesMax` | 4 | **专家路由提示**：prompt 中"最多 N 个"的硬上限提示，与 `routingMaxExperts` 保持一致。 |

---

## 修改建议

- **提高回答详细程度**：`coordinatorAnswerSoftLimitChars` 已设为 -1，如需给模型一个参考目标可改为 `1500`。
- **加快响应速度 / 降低费用**：减小 `routingMaxExperts`（改为 3）或 `decompositionMaxSubQuestions`（改为 2）。
- **让法条检索更全面**：增大 `statuteArticlesPerLawMax` 和 `statuteArticlesTotalMax`，但会增加 context 长度。
