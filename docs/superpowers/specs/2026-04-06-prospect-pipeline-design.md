# LinkedIn CLI Prospect Pipeline — Design Spec

**Date:** 2026-04-06
**Status:** Approved
**Goal:** Transform linkedin-cli from a collection of standalone adapters into a semi-automated prospecting pipeline for Dash/HCO customer acquisition.

## Context

linkedin-cli currently has 7 YAML adapters (profile, post, like, comment, repost, send-dm, inbox) that provide full LinkedIn read+write capability via opencli's Browser Bridge. The next step is to wire these into a prospecting pipeline that:

1. **Finds potential HCO customers** on LinkedIn (89% weight — precision outreach)
2. **Supports content posting** for brand presence (11% weight — deferred to P2)
3. **Optimizes personal profile** (deferred to P2)

### Target Personas

**B2B:**
- OTA / travel agency operations managers (cashback promotion, hotel reconciliation)
- Hotel group revenue management / finance staff
- Capricorn-type intermediaries (cashback distribution, manual Excel reconciliation)

**B2C:**
- High-frequency business travelers who could use a personal version of HCO to track cashback flows (identified via LinkedIn profile social engineering — role, travel keywords, seniority)

### Workflow

Semi-automated pipeline: CLI handles batch search → profile scan → scoring → candidate list generation. Human reviews and approves before any outreach is executed.

---

## Architecture

```
linkedin-cli/
├── adapters/                    # opencli YAML adapters (existing + new)
│   ├── profile.yaml             # ENHANCED: add industry/travel signals
│   ├── post.yaml                # existing
│   ├── like.yaml                # existing
│   ├── comment.yaml             # existing
│   ├── repost.yaml              # existing
│   ├── send-dm.yaml             # ENHANCED: add --template flag
│   ├── inbox.yaml               # existing (needs commit)
│   ├── search-people.yaml       # NEW: people search by keyword/industry/location
│   └── connections.yaml         # NEW: list own connections
├── scripts/
│   └── prospect.sh              # Pipeline orchestrator (4 subcommands)
├── templates/
│   ├── hco-intro.txt            # B2B outreach template
│   ├── hco-traveler.txt         # B2C high-frequency traveler template
│   └── warm-reconnect.txt       # Warm reconnect for existing connections
├── data/
│   └── leads.jsonl              # Persistent lead tracking (append-only)
├── tests/
│   └── test-all.sh              # Smoke tests (existing, extend)
├── install.sh                   # Symlink installer (existing)
├── PLAN.md                      # Implementation plan (existing)
└── README.md                    # Usage docs (existing, update)
```

---

## Component Design

### 1. New Adapter: `search-people.yaml`

**Priority:** P0 — pipeline entry point.

Searches LinkedIn for people by keywords, using the Voyager search API (`/voyager/api/search/dash/clusters`).

**Args:**
- `query` (positional, required) — search keywords (e.g., "hotel revenue manager")
- `--location` — geographic filter
- `--limit` — max results (default: 20)

**Output columns:** `rank, name, vanity, headline, location, profile_url`

**Implementation note:** LinkedIn's people search uses a different Voyager endpoint than job search. The adapter navigates to LinkedIn search page, then calls the Voyager cluster search API with `origin=GLOBAL_SEARCH_HEADER` and `type=PEOPLE`.

### 2. New Adapter: `connections.yaml`

**Priority:** P1 — warm lead pool.

Lists the user's own connections via Voyager API.

**Args:**
- `--limit` — max results (default: 50)
- `--query` — filter by name/keyword

**Output columns:** `rank, name, vanity, headline, connected_at, profile_url`

### 3. Enhanced: `profile.yaml`

**New fields to extract:**

| Field | Source | Purpose |
|-------|--------|---------|
| `industry` | Page meta / about section keywords | Industry scoring |
| `current_company` | Experience section (first/current entry) | Lead qualification |
| `post_count` | Activity section count | Engagement signal |
| `travel_signals` | Keywords in about/experience: travel, 出差, frequent flyer, 差旅, business travel | B2C qualification |

### 4. Enhanced: `send-dm.yaml`

**New flag:** `--template <path>`

When provided, reads the template file and substitutes `{{variable}}` placeholders with values from `--vars` JSON argument:

```bash
opencli linkedin send-dm "johndoe" \
  --template templates/hco-intro.txt \
  --vars '{"first_name":"John","company":"Marriott"}' \
  --dry-run
```

If `--text` is also provided, `--text` takes precedence (backward compatible).

### 5. Pipeline Orchestrator: `scripts/prospect.sh`

Single bash script with 4 subcommands:

#### `prospect.sh search <query> [--location X] [--limit N]`

1. Calls `opencli linkedin search-people <query> --format json`
2. Parses JSON output
3. For each result, creates a lead entry with `status=new`
4. Appends to `data/leads.jsonl`
5. Deduplicates by `vanity` (skips if already exists)
6. Reports: "Added N new leads, skipped M duplicates"

#### `prospect.sh scan`

1. Reads `data/leads.jsonl`, filters `status=new`
2. For each lead:
   - Calls `opencli linkedin profile <url> --format json`
   - Extracts scoring signals
   - Computes `industry_score`, `travel_score`, `total_score`
   - Updates status to `scanned`
3. Rewrites the lead's line in `leads.jsonl`
4. Rate limiting: 3-second delay between profile fetches
5. Reports: "Scanned N leads, avg score: X"

**Scoring matrix:**

| Signal | Points | Detection |
|--------|--------|-----------|
| Industry keyword match (hotel, OTA, cashback, reconciliation, revenue) | +3 per keyword | headline, about, experience |
| Seniority (Manager) | +2 | headline |
| Seniority (Director) | +3 | headline |
| Seniority (VP/C-level) | +4 | headline |
| Travel keyword match (travel, 出差, frequent flyer, 差旅) | +2 per keyword | about, experience |
| 500+ connections | +1 | connections field |
| Recently active (has posts) | +1 | post_count > 0 |

Score ≥ 10 → marked `recommended` in notes field.

#### `prospect.sh review`

1. Reads `data/leads.jsonl`, filters `status=scanned`
2. Sorts by `total_score` descending
3. For each lead, displays:
   ```
   [1/15] John Doe | Revenue Manager @ Marriott | score:14 ★
   Headline: Revenue Management & Cashback Operations
   Travel signals: frequent business travel, hotel partnerships
   ─────────────────────────────────
   [y] approve  [n] skip  [s] star for later  [q] quit
   ```
4. Updates status: `approved`, `skipped`, or keeps `scanned` (for `s`)

#### `prospect.sh outreach --template <path> [--dry-run] [--batch N]`

1. Reads `data/leads.jsonl`, filters `status=approved`
2. For each lead:
   - Reads template file
   - Substitutes variables from lead data
   - If `--dry-run`: prints the composed message, does NOT send
   - If not dry-run: calls `opencli linkedin send-dm`
   - Updates status to `contacted`, sets `contacted_at`
3. **Safety gates:**
   - First run MUST be `--dry-run` (script checks if any approved leads have been dry-run previewed)
   - `--batch` defaults to 20, max 20 per run
   - 10-second delay between sends
4. Reports: "Sent N messages, M remaining"

### 6. leads.jsonl Schema

```json
{
  "id": "a1b2c3",
  "vanity": "johndoe",
  "profile_url": "https://linkedin.com/in/johndoe",
  "name": "John Doe",
  "headline": "Revenue Manager @ Marriott",
  "company": "Marriott",
  "industry_score": 8,
  "travel_score": 6,
  "total_score": 14,
  "status": "new",
  "dm_template": "",
  "dm_preview": "",
  "contacted_at": "",
  "notes": "",
  "search_query": "hotel cashback operations",
  "created_at": "2026-04-06T23:00:00Z"
}
```

**Status lifecycle:** `new` → `scanned` → `approved`/`skipped` → `contacted` → `replied` (manual)

**Storage format:** JSONL (one JSON object per line). Append-only for new entries; in-place update for status changes via temp file + mv.

### 7. DM Templates

Plain text files with `{{variable}}` placeholders.

**`templates/hco-intro.txt`:**
```
Hi {{first_name}},

I noticed you're working in hotel operations at {{company}}. We've built a system that automates cashback reconciliation — replacing the Excel spreadsheets with an auditable, tamper-proof workflow.

It handles the messy parts: name mismatches across booking systems, split reservations, and reused confirmation numbers.

Would love to share a quick demo if this is relevant to your team. No pressure either way.

Best,
Nolan
```

**`templates/hco-traveler.txt`:**
```
Hi {{first_name}},

Given your role at {{company}}, I imagine you deal with hotel bookings and cashback programs regularly. We're exploring a personal tool that tracks cashback flows across bookings — so you always know what's been claimed vs. what's actually returned.

Still early stage, but would value your perspective as someone who lives this daily. Open to a quick chat?

Nolan
```

**`templates/warm-reconnect.txt`:**
```
Hi {{first_name}},

It's been a while — hope things are going well at {{company}}. I've been building tools for hotel operations teams lately and thought of you.

Would love to catch up briefly if you're open to it.

Nolan
```

---

## What's NOT in Scope

- **notifications.yaml** — P2, not needed for prospecting pipeline
- **Profile optimization** — P2, read own profile + generate suggestions
- **Content posting automation** — P2, scheduled posting / content calendar
- **Full CRM** — leads.jsonl is intentionally minimal; if it outgrows JSONL, migrate to SQLite later
- **LinkedIn Sales Navigator integration** — requires separate subscription, out of scope

---

## Success Criteria

1. `prospect.sh search "hotel revenue manager"` returns ≥10 results and writes to leads.jsonl
2. `prospect.sh scan` enriches leads with scores, avg score reflects industry relevance
3. `prospect.sh review` displays candidates sorted by score with interactive y/n/s
4. `prospect.sh outreach --dry-run` shows personalized DM previews with correct variable substitution
5. `prospect.sh outreach` sends DMs with 10s rate limiting and updates lead status
6. All existing adapters continue to work (backward compatible)
7. `test-all.sh` passes with new adapters included

---

## Implementation Order

1. Commit `inbox.yaml` (already built, just untracked)
2. Build `search-people.yaml` (P0 — pipeline entry)
3. Enhance `profile.yaml` (new scoring fields)
4. Build `connections.yaml`
5. Build `scripts/prospect.sh` (search + scan + review + outreach)
6. Create DM templates
7. Enhance `send-dm.yaml` (--template flag)
8. Update `test-all.sh`
9. Update `README.md`
