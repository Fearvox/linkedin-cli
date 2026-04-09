<div align="center">

[English](README.md) | **中文**

# linkedin-cli

**从终端完成 LinkedIn 全流程自动化 — 搜索、评分、建联、发消息。**

![Version](https://img.shields.io/badge/version-v1.0.0-blue)
![License](https://img.shields.io/badge/License-CC%20BY--NC--ND%204.0-red)
![opencli](https://img.shields.io/badge/opencli-v1.6.8+-blue)
![Playwright](https://img.shields.io/badge/Playwright-Browser%20Automation-2ea44f)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white)
![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-7C3AED)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

</div>

---

## 目录

- [概述](#概述)
- [快速开始](#快速开始)
- [命令列表](#命令列表)
- [线索挖掘流水线](#线索挖掘流水线)
- [评分引擎](#评分引擎)
- [消息模板](#消息模板)
- [项目架构](#项目架构)
- [算法决策](#算法决策)
- [安全与速率限制](#安全与速率限制)
- [求职模式](#求职模式)
- [测试](#测试)
- [贡献指南](#贡献指南)
- [安全与合规使用](#安全与合规使用)
- [许可证](#许可证)

---

## 概述

每个 B2B 团队都在做 LinkedIn 触达。大多数都靠手工——把名字复制进消息模板，在浏览器和电子表格之间来回切换，忘了上周联系过谁。Apollo.io 和 Lemlist 各解决了一部分问题，但都没给你一个终端、一个评分引擎和对数据的完全控制权。

linkedin-cli 将这一切变成一条流水线。11 个 YAML 适配器覆盖每一种 LinkedIn 操作。Python/Bash 评分引擎通过门控级联将线索分类为不同等级。人工审核环节确保没有经过你批准的内容不会被发送。所有数据以 JSONL 格式存储在本地。所有逻辑完全由你掌控。

`搜索 → 评分 → 审核 → 建联 → 发消息`

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 快速开始

```bash
git clone https://github.com/Fearvox/linkedin-cli.git
cd linkedin-cli
./install.sh
```

**前置条件：**

1. [opencli](https://github.com/jackwener/opencli) v1.6.8+ 已添加到 `$PATH`
2. Chrome 已加载 opencli Browser Bridge 扩展
3. 在该 Chrome 配置文件中已登录 LinkedIn
4. Python 3.10+，Bash 5.0+

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 命令列表

所有适配器通过 `opencli linkedin <command>` 运行。每个写入命令均支持 `--dry-run`。

| 命令 | 类型 | 说明 |
|------|------|------|
| `profile <url>` | 读取 | 获取头衔、简介、工作经历、人脉数量、公司 |
| `search-people <query>` | 读取 | 按关键词搜索，支持人脉度数筛选 |
| `connections` | 读取 | 列出你的一度人脉 |
| `inbox` | 读取 | 最近的对话 |
| `notifications` | 读取 | 最近的通知 |
| `post <text>` | 写入 | 发布文字帖子 |
| `like <url>` | 写入 | 点赞帖子 |
| `comment <url> --text "..."` | 写入 | 评论帖子（支持 `--reply-to` 进行回复） |
| `repost <url>` | 写入 | 转发，可附带评论 |
| `connect <url> --note "..."` | 写入 | 发送带个性化备注的建联请求 |
| `send-dm <profile> --text "..."` | 写入 | 向人脉发送私信 |

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 线索挖掘流水线

八个子命令，通过单一脚本编排。

```bash
# 1. 搜索 — 按关键词拉取候选人，去重，预过滤
./scripts/prospect.sh search "hotel revenue manager" --limit 20

# 2. 扫描 — 用完整资料充实线索 + 三阶段评分
./scripts/prospect.sh scan

# 3. 审核 — 交互式人工审核（y/n/s/q）
./scripts/prospect.sh review

# 4. 触达 — 使用模板替换向已批准的线索发送私信
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run

# 5. 建联 — 按等级发送带备注的建联请求
./scripts/prospect.sh connect --tier a --dry-run

# 6. 监控 — 检查已接受的建联请求
./scripts/prospect.sh monitor --auto-outreach

# 7. 模板 — 渲染等级专属建联备注，支持变量替换
./scripts/prospect.sh template --tier b --first_name "Sarah" --company "Hilton"

# 8. 批量 — 运行预设关键词组（Tier A/B 搜索查询）
./scripts/prospect.sh batch
```

| 子命令 | 说明 |
|--------|------|
| `search` | 按关键词拉取候选人，对现有线索去重，预过滤 |
| `scan` | 为每条线索补充完整资料，运行三阶段评分级联 |
| `review` | 交互式审核 — `y` 批准、`n` 拒绝、`s` 跳过、`q` 退出 |
| `outreach` | 使用 `{{variable}}` 变量替换模板向已批准线索发送私信 |
| `connect` | 发送带等级专属备注的建联请求（支持 `--tier a\|b\|c`） |
| `monitor` | 检查已接受的建联请求（支持 `--auto-outreach`） |
| `template` | 渲染等级专属建联备注，支持变量替换 |
| `batch` | 运行预设关键词组，执行 Tier A/B 搜索查询 |

线索持久化存储在 `data/leads.jsonl` 中。内置去重功能。准备好正式发送时去掉 `--dry-run` 即可。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 评分引擎

三阶段门控级联。任一阶段未通过即被淘汰。

### 第一阶段：质量门控

六个信号在语义评分之前过滤噪音：

- 头衔过短（<20 字符 = 不完整资料）
- 全大写比例 >70%（求职者、自由职业者）
- 求职短语（"looking for"、"open to"、"in transition"）
- 无 "at Company" 或 "|" 模式（低信息量头衔）
- 简介缺失或过于简短
- 工作经历为空

### 第二阶段：行业门控

必须匹配至少一个关键词：

- **核心：** `hotel`、`hospitality`、`ota`、`resort`、`lodging`
- **相邻：** `cashback`、`reconciliation`、`revenue`、`booking`、`travel agency`

零匹配 = Tier D，跳过。

### 第三阶段：多维度评分

五个维度独立评分：

| 维度 | 范围 | 计算方式 |
|------|------|----------|
| 权威度 (Authority) | 0–25 | `seniority(0-5) × company_tier(0-5)`。50+ 品牌的等级字典（Hilton=5、Millennium=3、generic=1） |
| 相关度 (Relevance) | 0–5 | 行业关键词深度（核心匹配计双倍） |
| 接近度 (Proximity) | 0–5 | 与你 Tier-1 人脉的共同连接数 |
| 活跃度 (Activity) | 0–3 | 人脉数 500+ 且有近期帖子 |
| 共鸣度 (Resonance) | 0–3 | 共同背景信号（学校、专业、工具） |

等级分类使用 (Authority, Relevance) 的二维空间，而非简单的加法总分：

- **Tier A** — authority >= 12 且 relevance >= 3（大品牌的决策者）
- **Tier B** — authority >= 6 或 高相关度 + 人脉资源
- **Tier C** — 在行业内，权威度较低
- **Tier D** — 未通过门控或各维度均较低

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 消息模板

六个模板，支持 `{{variable}}` 变量替换（`first_name`、`company`、`mutual_connection`、`topic`）：

| 模板 | 路径 | 使用场景 |
|------|------|----------|
| Tier A — 交叉背景 | `templates/connect/tier-a-crossover.txt` | 有共同背景（同校、同领域） |
| Tier B — 产品 | `templates/connect/tier-b-product.txt` | 以共同人脉作为引荐切入点 |
| Tier C — 借力 | `templates/connect/tier-c-leverage.txt` | 对方曾互动过你的内容 |
| HCO 介绍 | `templates/hco-intro.txt` | 面向酒店运营决策者的冷启动 B2B 推介 |
| HCO 旅客 | `templates/hco-traveler.txt` | 面向高频旅客的个人返现工具推介 |
| 暖场重联 | `templates/warm-reconnect.txt` | 重新激活沉寂的一度人脉 |

纯文本文件存放在 `templates/` 目录下。编辑模板无需修改流水线代码。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 项目架构

```
linkedin-cli/
├── adapters/                  # 11 个 YAML 适配器（opencli 格式）
│   ├── profile.yaml           # 读取：完整资料抓取
│   ├── search-people.yaml     # 读取：Voyager API + DOM 回退
│   ├── connections.yaml       # 读取：一度人脉列表
│   ├── inbox.yaml             # 读取：对话
│   ├── notifications.yaml     # 读取：通知流
│   ├── post.yaml              # 写入：创建帖子
│   ├── like.yaml              # 写入：点赞帖子
│   ├── comment.yaml           # 写入：评论（+ 线程回复）
│   ├── repost.yaml            # 写入：转发
│   ├── connect.yaml           # 写入：建联请求
│   └── send-dm.yaml           # 写入：私信
├── scripts/
│   └── prospect.sh            # 流水线编排器（约 1300 行）
├── templates/
│   ├── connect/               # 等级专属建联备注
│   │   ├── tier-a-crossover.txt
│   │   ├── tier-b-product.txt
│   │   └── tier-c-leverage.txt
│   ├── hco-intro.txt          # B2B 冷启动推介
│   ├── hco-traveler.txt       # 面向旅客的返现工具推介
│   └── warm-reconnect.txt     # 重联现有人脉
├── .algo-profile/             # 持久化算法决策
├── data/                      # leads.jsonl（已 gitignore）
├── tests/
│   └── test-all.sh            # 13 项冒烟测试
├── docs/
│   ├── job-hunt-2026-04-08.md # 求职集成报告
│   └── reports/               # 生成的基准报告
├── install.sh                 # 将适配器软链接到 ~/.opencli/
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md
```

**适配器系统：** 每个 YAML 适配器定义一个 LinkedIn 操作——选择器、API 端点、输入参数和输出模式。`opencli` 加载适配器并驱动 Playwright 在活跃的浏览器会话中执行操作。

**流水线流程：** `prospect.sh` 编排整个周期。搜索填充 `data/leads.jsonl`，扫描为每条记录补充资料并评分，审核添加人工批准标记，触达/建联仅向已批准的线索发送消息。

**数据格式：** 所有线索数据以换行分隔的 JSON（JSONL）格式存储。每条线索一条记录，流水线推进时就地更新。字段包括资料 URL、头衔、简介、工作经历、评分、等级和审批状态。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 算法决策

`.algo-profile/` 目录跨会话持久化每一个重要的算法决策。完整日志参见 [.algo-profile/README.md](.algo-profile/README.md)。

评分引擎经历了两次重大迭代。最初采用扁平加法模型（7 个维度，求和得总分，>=10 则推荐）。实际触达数据暴露了缺陷：8 个弱信号堆叠到的分数与 1 个强信号相同。当前的门控级联正是针对此问题的修复。

质量门控从最初的单一 `len(headline) < 20` 检查，演进为 6 信号复合检查——因为首批数据中全大写的求职者和不完整资料通过了初始过滤。

公司等级字典、关键词列表和等级阈值均可调整。将回复率数据回馈，调整权重，重新评分。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 安全与速率限制

- **3 秒间隔** — API 调用之间固定延迟，每批次最多 20 次
- **`--dry-run` 标志** — 每个写入命令均支持，正式操作前必须先试运行
- **不存储凭证** — 仅通过浏览器会话认证，不保存密码或令牌
- **人工审核环节为强制性的** — 未经你明确批准不会发送任何内容
- **模板专业得体** — 个性化，每条 3–7 行

请将此工具用于有真实意图的精准触达。批量滥用会导致你的账号被标记，也违背了评分引擎的初衷。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 求职模式

线索挖掘流水线与 grunk 的求职流水线集成，实现端到端的求职搜索与内推触达。完整的研究报告和工作流程参见 [docs/job-hunt-2026-04-08.md](docs/job-hunt-2026-04-08.md)。

```bash
# 研究职位（公开信息，无需登录）
opencli linkedin search "Go backend engineer remote" --limit 20

# 在目标公司找员工以获取内推
opencli linkedin search-people "software engineer at DoorDash Toronto" --limit 10

# 通过线索挖掘流水线进行评分和触达
./scripts/prospect.sh search "software engineer at DoorDash" --limit 20
./scripts/prospect.sh scan
```

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 测试

```bash
./tests/test-all.sh
```

运行 13 项冒烟测试，覆盖适配器加载、流水线子命令、模板渲染和数据格式验证。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 贡献指南

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。最有价值的贡献方向：

- 酒店业以外的行业等级字典
- 附带文档化方法论的新评分维度
- 覆盖尚未支持的 LinkedIn 操作的新适配器命令

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 安全与合规使用

详见 [SECURITY.md](SECURITY.md) 了解漏洞报告和合规使用指南。

此工具与实时 LinkedIn 会话交互。它不存储凭证，不绕过认证机制，并在设计上强制执行速率限制和人工审核环节。你有责任遵守 LinkedIn 的服务条款。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>

---

## 许可证

**CC BY-NC-ND 4.0** — 详见 [LICENSE](LICENSE)。

具体含义：
- **禁止商用** — 不得将本项目用于商业目的
- **禁止演绎** — 不得分发修改版本
- **署名必须** — 必须给予适当的署名

版权所有 (c) Nolan Zhu。

<p align="right"><a href="#linkedin-cli">回到顶部 ↑</a></p>
