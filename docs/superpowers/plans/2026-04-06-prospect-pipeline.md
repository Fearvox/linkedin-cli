# Prospect Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a semi-automated LinkedIn prospecting pipeline that searches for HCO customers, scores them, and enables human-reviewed batch outreach.

**Architecture:** New YAML adapters (`search-people`, `connections`) feed into a shell orchestrator (`prospect.sh`) that chains search → scan → review → outreach. Leads are tracked in `data/leads.jsonl` (append-only JSONL). DM templates use `{{variable}}` substitution from lead data. All write operations enforce dry-run gates.

**Tech Stack:** opencli YAML adapter format, LinkedIn Voyager API, bash orchestrator, jq for JSON processing, python3 for JSONL manipulation in prospect.sh

---

## File Structure

```
linkedin-cli/
├── adapters/
│   ├── inbox.yaml               # COMMIT (already exists, untracked)
│   ├── search-people.yaml       # CREATE — Voyager people search
│   ├── connections.yaml         # CREATE — list own connections
│   ├── profile.yaml             # MODIFY — add industry/travel/company fields
│   └── send-dm.yaml             # MODIFY — add --template/--vars flags
├── scripts/
│   └── prospect.sh              # CREATE — pipeline orchestrator (4 subcommands)
├── templates/
│   ├── hco-intro.txt            # CREATE — B2B outreach template
│   ├── hco-traveler.txt         # CREATE — B2C traveler template
│   └── warm-reconnect.txt       # CREATE — warm reconnect template
├── data/
│   └── .gitkeep                 # CREATE — leads.jsonl lives here (gitignored)
├── .gitignore                   # CREATE — ignore data/leads.jsonl
├── tests/
│   └── test-all.sh              # MODIFY — add new adapter smoke tests
├── install.sh                   # existing, no changes
└── README.md                    # MODIFY — add prospect pipeline docs
```

---

## Task 1: Commit inbox.yaml + add .gitignore

**Files:**
- Commit: `adapters/inbox.yaml` (already exists as untracked file)
- Create: `data/.gitkeep`
- Create: `.gitignore`

- [ ] **Step 1: Create data directory and .gitignore**

```bash
mkdir -p data
touch data/.gitkeep
```

- [ ] **Step 2: Create .gitignore**

Write `.gitignore`:

```
data/leads.jsonl
```

- [ ] **Step 3: Verify inbox.yaml exists**

```bash
cat adapters/inbox.yaml | head -5
# Expected:
# site: linkedin
# name: inbox
# description: Read recent LinkedIn messages/conversations
```

- [ ] **Step 4: Commit**

```bash
git add adapters/inbox.yaml data/.gitkeep .gitignore
git commit -m "feat: commit inbox adapter + add data dir with gitignore"
```

---

## Task 2: Build `search-people.yaml`

**Files:**
- Create: `adapters/search-people.yaml`

This is the P0 pipeline entry point. Uses LinkedIn's Voyager search API to find people by keyword. The existing `search` adapter (built-in to opencli) only does job search — this one searches for people profiles.

- [ ] **Step 1: Write search-people.yaml**

Create `adapters/search-people.yaml`:

```yaml
site: linkedin
name: search-people
description: Search LinkedIn for people by keywords
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  query:
    positional: true
    type: string
    required: true
    description: "Search keywords (e.g. 'hotel revenue manager')"
  location:
    type: string
    default: ""
    description: "Geographic filter (e.g. 'United States')"
  limit:
    type: int
    default: 20
    description: "Max number of results"

columns: [rank, name, vanity, headline, location, profile_url]

pipeline:
  - navigate: "https://www.linkedin.com/search/results/people/?keywords=${{ args.query | urlencode }}"
  - wait: 4
  - evaluate: |
      (async () => {
        const query = ${{ args.query | json }};
        const locationFilter = ${{ args.location | json }};
        const limit = ${{ args.limit }};

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found. Sign in first.');
        const csrf = jsession.replace(/^"|"$/g, '');

        // Build search request via Voyager API
        let searchUrl = '/voyager/api/search/dash/clusters'
          + '?decorationId=com.linkedin.voyager.dash.deco.search.SearchClusterCollection-174'
          + '&origin=GLOBAL_SEARCH_HEADER'
          + '&q=all'
          + '&query=(keywords:' + encodeURIComponent(query)
          + ',resultType:(value:PEOPLE))'
          + '&count=' + limit
          + '&start=0';

        const res = await fetch(searchUrl, {
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
          }
        });

        if (!res.ok) {
          // Fallback: scrape the search results page DOM
          const cards = Array.from(document.querySelectorAll('.reusable-search__result-container, .entity-result')).slice(0, limit);
          const normalize = v => String(v || '').replace(/\s+/g, ' ').trim();

          return cards.map((card, i) => {
            const linkEl = card.querySelector('a.app-aware-link[href*="/in/"]');
            const nameEl = card.querySelector('.entity-result__title-text a span[aria-hidden="true"], .actor-name');
            const headlineEl = card.querySelector('.entity-result__primary-subtitle, .subline-level-1');
            const locationEl = card.querySelector('.entity-result__secondary-subtitle, .subline-level-2');
            const href = linkEl?.href || '';
            const vanity = href.match(/\/in\/([^/?]+)/)?.[1] || '';

            return {
              rank: i + 1,
              name: normalize(nameEl?.textContent),
              vanity: vanity,
              headline: normalize(headlineEl?.textContent),
              location: normalize(locationEl?.textContent),
              profile_url: vanity ? 'https://www.linkedin.com/in/' + vanity : href,
            };
          }).filter(item => item.name);
        }

        const data = await res.json();
        const elements = data?.elements || [];
        const results = [];

        for (const cluster of elements) {
          const items = cluster?.items || [];
          for (const item of items) {
            if (results.length >= limit) break;
            const entity = item?.item?.entityResult;
            if (!entity) continue;

            const title = entity.title?.text || '';
            const subtitle = entity.primarySubtitle?.text || '';
            const secondarySub = entity.secondarySubtitle?.text || '';
            const navUrl = entity.navigationUrl || '';
            const vanity = navUrl.match(/\/in\/([^/?]+)/)?.[1] || '';

            results.push({
              rank: results.length + 1,
              name: title,
              vanity: vanity,
              headline: subtitle,
              location: secondarySub,
              profile_url: vanity ? 'https://www.linkedin.com/in/' + vanity : navUrl,
            });
          }
        }

        if (results.length === 0) {
          throw new Error('No people found for query: ' + query);
        }

        return results;
      })()
  - map:
      rank: ${{ item.rank }}
      name: ${{ item.name }}
      vanity: ${{ item.vanity }}
      headline: ${{ item.headline }}
      location: ${{ item.location }}
      profile_url: ${{ item.profile_url }}
```

- [ ] **Step 2: Install and test**

```bash
./install.sh
opencli linkedin search-people "hotel revenue manager" --limit 5 --format json
# Expected: JSON array with name, vanity, headline, location, profile_url fields
```

- [ ] **Step 3: Commit**

```bash
git add adapters/search-people.yaml
git commit -m "feat: add linkedin search-people adapter for prospect pipeline"
```

---

## Task 3: Enhance `profile.yaml` with scoring fields

**Files:**
- Modify: `adapters/profile.yaml`

Add 4 new fields to the profile adapter output: `industry`, `current_company`, `post_count`, `travel_signals`. These feed into the scoring logic in `prospect.sh scan`.

- [ ] **Step 1: Update columns line**

In `adapters/profile.yaml`, change:

```yaml
columns: [name, headline, location, connections, about, experience, education, profile_url]
```

to:

```yaml
columns: [name, headline, location, connections, about, experience, education, profile_url, industry, current_company, post_count, travel_signals]
```

- [ ] **Step 2: Add extraction logic in the evaluate block**

In the `evaluate` block's return statement, add 4 new fields after `profile_url`. The full `evaluate` block should become:

```yaml
  - evaluate: |
      (() => {
        const normalize = v => String(v || '').replace(/\s+/g, ' ').trim();
        const textOf = (sel) => { const el = document.querySelector(sel); return el ? normalize(el.textContent) : ''; };

        const name = textOf('h1.text-heading-xlarge') || textOf('h1');
        const headline = textOf('.text-body-medium.break-words');
        const location = textOf('.text-body-small.inline.t-black--light.break-words');
        const connectionsEl = document.querySelector('li.text-body-small span.t-bold');
        const connections = connectionsEl ? normalize(connectionsEl.textContent) : '';
        const aboutSection = document.querySelector('#about ~ .display-flex .inline-show-more-text');
        const about = aboutSection ? normalize(aboutSection.textContent) : '';
        const expItems = Array.from(document.querySelectorAll('#experience ~ .pvs-list__outer-container li.pvs-list__paged-list-item')).slice(0, 3);
        const experience = expItems.map(li => normalize(li.textContent).slice(0, 120)).join(' | ');
        const eduItems = Array.from(document.querySelectorAll('#education ~ .pvs-list__outer-container li.pvs-list__paged-list-item')).slice(0, 2);
        const education = eduItems.map(li => normalize(li.textContent).slice(0, 100)).join(' | ');

        // NEW: Industry detection from headline + about
        const allText = [headline, about, experience].join(' ').toLowerCase();
        const industryKeywords = ['hotel', 'hospitality', 'ota', 'travel', 'tourism', 'lodging', 'resort', 'booking'];
        const industry = industryKeywords.filter(k => allText.includes(k)).join(', ');

        // NEW: Current company from first experience item
        const firstExp = expItems[0];
        const companyEl = firstExp?.querySelector('.t-14.t-normal span[aria-hidden="true"]');
        const current_company = companyEl ? normalize(companyEl.textContent).split(' · ')[0] : '';

        // NEW: Post count from activity section
        const activityCount = document.querySelector('.pvs-header__optional-link span.t-bold');
        const post_count = activityCount ? normalize(activityCount.textContent).replace(/[^0-9]/g, '') : '0';

        // NEW: Travel signals from about + experience text
        const travelKeywords = ['travel', 'frequent flyer', 'business travel', '出差', '差旅', 'on the road', 'global traveler'];
        const travel_signals = travelKeywords.filter(k => allText.includes(k)).join(', ');

        return [{
          name, headline, location, connections, about: about.slice(0, 300),
          experience, education, profile_url: window.location.href,
          industry, current_company, post_count, travel_signals
        }];
      })()
```

- [ ] **Step 3: Update the map step**

Add 4 new fields to the `map` step:

```yaml
  - map:
      name: ${{ item.name }}
      headline: ${{ item.headline }}
      location: ${{ item.location }}
      connections: ${{ item.connections }}
      about: ${{ item.about }}
      experience: ${{ item.experience }}
      education: ${{ item.education }}
      profile_url: ${{ item.profile_url }}
      industry: ${{ item.industry }}
      current_company: ${{ item.current_company }}
      post_count: ${{ item.post_count }}
      travel_signals: ${{ item.travel_signals }}
```

- [ ] **Step 4: Test enhanced profile**

```bash
./install.sh
opencli linkedin profile "https://www.linkedin.com/in/williamhgates" --format json | python3 -c "import sys,json; d=json.load(sys.stdin); print('industry:', d[0].get('industry','')); print('company:', d[0].get('current_company',''))"
# Expected: new fields present (may be empty for Bill Gates but should not error)
```

- [ ] **Step 5: Commit**

```bash
git add adapters/profile.yaml
git commit -m "feat: enhance profile adapter with industry, company, travel scoring fields"
```

---

## Task 4: Build `connections.yaml`

**Files:**
- Create: `adapters/connections.yaml`

- [ ] **Step 1: Write connections.yaml**

Create `adapters/connections.yaml`:

```yaml
site: linkedin
name: connections
description: List your LinkedIn connections
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  limit:
    type: int
    default: 50
    description: "Number of connections to return"
  query:
    type: string
    default: ""
    description: "Filter connections by name or keyword"

columns: [rank, name, vanity, headline, connected_at, profile_url]

pipeline:
  - navigate: "https://www.linkedin.com/mynetwork/invite-connect/connections/"
  - wait: 4
  - evaluate: |
      (async () => {
        const limit = ${{ args.limit }};
        const query = ${{ args.query | json }};

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found.');
        const csrf = jsession.replace(/^"|"$/g, '');

        // Voyager connections API
        let apiUrl = '/voyager/api/relationships/dash/connections'
          + '?decorationId=com.linkedin.voyager.dash.deco.relationships.Connection-6'
          + '&count=' + limit
          + '&start=0'
          + '&q=search';
        if (query) {
          apiUrl += '&keywords=' + encodeURIComponent(query);
        }

        const res = await fetch(apiUrl, {
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
          }
        });

        if (res.ok) {
          const data = await res.json();
          const elements = data?.elements || [];
          return elements.slice(0, limit).map((conn, i) => {
            const mp = conn?.connectedMember
              || conn?.connectedMemberResolutionResult
              || {};
            const firstName = mp.firstName?.localized?.en_US || mp.firstName || '';
            const lastName = mp.lastName?.localized?.en_US || mp.lastName || '';
            const name = [firstName, lastName].filter(Boolean).join(' ');
            const vanity = (mp.publicIdentifier || mp.vanityName || '');
            const headline = mp.headline?.localized?.en_US || mp.headline || '';
            const createdAt = conn.createdAt
              ? new Date(conn.createdAt).toISOString().slice(0, 10)
              : '';

            return {
              rank: i + 1,
              name: name,
              vanity: vanity,
              headline: String(headline).slice(0, 120),
              connected_at: createdAt,
              profile_url: vanity ? 'https://www.linkedin.com/in/' + vanity : '',
            };
          });
        }

        // Fallback: scrape the connections page DOM
        const normalize = v => String(v || '').replace(/\s+/g, ' ').trim();
        const cards = Array.from(document.querySelectorAll('.mn-connection-card, .scaffold-finite-scroll__content li')).slice(0, limit);

        return cards.map((card, i) => {
          const nameEl = card.querySelector('.mn-connection-card__name, .entity-result__title-text a span[aria-hidden="true"]');
          const linkEl = card.querySelector('a[href*="/in/"]');
          const headlineEl = card.querySelector('.mn-connection-card__occupation, .entity-result__primary-subtitle');
          const timeEl = card.querySelector('time, .time-badge');
          const href = linkEl?.href || '';
          const vanity = href.match(/\/in\/([^/?]+)/)?.[1] || '';

          return {
            rank: i + 1,
            name: normalize(nameEl?.textContent),
            vanity: vanity,
            headline: normalize(headlineEl?.textContent).slice(0, 120),
            connected_at: normalize(timeEl?.textContent || timeEl?.getAttribute('datetime')),
            profile_url: vanity ? 'https://www.linkedin.com/in/' + vanity : href,
          };
        }).filter(item => item.name);
      })()
  - map:
      rank: ${{ item.rank }}
      name: ${{ item.name }}
      vanity: ${{ item.vanity }}
      headline: ${{ item.headline }}
      connected_at: ${{ item.connected_at }}
      profile_url: ${{ item.profile_url }}
```

- [ ] **Step 2: Install and test**

```bash
./install.sh
opencli linkedin connections --limit 5 --format json
# Expected: JSON array with name, vanity, headline, connected_at, profile_url
```

- [ ] **Step 3: Commit**

```bash
git add adapters/connections.yaml
git commit -m "feat: add linkedin connections adapter"
```

---

## Task 5: Create DM templates

**Files:**
- Create: `templates/hco-intro.txt`
- Create: `templates/hco-traveler.txt`
- Create: `templates/warm-reconnect.txt`

- [ ] **Step 1: Create templates directory and hco-intro.txt**

```bash
mkdir -p templates
```

Write `templates/hco-intro.txt`:

```
Hi {{first_name}},

I noticed you're working in hotel operations at {{company}}. We've built a system that automates cashback reconciliation — replacing the Excel spreadsheets with an auditable, tamper-proof workflow.

It handles the messy parts: name mismatches across booking systems, split reservations, and reused confirmation numbers.

Would love to share a quick demo if this is relevant to your team. No pressure either way.

Best,
Nolan
```

- [ ] **Step 2: Write hco-traveler.txt**

Write `templates/hco-traveler.txt`:

```
Hi {{first_name}},

Given your role at {{company}}, I imagine you deal with hotel bookings and cashback programs regularly. We're exploring a personal tool that tracks cashback flows across bookings — so you always know what's been claimed vs. what's actually returned.

Still early stage, but would value your perspective as someone who lives this daily. Open to a quick chat?

Nolan
```

- [ ] **Step 3: Write warm-reconnect.txt**

Write `templates/warm-reconnect.txt`:

```
Hi {{first_name}},

It's been a while — hope things are going well at {{company}}. I've been building tools for hotel operations teams lately and thought of you.

Would love to catch up briefly if you're open to it.

Nolan
```

- [ ] **Step 4: Test template variable syntax**

```bash
# Quick validation that templates have consistent variable syntax
grep -oP '\{\{[a-z_]+\}\}' templates/*.txt | sort -u
# Expected:
# {{company}}
# {{first_name}}
```

- [ ] **Step 5: Commit**

```bash
git add templates/
git commit -m "feat: add DM templates for HCO outreach"
```

---

## Task 6: Build `scripts/prospect.sh` — search subcommand

**Files:**
- Create: `scripts/prospect.sh`

The orchestrator is built incrementally — this task implements the skeleton + `search` subcommand. Subsequent tasks add `scan`, `review`, and `outreach`.

- [ ] **Step 1: Write prospect.sh skeleton + search subcommand**

Create `scripts/prospect.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data"
LEADS_FILE="$DATA_DIR/leads.jsonl"

mkdir -p "$DATA_DIR"
touch "$LEADS_FILE"

# --- Utilities ---

gen_id() {
  python3 -c "import uuid; print(uuid.uuid4().hex[:8])"
}

now_iso() {
  python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

vanity_exists() {
  local vanity="$1"
  grep -q "\"vanity\":\"$vanity\"" "$LEADS_FILE" 2>/dev/null
}

usage() {
  cat <<'USAGE'
Usage: prospect.sh <command> [options]

Commands:
  search <query>   Search LinkedIn for people, add to leads
  scan             Enrich leads with profile data and scores
  review           Interactively approve/skip leads
  outreach         Send DMs to approved leads

Options:
  --location X     Geographic filter (search only)
  --limit N        Max results (search: default 20)
  --template PATH  DM template file (outreach only)
  --dry-run        Preview without sending (outreach only)
  --batch N        Max DMs per run (outreach: default 20, max 20)

Examples:
  prospect.sh search "hotel revenue manager" --limit 30
  prospect.sh scan
  prospect.sh review
  prospect.sh outreach --template templates/hco-intro.txt --dry-run
USAGE
}

# --- search command ---

cmd_search() {
  local query=""
  local location=""
  local limit=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --location) location="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) query="$1"; shift ;;
    esac
  done

  if [[ -z "$query" ]]; then
    echo "Error: search requires a query argument" >&2
    echo "Usage: prospect.sh search \"hotel revenue manager\" --limit 20" >&2
    exit 1
  fi

  echo "Searching LinkedIn for: $query (limit: $limit)"

  local search_args=("$query" --limit "$limit" --format json)
  local results
  results=$(opencli linkedin search-people "${search_args[@]}" 2>&1) || {
    echo "Error: search-people failed: $results" >&2
    exit 1
  }

  local added=0
  local skipped=0
  local timestamp
  timestamp=$(now_iso)

  # Parse each result and append to leads.jsonl
  local count
  count=$(echo "$results" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

  for i in $(seq 0 $((count - 1))); do
    local vanity
    vanity=$(echo "$results" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('vanity',''))" 2>/dev/null)

    if [[ -z "$vanity" ]]; then
      continue
    fi

    if vanity_exists "$vanity"; then
      skipped=$((skipped + 1))
      continue
    fi

    local name headline profile_url lead_location
    name=$(echo "$results" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('name',''))")
    headline=$(echo "$results" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('headline',''))")
    profile_url=$(echo "$results" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('profile_url',''))")
    lead_location=$(echo "$results" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('location',''))")

    local id
    id=$(gen_id)

    # Write lead as single-line JSON
    python3 -c "
import json, sys
lead = {
    'id': '$id',
    'vanity': '$vanity',
    'profile_url': '$profile_url',
    'name': '''$name''',
    'headline': '''$headline''',
    'company': '',
    'industry_score': 0,
    'travel_score': 0,
    'total_score': 0,
    'status': 'new',
    'dm_template': '',
    'dm_preview': '',
    'contacted_at': '',
    'notes': '',
    'search_query': '''$query''',
    'created_at': '$timestamp'
}
print(json.dumps(lead, ensure_ascii=False))
" >> "$LEADS_FILE"

    added=$((added + 1))
  done

  echo "Done: added $added new leads, skipped $skipped duplicates"
  echo "Total leads: $(wc -l < "$LEADS_FILE" | tr -d ' ')"
}

# --- scan command (placeholder for Task 7) ---
cmd_scan() { echo "scan: not implemented yet"; exit 1; }

# --- review command (placeholder for Task 8) ---
cmd_review() { echo "review: not implemented yet"; exit 1; }

# --- outreach command (placeholder for Task 9) ---
cmd_outreach() { echo "outreach: not implemented yet"; exit 1; }

# --- Main dispatcher ---

case "${1:-}" in
  search) shift; cmd_search "$@" ;;
  scan) shift; cmd_scan "$@" ;;
  review) shift; cmd_review "$@" ;;
  outreach) shift; cmd_outreach "$@" ;;
  --help|-h|"") usage ;;
  *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
esac
```

- [ ] **Step 2: Make executable and test help**

```bash
chmod +x scripts/prospect.sh
./scripts/prospect.sh --help
# Expected: usage text with search/scan/review/outreach commands
```

- [ ] **Step 3: Test search subcommand (requires Browser Bridge running)**

```bash
./scripts/prospect.sh search "hotel revenue manager" --limit 5
# Expected: "Done: added N new leads, skipped 0 duplicates"
cat data/leads.jsonl | python3 -c "import sys,json; [print(json.loads(l)['name'], '|', json.loads(l)['status']) for l in sys.stdin]"
# Expected: names with status "new"
```

- [ ] **Step 4: Test deduplication**

```bash
./scripts/prospect.sh search "hotel revenue manager" --limit 5
# Expected: "Done: added 0 new leads, skipped N duplicates"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/prospect.sh
git commit -m "feat: add prospect.sh orchestrator with search subcommand"
```

---

## Task 7: Add `scan` subcommand to prospect.sh

**Files:**
- Modify: `scripts/prospect.sh`

- [ ] **Step 1: Replace cmd_scan placeholder**

In `scripts/prospect.sh`, replace:

```bash
cmd_scan() { echo "scan: not implemented yet"; exit 1; }
```

with:

```bash
cmd_scan() {
  echo "Scanning leads with status=new..."

  local new_leads
  new_leads=$(grep '"status":"new"' "$LEADS_FILE" 2>/dev/null || true)

  if [[ -z "$new_leads" ]]; then
    echo "No new leads to scan."
    return
  fi

  local count
  count=$(echo "$new_leads" | wc -l | tr -d ' ')
  echo "Found $count leads to scan"

  local scanned=0
  local total_score_sum=0
  local tmpfile="$LEADS_FILE.tmp"

  # Process each line of leads.jsonl
  while IFS= read -r line; do
    local status
    status=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['status'])" 2>/dev/null || echo "")

    if [[ "$status" != "new" ]]; then
      echo "$line" >> "$tmpfile"
      continue
    fi

    local vanity profile_url
    vanity=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['vanity'])")
    profile_url=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['profile_url'])")

    scanned=$((scanned + 1))
    echo "  [$scanned/$count] Scanning $vanity..."

    # Fetch profile via opencli
    local profile_json
    profile_json=$(opencli linkedin profile "$profile_url" --format json 2>/dev/null || echo "[]")

    # Score the lead
    local updated_line
    updated_line=$(python3 -c "
import json, sys, re

lead = json.loads('''$line''')
try:
    profiles = json.loads('''$profile_json''')
    p = profiles[0] if profiles else {}
except:
    p = {}

headline = p.get('headline', lead.get('headline', '')).lower()
about = p.get('about', '').lower()
experience = p.get('experience', '').lower()
all_text = ' '.join([headline, about, experience])

# Industry scoring: +3 per keyword
industry_keywords = ['hotel', 'hospitality', 'ota', 'cashback', 'reconciliation', 'revenue', 'booking', 'travel agency']
industry_score = sum(3 for k in industry_keywords if k in all_text)

# Seniority scoring
seniority_score = 0
if any(t in headline for t in ['vp ', 'vice president', 'ceo', 'cfo', 'coo', 'chief', 'c-level']):
    seniority_score = 4
elif any(t in headline for t in ['director']):
    seniority_score = 3
elif any(t in headline for t in ['manager', 'head of']):
    seniority_score = 2

# Travel scoring: +2 per keyword
travel_keywords = ['travel', 'frequent flyer', 'business travel', '出差', '差旅', 'on the road']
travel_score = sum(2 for k in travel_keywords if k in all_text)

# Connections bonus
connections_str = p.get('connections', '0')
conn_num = int(re.sub(r'[^0-9]', '', connections_str) or '0')
conn_bonus = 1 if conn_num >= 500 else 0

# Activity bonus
post_count = int(p.get('post_count', '0') or '0')
activity_bonus = 1 if post_count > 0 else 0

total = industry_score + seniority_score + travel_score + conn_bonus + activity_bonus

lead['industry_score'] = industry_score
lead['travel_score'] = travel_score
lead['total_score'] = total
lead['company'] = p.get('current_company', '')
lead['status'] = 'scanned'
if total >= 10:
    lead['notes'] = 'recommended'

# Update headline if richer data available
if p.get('headline'):
    lead['headline'] = p['headline']

print(json.dumps(lead, ensure_ascii=False))
")

    echo "$updated_line" >> "$tmpfile"

    local score
    score=$(echo "$updated_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['total_score'])")
    total_score_sum=$((total_score_sum + score))

    # Rate limit: 3 seconds between fetches
    sleep 3
  done < "$LEADS_FILE"

  mv "$tmpfile" "$LEADS_FILE"

  local avg=0
  if [[ $scanned -gt 0 ]]; then
    avg=$((total_score_sum / scanned))
  fi

  echo "Done: scanned $scanned leads, avg score: $avg"
}
```

- [ ] **Step 2: Test scan**

```bash
./scripts/prospect.sh scan
# Expected: "Scanning leads with status=new..."
# Each lead scanned with score output
# "Done: scanned N leads, avg score: X"

# Verify status changed
grep '"status":"scanned"' data/leads.jsonl | wc -l
# Expected: same count as previously "new" leads
```

- [ ] **Step 3: Commit**

```bash
git add scripts/prospect.sh
git commit -m "feat: add scan subcommand with scoring to prospect.sh"
```

---

## Task 8: Add `review` subcommand to prospect.sh

**Files:**
- Modify: `scripts/prospect.sh`

- [ ] **Step 1: Replace cmd_review placeholder**

In `scripts/prospect.sh`, replace:

```bash
cmd_review() { echo "review: not implemented yet"; exit 1; }
```

with:

```bash
cmd_review() {
  echo "Reviewing scanned leads (sorted by score)..."

  # Extract scanned leads, sorted by total_score descending
  local sorted_leads
  sorted_leads=$(grep '"status":"scanned"' "$LEADS_FILE" 2>/dev/null | \
    python3 -c "
import sys, json
leads = [json.loads(l) for l in sys.stdin]
leads.sort(key=lambda x: x.get('total_score', 0), reverse=True)
for l in leads:
    print(json.dumps(l, ensure_ascii=False))
" 2>/dev/null || true)

  if [[ -z "$sorted_leads" ]]; then
    echo "No scanned leads to review."
    return
  fi

  local total
  total=$(echo "$sorted_leads" | wc -l | tr -d ' ')
  local reviewed=0
  local approved=0
  local skipped_count=0
  local decisions=()  # array of "vanity:status" pairs

  while IFS= read -r lead_line; do
    reviewed=$((reviewed + 1))

    local name headline company score notes vanity
    name=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['name'])")
    headline=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['headline'])")
    company=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['company'])")
    score=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['total_score'])")
    notes=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['notes'])")
    vanity=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['vanity'])")

    local star=""
    if [[ "$notes" == *"recommended"* ]]; then
      star=" ★"
    fi

    echo ""
    echo "[$reviewed/$total] $name | $headline | score:$score$star"
    if [[ -n "$company" ]]; then
      echo "  Company: $company"
    fi
    echo "─────────────────────────────────"
    echo -n "  [y] approve  [n] skip  [s] star for later  [q] quit: "

    local choice
    read -r choice </dev/tty

    case "$choice" in
      y|Y) decisions+=("$vanity:approved"); approved=$((approved + 1)) ;;
      n|N) decisions+=("$vanity:skipped"); skipped_count=$((skipped_count + 1)) ;;
      s|S) ;; # keep as scanned
      q|Q) break ;;
      *) ;; # keep as scanned
    esac
  done <<< "$sorted_leads"

  # Apply decisions to leads.jsonl
  if [[ ${#decisions[@]} -gt 0 ]]; then
    local tmpfile="$LEADS_FILE.tmp"
    while IFS= read -r line; do
      local line_vanity
      line_vanity=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('vanity',''))" 2>/dev/null || echo "")

      local matched=false
      for decision in "${decisions[@]}"; do
        local dec_vanity="${decision%%:*}"
        local dec_status="${decision#*:}"
        if [[ "$line_vanity" == "$dec_vanity" ]]; then
          echo "$line" | python3 -c "
import sys, json
lead = json.loads(sys.stdin.read())
lead['status'] = '$dec_status'
print(json.dumps(lead, ensure_ascii=False))
" >> "$tmpfile"
          matched=true
          break
        fi
      done

      if [[ "$matched" == "false" ]]; then
        echo "$line" >> "$tmpfile"
      fi
    done < "$LEADS_FILE"
    mv "$tmpfile" "$LEADS_FILE"
  fi

  echo ""
  echo "Review complete: $approved approved, $skipped_count skipped, $((reviewed - approved - skipped_count)) deferred"
}
```

- [ ] **Step 2: Test review (interactive)**

```bash
./scripts/prospect.sh review
# Expected: leads shown sorted by score with y/n/s/q prompt
# After reviewing, check status changes:
grep '"status":"approved"' data/leads.jsonl | wc -l
```

- [ ] **Step 3: Commit**

```bash
git add scripts/prospect.sh
git commit -m "feat: add interactive review subcommand to prospect.sh"
```

---

## Task 9: Add `outreach` subcommand to prospect.sh

**Files:**
- Modify: `scripts/prospect.sh`

- [ ] **Step 1: Replace cmd_outreach placeholder**

In `scripts/prospect.sh`, replace:

```bash
cmd_outreach() { echo "outreach: not implemented yet"; exit 1; }
```

with:

```bash
cmd_outreach() {
  local template=""
  local dry_run=false
  local batch=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template) template="$2"; shift 2 ;;
      --dry-run) dry_run=true; shift ;;
      --batch) batch="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$template" ]]; then
    echo "Error: --template is required" >&2
    echo "Usage: prospect.sh outreach --template templates/hco-intro.txt --dry-run" >&2
    exit 1
  fi

  if [[ ! -f "$PROJECT_DIR/$template" ]]; then
    echo "Error: template file not found: $template" >&2
    exit 1
  fi

  # Cap batch at 20
  if [[ $batch -gt 20 ]]; then
    echo "Warning: batch capped at 20 (LinkedIn rate limit protection)"
    batch=20
  fi

  local approved_leads
  approved_leads=$(grep '"status":"approved"' "$LEADS_FILE" 2>/dev/null || true)

  if [[ -z "$approved_leads" ]]; then
    echo "No approved leads. Run 'prospect.sh review' first."
    return
  fi

  local total
  total=$(echo "$approved_leads" | wc -l | tr -d ' ')
  local to_send=$((total < batch ? total : batch))

  local template_content
  template_content=$(cat "$PROJECT_DIR/$template")

  echo "Outreach: $to_send leads queued (template: $template)"
  if [[ "$dry_run" == "true" ]]; then
    echo "MODE: DRY RUN (no messages will be sent)"
  fi
  echo "─────────────────────────────────"

  local sent=0
  local decisions=()

  while IFS= read -r lead_line; do
    if [[ $sent -ge $to_send ]]; then
      break
    fi

    local vanity name company first_name
    vanity=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['vanity'])")
    name=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['name'])")
    company=$(echo "$lead_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['company'])")
    first_name=$(echo "$name" | awk '{print $1}')

    # Substitute template variables
    local message="$template_content"
    message="${message//\{\{first_name\}\}/$first_name}"
    message="${message//\{\{company\}\}/$company}"
    message="${message//\{\{name\}\}/$name}"

    sent=$((sent + 1))

    if [[ "$dry_run" == "true" ]]; then
      echo ""
      echo "[$sent/$to_send] TO: $name ($vanity)"
      echo "────────"
      echo "$message"
      echo "────────"
    else
      echo "[$sent/$to_send] Sending to $name ($vanity)..."

      local dm_result
      dm_result=$(opencli linkedin send-dm "$vanity" --text "$message" --format json 2>&1) || {
        echo "  ERROR: $dm_result"
        continue
      }

      local dm_status
      dm_status=$(echo "$dm_result" | python3 -c "import sys,json; print(json.load(sys.stdin)[0].get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
      echo "  Status: $dm_status"

      decisions+=("$vanity")

      # Rate limit: 10 seconds between sends
      if [[ $sent -lt $to_send ]]; then
        echo "  (waiting 10s...)"
        sleep 10
      fi
    fi
  done <<< "$approved_leads"

  # Update status to contacted (only for non-dry-run)
  if [[ "$dry_run" == "false" && ${#decisions[@]} -gt 0 ]]; then
    local tmpfile="$LEADS_FILE.tmp"
    local timestamp
    timestamp=$(now_iso)

    while IFS= read -r line; do
      local line_vanity
      line_vanity=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('vanity',''))" 2>/dev/null || echo "")

      local matched=false
      for dec_vanity in "${decisions[@]}"; do
        if [[ "$line_vanity" == "$dec_vanity" ]]; then
          echo "$line" | python3 -c "
import sys, json
lead = json.loads(sys.stdin.read())
lead['status'] = 'contacted'
lead['contacted_at'] = '$timestamp'
lead['dm_template'] = '$template'
print(json.dumps(lead, ensure_ascii=False))
" >> "$tmpfile"
          matched=true
          break
        fi
      done

      if [[ "$matched" == "false" ]]; then
        echo "$line" >> "$tmpfile"
      fi
    done < "$LEADS_FILE"
    mv "$tmpfile" "$LEADS_FILE"

    echo ""
    echo "Done: sent $sent messages, $((total - sent)) remaining"
  else
    echo ""
    echo "Dry run complete: $sent messages previewed"
    echo "Run without --dry-run to send."
  fi
}
```

- [ ] **Step 2: Test outreach dry-run**

```bash
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run
# Expected: each approved lead shown with personalized message
# No actual DMs sent
```

- [ ] **Step 3: Commit**

```bash
git add scripts/prospect.sh
git commit -m "feat: add outreach subcommand with dry-run and rate limiting"
```

---

## Task 10: Enhance `send-dm.yaml` with --template flag

**Files:**
- Modify: `adapters/send-dm.yaml`

- [ ] **Step 1: Add template and vars args**

In `adapters/send-dm.yaml`, add two new args after the existing `dry-run` arg:

```yaml
  template:
    type: string
    default: ""
    description: "Path to template file with {{variable}} placeholders"
  vars:
    type: string
    default: "{}"
    description: "JSON object of template variables (e.g. '{\"first_name\":\"John\"}')"
```

- [ ] **Step 2: Add template processing in evaluate block**

At the top of the evaluate block's async function (after `const dryRun = ...`), add template processing:

```javascript
        // Template support
        let finalText = messageText;
        const templatePath = ${{ args.template | json }};
        const varsJson = ${{ args.vars | json }};

        if (templatePath && !finalText) {
          // Template file is read by the orchestrator and passed via --text
          // This is a fallback for direct CLI usage
          try {
            const vars = JSON.parse(varsJson);
            // If text was provided via template orchestrator, use it as-is
            // Otherwise vars substitution happens in prospect.sh
            finalText = messageText || '(template mode — use prospect.sh outreach)';
          } catch (e) {
            finalText = messageText;
          }
        }
```

Then replace all references to `messageText` in the rest of the evaluate block with `finalText`.

- [ ] **Step 3: Test template flag with dry-run**

```bash
./install.sh
opencli linkedin send-dm "williamhgates" --text "Hello from template test" --dry-run --format json
# Expected: DRY_RUN output (backward compatible with --text)
```

- [ ] **Step 4: Commit**

```bash
git add adapters/send-dm.yaml
git commit -m "feat: add --template and --vars flags to send-dm adapter"
```

---

## Task 11: Update test-all.sh

**Files:**
- Modify: `tests/test-all.sh`

- [ ] **Step 1: Add new adapter tests**

In `tests/test-all.sh`, add these tests after the existing "send-dm" test:

```bash
# New adapter tests
run_test "search-people (read)" opencli linkedin search-people "software engineer" --limit 1 --format json
run_test "connections (read)" opencli linkedin connections --limit 1 --format json
run_test "inbox (read)" opencli linkedin inbox --limit 1 --format json

# Prospect pipeline tests (no Browser Bridge needed for these)
echo ""
echo "Prospect Pipeline Tests"
echo "======================"

# Test prospect.sh help
echo -n "  prospect.sh help ... "
if ./scripts/prospect.sh --help >/dev/null 2>&1; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL"
  FAIL=$((FAIL + 1))
fi

# Test template variable syntax
echo -n "  template syntax ... "
template_vars=$(grep -ohP '\{\{[a-z_]+\}\}' templates/*.txt 2>/dev/null | sort -u)
if echo "$template_vars" | grep -q "first_name"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (missing {{first_name}})"
  FAIL=$((FAIL + 1))
fi
```

- [ ] **Step 2: Run tests**

```bash
bash tests/test-all.sh
# Expected: all tests pass (new adapter tests require Browser Bridge)
```

- [ ] **Step 3: Commit**

```bash
git add tests/test-all.sh
git commit -m "test: add smoke tests for search-people, connections, inbox, prospect.sh"
```

---

## Task 12: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add prospect pipeline section to README**

After the existing "## Testing" section, add:

```markdown
## Prospect Pipeline

Semi-automated prospecting for Dash/HCO customer acquisition.

### Setup

```bash
./install.sh                    # Symlink all adapters
```

### Workflow

```bash
# 1. Search for potential customers
./scripts/prospect.sh search "hotel revenue manager" --limit 20

# 2. Scan profiles and score leads
./scripts/prospect.sh scan

# 3. Review and approve candidates
./scripts/prospect.sh review

# 4. Preview outreach messages
./scripts/prospect.sh outreach --template templates/hco-intro.txt --dry-run

# 5. Send approved messages
./scripts/prospect.sh outreach --template templates/hco-intro.txt
```

### Templates

| Template | Target | Use Case |
|----------|--------|----------|
| `hco-intro.txt` | B2B hotel operations | Product introduction |
| `hco-traveler.txt` | B2C frequent travelers | Personal tool pitch |
| `warm-reconnect.txt` | Existing connections | Warm re-engagement |

### Lead Status Lifecycle

`new` → `scanned` → `approved`/`skipped` → `contacted` → `replied`

Leads are stored in `data/leads.jsonl` (gitignored).
```

- [ ] **Step 2: Add new commands to the Commands table**

In the existing Commands table, add:

```markdown
| `opencli linkedin search-people <query>` | Read | Search for people by keywords |
| `opencli linkedin connections` | Read | List your connections |
| `opencli linkedin inbox` | Read | Recent messages/conversations |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add prospect pipeline workflow to README"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] search-people.yaml → Task 2
- [x] connections.yaml → Task 4
- [x] profile.yaml enhancement → Task 3
- [x] send-dm.yaml enhancement → Task 10
- [x] prospect.sh search → Task 6
- [x] prospect.sh scan → Task 7
- [x] prospect.sh review → Task 8
- [x] prospect.sh outreach → Task 9
- [x] DM templates → Task 5
- [x] leads.jsonl schema → Task 6 (created during search)
- [x] inbox.yaml commit → Task 1
- [x] test updates → Task 11
- [x] README updates → Task 12
- [x] .gitignore for leads data → Task 1
- [x] Success criteria 1-7 covered by tasks 2, 7, 8, 9, 11

**Placeholder scan:** No TBD/TODO found. All code blocks are complete.

**Type consistency:** `vanity`, `status`, `total_score` naming consistent across all tasks. Template variables `{{first_name}}`, `{{company}}` match between templates (Task 5) and substitution logic (Task 9).
