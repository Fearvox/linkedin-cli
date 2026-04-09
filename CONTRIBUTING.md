# Contributing to linkedin-cli

<a name="top"></a>

> **Language / 语言**: English primary. 关键章节附中文翻译。
>
> See also: [README](README.md) · [SECURITY](SECURITY.md) · [LICENSE](LICENSE)

Thank you for your interest in improving linkedin-cli! This guide explains how to contribute adapters, scoring dimensions, message templates, and bug fixes.

感谢你对 linkedin-cli 的关注！本指南说明如何贡献适配器、评分维度、消息模板和错误修复。

---

## Code of Conduct / 行为准则

Be respectful, constructive, and professional. Harassment, spam, and off-topic self-promotion will not be tolerated. We are here to build useful tools together.

请保持尊重、建设性和专业态度。不容忍骚扰、垃圾信息和无关的自我推广。

---

## How to Contribute / 如何贡献

1. **Fork** this repository and clone your fork locally.
2. **Create a branch**: `git checkout -b feat/your-feature` or `fix/your-fix`.
3. **Make changes** following the guidelines below.
4. **Test** with `--dry-run` — never run live writes against LinkedIn during development.
5. **Commit** with clear, descriptive messages (e.g., `add adapter: glassdoor`).
6. **Open a Pull Request** against `main` with a summary of what changed and why.

Questions? Open a GitHub Discussion before starting large changes.

---

## Adding Adapters / 添加适配器

Place a YAML file in `adapters/` following the existing format.

**Required fields:**

| Field | Description |
|-------|-------------|
| `site` | Platform identifier (lowercase) |
| `name` | Human-readable adapter name |
| `description` | One-line summary of what the adapter does |
| `domain` | Target domain (e.g., `linkedin.com`) |
| `strategy` | Crawl/scrape strategy key |
| `browser` | Browser engine (`chromium`, `firefox`, etc.) |
| `args` | CLI arguments the adapter accepts |
| `columns` | Output columns for the pipeline |
| `pipeline` | Processing pipeline steps |

Always validate with `--dry-run` before submitting. Include dry-run output in your PR description.

---

## Adding Scoring Dimensions / 添加评分维度

Edit the Python heredoc in `scripts/prospect.sh` (scoring engine section).

- Each axis **must** be normalized to a **0–5** scale.
- If your new signal shifts the score distribution, update tier classification thresholds accordingly.
- Document the signal's rationale in your PR: what it measures and why it predicts fit.

每个评分轴必须归一化到 0–5 范围。如果新信号改变了分数分布，请同步更新分层阈值。

---

## Adding Message Templates / 添加消息模板

Place files in `templates/`. Supported `{{variable}}` tokens:

- `{{first_name}}` · `{{company}}` · `{{mutual_connection}}` · `{{topic}}`

**Rules:**
- Keep messages professional, specific, and non-generic.
- Hard limit: **3–7 lines** per template.
- No sales pitches or spammy language.

模板限制为 3–7 行，使用 `{{variable}}` 语法，保持专业和具体。

---

## PR Requirements / PR 要求

- [ ] Run all write operations with `--dry-run` and include output in the PR description.
- [ ] No credentials, tokens, or API keys anywhere in code or config.
- [ ] No `leads.jsonl`, personal data, or PII committed. See [SECURITY](SECURITY.md).
- [ ] Follow existing code style: Bash scripts with Python heredocs for logic.
- [ ] One logical change per PR — keep diffs focused and reviewable.

---

## Issue Guidelines / 提交 Issue 指南

Use the appropriate template when opening an issue:

- **Bug** — adapter name + exact command + expected vs. actual behavior.
- **Feature** — describe the LinkedIn action, proposed adapter or flag, and edge cases.
- **Scoring** — name the signal, explain why it predicts fit, suggest a weight (0–5).

---

## License Note / 许可证说明

This project is licensed under **CC BY-NC-ND 4.0**. By contributing, you agree that:

- Your contributions fall under the same [LICENSE](LICENSE).
- **No commercial use** of this project or derivatives is permitted.
- **No distribution of modified versions** — derivatives may not be redistributed.

See the full license at [LICENSE](LICENSE).

本项目采用 CC BY-NC-ND 4.0 许可证。贡献即表示同意相同条款：禁止商用，禁止分发修改版本。

---

<p align="right"><a href="#top">↑ Back to top / 回到顶部</a></p>
