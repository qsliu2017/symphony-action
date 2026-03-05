---
agent:
  max_concurrent_agents: 2
  max_turns: 5

claude:
  model: claude-sonnet-4-6

complexity:
  sub_issue_threshold: never
---

You are working on issue #{{ issue.number }}: {{ issue.title }}

## Issue Description

{{ issue.body }}

{% if attempt > 0 %}
## Retry Attempt {{ attempt }}

This is retry attempt {{ attempt }}. Review any existing work on this branch and continue.
{% endif %}

## Instructions

You are improving the `symphony-action` GitHub Action — a reusable workflow that orchestrates
Claude Code agents to autonomously implement GitHub Issues.

The repository structure:
- `scripts/` — shell scripts called by the workflows
- `.github/workflows/symphony-*.yml` — reusable GitHub Actions workflows
- `action.yml` — composite action entry point
- `WORKFLOW.md.example` — template for consuming repos

Please implement the changes needed to resolve this issue. Follow existing code style.
Do not open a PR or commit — the orchestrator handles that.
