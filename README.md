# LinkedIn CLI Adapters for opencli

Custom adapters that extend [opencli](https://github.com/jackwener/opencli) with full LinkedIn read+write capability.

## Prerequisites

- opencli v1.6.8+ (`npm i -g @jackwener/opencli`)
- opencli Browser Bridge extension loaded in Chrome
- Signed in to LinkedIn in Chrome

## Install

```bash
./install.sh
```

Symlinks all YAML adapters into `~/.opencli/clis/linkedin/`.

## Commands

| Command | Type | Description |
|---------|------|-------------|
| `opencli linkedin timeline` | Read | Home feed posts (built-in) |
| `opencli linkedin search` | Read | Job search (built-in) |
| `opencli linkedin profile <url>` | Read | View member profile |
| `opencli linkedin post <text>` | Write | Create a text post |
| `opencli linkedin like <url>` | Write | Like a post |
| `opencli linkedin comment <url> --text "..."` | Write | Comment on a post |
| `opencli linkedin repost <url>` | Write | Repost with optional commentary |
| `opencli linkedin send-dm <profile> --text "..."` | Write | DM a connection |
| `opencli linkedin search-people <query>` | Read | Search for people by keywords |
| `opencli linkedin connections` | Read | List your connections |
| `opencli linkedin inbox` | Read | Recent messages/conversations |
| `opencli linkedin notifications` | Read | Recent notifications |

All write commands support `--dry-run` to preview without executing.

## Examples

```bash
# Read your feed
opencli linkedin timeline --limit 5 --format json

# Post (with dry-run preview)
opencli linkedin post "Excited to share..." --dry-run
opencli linkedin post "Excited to share..."

# Like a post
opencli linkedin like "https://www.linkedin.com/feed/update/urn:li:activity:123/"

# Comment
opencli linkedin comment "https://www.linkedin.com/feed/update/urn:li:activity:123/" --text "Great post!"

# Repost with commentary
opencli linkedin repost "https://www.linkedin.com/feed/update/urn:li:activity:123/" --text "Check this out"

# DM someone
opencli linkedin send-dm "username" --text "Hey, wanted to reach out"

# View a profile
opencli linkedin profile "https://www.linkedin.com/in/username" --format json
```

## Testing

```bash
bash tests/test-all.sh
```

## Prospect Pipeline

Semi-automated prospecting for Dash/HCO customer acquisition.

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
