#!/usr/bin/env bash
# setup-labels.sh — Create all required Symphony labels in a GitHub repository.
#
# Usage:
#   bash scripts/setup-labels.sh [--repo owner/repo]
#
# If --repo is omitted, the current repository is detected via `gh repo view`.
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

# name, color (hex without #), description
LABELS=(
  "symphony:todo|0075ca|Issue queued for Symphony to implement"
  "symphony:claimed|e4e669|Issue claimed by a Symphony worker"
  "symphony:in-progress|fbca04|Symphony is actively implementing this issue"
  "symphony:pr-open|0052cc|Pull request opened by Symphony"
  "symphony:reviewing|bfd4f2|Symphony PR is under review"
  "symphony:done|0e8a16|Symphony successfully completed this issue"
  "symphony:failed|d93f0b|Symphony was unable to complete this issue"
)

created=0
skipped=0

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color description <<< "$entry"
  if gh label create "$name" \
       --repo "$REPO" \
       --color "$color" \
       --description "$description" 2>/dev/null; then
    echo "Created:  $name"
    (( created++ )) || true
  else
    echo "Skipped:  $name (already exists)"
    (( skipped++ )) || true
  fi
done

echo ""
echo "Summary: $created created, $skipped skipped."
