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

# New adapter tests
run_test "search-people (read)" opencli linkedin search-people "software engineer" --limit 1 --format json
run_test "connections (read)" opencli linkedin connections --limit 1 --format json
run_test "inbox (read)" opencli linkedin inbox --limit 1 --format json
run_test "notifications (read)" opencli linkedin notifications --limit 1 --format json

# Prospect pipeline tests
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
