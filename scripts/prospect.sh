#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data"
LEADS_FILE="$DATA_DIR/leads.jsonl"

mkdir -p "$DATA_DIR"
touch "$LEADS_FILE"

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

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
USAGE
}

# ---------------------------------------------------------------------------
# search subcommand
# ---------------------------------------------------------------------------

cmd_search() {
  local query=""
  local location=""
  local limit=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --location) location="$2"; shift 2 ;;
      --limit)    limit="$2";    shift 2 ;;
      --help|-h)  usage; return 0 ;;
      -*)         echo "Unknown option: $1" >&2; usage; exit 1 ;;
      *)
        if [[ -z "$query" ]]; then
          query="$1"; shift
        else
          query="$query $1"; shift
        fi
        ;;
    esac
  done

  if [[ -z "$query" ]]; then
    echo "Error: search requires a query argument" >&2
    usage
    exit 1
  fi

  echo "Searching LinkedIn for: $query (limit=$limit${location:+, location=$location})"

  # Build the opencli command
  local cmd=(opencli linkedin search-people "$query" --limit "$limit" --format json)
  if [[ -n "$location" ]]; then
    cmd+=(--location "$location")
  fi

  # Run search and capture JSON output
  local raw_json
  raw_json=$("${cmd[@]}" 2>&1) || {
    echo "Error: search-people command failed" >&2
    echo "$raw_json" >&2
    exit 1
  }

  # Use python3 for all JSON processing: parse results, dedup, create leads, append
  python3 - "$raw_json" "$query" "$LEADS_FILE" <<'PYEOF'
import json
import sys
import uuid
from datetime import datetime, timezone

raw_json = sys.argv[1]
search_query = sys.argv[2]
leads_file = sys.argv[3]

# Parse search results
try:
    results = json.loads(raw_json)
except json.JSONDecodeError:
    print(f"Error: could not parse search results as JSON", file=sys.stderr)
    print(f"Raw output: {raw_json[:500]}", file=sys.stderr)
    sys.exit(1)

if not isinstance(results, list):
    results = [results]

# Load existing vanities for dedup
existing_vanities = set()
try:
    with open(leads_file, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    lead = json.loads(line)
                    existing_vanities.add(lead.get("vanity", ""))
                except json.JSONDecodeError:
                    continue
except FileNotFoundError:
    pass

added = 0
skipped = 0

with open(leads_file, "a") as f:
    for result in results:
        vanity = result.get("vanity", "")
        if not vanity:
            continue

        if vanity in existing_vanities:
            skipped += 1
            continue

        lead = {
            "id": uuid.uuid4().hex[:8],
            "vanity": vanity,
            "profile_url": result.get("profile_url", ""),
            "name": result.get("name", ""),
            "headline": result.get("headline", ""),
            "company": "",
            "industry_score": 0,
            "travel_score": 0,
            "total_score": 0,
            "status": "new",
            "dm_template": "",
            "dm_preview": "",
            "contacted_at": "",
            "notes": "",
            "search_query": search_query,
            "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }

        f.write(json.dumps(lead, ensure_ascii=False) + "\n")
        existing_vanities.add(vanity)
        added += 1

print(f"Done: added {added} new leads, skipped {skipped} duplicates")
PYEOF
}

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

cmd_scan()     { echo "scan: not implemented yet";     exit 1; }
cmd_review()   { echo "review: not implemented yet";   exit 1; }
cmd_outreach() { echo "outreach: not implemented yet"; exit 1; }

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

case "${1:-}" in
  search)   shift; cmd_search "$@" ;;
  scan)     shift; cmd_scan "$@" ;;
  review)   shift; cmd_review "$@" ;;
  outreach) shift; cmd_outreach "$@" ;;
  --help|-h|"") usage ;;
  *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
esac
