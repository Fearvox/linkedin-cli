<div align="center">

# linkedin-cli

**LinkedIn 全自动外联流水线——搜索、评分、触达，端到端。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![Playwright](https://img.shields.io/badge/browser-Playwright-green.svg)](https://playwright.dev/)
[![Shell](https://img.shields.io/badge/shell-bash-lightgrey.svg)](https://www.gnu.org/software/bash/)

</div>

---

## 问题从这里开始

每个 B2B 团队都在做 LinkedIn 外联。多数人手动操作——一个一个看 profile，一条一条发消息，在一堆标签页里复制粘贴，希望自己没漏掉重要的人。

这不是策略，这是体力活。

linkedin-cli 把这件事变成了流水线。从关键词搜索，到 profile 评分，到人工 review，到精准发出连接请求和私信——每一步都是命令行，每一步都可审计，每一步都不需要你盯着屏幕点鼠标。

这不是群发工具。这是一套猎人系统。

---

## 快速开始

```bash
# 克隆
git clone https://github.com/yourname/linkedin-cli.git
cd linkedin-cli

# 安装依赖
pip install playwright pyyaml
playwright install chromium

# 配置浏览器 session（一次性）
# 用已登录的 LinkedIn 浏览器 session，无需账号密码
cp .env.example .env
```

---

## 11 个 Adapter

11 个 adapter，覆盖 LinkedIn 所有读写操作。搜索是猎物入口，评分是筛选机制，外联是精确打击。

| 命令 | 类型 | 功能 |
|------|------|------|
| `profile` | Read | 抓取指定用户的完整 profile |
| `search-people` | Read | 关键词 + 过滤条件搜索目标人群 |
| `connections` | Read | 导出一度连接列表 |
| `inbox` | Read | 读取私信列表 |
| `notifications` | Read | 读取通知流 |
| `post` | Write | 发布内容 |
| `like` | Write | 点赞指定帖子 |
| `comment` | Write | 在帖子下评论 |
| `repost` | Write | 转发帖子 |
| `connect` | Write | 发送连接请求（含 note） |
| `send-dm` | Write | 发送私信 |

所有 Write 操作均支持 `--dry-run`，先看再打。

---

## Prospect Pipeline

四个阶段，一条命令链。

```bash
# Stage 1 — 搜索：把目标人群抓进本地
bash prospect.sh search --query "revenue manager hotel" --limit 100

# Stage 2 — 评分：跑评分引擎，过滤噪音
bash prospect.sh scan

# Stage 3 — Review：人工确认，标记 approve/skip
bash prospect.sh review

# Stage 4 — 外联：对 approved 名单精准触达
bash prospect.sh outreach --template tier-a-crossover
```

数据落在本地 JSONL 文件，每一步的决策都可以追溯。

---

## 评分引擎：三级门控级联

不是简单加分，是有门控的级联筛选。只有通过前一级，才会进入下一级评估。

**第一级：Quality Gate（6 信号复合）**

headline 长度、ALL CAPS 占比、求职关键词（"open to work"类）、"at Company" 模板化模式、about 段落存在与否、工作经历完整度。质量不达标，直接淘汰，不浪费后续计算。

**第二级：Industry Gate**

核心行业：hotel / hospitality / OTA / resort / lodging。相邻行业：cashback / reconciliation / revenue / booking。不在目标行业，跳过。

**第三级：多维评分**

- Seniority（0-5）× Company Tier（0-5）= Authority（0-25）
- + Relevance（行业吻合度）
- + Proximity（网络距离）
- + Activity（近期活跃度）
- + Resonance（内容互动信号）

最终输出 Tier A / B / C / D，对应不同外联策略。

---

## 消息模板

5 套模板，按 Tier 对应，`{{variable}}` 变量替换。

| 模板 | 适用场景 |
|------|----------|
| `tier-a-crossover` | 共同背景切入，高意图目标 |
| `tier-b-product` | 借助共同连接，产品价值导向 |
| `tier-c-leverage` | 基于对方内容互动，低门槛建联 |
| `hco-intro` | B2B 直接 pitch，酒店渠道决策人 |
| `warm-reconnect` | 已有连接，重新激活对话 |

模板文件在 `templates/`，可以直接改，pipeline 会自动读取。

---

## 自进化：.algo-profile/

系统把所有评分决策持久化在 `.algo-profile/` 目录。评分逻辑不是一次性写死的——它记录了每次迭代的原因。

评分引擎自身的演进路径：从最初的线性加法，到引入 Quality Gate，再到 Quality Gate 从单一 `len<20` 扩展为 6 信号复合。每次改动都有对应的记录。

这让调优有据可查，下次换目标行业时，不是从零开始。

---

## 安全机制

- 操作间隔固定 3 秒，不触发 LinkedIn 速率限制
- 每批最多 20 条，不做大规模轰炸
- 所有 Write 操作支持 `--dry-run`，确认后再执行
- 使用浏览器 session 鉴权，不存储账号密码
- 模板经过人工审核，专业语气，不群发垃圾内容

---

## 项目结构

```
linkedin-cli/
├── adapters/               # 11 个 YAML adapter
│   ├── profile.yaml
│   ├── search-people.yaml
│   ├── connections.yaml
│   ├── inbox.yaml
│   ├── notifications.yaml
│   ├── post.yaml
│   ├── like.yaml
│   ├── comment.yaml
│   ├── repost.yaml
│   ├── connect.yaml
│   └── send-dm.yaml
├── prospect.sh             # Pipeline 入口
├── score.py                # 评分引擎
├── templates/              # 消息模板
│   ├── tier-a-crossover.txt
│   ├── tier-b-product.txt
│   ├── tier-c-leverage.txt
│   ├── hco-intro.txt
│   └── warm-reconnect.txt
├── .algo-profile/          # 评分决策持久化
├── data/                   # 本地数据（JSONL）
├── .env.example
└── README.md
```

---

## Contributing

欢迎提交新 adapter、改进评分逻辑、或者增加新的消息模板。提 PR 前跑一下现有的 adapter 确认没有 regression。

---

## License

MIT
