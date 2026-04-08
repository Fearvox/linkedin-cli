<div align="center">

**English** | [中文](README-zh.md)

# linkedin-cli

**Full LinkedIn automation from your terminal — search, score, connect, message.**

![opencli](https://img.shields.io/badge/opencli-v1.6.8+-blue) ![Playwright](https://img.shields.io/badge/Playwright-Browser%20Automation-2ea44f) ![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white) ![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-7C3AED) ![License](https://img.shields.io/badge/License-MIT-brightgreen) [![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa?style=flat-square&logo=github-sponsors)](https://github.com/sponsors/Synslius)

</div>

---

Every B2B team does LinkedIn outreach. Most do it by hand. Copy names into messages, tab between browser and spreadsheet, forget who got contacted last week. Apollo.io and Lemlist solve pieces of this. Neither gives you a terminal, a scoring engine, or full control over the data.

linkedin-cli turns that into a pipeline. 11 YAML adapters for every LinkedIn action. A Python/Bash scoring engine that classifies leads into tiers. A human review gate before anything goes out. The data stays local. The logic is yours to tune.

`Search → Score → Review → Connect → Message`

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

---

## Commands

All adapters run via `opencli linkedin <command>`. Every write command supports `--dry-run`.

| Command | Type | What it does |
|---|---|---|
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

---

## Prospect Pipeline

Four stages, one script.

```bash
# 1. Search — pull candidates matching a target persona
./scripts/prospect.sh search "hotel revenue manager" --limit 20

# 2. Score — run the gated cascade over every unscored lead
./scripts/prospect.sh scan

# 3. Review — human-in-the-loop: approve, skip, or flag each lead
./scripts/prospect.sh review

# 4. Outreach — send connection requests from approved leads
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run
```

Leads persist in `data/leads.jsonl`. Dedup is built in. Drop `--dry-run` when ready to send.

---

## Scoring Engine

Three-stage gated cascade. Fail any gate, get dropped.

**Stage 1: Quality Gate** — 6 signals filter noise before semantic scoring:

- Headline too short (<20 chars = incomplete profile)
- ALL CAPS ratio >70% (job seekers, freelancers)
- Job-seeker phrases ("looking for", "open to", "in transition")
- No "at Company" or "|" pattern (low-info headline)
- About section missing or thin
- Experience section empty

**Stage 2: Industry Gate** — must match at least one keyword:

- Core: `hotel`, `hospitality`, `ota`, `resort`, `lodging`
- Adjacent: `cashback`, `reconciliation`, `revenue`, `booking`, `travel agency`

Zero matches = Tier D, skipped.

**Stage 3: Multi-Axis Score** — 5 dimensions:

| Axis | Range | How it works |
|------|-------|-------------|
| Authority | 0-25 | `seniority(0-5) * company_tier(0-5)`. 50+ brands in the tier dict (Hilton=5, Millennium=3, generic=1) |
| Relevance | 0-5 | Industry keyword depth (core matches count double) |
| Proximity | 0-5 | Shared connections with your Tier-1 network |
| Activity | 0-3 | Connection count 500+ and recent posts |
| Resonance | 0-3 | Shared background signals (school, discipline, tools) |

Tier classification uses the 2D space of (Authority, Relevance), not an additive total:

- **A** — authority >= 12 AND relevance >= 3 (decision-maker at a major brand)
- **B** — authority >= 6 OR strong relevance + network access
- **C** — in the industry, low authority
- **D** — failed a gate or low on all axes

---

## Message Templates

5 templates with `{{variable}}` substitution (first_name, company, mutual_connection, topic):

| Template | When to use |
|---|---|
| `tier-a-crossover.txt` | Shared background (same school, same field) |
| `tier-b-product.txt` | Mutual connection as intro context |
| `tier-c-leverage.txt` | They engaged with your content |
| `hco-intro.txt` | Cold B2B pitch to hotel operations decision-makers |
| `warm-reconnect.txt` | Re-engage a dormant 1st-degree connection |

Plain text files in `templates/`. Edit without touching pipeline code.

---

## Self-Evolution

`.algo-profile/` persists every non-trivial algorithmic decision across sessions.

The scoring engine has been through two major iterations. It started as a flat additive model (7 dimensions, sum to total, if >= 10 then recommended). Real outreach data showed the problem: 8 weak signals stacking to the same score as one strong signal. The current gated cascade was the fix. Quality gate evolved from a single `len(headline) < 20` check to a 6-signal composite after the first batch surfaced ALL CAPS job seekers and incomplete profiles passing through.

Company tier dictionary, keyword lists, tier thresholds — all tunable. Feed reply rates back in, adjust weights, re-score.

---

## Safety

- 3-second delay between API calls, max 20 per batch
- `--dry-run` required before any live write operation
- Auth via browser session only — no passwords or tokens stored
- Templates are professional, personalized, 3-7 lines each
- Human review gate is mandatory — nothing sends without your approval

Use this for targeted outreach with real intent. Bulk abuse will get your account flagged and defeats the scoring engine's purpose.

---

## Project Structure

```
linkedin-cli/
├── adapters/               # 11 YAML adapters (opencli format)
│   ├── profile.yaml        # Read: full profile scrape
│   ├── search-people.yaml  # Read: Voyager API + DOM fallback
│   ├── connections.yaml    # Read: 1st-degree list
│   ├── inbox.yaml          # Read: conversations
│   ├── notifications.yaml  # Read: notification feed
│   ├── post.yaml           # Write: create post
│   ├── like.yaml           # Write: like post
│   ├── comment.yaml        # Write: comment (+ thread replies)
│   ├── repost.yaml         # Write: repost
│   ├── connect.yaml        # Write: connection request
│   └── send-dm.yaml        # Write: direct message
├── scripts/
│   └── prospect.sh         # Pipeline orchestrator (~1300 lines)
├── templates/
│   ├── connect/             # Tier-specific connection notes
│   ├── hco-intro.txt        # B2B cold pitch
│   └── warm-reconnect.txt   # Existing connection re-engage
├── .algo-profile/           # Persistent algorithm decisions
├── data/                    # leads.jsonl (gitignored)
├── tests/
│   └── test-all.sh          # Smoke tests
├── docs/reports/            # Generated benchmark reports
├── install.sh               # Symlink adapters to ~/.opencli/
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Highest-value contributions:

- Industry tier dictionaries beyond hospitality
- New scoring dimensions with documented methodology
- New adapter commands for LinkedIn actions we don't cover yet

---

## License

MIT. See [LICENSE](LICENSE).
