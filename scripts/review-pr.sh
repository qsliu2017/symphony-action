#!/usr/bin/env bash
# review-pr.sh �� Ask Claude to review a PR diff and apply fixes if needed.
#
# Required env:
#   PR_NUMBER           — GitHub PR number
#   ISSUE_JSON          — JSON from `gh issue view --json` for the linked issue
#   SYMPHONY_CLAUDE_COMMAND   — binary name (default: claude)
#   SYMPHONY_CLAUDE_MODEL     — optional model override
#   CLAUDE_CODE_OAUTH_TOKEN   — Claude.ai OAuth token (or use ANTHROPIC_API_KEY)
#
# Exit codes:
#   0 — review complete, no changes needed (ready to merge)
#   1 — error
#
# Side effects:
#   If changes needed: commits and pushes them to the PR branch.
set -euo pipefail

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
ISSUE_JSON="${ISSUE_JSON:-{}}"
CLAUDE_CMD="${SYMPHONY_CLAUDE_COMMAND:-claude}"
CLAUDE_MODEL="${SYMPHONY_CLAUDE_MODEL:-}"
MAX_TURNS="${SYMPHONY_MAX_TURNS:-5}"

MODEL_FLAG=""
if [[ -n "$CLAUDE_MODEL" ]]; then
  MODEL_FLAG="--model $CLAUDE_MODEL"
fi

ISSUE_TITLE=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null || echo "")
ISSUE_BODY=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body',''))" 2>/dev/null || echo "")

echo "=== Fetching PR diff for PR #${PR_NUMBER} ===" >&2
PR_DIFF=$(gh pr diff "$PR_NUMBER" 2>&1 || echo "(no diff available)")
PR_INFO=$(gh pr view "$PR_NUMBER" --json title,body,headRefName 2>&1 || echo "{}")

for iteration in $(seq 1 "$MAX_TURNS"); do
  echo "=== Review iteration ${iteration}/${MAX_TURNS} ===" >&2

  REVIEW_PROMPT="You are a code reviewer for a software project.

ISSUE being resolved:
Title: ${ISSUE_TITLE}
Body: ${ISSUE_BODY}

PULL REQUEST:
$(echo "$PR_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Title: {d.get(\"title\",\"\")}\\nBranch: {d.get(\"headRefName\",\"\")}')" 2>/dev/null || echo "$PR_INFO")

PR DIFF:
${PR_DIFF}

Review this pull request and determine if it correctly and completely resolves the issue.
Check for:
1. Does it actually solve what the issue asks for?
2. Are there bugs, logic errors, or missing edge cases?
3. Are there obvious style/quality issues that should be fixed?
4. Is the implementation complete, or are there TODOs or stubs?

Respond with ONLY a JSON object — no prose, no markdown fences:
{
  \"changes_needed\": <true|false>,
  \"explanation\": \"<concise summary of findings>\",
  \"changes\": \"<if changes_needed=true: describe exactly what to fix; if false: leave empty>\"
}

If changes_needed=true, after outputting the JSON, you will need to make the actual file edits
using your tools. Make the minimum changes needed to fix the issues identified."

  REVIEW_RESULT=$(echo "$REVIEW_PROMPT" | $CLAUDE_CMD --print --dangerously-skip-permissions $MODEL_FLAG 2>&1)

  # Extract JSON from the result (Claude may include extra text)
  REVIEW_JSON=$(echo "$REVIEW_RESULT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# Find JSON object in the output
match = re.search(r'\{[^{}]*\"changes_needed\"[^{}]*\}', text, re.DOTALL)
if match:
    obj = json.loads(match.group(0))
    print(json.dumps(obj))
else:
    # Try parsing whole output as JSON
    print(json.dumps(json.loads(text.strip())))
" 2>/dev/null || echo '{"changes_needed":false,"explanation":"Could not parse review output","changes":""}')

  CHANGES_NEEDED=$(echo "$REVIEW_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('changes_needed',False)).lower())")
  EXPLANATION=$(echo "$REVIEW_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('explanation',''))")

  echo "Changes needed: ${CHANGES_NEEDED}" >&2
  echo "Explanation: ${EXPLANATION}" >&2

  if [[ "$CHANGES_NEEDED" == "false" ]]; then
    echo "=== Review passed — no changes needed ===" >&2
    exit 0
  fi

  # Claude needs to make changes — run Claude again with edit permissions
  CHANGES=$(echo "$REVIEW_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('changes',''))")

  FIX_PROMPT="You are fixing issues found during PR review.

Issues to fix:
${CHANGES}

Please make the necessary changes to the files in the current directory to address these issues.
Do not open a PR or create new branches — just edit the files directly."

  echo "=== Applying review fixes ===" >&2
  echo "$FIX_PROMPT" | $CLAUDE_CMD --print --dangerously-skip-permissions $MODEL_FLAG

  # Check if there are changes to commit
  if git diff --quiet && git diff --staged --quiet; then
    echo "=== No file changes after review fix — treating as done ===" >&2
    exit 0
  fi

  # Commit and push the fixes
  git add -A
  git commit -m "review: apply fixes from review iteration ${iteration}"
  git push

  # Re-fetch the diff for the next iteration
  PR_DIFF=$(gh pr diff "$PR_NUMBER" 2>&1 || echo "(no diff available)")

  echo "=== Waiting for CI to process new push ===" >&2
  # Give CI a moment to register the new commit before next review loop
  sleep 10
done

echo "ERROR: Exceeded max review iterations (${MAX_TURNS})" >&2
exit 1
