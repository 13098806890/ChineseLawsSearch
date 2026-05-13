# 中国法律助手

中国法律法规检索与智能咨询 iOS 应用，数据来源于 [laws-data](https://github.com/13098806890/laws-data) 开放数据集。

---

## 功能

### 法律浏览
- 按法律部门（民法、刑法、行政法等）分类浏览 ~1,945 部法律法规
- 编 / 章 / 节 / 条 层级导航，支持目录跳转
- 条文内容全文展示，支持字号调节
- **法考模式**：一键切换，仅显示法律职业资格考试收录的 208 部法律
- 条文收藏（书签）与历史阅读记录恢复

### 全文搜索
- FTS5 trigram 索引，支持任意中文短语搜索（≥3 字）
- 1–2 字短词搜索（unicode61 分词）
- 结果按法律部门过滤，关键词高亮显示
- 支持仅搜标题 / 含条文内容两种模式

### 人民法院公报
- 浏览最高人民法院公报全量数据
  - **指导案例**：986 篇，含裁判要点摘要和关键词
  - **司法文件**：860 篇
  - **裁判文书**：443 篇
- 关键词全文搜索（FTS5 trigram）
- 点击查看全文，支持跳转原始网页

### 法律咨询（AI）
- 基于 RAG（检索增强生成）的法律问答
- **RAG 模式**：快速检索相关法条，DeepSeek 生成简要解答
- **专家模式**：多层专家协作（协调员 → 6 个专家组 → 17 个细分专家），追问补全关键信息（最多 1–5 轮，可在设置中配置）
- 意图识别自动路由，支持条文直查、实体提取等场景
- 对话历史持久化，支持跨 session 恢复
- 对话内容导出分享

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
| `LegalRAGService.swift` | RAG pipeline：意图分类 → FTS 检索 → 上下文构建 → LLM 流式生成 |
| `LegalExpertService.swift` | 专家协作系统：角色分配 → 信息收集 → 并行检索 → 综合分析 |
| `LegalChatViewModel` | 对话状态管理，追问轮次控制，ViewModel 驱动 UI |
| `ChatHistoryStore.swift` | 对话历史持久化（Documents/chat_history.json） |
| `GongbaoView.swift` | 公报浏览与搜索界面 |
| `TOCView.swift` | 法律目录树（`law_menu.json` / `flk_menu.json`） |
| `LawDetailView.swift` | 法律全文阅读，支持条文锚点滚动 |

LLM 接入：默认 DeepSeek（`deepseek-chat` / `deepseek-reasoner`），API Key 存储于系统 Keychain。

---

## 变现

- **免费**：5 次体验额度
- **畅用版**（内购）：内置 API Key，每周 N 次，周一自动重置
- **基础版**（内购）：自备 DeepSeek API Key，无次数限制

---

## 数据来源

- 法律法规：[国家法律法规数据库](https://flk.npc.gov.cn/)
- 最高人民法院公报：[gongbao.court.gov.cn](https://gongbao.court.gov.cn)
- 数据处理 pipeline：[laws-data](https://github.com/13098806890/laws-data)
