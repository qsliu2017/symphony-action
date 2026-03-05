#!/usr/bin/env bash
# assess-and-plan.sh — Ask Claude to assess issue complexity and return a plan.
#
# Required env:
#   ISSUE_JSON          — JSON string from `gh issue view --json`
#   CLAUDE_CODE_OAUTH_TOKEN — Claude.ai OAuth token (or use ANTHROPIC_API_KEY)
#   SYMPHONY_COMPLEXITY_THRESHOLD — "auto" | "never"
#   SYMPHONY_CLAUDE_COMMAND       — binary name (default: claude)
#   SYMPHONY_CLAUDE_MODEL         — optional model flag
#
# Outputs (to stdout): JSON object
#   {"complex": bool, "reason": "...", "sub_issues": [{"title":"...","body":"..."}]}
set -euo pipefail

ISSUE_JSON="${ISSUE_JSON:?ISSUE_JSON is required}"
THRESHOLD="${SYMPHONY_COMPLEXITY_THRESHOLD:-auto}"
CLAUDE_CMD="${SYMPHONY_CLAUDE_COMMAND:-claude}"
CLAUDE_MODEL="${SYMPHONY_CLAUDE_MODEL:-}"

# If complexity splitting is disabled, always return simple
if [[ "$THRESHOLD" == "never" ]]; then
  echo '{"complex":false,"reason":"complexity splitting disabled","sub_issues":[]}'
  exit 0
fi

MODEL_FLAG=""
if [[ -n "$CLAUDE_MODEL" ]]; then
  MODEL_FLAG="--model $CLAUDE_MODEL"
fi

PLAN_PROMPT="You are a planning agent for a software project.

Given the following GitHub issue, assess whether it is complex enough to warrant being broken
into smaller sub-issues, or whether it can be implemented directly in one pass.

ISSUE JSON:
${ISSUE_JSON}

Guidelines for complexity:
- Simple: single-file changes, clear requirements, well-defined scope (< 1 day of work)
- Complex: multiple subsystems, unclear requirements, large refactors, or multiple independent pieces

Respond with ONLY a JSON object — no prose, no markdown fences:
{
  \"complex\": <true|false>,
  \"reason\": \"<one sentence explanation>\",
  \"sub_issues\": [
    {\"title\": \"<sub-issue title>\", \"body\": \"<sub-issue body in markdown>\"}
  ]
}

If complex=false, sub_issues must be an empty array [].
If complex=true, sub_issues must have 2-5 items that together fully cover the parent issue."

RESULT=$(echo "$PLAN_PROMPT" | $CLAUDE_CMD --print $MODEL_FLAG 2>&1)

# Validate that the result is valid JSON
echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d))"
