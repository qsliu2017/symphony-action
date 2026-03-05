#!/usr/bin/env bash
# implement-issue.sh ��� Run Claude Code to implement a GitHub issue.
#
# Required env:
#   ISSUE_NUMBER        — GitHub issue number
#   ISSUE_JSON          — JSON from `gh issue view --json`
#   ATTEMPT             — retry attempt number (default: 0)
#   SYMPHONY_PROMPT_TEMPLATE  — Jinja2-like template from WORKFLOW.md body
#   SYMPHONY_CLAUDE_COMMAND   — binary name (default: claude)
#   SYMPHONY_CLAUDE_MODEL     — optional model override
#   CLAUDE_CODE_OAUTH_TOKEN   — Claude.ai OAuth token (or use ANTHROPIC_API_KEY)
set -euo pipefail

ISSUE_NUMBER="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
ISSUE_JSON="${ISSUE_JSON:?ISSUE_JSON is required}"
ATTEMPT="${ATTEMPT:-0}"
PROMPT_TEMPLATE="${SYMPHONY_PROMPT_TEMPLATE:-}"
CLAUDE_CMD="${SYMPHONY_CLAUDE_COMMAND:-claude}"
CLAUDE_MODEL="${SYMPHONY_CLAUDE_MODEL:-}"

MODEL_FLAG=""
if [[ -n "$CLAUDE_MODEL" ]]; then
  MODEL_FLAG="--model $CLAUDE_MODEL"
fi

# Render the prompt template.
# Supports simple {{ variable }} substitution using Python.
render_prompt() {
  python3 - "$PROMPT_TEMPLATE" "$ISSUE_JSON" "$ATTEMPT" <<'PYEOF'
import sys
import json
import re

template = sys.argv[1]
issue_raw = sys.argv[2]
attempt = int(sys.argv[3])

issue = json.loads(issue_raw)

# Simple {{ expr }} substitution — no loops, just variable access
def replacer(m):
    expr = m.group(1).strip()
    # Support dot-access: issue.number, issue.title, issue.body
    parts = expr.split('.')
    if parts[0] == 'issue' and len(parts) == 2:
        return str(issue.get(parts[1], ''))
    if expr == 'attempt':
        return str(attempt)
    return m.group(0)  # leave unknown expressions as-is

result = re.sub(r'\{\{\s*(.*?)\s*\}\}', replacer, template)

# Handle {% if attempt > 0 %} ... {% endif %} blocks
def if_block(m):
    condition_str = m.group(1).strip()
    body = m.group(2)
    try:
        # Safe evaluation: only allow comparison of 'attempt'
        cond_match = re.match(r'^attempt\s*([><=!]+)\s*(\d+)$', condition_str)
        if cond_match:
            op, val = cond_match.group(1), int(cond_match.group(2))
            ops = {'>': attempt > val, '<': attempt < val, '>=': attempt >= val,
                   '<=': attempt <= val, '==': attempt == val, '!=': attempt != val}
            return body if ops.get(op, False) else ''
    except Exception:
        pass
    return ''

result = re.sub(r'\{%\s*if\s+(.*?)\s*%\}(.*?)\{%\s*endif\s*%\}', if_block, result, flags=re.DOTALL)
print(result, end='')
PYEOF
}

# Build the prompt
if [[ -n "$PROMPT_TEMPLATE" ]]; then
  RENDERED_PROMPT="$(render_prompt)"
else
  # Default prompt if no WORKFLOW.md template configured
  ISSUE_TITLE=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))")
  ISSUE_BODY=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body',''))")
  RENDERED_PROMPT="You are working on issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

Please implement the changes needed to resolve this issue. When done, do not open a PR —
the orchestrator will handle that. Commit any changes to the current branch."
fi

if [[ "$ATTEMPT" -gt 0 ]]; then
  RENDERED_PROMPT="${RENDERED_PROMPT}

(Retry attempt ${ATTEMPT} — please review any existing work on this branch and continue or fix it.)"
fi

echo "=== Running Claude Code for issue #${ISSUE_NUMBER} (attempt ${ATTEMPT}) ===" >&2
echo "$RENDERED_PROMPT" | $CLAUDE_CMD --print $MODEL_FLAG
