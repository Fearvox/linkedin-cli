<div align="center">

**English** | [中文](README-zh.md)

# linkedin-cli

**Full LinkedIn automation from your terminal — search, score, connect, message.**

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

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Prospect Pipeline](#prospect-pipeline)
- [Scoring Engine](#scoring-engine)
- [Message Templates](#message-templates)
- [Architecture](#architecture)
- [Algorithm Decisions](#algorithm-decisions)
- [Safety and Rate Limiting](#safety-and-rate-limiting)
- [Job Hunt Mode](#job-hunt-mode)
- [Testing](#testing)
- [Contributing](#contributing)
- [Security and Responsible Use](#security-and-responsible-use)
- [License](#license)

---

## Overview

Every B2B team does LinkedIn outreach. Most do it by hand — copy names into messages, tab between browser and spreadsheet, forget who got contacted last week. Apollo.io and Lemlist solve pieces of this. Neither gives you a terminal, a scoring engine, or full control over the data.

linkedin-cli turns that into a pipeline. 11 YAML adapters cover every LinkedIn action. A Python/Bash scoring engine classifies leads into tiers with a gated cascade. A human review gate ensures nothing sends without your approval. All data stays local in JSONL. All logic is yours to tune.

`Search → Score → Review → Connect → Message`

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Quick Start

```bash
git clone https://github.com/Fearvox/linkedin-cli.git
cd linkedin-cli
./install.sh
```

**Prerequisites:**

1. [opencli](https://github.com/jackwener/opencli) v1.6.8+ on your `$PATH`
2. Chrome with the opencli Browser Bridge extension loaded
3. Signed into LinkedIn in that Chrome profile
4. Python 3.10+, Bash 5.0+

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Commands

All adapters run via `opencli linkedin <command>`. Every write command supports `--dry-run`.

| Command | Type | Description |
|---------|------|-------------|
| `profile <url>` | Read | Fetch headline, about, experience, connections, company |
| `search-people <query>` | Read | Keyword search with network degree filter |
| `connections` | Read | List your 1st-degree connections |
| `inbox` | Read | Recent conversations |
| `notifications` | Read | Recent notifications |
| `post <text>` | Write | Publish a text post |
| `like <url>` | Write | Like a post |
| `comment <url> --text "..."` | Write | Comment on a post (supports `--reply-to` for threads) |
| `repost <url>` | Write | Repost with optional commentary |
| `connect <url> --note "..."` | Write | Send connection request with personalized note |
| `send-dm <profile> --text "..."` | Write | Direct message a connection |

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Prospect Pipeline

Eight subcommands orchestrated through a single script.

```bash
# 1. Search — pull candidates by keyword, dedup, pre-filter
./scripts/prospect.sh search "hotel revenue manager" --limit 20

# 2. Scan — enrich with full profile data + 3-stage scoring
./scripts/prospect.sh scan

# 3. Review — interactive human-in-the-loop approval (y/n/s/q)
./scripts/prospect.sh review

# 4. Outreach — send DMs to approved leads with template substitution
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run

# 5. Connect — send connection requests with tier-specific notes
./scripts/prospect.sh connect --tier a --dry-run

# 6. Monitor — check accepted connection requests
./scripts/prospect.sh monitor --auto-outreach

# 7. Template — render tier-specific connection note with variable substitution
./scripts/prospect.sh template --tier b --first_name "Sarah" --company "Hilton"

# 8. Batch — run preset keyword groups (Tier A/B search queries)
./scripts/prospect.sh batch
```

| Subcommand | Description |
|------------|-------------|
| `search` | Pull candidates by keyword, dedup against existing leads, pre-filter |
| `scan` | Enrich each lead with full profile data, run 3-stage scoring cascade |
| `review` | Interactive approval — `y` approve, `n` reject, `s` skip, `q` quit |
| `outreach` | Send DMs to approved leads using template with `{{variable}}` substitution |
| `connect` | Send connection requests with tier-specific notes (supports `--tier a\|b\|c`) |
| `monitor` | Check accepted connection requests (supports `--auto-outreach`) |
| `template` | Render a tier-specific connection note with variable substitution |
| `batch` | Run preset keyword groups for Tier A/B search queries |

Leads persist in `data/leads.jsonl`. Dedup is built in. Drop `--dry-run` when ready to send.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Scoring Engine

Three-stage gated cascade. Fail any gate, get dropped.

### Stage 1: Quality Gate

Six signals filter noise before semantic scoring:

- Headline too short (<20 chars = incomplete profile)
- ALL CAPS ratio >70% (job seekers, freelancers)
- Job-seeker phrases ("looking for", "open to", "in transition")
- No "at Company" or "|" pattern (low-info headline)
- About section missing or thin
- Experience section empty

### Stage 2: Industry Gate

Must match at least one keyword:

- **Core:** `hotel`, `hospitality`, `ota`, `resort`, `lodging`
- **Adjacent:** `cashback`, `reconciliation`, `revenue`, `booking`, `travel agency`

Zero matches = Tier D, skipped.

### Stage 3: Multi-Axis Score

Five dimensions scored independently:

| Axis | Range | How it works |
|------|-------|--------------|
| Authority | 0–25 | `seniority(0-5) × company_tier(0-5)`. 50+ brands in the tier dict (Hilton=5, Millennium=3, generic=1) |
| Relevance | 0–5 | Industry keyword depth (core matches count double) |
| Proximity | 0–5 | Shared connections with your Tier-1 network |
| Activity | 0–3 | Connection count 500+ and recent posts |
| Resonance | 0–3 | Shared background signals (school, discipline, tools) |

Tier classification uses the 2D space of (Authority, Relevance), not an additive total:

- **Tier A** — authority >= 12 AND relevance >= 3 (decision-maker at a major brand)
- **Tier B** — authority >= 6 OR strong relevance + network access
- **Tier C** — in the industry, low authority
- **Tier D** — failed a gate or low on all axes

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Message Templates

Six templates with `{{variable}}` substitution (`first_name`, `company`, `mutual_connection`, `topic`):

| Template | Path | When to use |
|----------|------|-------------|
| Tier A — Crossover | `templates/connect/tier-a-crossover.txt` | Shared background (same school, same field) |
| Tier B — Product | `templates/connect/tier-b-product.txt` | Mutual connection as intro context |
| Tier C — Leverage | `templates/connect/tier-c-leverage.txt` | They engaged with your content |
| HCO Intro | `templates/hco-intro.txt` | Cold B2B pitch to hotel operations decision-makers |
| HCO Traveler | `templates/hco-traveler.txt` | Personal cashback tool pitch for frequent travelers |
| Warm Reconnect | `templates/warm-reconnect.txt` | Re-engage a dormant 1st-degree connection |

Plain text files in `templates/`. Edit without touching pipeline code.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Architecture

```
linkedin-cli/
├── adapters/                  # 11 YAML adapters (opencli format)
│   ├── profile.yaml           # Read: full profile scrape
│   ├── search-people.yaml     # Read: Voyager API + DOM fallback
│   ├── connections.yaml       # Read: 1st-degree list
│   ├── inbox.yaml             # Read: conversations
│   ├── notifications.yaml     # Read: notification feed
│   ├── post.yaml              # Write: create post
│   ├── like.yaml              # Write: like post
│   ├── comment.yaml           # Write: comment (+ thread replies)
│   ├── repost.yaml            # Write: repost
│   ├── connect.yaml           # Write: connection request
│   └── send-dm.yaml           # Write: direct message
├── scripts/
│   └── prospect.sh            # Pipeline orchestrator (~1300 lines)
├── templates/
│   ├── connect/               # Tier-specific connection notes
│   │   ├── tier-a-crossover.txt
│   │   ├── tier-b-product.txt
│   │   └── tier-c-leverage.txt
│   ├── hco-intro.txt          # B2B cold pitch
│   ├── hco-traveler.txt       # Cashback tool pitch for travelers
│   └── warm-reconnect.txt     # Existing connection re-engage
├── .algo-profile/             # Persistent algorithm decisions
├── data/                      # leads.jsonl (gitignored)
├── tests/
│   └── test-all.sh            # 13 smoke tests
├── docs/
│   ├── job-hunt-2026-04-08.md # Job hunt integration report
│   └── reports/               # Generated benchmark reports
├── install.sh                 # Symlink adapters to ~/.opencli/
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md
```

**Adapter system:** Each YAML adapter defines a single LinkedIn action — selectors, API endpoints, input parameters, and output schema. `opencli` loads them and drives Playwright to execute against a live browser session.

**Pipeline flow:** `prospect.sh` orchestrates the full cycle. Search populates `data/leads.jsonl`, scan enriches each record with profile data and scores, review adds human approval flags, and outreach/connect sends messages to approved leads only.

**Data format:** All lead data is stored as newline-delimited JSON (JSONL). One record per lead, updated in place as the pipeline progresses. Fields include profile URL, headline, about, experience, scores, tier, and approval status.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Algorithm Decisions

The `.algo-profile/` directory persists every non-trivial algorithmic decision across sessions. See [.algo-profile/README.md](.algo-profile/README.md) for the full log.

The scoring engine has been through two major iterations. It started as a flat additive model (7 dimensions, sum to total, recommend if >= 10). Real outreach data exposed the flaw: 8 weak signals stacking to the same score as one strong signal. The current gated cascade was the fix.

The quality gate evolved from a single `len(headline) < 20` check to a 6-signal composite after the first batch surfaced ALL CAPS job seekers and incomplete profiles passing through.

Company tier dictionary, keyword lists, and tier thresholds are all tunable. Feed reply rates back in, adjust weights, re-score.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Safety and Rate Limiting

- **3-second delay** between API calls, max 20 per batch
- **`--dry-run` flag** on every write command — required before any live operation
- **No credential storage** — auth via browser session only, no passwords or tokens
- **Human review gate is mandatory** — nothing sends without your explicit approval
- **Templates are professional** — personalized, 3–7 lines each

Use this for targeted outreach with real intent. Bulk abuse will get your account flagged and defeats the scoring engine's purpose.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Job Hunt Mode

The prospect pipeline integrates with grunk's job-hunt pipeline for end-to-end job search and referral outreach. See [docs/job-hunt-2026-04-08.md](docs/job-hunt-2026-04-08.md) for the full research report and workflow.

```bash
# Research jobs (public, no login required)
opencli linkedin search "Go backend engineer remote" --limit 20

# Find employees at target company for referrals
opencli linkedin search-people "software engineer at DoorDash Toronto" --limit 10

# Score and outreach via prospect pipeline
./scripts/prospect.sh search "software engineer at DoorDash" --limit 20
./scripts/prospect.sh scan
```

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Testing

```bash
./tests/test-all.sh
```

Runs 13 smoke tests covering adapter loading, pipeline subcommands, template rendering, and data format validation.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Highest-value contributions:

- Industry tier dictionaries beyond hospitality
- New scoring dimensions with documented methodology
- New adapter commands for LinkedIn actions not yet covered

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## Security and Responsible Use

See [SECURITY.md](SECURITY.md) for vulnerability reporting and responsible use guidelines.

This tool interacts with a live LinkedIn session. It does not store credentials, does not bypass authentication, and enforces rate limits and human review gates by design. You are responsible for compliance with LinkedIn's Terms of Service.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>

---

## License

**CC BY-NC-ND 4.0** — see [LICENSE](LICENSE).

This means:
- **No commercial use** — you may not use this project for commercial purposes
- **No derivatives** — you may not distribute modified versions
- **Attribution required** — you must give appropriate credit

Copyright (c) Nolan Zhu.

<p align="right"><a href="#linkedin-cli">Back to top ↑</a></p>
