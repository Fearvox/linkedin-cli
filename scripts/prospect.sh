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

cmd_scan() {
  # -------------------------------------------------------------------------
  # Step 1: Extract new leads (vanity + profile_url) via python3
  # -------------------------------------------------------------------------
  local new_leads
  new_leads=$(python3 - "$LEADS_FILE" <<'PYEOF'
import json, sys
leads_file = sys.argv[1]
try:
    with open(leads_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lead = json.loads(line)
                if lead.get("status") == "new":
                    # Output tab-separated vanity and profile_url
                    print(f"{lead.get('vanity', '')}\t{lead.get('profile_url', '')}")
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass
PYEOF
  )

  if [[ -z "$new_leads" ]]; then
    echo "No new leads to scan."
    return 0
  fi

  local count=0
  local total_score_sum=0

  # We will collect scored lead JSON lines in a temp file, keyed by vanity
  local scored_tmp
  scored_tmp=$(mktemp)
  trap "rm -f '$scored_tmp'" EXIT

  # -------------------------------------------------------------------------
  # Step 2: For each new lead, fetch profile and score
  # -------------------------------------------------------------------------
  while IFS=$'\t' read -r vanity profile_url; do
    [[ -z "$vanity" ]] && continue

    if [[ $count -gt 0 ]]; then
      sleep 3
    fi

    echo "Scanning: $vanity ($profile_url)"

    local profile_json=""
    profile_json=$(opencli linkedin profile "$profile_url" --format json 2>&1) || {
      echo "  Warning: profile fetch failed for $vanity, skipping" >&2
      continue
    }

    # Feed profile JSON to python3 scoring script, output updated lead JSON
    local scored_line
    scored_line=$(python3 - "$profile_json" "$vanity" "$LEADS_FILE" <<'PYEOF'
import json, sys, re

profile_raw = sys.argv[1]
target_vanity = sys.argv[2]
leads_file = sys.argv[3]

# Parse profile data
try:
    profile_data = json.loads(profile_raw)
    if isinstance(profile_data, list):
        profile_data = profile_data[0] if profile_data else {}
except json.JSONDecodeError:
    profile_data = {}

# Find the original lead line
original_lead = None
with open(leads_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            lead = json.loads(line)
            if lead.get("vanity") == target_vanity:
                original_lead = lead
                break
        except json.JSONDecodeError:
            continue

if not original_lead:
    sys.exit(1)

# Build combined text for scanning
p_headline = str(profile_data.get("headline", "")).lower()
p_about = str(profile_data.get("about", "")).lower()
p_experience = str(profile_data.get("experience", "")).lower()
p_connections = str(profile_data.get("connections", ""))
p_post_count = str(profile_data.get("post_count", "0"))
p_industry = str(profile_data.get("industry", "")).lower()
p_travel_signals = str(profile_data.get("travel_signals", "")).lower()
p_company = str(profile_data.get("current_company", ""))

all_text = f"{p_headline} {p_about} {p_experience}"

# --- Scoring ---

# 1. Industry keyword match: +3 per keyword found in headline + about + experience
industry_keywords = ["hotel", "hospitality", "ota", "cashback", "reconciliation",
                     "revenue", "booking", "travel agency"]
industry_score = 0
matched_industry = set()
for kw in industry_keywords:
    if kw in all_text:
        matched_industry.add(kw)
# Also check pre-extracted industry field from profile adapter
if p_industry:
    for part in p_industry.split(","):
        part = part.strip()
        if part and part in [k for k in industry_keywords]:
            matched_industry.add(part)
industry_score = len(matched_industry) * 3

# 2. Seniority scoring from headline
seniority_score = 0
headline_lower = p_headline
# Check highest tier first (VP/C-level: +4)
vp_patterns = ["vp", "vice president", "ceo", "cfo", "coo", "chief", "c-level"]
director_patterns = ["director"]
manager_patterns = ["manager", "head of"]

matched_vp = any(pat in headline_lower for pat in vp_patterns)
matched_director = any(pat in headline_lower for pat in director_patterns)
matched_manager = any(pat in headline_lower for pat in manager_patterns)

if matched_vp:
    seniority_score = 4
elif matched_director:
    seniority_score = 3
elif matched_manager:
    seniority_score = 2

# 3. Travel keyword match: +2 per keyword found in about + experience
travel_keywords = ["travel", "frequent flyer", "business travel", "出差", "差旅", "on the road"]
travel_text = f"{p_about} {p_experience}"
travel_matched = set()
for kw in travel_keywords:
    if kw in travel_text:
        travel_matched.add(kw)
# Also check pre-extracted travel_signals field
if p_travel_signals:
    for part in p_travel_signals.split(","):
        part = part.strip()
        if part and part in travel_keywords:
            travel_matched.add(part)
travel_score = len(travel_matched) * 2

# 4. 500+ connections: +1
conn_bonus = 0
conn_numeric = re.sub(r'[^0-9]', '', p_connections)
if conn_numeric and int(conn_numeric) >= 500:
    conn_bonus = 1

# 5. Recently active (post_count > 0): +1
activity_bonus = 0
pc_numeric = re.sub(r'[^0-9]', '', p_post_count)
if pc_numeric and int(pc_numeric) > 0:
    activity_bonus = 1

total_score = industry_score + seniority_score + travel_score + conn_bonus + activity_bonus

# Update the lead
original_lead["industry_score"] = industry_score
original_lead["travel_score"] = travel_score
original_lead["total_score"] = total_score
original_lead["company"] = p_company if p_company else original_lead.get("company", "")
original_lead["status"] = "scanned"
if total_score >= 10:
    original_lead["notes"] = "recommended"

# Output as single JSON line
print(json.dumps(original_lead, ensure_ascii=False))
PYEOF
    )

    if [[ -n "$scored_line" ]]; then
      echo "$vanity	$scored_line" >> "$scored_tmp"
      local lead_score
      lead_score=$(echo "$scored_line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('total_score',0))")
      echo "  Score: $lead_score"
      total_score_sum=$((total_score_sum + lead_score))
      count=$((count + 1))
    else
      echo "  Warning: scoring failed for $vanity" >&2
    fi

  done <<< "$new_leads"

  if [[ $count -eq 0 ]]; then
    echo "No new leads to scan."
    return 0
  fi

  # -------------------------------------------------------------------------
  # Step 3: Rebuild leads.jsonl atomically (non-new kept as-is, new replaced)
  # -------------------------------------------------------------------------
  python3 - "$LEADS_FILE" "$scored_tmp" <<'PYEOF'
import json, sys, tempfile, os

leads_file = sys.argv[1]
scored_tmp = sys.argv[2]

# Load scored leads keyed by vanity
scored = {}
with open(scored_tmp, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t", 1)
        if len(parts) == 2:
            scored[parts[0]] = parts[1]

# Rewrite leads.jsonl
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(leads_file), suffix=".jsonl")
try:
    with os.fdopen(tmp_fd, "w") as out:
        with open(leads_file, "r") as inp:
            for line in inp:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    lead = json.loads(raw)
                    vanity = lead.get("vanity", "")
                    if vanity in scored:
                        out.write(scored[vanity] + "\n")
                        del scored[vanity]
                    else:
                        out.write(raw + "\n")
                except json.JSONDecodeError:
                    out.write(raw + "\n")
    os.replace(tmp_path, leads_file)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF

  # -------------------------------------------------------------------------
  # Step 4: Report
  # -------------------------------------------------------------------------
  local avg_score
  if [[ $count -gt 0 ]]; then
    avg_score=$(python3 -c "print(round($total_score_sum / $count, 1))")
  else
    avg_score="0"
  fi
  echo "Done: scanned $count leads, avg score: $avg_score"
}
cmd_review() {
  # ---------------------------------------------------------------------------
  # Step 1: Extract scanned leads sorted by total_score descending
  # ---------------------------------------------------------------------------
  local sorted_leads
  sorted_leads=$(python3 - "$LEADS_FILE" <<'PYEOF'
import json, sys

leads_file = sys.argv[1]
scanned = []
try:
    with open(leads_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lead = json.loads(line)
                if lead.get("status") == "scanned":
                    scanned.append(lead)
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass

# Sort by total_score descending
scanned.sort(key=lambda x: x.get("total_score", 0), reverse=True)

for lead in scanned:
    print(json.dumps(lead, ensure_ascii=False))
PYEOF
  )

  if [[ -z "$sorted_leads" ]]; then
    echo "No scanned leads to review."
    return 0
  fi

  # Count total scanned leads
  local total
  total=$(echo "$sorted_leads" | wc -l | tr -d ' ')

  # ---------------------------------------------------------------------------
  # Step 2: Interactive review loop
  # ---------------------------------------------------------------------------
  local idx=0
  local approved=0
  local skipped=0
  local deferred=0
  local quit_early=false

  # Collect decisions as vanity:status pairs in a temp file
  local decisions_tmp
  decisions_tmp=$(mktemp)
  trap "rm -f '$decisions_tmp'" EXIT

  while IFS= read -r lead_json; do
    [[ -z "$lead_json" ]] && continue
    idx=$((idx + 1))

    # Extract display fields via python3
    local display_info
    display_info=$(python3 -c "
import json, sys
lead = json.loads(sys.argv[1])
name = lead.get('name', 'Unknown')
headline = lead.get('headline', '')
company = lead.get('company', '')
score = lead.get('total_score', 0)
notes = lead.get('notes', '')
vanity = lead.get('vanity', '')
recommended = '1' if 'recommended' in notes.lower() else '0'
print(f'{vanity}\t{name}\t{headline}\t{company}\t{score}\t{recommended}')
" "$lead_json")

    local vanity name headline company score recommended
    IFS=$'\t' read -r vanity name headline company score recommended <<< "$display_info"

    # Build display
    local star=""
    if [[ "$recommended" == "1" ]]; then
      star=" ★"
    fi

    echo ""
    echo "[$idx/$total] $name | $headline | score:${score}${star}"
    if [[ -n "$company" ]]; then
      echo "  Company: $company"
    fi
    echo "─────────────────────────────────"

    # Read user input from /dev/tty
    local choice=""
    printf "  [y] approve  [n] skip  [s] star for later  [q] quit: "
    read -r choice </dev/tty || choice=""

    case "$choice" in
      y|Y)
        echo "$vanity	approved" >> "$decisions_tmp"
        approved=$((approved + 1))
        ;;
      n|N)
        echo "$vanity	skipped" >> "$decisions_tmp"
        skipped=$((skipped + 1))
        ;;
      s|S)
        # Keep as scanned — no decision recorded
        deferred=$((deferred + 1))
        ;;
      q|Q)
        deferred=$((deferred + (total - idx)))
        quit_early=true
        break
        ;;
      *)
        # Anything else: keep as scanned
        deferred=$((deferred + 1))
        ;;
    esac

  done <<< "$sorted_leads"

  # ---------------------------------------------------------------------------
  # Step 3: Apply all decisions to leads.jsonl atomically
  # ---------------------------------------------------------------------------
  python3 - "$LEADS_FILE" "$decisions_tmp" <<'PYEOF'
import json, sys, tempfile, os

leads_file = sys.argv[1]
decisions_file = sys.argv[2]

# Load decisions: vanity -> new status
decisions = {}
try:
    with open(decisions_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t", 1)
            if len(parts) == 2:
                decisions[parts[0]] = parts[1]
except FileNotFoundError:
    pass

if not decisions:
    sys.exit(0)

# Rewrite leads.jsonl with updated statuses
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(leads_file), suffix=".jsonl")
try:
    with os.fdopen(tmp_fd, "w") as out:
        with open(leads_file, "r") as inp:
            for line in inp:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    lead = json.loads(raw)
                    vanity = lead.get("vanity", "")
                    if vanity in decisions:
                        lead["status"] = decisions[vanity]
                    out.write(json.dumps(lead, ensure_ascii=False) + "\n")
                except json.JSONDecodeError:
                    out.write(raw + "\n")
    os.replace(tmp_path, leads_file)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF

  # ---------------------------------------------------------------------------
  # Step 4: Report
  # ---------------------------------------------------------------------------
  echo ""
  echo "Review complete: $approved approved, $skipped skipped, $deferred deferred"
}
cmd_outreach() {
  local template=""
  local dry_run=false
  local batch=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)  template="$2"; shift 2 ;;
      --dry-run)   dry_run=true; shift ;;
      --batch)     batch="$2"; shift 2 ;;
      --help|-h)   usage; return 0 ;;
      -*)          echo "Unknown option: $1" >&2; usage; exit 1 ;;
      *)           echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done

  # Validate --template is provided
  if [[ -z "$template" ]]; then
    echo "Error: --template PATH is required" >&2
    echo "" >&2
    echo "Usage: prospect.sh outreach --template <path> [--dry-run] [--batch N]" >&2
    exit 1
  fi

  # Resolve template path relative to project root
  local template_path="$PROJECT_DIR/$template"
  if [[ ! -f "$template_path" ]]; then
    echo "Error: template file not found: $template_path" >&2
    exit 1
  fi

  # Cap batch at 20
  if [[ "$batch" -gt 20 ]]; then
    echo "Warning: batch capped at 20 (LinkedIn rate limit protection)"
    batch=20
  fi

  # Read approved leads
  local approved_leads
  approved_leads=$(python3 - "$LEADS_FILE" <<'PYEOF'
import json, sys

leads_file = sys.argv[1]
try:
    with open(leads_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lead = json.loads(line)
                if lead.get("status") == "approved":
                    print(json.dumps(lead, ensure_ascii=False))
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass
PYEOF
  )

  if [[ -z "$approved_leads" ]]; then
    echo "No approved leads. Run 'prospect.sh review' first."
    return 0
  fi

  # Read template content
  local template_content
  template_content=$(<"$template_path")

  # Count approved leads
  local total
  total=$(echo "$approved_leads" | wc -l | tr -d ' ')
  if [[ "$total" -gt "$batch" ]]; then
    total="$batch"
  fi

  local sent=0
  local idx=0

  # Collect updates for post-send status changes (vanity \t timestamp)
  local updates_tmp
  updates_tmp=$(mktemp)
  trap "rm -f '$updates_tmp'" EXIT

  while IFS= read -r lead_json; do
    [[ -z "$lead_json" ]] && continue
    idx=$((idx + 1))
    if [[ $idx -gt $batch ]]; then
      break
    fi

    # Extract fields via python3
    local lead_info
    lead_info=$(python3 -c "
import json, sys
lead = json.loads(sys.argv[1])
name = lead.get('name', '')
vanity = lead.get('vanity', '')
company = lead.get('company', '')
print(f'{name}\t{vanity}\t{company}')
" "$lead_json")

    local name vanity company
    IFS=$'\t' read -r name vanity company <<< "$lead_info"

    # Extract first_name (first word of name)
    local first_name
    first_name=$(echo "$name" | awk '{print $1}')

    # Substitute template variables
    local message
    message="${template_content//\{\{first_name\}\}/$first_name}"
    message="${message//\{\{company\}\}/$company}"
    message="${message//\{\{name\}\}/$name}"

    if [[ "$dry_run" == true ]]; then
      echo "[$idx/$total] TO: $name ($vanity)"
      echo "$message"
      echo ""
      sent=$((sent + 1))
    else
      echo "[$idx/$total] Sending to $name ($vanity)..."

      # Write message to temp file to handle newlines and special characters safely
      local msg_tmp
      msg_tmp=$(mktemp)
      printf '%s' "$message" > "$msg_tmp"

      local send_result
      send_result=$(python3 - "$vanity" "$msg_tmp" <<'PYEOF'
import subprocess, sys, json

vanity = sys.argv[1]
msg_file = sys.argv[2]

with open(msg_file, "r") as f:
    msg_text = f.read()

try:
    result = subprocess.run(
        ["opencli", "linkedin", "send-dm", vanity, "--text", msg_text, "--format", "json"],
        capture_output=True, text=True, timeout=60
    )
    if result.returncode == 0:
        print("OK")
    else:
        print(f"FAIL: {result.stderr.strip() or result.stdout.strip()}")
except Exception as e:
    print(f"FAIL: {e}")
PYEOF
      )
      rm -f "$msg_tmp"

      if [[ "$send_result" == "OK" ]]; then
        echo "  Sent successfully"
        sent=$((sent + 1))
        local ts
        ts=$(now_iso)
        echo "$vanity	$ts" >> "$updates_tmp"
      else
        echo "  $send_result" >&2
      fi

      # Rate limit: sleep 10 seconds between sends (skip after last one)
      if [[ $idx -lt $total ]]; then
        sleep 10
      fi
    fi

  done <<< "$approved_leads"

  # Update leads.jsonl with contacted status (non-dry-run only)
  if [[ "$dry_run" == false && -s "$updates_tmp" ]]; then
    python3 - "$LEADS_FILE" "$updates_tmp" "$template" <<'PYEOF'
import json, sys, tempfile, os

leads_file = sys.argv[1]
updates_file = sys.argv[2]
dm_template = sys.argv[3]

# Load updates: vanity -> timestamp
updates = {}
with open(updates_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t", 1)
        if len(parts) == 2:
            updates[parts[0]] = parts[1]

if not updates:
    sys.exit(0)

# Rewrite leads.jsonl atomically
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(leads_file), suffix=".jsonl")
try:
    with os.fdopen(tmp_fd, "w") as out:
        with open(leads_file, "r") as inp:
            for line in inp:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    lead = json.loads(raw)
                    vanity = lead.get("vanity", "")
                    if vanity in updates:
                        lead["status"] = "contacted"
                        lead["contacted_at"] = updates[vanity]
                        lead["dm_template"] = dm_template
                    out.write(json.dumps(lead, ensure_ascii=False) + "\n")
                except json.JSONDecodeError:
                    out.write(raw + "\n")
    os.replace(tmp_path, leads_file)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
  fi

  # Report
  if [[ "$dry_run" == true ]]; then
    echo "Dry run complete: $sent messages previewed"
  else
    local remaining
    remaining=$(python3 -c "
import json, sys
leads_file = sys.argv[1]
count = 0
try:
    with open(leads_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lead = json.loads(line)
                if lead.get('status') == 'approved':
                    count += 1
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass
print(count)
" "$LEADS_FILE")
    echo "Done: sent $sent messages, $remaining remaining"
  fi
}

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
