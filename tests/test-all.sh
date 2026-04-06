#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

run_test() {
  local name="$1"; shift
  echo -n "  $name ... "
  if output=$("$@" 2>&1); then
    # Check it's valid JSON
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
      echo "PASS"
      PASS=$((PASS + 1))
    else
      echo "FAIL (invalid JSON)"
      echo "    $output" | head -3
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL (exit $?)"
    echo "    $output" | head -3
    FAIL=$((FAIL + 1))
  fi
}

echo "LinkedIn CLI Adapter Smoke Tests"
echo "================================"

# Read-only tests
run_test "timeline (read)" opencli linkedin timeline --limit 1 --format json
run_test "search (read)" opencli linkedin search "software engineer" --limit 1 --format json

# Write dry-run tests
run_test "post (dry-run)" opencli linkedin post "Test" --dry-run --format json
run_test "like (dry-run)" opencli linkedin like "https://www.linkedin.com/feed/update/urn:li:activity:7314825673041756161/" --dry-run --format json
run_test "comment (dry-run)" opencli linkedin comment "https://www.linkedin.com/feed/update/urn:li:activity:7314825673041756161/" --text "test" --dry-run --format json
run_test "repost (dry-run)" opencli linkedin repost "https://www.linkedin.com/feed/update/urn:li:activity:7314825673041756161/" --dry-run --format json
run_test "send-dm (dry-run)" opencli linkedin send-dm "williamhgates" --text "test" --dry-run --format json

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
