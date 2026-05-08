# 中国法律法规检索

一款面向 iPhone 和 iPad 的中文法律法规离线浏览与全文检索 App，内置完整的 SQLite 数据库，支持完全离线使用，并集成多专家协作 LLM 法律问答功能。

---

## 功能

### 目录浏览
- 按分类（宪法、法律、行政法规、司法解释等）层级展开浏览 1,526 部现行法律法规
- 7 个展示分组（宪法与国家机构 / 民事与商事 / 刑事 / 行政与公法 / 经济税务与金融 / 劳动与社会保障 / 诉讼与司法程序），支持折叠 / 展开
- 启动时自动恢复上次阅读位置，精确到条文

### 全文检索
- 法律名称搜索 + 条文内容全文搜索
- 搜索结果高亮匹配关键词
- 支持中文数字与阿拉伯数字互转（搜"第10条"自动匹配"第十条"）
- 可选项：
  - **忽略条号匹配**：过滤仅因"第 X 条"编号命中的噪声结果
  - **仅搜标题**：只在法律名称中检索
  - 结果数量上限：50 / 100 / 200 条

### 法律详情
- 完整条文阅读，支持编 / 章 / 节 / 条层级结构展示
- 右侧滚动索引条：按比例显示条号，拖拽或点击直接跳转（可在设置中关闭）
- 条内搜索：点击搜索按钮后输入关键词，实时过滤当前法律条文
- 交叉引用：
  - 条文内的法律引用以彩色超链接呈现，点击跳转至被引用条文
  - 每条文底部列出被其他法律引用的来源（被引法律名称 + 条号），可点击跳转
- 跳转历史链路持久化：从引用跳转时记录返回栈，App 重启后可继续沿链路返回

### 法律咨询（AI 问答）

内置两种问答模式。每次对话开始前通过意图分类器自动路由（案情陈述 / 追问 / 法律知识 / 无关问题），减少不必要的专家调用。

#### 快速模式（RAG）
关键词检索 + LLM 生成回答的流水线：
1. 问题拆分（多问题自动识别）
2. 领域路由（8 个法律部门）
3. 关键词提取 + 别名扩展（日常用语 → 法律术语）
4. 分层检索（法律原文 + 司法解释，按相关度排序）
5. 相关性过滤
6. LLM 流式生成回答
7. 参考法条从答案正文引用中自动匹配并展示

#### 专家模式
多层专家协作系统，适合复杂法律问题：

- **意图分类**（每轮对话第一步）：LLM 4-way 分类（案情 / 追问 / 法律知识 / 无关），分别路由至不同处理路径
- **Coordinator**：案情定性，路由至 6 个专家组
- **细分专家**（17 个）：合同通则、买卖、租赁、借款、建设工程、侵权责任、产品责任、交通事故、医疗损害、人格权、物权、婚姻家庭、继承、刑事犯罪、劳动纠纷、行政诉讼、民事诉讼程序
- **专家组综合**：合并同组专家分析，消除重复
- **Coordinator 整合**：生成最终连贯回答
- **追问支持**：关键事实缺失时先从案情文本自动提取，提取不到才向用户追问；专家上下文跨轮次保持，加载历史会话后可继续追问

#### 通用特性
- 思考过程可展开 / 折叠，显示每步推理内容及检索到的条文
- 参考法条可展开，点击跳转至对应条文位置
- 对话历史自动保存（含专家上下文、已提取事实、Token 统计），重启后完整恢复
- 支持多种 LLM 后端：Gemini Flash、DeepSeek、Groq（Llama 3.3 70B）、本地 Ollama

### 设置
| 项目 | 说明 |
|------|------|
| 显示右侧条文索引 | 法律详情页右侧快速跳转索引条开关 |
| 显示思考过程 | 专家模式分析步骤是否展开显示 |
| 专家最多追问轮次 | 0–5 轮，0 = 不追问直接分析 |
| 参考法条最多数量 | 0 = 不限，步长 10 |
| 每专家上下文法条数 | 5–1000 |
| 模型选择 | Gemini / DeepSeek / Groq / Ollama |
| API Key 管理 | 加密存储于系统 Keychain |

---

## 架构

```
ChineseLawsSearch/
├── ContentView.swift          # 根视图，Tab 路由，导航状态，启动恢复
├── UserStore.swift            # 用户偏好与阅读记录（UserDefaults，单一数据源）
├── DatabaseManager.swift      # SQLite 封装，只读 bundle DB
├── LegalRAGService.swift      # RAG pipeline 核心（事件流 RAGEvent）
├── LegalChatView.swift        # 法律咨询 UI + LegalChatViewModel
├── ChatHistory.swift          # 对话历史持久化（ChatSession / ChatHistoryStore）
├── TOCView.swift              # 法律目录 / 搜索
├── LawDetailView.swift        # 法律条文详情 + 交叉引用
├── LLMProvider.swift          # LLM 多后端抽象（Gemini / DeepSeek / Groq / Ollama）
└── Agents/
    ├── LegalExpertService.swift   # 专家流程入口（意图分类、追问、general 路径）
    ├── ExpertGroups.swift         # 6 个专家组定义
    ├── Core/
    │   ├── ExpertModels.swift     # SubExpert / ExpertGroup / RequiredInfo
    │   └── ExpertRegistry.swift   # 专家查询工具
    └── Experts/                   # 17 个细分专家实现
```

### 核心数据流

```
用户输入
  → 意图分类（case / follow_up / general / off_topic）
      ├── off_topic  → 硬编码引导回复
      ├── general    → askGeneral（复杂度判断 → FTS + LLM）
      ├── follow_up  → askFollowUp（复用上次专家 + 追问上下文）
      └── case       → runCasePipeline
                          → Coordinator 路由
                          → 并行调用细分专家
                          → 专家组综合
                          → Coordinator 整合
                          → 流式输出 + 参考法条
```

### 持久化一览

| 数据 | 存储位置 | 说明 |
|------|----------|------|
| 用户偏好（模型、显示设置等） | `UserDefaults`（`UserStore`） | 随系统备份 |
| 上次阅读法律 + 条文 | `UserDefaults` | 启动自动恢复 |
| 跳转返回链路（backStack） | `UserDefaults` | 恢复跨法条跳转链路 |
| 对话历史（消息 + 专家上下文 + Token） | `Documents/chat_history.json` | 完整恢复追问能力 |
| API Key | 系统 Keychain | AES-256 加密 |

---

## 数据库结构

数据库文件 `law_content.db`（SQLite，约 132 MB），只读，随 App Bundle 分发。使用 `journal_mode=DELETE`（非 WAL），兼容只读文件系统。

### `laws` — 法律元数据

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER PK | 稳定主键，跨数据库重建不变 |
| `title` | TEXT | 法律全称 |
| `filename` | TEXT UNIQUE | `{标题}_{YYYYMMDD}` |
| `category` | TEXT | 宪法 / 法律 / 行政法规 / 司法解释 / 修正案 / 法律解释 / 监察法规 |
| `legal_domain` | TEXT | 民法典 / 民法商法 / 刑法 / 行政法 / 经济法 / 社会法 / 宪法相关法 / 诉讼与非诉讼程序法 |
| `pub_date` | TEXT | 公布日期 `YYYY-MM-DD` |
| `effective_date` | TEXT | 生效日期 |
| `issuing_org` | TEXT | 发布机关（白名单精确匹配） |
| `doc_number` | TEXT | 发文字号（法释〔2000〕29号 等） |
| `total_articles` | INTEGER | 条文总数 |
| `is_current` | INTEGER | 1 = 现行版本，0 = 历史版本 |
| `aliases` | TEXT | 逗号分隔别名（如 `民法典,民法`） |

### `nodes` — 条文层级节点

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER PK | 节点 ID |
| `law_id` | INTEGER FK | 所属法律 |
| `parent_id` | INTEGER FK | 父节点（树形结构） |
| `type` | TEXT | `part` / `chapter` / `section` / `article` |
| `article_number` | TEXT | 条号文本（如"第一条"） |
| `content` | TEXT | 节点完整文本 |
| `global_order` | INTEGER | 全文深度优先遍历序号，`ORDER BY global_order` 得正确展示顺序 |
| `article_num` | INTEGER | 条号数值（用于跳转定位和范围查询） |

**索引**：`(law_id, global_order)`、`(law_id, part_num, chapter_num, section_num, article_num)`

### `nodes_fts` — 全文检索虚表（FTS5，trigram）

trigram 分词，最少 3 个字符，支持任意中文子串精确匹配。短词（1–2 字）用 `nodes_fts_bigram`（unicode61 分词）。

均为**外部内容表**（`content="nodes"`），不复制原文，节省约 175 MB 空间。

### `article_references` — 条文引用关系

| 字段 | 说明 |
|------|------|
| `from_node_id / from_law_id / from_article_num` | 引用来源 |
| `to_node_id / to_law_id / to_article_num` | 被引用目标 |
| `ref_type` | `cross_law`（跨法引用）或 `self_ref`（本法内引用） |
| `raw_text` | 原文引用字符串 |
| `resolved` | 是否成功解析到具体节点 |

共 6,452 条引用记录，解析率 98.8%。

---

## 数据来源

法律原文数据来源于**[国家法律法规数据库](https://flk.npc.gov.cn/)**（全国人大常委会法制工作委员会官方发布平台），由 [laws_data](https://github.com/doxie/laws_data) pipeline 结构化处理后打包。

中华人民共和国法律法规原文属于国家公开文献，不受著作权保护，可自由使用。

---

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 6 |
| UI 框架 | SwiftUI |
| 数据库 | SQLite（C API 直接调用，不依赖 ORM） |
| LLM 集成 | Gemini Flash 2.0、DeepSeek V3、Groq Llama 3.3 70B、Ollama |
| 最低系统要求 | iOS 17 / iPadOS 17 |
| 支持设备 | iPhone、iPad（含旋转适配） |
