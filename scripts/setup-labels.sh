#!/usr/bin/env bash
# setup-labels.sh — Create all required Symphony labels in a GitHub repository.
#
# Usage:
#   bash scripts/setup-labels.sh [--repo owner/repo]
#
# Options:
#   --repo owner/repo   Target repository (defaults to current repo via gh repo view)
#
# Requires: gh CLI authenticated with repo write access
set -euo pipefail

REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

echo "Setting up Symphony labels in $REPO"

created=0
skipped=0

create_label() {
  local name="$1"
  local color="$2"
  local description="$3"

  if gh label create "$name" \
      --repo "$REPO" \
      --color "$color" \
      --description "$description" 2>/dev/null; then
    echo "  created: $name"
    ((created++))
  else
    echo "  skipped: $name (already exists)"
    ((skipped++))
  fi
}

create_label "symphony:todo"        "e4e669" "Issue queued for Symphony to implement"
create_label "symphony:claimed"     "f9d0c4" "Symphony agent has claimed this issue"
create_label "symphony:in-progress" "f29513" "Symphony agent is actively implementing"
create_label "symphony:pr-open"     "0075ca" "Symphony has opened a PR for this issue"
create_label "symphony:reviewing"   "6f42c1" "PR is under automated review"
create_label "symphony:done"        "0e8a16" "Symphony successfully completed this issue"
create_label "symphony:failed"      "d93f0b" "Symphony encountered an error"

echo ""
echo "Done. Created: $created, Skipped: $skipped"
