#!/usr/bin/env bash
# find-open-issues.sh — Find open GitHub issues not yet claimed by Symphony.
#
# Prints a newline-separated list of issue numbers to stdout.
#
# An issue is eligible if it:
#   1. Is open
#   2. Has no symphony:* labels (or only symphony:todo)
#
# Usage:
#   bash scripts/find-open-issues.sh
#
# Required env (set by GitHub Actions automatically):
#   GITHUB_REPOSITORY — e.g. "owner/repo"
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

# Labels that mean "symphony is already handling this"
BUSY_LABELS="symphony:claimed,symphony:in-progress,symphony:pr-open,symphony:reviewing,symphony:done,symphony:failed"

# Fetch open issues and filter out ones with busy labels
ISSUES_RAW=$(gh issue list \
  --repo "$REPO" \
  --state open \
  --json number,labels \
  --limit 100 2>/dev/null || echo "[]")

echo "$ISSUES_RAW" | python3 -c "
import sys, json
busy = set('$BUSY_LABELS'.split(','))
raw = sys.stdin.read().strip()
issues = json.loads(raw) if raw else []
eligible = []
for issue in issues:
    labels = {l['name'] for l in issue.get('labels', [])}
    busy_without_todo = busy - {'symphony:todo'}
    if not labels.intersection(busy_without_todo):
        eligible.append(issue['number'])
for n in eligible:
    print(n)
"
