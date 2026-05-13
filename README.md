# 律疏 · 中国法律助手

中国法律法规检索与智能咨询 iOS 应用，数据来源于 [laws-data](https://github.com/13098806890/laws-data) 开放数据集。

**当前版本：1.03** — [Release Notes](CHANGELOG.md)

---

## 功能

### 法律浏览
- 按法律部门（民法、刑法、行政法等）分类浏览约 1,945 部现行有效法规
- 编 / 章 / 节 / 条 层级导航，支持目录跳转与条文锚点滚动
- 条文内容全文展示，支持字号调节（小 / 中 / 大 / 超大）
- 条文收藏（书签）与 iCloud 多设备同步
- 法条下方显示关联公报案例链接，点击跳转对应文书

### 全文搜索
- FTS5 trigram 索引，支持任意中文短语搜索（≥3 字）
- FTS5 unicode61 索引，支持 1–2 字短词搜索
- 结果按法律部门过滤，关键词高亮显示
- 支持仅搜标题 / 含条文内容两种模式

### 人民法院公报
- 收录最高人民法院公报全量数据，共 2,289 篇
  - **指导案例**：986 篇，含裁判要点摘要和关键词
  - **司法文件**：860 篇
  - **裁判文书**：443 篇
- 关键词全文搜索（FTS5 trigram）
- 案例笔记：为文书添加个人标注，辅助 AI 咨询时的相关案例推荐
- 收藏案例，iCloud 多设备同步

### 法律顾问（AI）
- 意图识别自动路由三种模式：案情分析 / 法律咨询 / 法条与案例检索
- **多专家协作**：协调员 → 6 个专家组 → 17 个细分领域专家，追问补全关键信息（最多 1–5 轮，可在设置中配置）
- **关联公报案例**：回答结束后自动检索相关公报案例，以卡片形式展示，点击查看完整文书
- 对话历史持久化，支持跨 session 恢复
- 对话内容导出为文本或 PDF

---

## 数据库

应用内置两个 SQLite 数据库（Bundle 资源，只读）：

| 文件 | 大小 | 说明 |
|------|-----:|------|
| `law_content.db` | ~250MB | 主库：laws / nodes / nodes_fts / article_references / gongbao_* |
| `law_enhancements.db` | ~120KB | RAG 增强：term_aliases / topic_law_hints / keyword_synonyms |

主要表结构：

| 表 | 说明 |
|----|------|
| `laws` | 1,945 部法律元数据，含 `is_current`、`is_flk`、`aliases` 等字段 |
| `nodes` | ~78,000 条条文及编章节节点，含 `global_order`、`article_num` 等 |
| `nodes_fts` | FTS5 trigram 全文索引（外部内容表，≥3 字） |
| `nodes_fts_bigram` | FTS5 unicode61 索引（1–2 字短词） |
| `article_references` | 6,452 条法条间引用关系，解析率 98.8% |
| `gongbao_docs` | 公报文书 2,289 条（指导案例/司法文件/裁判文书） |
| `gongbao_sfjs` | 公报独有司法解释 487 条 |
| `gongbao_case_law_links` | 公报文书 → 法条关联 3,526 条，解析率 99.8% |
| `gongbao_docs_fts` | 公报 FTS5 trigram 全文索引 |

数据库由 [laws-data](https://github.com/13098806890/laws-data) 项目的 pipeline 生成，每次发版随应用 Bundle 更新。

---

## 技术架构

| 组件 | 说明 |
|------|------|
| `DatabaseManager.swift` | SQLite 封装，单例，串行队列保证线程安全 |
| `LegalExpertService.swift` | 专家协作系统：意图分类 → 角色分配 → 信息收集 → 并行检索 → 综合分析 → 公报案例检索 |
| `LegalChatViewModel` | 对话状态管理，追问轮次控制，ViewModel 驱动 UI |
| `ChatHistoryStore.swift` | 对话历史持久化（iCloud Documents / 本地 Documents fallback） |
| `PurchaseManager.swift` | StoreKit 2 内购管理，免费次数 + 每周 Pro 配额 |
| `GongbaoView.swift` | 公报浏览、搜索、案例笔记界面 |
| `LawDetailView.swift` | 法律全文阅读，条文锚点滚动，公报案例链接 |
| `UserStore.swift` | 用户偏好、收藏、公报笔记持久化（iCloud KV） |

LLM 接入：DeepSeek（`deepseek-chat` / `deepseek-reasoner`），API Key 存储于系统 Keychain。

---

## 变现

- **免费**：5 次体验额度
- **畅用版**（月/年订阅）：内置 API Key，每周 80 次，周一自动重置
- **基础版**（买断）：自备 DeepSeek API Key，无次数限制

---

## 数据来源

- 法律法规：[国家法律法规数据库](https://flk.npc.gov.cn/)
- 最高人民法院公报：[gongbao.court.gov.cn](https://gongbao.court.gov.cn)
- 数据处理 pipeline：[laws-data](https://github.com/13098806890/laws-data)
