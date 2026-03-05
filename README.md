# Symphony Action

A reusable GitHub Action that runs an infinite loop of autonomous coding agents on your GitHub
Issues using Claude Code CLI.

**Loop:** Issue opened → Claude implements it on a branch → PR opened → CI runs → Claude reviews
→ merge → find more issues → repeat.

## Quick Start

### 1. Add the Symphony workflow to your repo

Create `.github/workflows/symphony.yml`:

```yaml
name: Symphony
on:
  issues:
    types: [opened, reopened, labeled]
  schedule:
    - cron: '0 * * * *'   # hourly sweep for un-claimed issues
  workflow_dispatch:
    inputs:
      issue_number:
        description: "Issue to work on (leave blank to auto-discover)"
        type: number
        required: false

jobs:
  dispatch:
    uses: <your-org>/symphony-action/.github/workflows/symphony-dispatch.yml@main
    with:
      issue_number: ${{ github.event.issue.number || inputs.issue_number }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}  # alternative: use API key instead

  # Trigger review after CI passes on a symphony PR
  review:
    if: github.event_name == 'pull_request' && startsWith(github.head_ref, 'symphony/issue-')
    uses: <your-org>/symphony-action/.github/workflows/symphony-review.yml@main
    with:
      pr_number: ${{ github.event.pull_request.number }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}  # alternative: use API key instead
```

### 2. Add WORKFLOW.md to your repo root

Copy `WORKFLOW.md.example` to `WORKFLOW.md` and customize the prompt and settings:

```bash
curl -O https://raw.githubusercontent.com/<your-org>/symphony-action/main/WORKFLOW.md.example
mv WORKFLOW.md.example WORKFLOW.md
```

### 3. Add the required secret

In your repo settings → Secrets → Actions, add **one** of:
- `CLAUDE_CODE_OAUTH_TOKEN` — token from `claude setup-token` (Claude.ai Pro/Max subscription)
- `ANTHROPIC_API_KEY` — Anthropic API key (pay-per-token)

### 4. Create GitHub issue labels

Symphony uses these labels to track issue state:

```bash
gh label create "symphony:todo"        --color "#0075ca" --description "Queued for Symphony"
gh label create "symphony:claimed"     --color "#e4e669" --description "Symphony has picked this up"
gh label create "symphony:in-progress" --color "#f9c74f" --description "Symphony is implementing"
gh label create "symphony:pr-open"     --color "#90be6d" --description "Symphony opened a PR"
gh label create "symphony:reviewing"   --color "#43aa8b" --description "Symphony is reviewing the PR"
gh label create "symphony:done"        --color "#2d6a4f" --description "Symphony completed this"
gh label create "symphony:failed"      --color "#e63946" --description "Symphony failed on this issue"
```

Or run the setup script:

```bash
bash <(curl -s https://raw.githubusercontent.com/<your-org>/symphony-action/main/scripts/setup-labels.sh)
```

---

## How It Works

```
Issue opened
     │
     ▼
symphony-dispatch  ──── checks concurrency limit
     │                  (max_concurrent_agents from WORKFLOW.md)
     ▼
symphony-worker    ──── labels issue symphony:in-progress
     │                  assesses complexity
     │                  creates sub-issues if complex
     │                  runs Claude Code on a branch
     │                  opens PR
     ▼
CI runs on PR      ──── your existing test/lint workflows
     │
   CI passes
     │
     ▼
symphony-review    ──── labels issue symphony:reviewing
     │                  runs Claude Code to review the diff
     │                  applies fixes if needed
     │                  merges when clean
     ▼
symphony-post-merge ─── finds remaining open issues
     │                  triggers symphony-dispatch again
     ▼
     (loop)
```

---

## WORKFLOW.md Reference

```yaml
---
agent:
  max_concurrent_agents: 3     # Max parallel Symphony runs (default: 10)
  max_turns: 10                # Max review iterations before giving up (default: 20)
  max_retry_backoff_ms: 300000 # Max backoff between retries

hooks:
  before_run: |                # Shell script run before Claude starts
    npm install
  after_run: |                 # Shell script run after Claude finishes
    npm run lint --fix
  timeout_ms: 120000           # Hook timeout in ms

claude:
  command: claude              # Claude Code CLI binary (default: claude)
  model: claude-sonnet-4-6     # Model to use (default: claude-sonnet-4-6)
  max_tokens: 8096

complexity:
  sub_issue_threshold: auto    # "auto" = Claude decides | "never" = always direct
---

Your prompt template goes here. Available variables:

  {{ issue.number }}   — issue number
  {{ issue.title }}    — issue title
  {{ issue.body }}     — issue body (markdown)
  {{ attempt }}        — retry attempt number (0 = first)

  {% if attempt > 0 %}
  This block only appears on retries.
  {% endif %}
```

---

## Triggering Manually

Dispatch a specific issue:

```bash
gh workflow run symphony.yml \
  --repo your-org/your-repo \
  --field issue_number=42
```

Run a full sweep for unclaimed issues:

```bash
gh workflow run symphony.yml --repo your-org/your-repo
```

---

## Issue State Machine

```
[no label]
    │  (dispatch picks up)
    ▼
[symphony:claimed]
    │
    ▼
[symphony:in-progress]  ← Claude is working
    │
    ├── complex → sub-issues created → [symphony:todo] on each
    │
    └── simple → branch created, PR opened
                     ��
                     ▼
               [symphony:pr-open]  ← CI running
                     │
                 CI passes
                     │
                     ▼
               [symphony:reviewing]  ← Claude reviewing
                     │
                 review clean
                     │
                     ▼
                   merged → closed → [symphony:done]
```

---

## Security Notes

- Symphony runs with your `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`) and a `GITHUB_TOKEN` with write access to issues,
  PRs, and contents.
- Claude Code runs inside GitHub Actions runners with access to your full repository.
- Only use Symphony on repos where you trust automated PRs to be reviewed before merging, or
  in repos with branch protection rules that require CI to pass.
- Consider restricting which issues Symphony picks up by using label filters or issue templates.

---

## Reusable Workflows

All four workflows are reusable (`workflow_call`) and can be composed in any order:

| Workflow | Purpose |
|---|---|
| `symphony-dispatch.yml` | Entry point; discovers and dispatches issues |
| `symphony-worker.yml` | Implements a single issue; opens a PR |
| `symphony-review.yml` | Reviews and merges a PR after CI passes |
| `symphony-post-merge.yml` | Finds remaining issues after a merge |
