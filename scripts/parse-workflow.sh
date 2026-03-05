#!/usr/bin/env bash
# parse-workflow.sh — Extract YAML front matter from WORKFLOW.md and emit shell variables.
#
# Usage:
#   eval "$(bash scripts/parse-workflow.sh WORKFLOW.md)"
#
# Outputs (to stdout, safe to eval):
#   SYMPHONY_MAX_CONCURRENT_AGENTS=10
#   SYMPHONY_MAX_TURNS=20
#   SYMPHONY_MAX_RETRY_BACKOFF_MS=300000
#   SYMPHONY_HOOK_AFTER_CREATE="..."
#   SYMPHONY_HOOK_BEFORE_RUN="..."
#   SYMPHONY_HOOK_AFTER_RUN="..."
#   SYMPHONY_HOOK_TIMEOUT_MS=60000
#   SYMPHONY_CLAUDE_COMMAND="claude"
#   SYMPHONY_CLAUDE_MODEL="claude-sonnet-4-6"
#   SYMPHONY_CLAUDE_MAX_TOKENS=8096
#   SYMPHONY_COMPLEXITY_THRESHOLD="auto"
#   SYMPHONY_PROMPT_TEMPLATE="..."   (the body after the front matter)
set -euo pipefail

WORKFLOW_FILE="${1:-WORKFLOW.md}"

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "ERROR: WORKFLOW.md not found at '$WORKFLOW_FILE'" >&2
  exit 1
fi

python3 - "$WORKFLOW_FILE" <<'PYEOF'
import sys
import re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Split on YAML front matter delimiters
match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)', content, re.DOTALL)
if not match:
    yaml_text = ''
    prompt_body = content
else:
    yaml_text = match.group(1)
    prompt_body = match.group(2)

# Parse YAML — try PyYAML first, then fall back to a hand-rolled parser
cfg = {}
try:
    import yaml
    cfg = yaml.safe_load(yaml_text) or {}
except ImportError:
    # Hand-rolled parser that handles block scalars (|) and simple key: value
    lines = yaml_text.splitlines()
    current_section = None
    i = 0
    while i < len(lines):
        line = lines[i]
        # Top-level section: no leading whitespace, ends with ':'
        section_m = re.match(r'^(\w+):\s*$', line)
        if section_m:
            current_section = section_m.group(1)
            if current_section not in cfg:
                cfg[current_section] = {}
            i += 1
            continue
        # Key-value under a section
        kv_m = re.match(r'^  (\w+):\s*(.*)', line)
        if kv_m and current_section:
            key = kv_m.group(1)
            raw_val = kv_m.group(2).strip()
            if raw_val in ('|', '|-', '|+'):
                # Block scalar: collect subsequent lines indented >= 4 spaces
                block_lines = []
                i += 1
                while i < len(lines):
                    if lines[i].startswith('    ') or lines[i] == '':
                        block_lines.append(lines[i][4:] if lines[i].startswith('    ') else '')
                        i += 1
                    else:
                        break
                # Trim trailing blank lines for |- style
                while block_lines and block_lines[-1] == '':
                    block_lines.pop()
                cfg[current_section][key] = '\n'.join(block_lines)
            else:
                cfg[current_section][key] = raw_val.strip('"\'')
                i += 1
            continue
        i += 1

agent = cfg.get('agent', {}) or {}
hooks = cfg.get('hooks', {}) or {}
claude_cfg = cfg.get('claude', {}) or {}
complexity = cfg.get('complexity', {}) or {}

def sh_escape(s):
    return "'" + str(s).replace("'", "'\\''") + "'"

lines = []
lines.append(f"SYMPHONY_MAX_CONCURRENT_AGENTS={sh_escape(agent.get('max_concurrent_agents', 10))}")
lines.append(f"SYMPHONY_MAX_TURNS={sh_escape(agent.get('max_turns', 20))}")
lines.append(f"SYMPHONY_MAX_RETRY_BACKOFF_MS={sh_escape(agent.get('max_retry_backoff_ms', 300000))}")
lines.append(f"SYMPHONY_HOOK_AFTER_CREATE={sh_escape(hooks.get('after_create', ''))}")
lines.append(f"SYMPHONY_HOOK_BEFORE_RUN={sh_escape(hooks.get('before_run', ''))}")
lines.append(f"SYMPHONY_HOOK_AFTER_RUN={sh_escape(hooks.get('after_run', ''))}")
lines.append(f"SYMPHONY_HOOK_TIMEOUT_MS={sh_escape(hooks.get('timeout_ms', 60000))}")
lines.append(f"SYMPHONY_CLAUDE_COMMAND={sh_escape(claude_cfg.get('command', 'claude'))}")
lines.append(f"SYMPHONY_CLAUDE_MODEL={sh_escape(claude_cfg.get('model', 'claude-sonnet-4-6'))}")
lines.append(f"SYMPHONY_CLAUDE_MAX_TOKENS={sh_escape(claude_cfg.get('max_tokens', 8096))}")
lines.append(f"SYMPHONY_COMPLEXITY_THRESHOLD={sh_escape(complexity.get('sub_issue_threshold', 'auto'))}")
lines.append(f"SYMPHONY_PROMPT_TEMPLATE={sh_escape(prompt_body)}")

print('\n'.join(lines))
PYEOF
