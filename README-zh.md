<div align="center">

[English](README.md) | **中文**

# linkedin-cli

**LinkedIn 全自动外联流水线 — 搜索、评分、触达，端到端。**

![opencli](https://img.shields.io/badge/opencli-v1.6.8+-blue) ![Playwright](https://img.shields.io/badge/Playwright-Browser%20Automation-2ea44f) ![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white) ![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-7C3AED) ![License](https://img.shields.io/badge/License-MIT-brightgreen)

</div>

---

每个 B2B 团队都在做 LinkedIn 外联。多数人手动操作 — 一个个看 profile，一条条发消息，在标签页和表格之间来回切换，忘了上周联系过谁。

linkedin-cli 把这件事变成了流水线。11 个 YAML adapter 覆盖 LinkedIn 所有读写操作。一套 Python/Bash 评分引擎把候选人分成 A/B/C/D 四档。人工 review 卡在发送前。数据留在本地，逻辑你随时能调。

`搜索 → 评分 → 审核 → 触达`

---

## 快速开始

```bash
git clone https://github.com/Fearvox/linkedin-cli.git
cd linkedin-cli
./install.sh
```

**前置条件：**

1. [opencli](https://github.com/jackwener/opencli) v1.6.8+ 已安装
2. Chrome 加载了 opencli Browser Bridge 扩展
3. Chrome 里已登录 LinkedIn

---

## 11 个 Adapter

所有命令通过 `opencli linkedin <command>` 调用。Write 操作均支持 `--dry-run`。

| 命令 | 类型 | 功能 |
|------|------|------|
| `profile <url>` | Read | 抓取完整 profile（headline、about、experience、connections） |
| `search-people <query>` | Read | 关键词搜索 + 网络度过滤 |
| `connections` | Read | 导出一度连接 |
| `inbox` | Read | 读取私信 |
| `notifications` | Read | 读取通知 |
| `post <text>` | Write | 发帖 |
| `like <url>` | Write | 点赞 |
| `comment <url> --text "..."` | Write | 评论（支持 `--reply-to` 回复楼中楼） |
| `repost <url>` | Write | 转发 |
| `connect <url> --note "..."` | Write | 发送连接请求 + 附言 |
| `send-dm <profile> --text "..."` | Write | 私信 |

---

## Prospect Pipeline

四个阶段，一条命令链。

```bash
# 1. 搜索 — 按目标画像抓取候选人
./scripts/prospect.sh search "hotel revenue manager" --limit 20

# 2. 评分 — 对未评分 lead 跑门控级联
./scripts/prospect.sh scan

# 3. 审核 — 人工逐条确认 approve / skip
./scripts/prospect.sh review

# 4. 触达 — 向已批准名单发连接请求
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run
```

数据存在 `data/leads.jsonl`，自动去重。去掉 `--dry-run` 正式发送。

---

## 评分引擎：三级门控级联

不是简单加分。逐级过关，挂在任何一级直接淘汰。

**第一级：Quality Gate** — 6 个信号过滤噪音：

- headline 太短（<20 字符 = 不完整 profile）
- ALL CAPS 占比 >70%（求职者、freelancer）
- 求职关键词（"looking for"、"open to"、"in transition"）
- 无 "at Company" 或 "|" 模式（低信息量 headline）
- about 缺失或过短
- experience 为空

**第二级：Industry Gate** — 至少匹配一个关键词：

- 核心：`hotel`、`hospitality`、`ota`、`resort`、`lodging`
- 相邻：`cashback`、`reconciliation`、`revenue`、`booking`、`travel agency`

零匹配 = Tier D，跳过。

**第三级：多维评分** — 5 个轴：

| 轴 | 范围 | 算法 |
|----|------|------|
| Authority | 0-25 | `seniority(0-5) * company_tier(0-5)`，50+ 品牌分级（Hilton=5, Millennium=3, 不知名=1） |
| Relevance | 0-5 | 行业关键词深度（核心匹配 ×2） |
| Proximity | 0-5 | 与你 Tier-1 人脉的共同连接 |
| Activity | 0-3 | connections 500+ 且近期有发帖 |
| Resonance | 0-3 | 共同背景信号（学校、专业、工具） |

Tier 分类用 (Authority, Relevance) 二维空间，不是加法总分：

- **A** — authority >= 12 且 relevance >= 3（大品牌决策者）
- **B** — authority >= 6 或 强行业 + 网络可达
- **C** — 在目标行业，authority 低
- **D** — 未过门控或各轴都弱

---

## 消息模板

5 套模板，`{{variable}}` 替换（first_name、company、mutual_connection、topic）：

| 模板 | 适用场景 |
|------|----------|
| `tier-a-crossover.txt` | 共同背景切入（同校、同行） |
| `tier-b-product.txt` | 共同连接做引子 |
| `tier-c-leverage.txt` | 对方与你内容有互动 |
| `hco-intro.txt` | B2B 冷启动 pitch（酒店运营决策人） |
| `warm-reconnect.txt` | 重新激活已有一度连接 |

纯文本文件，在 `templates/` 下直接改，不用碰 pipeline 代码。

---

## 自进化

`.algo-profile/` 目录持久化每个非平凡的算法决策。

评分引擎经历过两次大改。第一版是 7 维加法模型 — 跑了一批真实数据后发现问题：8 个弱信号堆出的总分和 1 个强信号一样。改成门控级联之后，ALL CAPS 求职者和不完整 profile 在第一级就被过滤掉了。

品牌分级、关键词、阈值 — 都可调。把回复率喂回来，改权重，重新跑分。

---

## 安全机制

- API 调用间隔 3 秒，每批最多 20 条
- 所有 Write 操作必须先 `--dry-run`
- 认证走浏览器 session，不存密码或 token
- 模板经人工审核，专业语气，3-7 行
- 人工审核是强制门控 — 没有你点头，什么都不会发出去

用于有真实意图的精准触达。大量群发会被 LinkedIn 风控拦掉。

---

## 项目结构

```
linkedin-cli/
├── adapters/               # 11 个 YAML adapter（opencli 格式）
│   ├── profile.yaml        # Read: profile 全量抓取
│   ├── search-people.yaml  # Read: Voyager API + DOM fallback
│   ├── connections.yaml    # Read: 一度连接
│   ├── inbox.yaml          # Read: 私信
│   ├── notifications.yaml  # Read: 通知
│   ├── post.yaml           # Write: 发帖
│   ├── like.yaml           # Write: 点赞
│   ├── comment.yaml        # Write: 评论（支持楼中楼）
│   ├── repost.yaml         # Write: 转发
│   ├── connect.yaml        # Write: 连接请求
│   └── send-dm.yaml        # Write: 私信
├── scripts/
│   └── prospect.sh         # Pipeline 主脚本（~1300 行）
├── templates/
│   ├── connect/             # Tier 分级连接附言
│   ├── hco-intro.txt        # B2B 冷启动 pitch
│   └── warm-reconnect.txt   # 已有连接重激活
├── .algo-profile/           # 算法决策持久化
├── data/                    # leads.jsonl（已 gitignore）
├── tests/
│   └── test-all.sh          # 冒烟测试
├── docs/reports/            # 生成的 benchmark 报告
├── install.sh               # adapter 软链安装器
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

---

## Job Hunt 模式

与 grunk job-hunt pipeline 打通：职位研究 → 内推找人 → 精准触达。详见 [docs/job-hunt-2026-04-08.md](docs/job-hunt-2026-04-08.md)。

快速上手：
```bash
# 职位市场研究（公开数据，无需 LinkedIn 登录）
opencli linkedin search "Go backend engineer remote" --limit 20

# 找目标公司员工
opencli linkedin search-people "software engineer at DoorDash Toronto" --limit 10

# 评分 + 触达
./scripts/prospect.sh search "software engineer at DoorDash" --limit 20
./scripts/prospect.sh scan
```

在 Claude Code 中激活：`/linkedin-job-hunt`

---

## Contributing

见 [CONTRIBUTING.md](CONTRIBUTING.md)。最有价值的贡献：

- 酒店业以外的行业分级字典
- 新评分维度 + 方法论文档
- 新 adapter（LinkedIn 我们还没覆盖的操作）

---

## License

MIT. 见 [LICENSE](LICENSE).
