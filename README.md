<div align="center">

**English** | [中文](README-zh.md)

# linkedin-cli

**Full LinkedIn automation from your terminal — search, score, connect, message.**

![opencli](https://img.shields.io/badge/opencli-v1.6.8+-blue) ![Playwright](https://img.shields.io/badge/Playwright-Browser%20Automation-2ea44f) ![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white) ![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-7C3AED) ![License](https://img.shields.io/badge/License-MIT-brightgreen)

</div>

---

Every B2B team does LinkedIn outreach. Most do it by hand — copy-pasting names into messages, tabbing between spreadsheets and browser tabs, losing track of who was contacted two weeks ago. It is slow, inconsistent, and impossible to iterate on. Apollo.io solves part of this. Lemlist solves another part. Neither gives you a terminal, a scoring engine, or full control over the data.

linkedin-cli turns that into a pipeline. It is a full LinkedIn automation toolkit built on opencli YAML adapters and a Python/Bash prospect engine. Every stage — search, score, human review, connect, message — runs from a single script. The data stays on your machine. The logic is transparent and tunable.

The flow is: `Search → Score → Review → Connect → Message`. You define the target persona once. The pipeline finds candidates, scores them against a multi-axis classifier, surfaces the top tier for your review, and sends personalized outreach — with a dry-run gate before anything touches a real inbox.

---

## Quick Start

```bash
git clone https://github.com/yourhandle/linkedin-cli && cd linkedin-cli && ./install.sh
```

**Prerequisites:**

1. [opencli](https://github.com/jackwener/opencli) v1.6.8+ installed and on your `$PATH`
2. Chrome with the opencli Browser Bridge extension installed and active
3. An active LinkedIn session in that Chrome profile

---

## Commands

All adapters run via `opencli linkedin <command>`. Write commands accept `--dry-run`.

| Command | Type | Description |
|---|---|---|
| `profile <url>` | Read | Fetch a LinkedIn profile by URL |
| `search-people <query>` | Read | Search LinkedIn people with filters |
| `connections` | Read | List your connections with metadata |
| `inbox` | Read | Read LinkedIn messages |
| `notifications` | Read | Read LinkedIn notifications |
| `post <text>` | Write | Create a LinkedIn post |
| `like <url>` | Write | Like a post by URL |
| `comment <url> --text "..."` | Write | Comment on a post |
| `repost <url>` | Write | Repost with optional commentary |
| `connect <url> --note "..."` | Write | Send a connection request with a note |
| `send-dm <profile> --text "..."` | Write | Send a direct message to a connection |

---

## Prospect Pipeline

The core of linkedin-cli. Four stages, one script.

**Stage 1 — Search.** Pull candidate profiles for a target persona.

```bash
./scripts/prospect.sh search "hotel revenue manager"
```

Results land in `data/leads.jsonl`. Duplicate detection is built in.

**Stage 2 — Score.** Run the scoring engine over every unscored lead.

```bash
./scripts/prospect.sh scan
```

Each lead gets a Tier A/B/C/D label and a structured score breakdown written back to the JSONL.

**Stage 3 — Review.** Human-in-the-loop checkpoint.

```bash
./scripts/prospect.sh review
```

Surfaces Tier A and B leads with score rationale. You approve, skip, or flag each one. No lead gets outreach without passing this gate.

**Stage 4 — Outreach.** Send connection requests or DMs from approved leads.

```bash
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run
```

Drop `--dry-run` when you are ready to send. The script logs every action and respects rate limits automatically.

---

## Scoring Engine

The scoring engine is a three-stage gated cascade. A lead must pass each gate in sequence — failing early terminates scoring without wasting cycles on the later stages.

**Stage 1 — Quality Gate.** Six composite signals that filter noise before any semantic scoring runs:

- Headline length below threshold (incomplete profiles)
- ALL CAPS headline (low-signal accounts)
- Job-seeker phrases ("open to work", "seeking opportunities")
- Missing profile photo
- Connection count below floor
- Headline keyword density below minimum

**Stage 2 — Industry Gate.** Keyword matching against a two-tier dictionary: core terms (direct match to target industry) and adjacent terms (related roles worth scoring). Leads with zero keyword hits are dropped.

**Stage 3 — Multi-Axis Score.** Five dimensions, weighted and combined:

- **Authority** — seniority level crossed with company tier (50+ hotel brands in the tier dictionary, expandable)
- **Relevance** — keyword density and title alignment
- **Proximity** — shared connections, schools, or geography
- **Activity** — recent posting frequency and engagement signals
- **Resonance** — content overlap with your defined target themes

Final score maps to Tier A (top 10%), B (next 20%), C (middle), or D (disqualified). Only A and B surface in the review stage.

---

## Message Templates

Five templates with `{{variable}}` substitution. The pipeline injects first name, company, title, and a personalization hook pulled from their profile.

| Template | Use case |
|---|---|
| `tier-a-crossover.txt` | Shared background or overlapping career history |
| `tier-b-product.txt` | Mutual connection intro with product context |
| `tier-c-leverage.txt` | Lead engaged with your content |
| `hco-intro.txt` | B2B product pitch to hospitality decision-makers |
| `warm-reconnect.txt` | Re-engaging an existing but dormant connection |

Every template is plain text. Edit them without touching the pipeline code.

---

## Self-Evolution

linkedin-cli is designed to improve from real outreach data. The `.algo-profile/` directory persists algorithmic decisions and changelog entries across sessions.

The scoring engine has already gone through two major iterations: from a flat additive 7-dimension model to the current gated cascade (which eliminated false positives from job-seeker accounts and incomplete profiles). The quality gate evolved from a single `len(headline) < 20` check to a 6-signal composite classifier after the first batch of scored leads surfaced systematic noise.

All thresholds — quality gate cutoffs, tier dictionary contents, dimension weights — are defined in plain configuration. Feed your reply rates back in, adjust the weights, re-score the backlog.

---

## Safety and Ethics

linkedin-cli is built for legitimate B2B outreach. It is not a spam tool.

- Rate limiting: 3 seconds between API calls, maximum 20 actions per batch
- `--dry-run` gate required on all write operations before live execution
- No credential storage: all auth runs through your existing browser session
- Templates are personalized and relationship-oriented, not broadcast messages
- Human review stage is mandatory — no automated outreach without approval

LinkedIn's terms of service prohibit automated scraping and bulk messaging. Use this tool for targeted, high-signal outreach with genuine intent to start a professional relationship. Volume abuse defeats the purpose of the scoring engine and will get your account flagged.

---

## Project Structure

```
linkedin-cli/
├── adapters/           # 11 YAML adapters (opencli interface)
├── scripts/            # prospect.sh pipeline (~1300 lines)
├── templates/          # 5 message templates
├── .algo-profile/      # Algorithm decision archive
├── data/               # leads.jsonl (gitignored)
├── tests/              # Smoke tests
├── install.sh          # Symlink installer
└── README.md
```

---

## Contributing

Issues and PRs are open. The highest-value contributions are:

- New industry tier dictionaries (currently optimized for hospitality)
- Additional scoring dimensions with documented methodology
- New adapter commands
- Replay-based test cases built from anonymized lead fixtures

---

## License

MIT. See `LICENSE`.
