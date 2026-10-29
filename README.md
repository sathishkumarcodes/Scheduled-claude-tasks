# Scheduled-claude-tasks

Version-controlled record of my Claude scheduled tasks: their instructions, their schedules, and the drafts they produce.

This repository is a **source of truth you can review, diff, back up and restore from**. It is not a sync engine: Claude does not read this repo to decide what runs, and pushing a change here does not change a live task. Changes move between the two only when you ask Claude to apply them (see the workflows below).

## What lives where

| Lives in GitHub (this repo) | Managed by Claude (not in this repo) |
|---|---|
| Full task instructions (`tasks/<slug>/instructions.md`) | The live scheduled task and when it actually fires |
| Schedule metadata: name, cron, timezone (`task.yaml`) | Enabled / paused state, next run time, run history |
| The Claude task ID linking each file to its live task | Approval setting (e.g. automatic approval) |
| Generated drafts (`drafts/`) | Connectors attached to the task and their permissions |
| Scripts, hooks, CI checks | Notifications (push / email) |
| A dated, read-only snapshot of the Claude-managed settings | GitHub, Google and other account connections and their credentials |

The `claude_managed_snapshot` block in each `task.yaml` is informational. Editing it does nothing; it records what the settings were at `synced_at` so a restore can recreate them.

## Layout

```
tasks/<slug>/
  instructions.md        exact prompt the task runs, verbatim
  task.yaml              name, schedule (cron + timezone), status, Claude task ID, output location
drafts/<slug>/<YYYY>/    generated drafts, one file per run
docs/                    commit-draft workflow
scripts/
  commit-draft.sh        save + secret-scan + commit + push one draft
  check-secrets.sh       block credentials from being committed
  validate_tasks.py      check every task.yaml
  new-task.sh            scaffold a task folder
  install-hooks.sh       enable the pre-commit hook
hooks/pre-commit         runs the secret scan and validator
templates/task/          starting point for new tasks
.github/workflows/       CI: validation + secret scan on every push
```

## Tasks

| Task | Schedule | Status | Output |
|---|---|---|---|
| [Automated Product Tech Post](tasks/automated-product-tech-post/) | Mondays 11:15 PM Pacific | active | `drafts/automated-product-tech-post/` |

## First-time setup

```bash
git clone https://github.com/sathishkumarcodes/Scheduled-claude-tasks.git
cd Scheduled-claude-tasks
scripts/install-hooks.sh                                          # in every clone
pip install pyyaml                                                # for the validator
```

Optional: install [gitleaks](https://github.com/gitleaks/gitleaks); `check-secrets.sh` runs it automatically when present, in addition to its own patterns.

## Workflows

### Create a task
1. `scripts/new-task.sh my-task "My Task"`, then write `instructions.md` and set `schedule` in `task.yaml`.
2. Commit it.
3. Ask Claude: *"Schedule the task in tasks/my-task from my Scheduled-claude-tasks repo."* Claude first lists your existing scheduled tasks so it doesn't create a duplicate, then creates the task from `instructions.md` and `claude_cron_expression`, and tells you which approval setting it got.
4. Record the returned task ID in `claude_task_id`, set `status: active`, update the snapshot, commit.

### Update a task
1. Edit `instructions.md` and/or `schedule` (keep `claude_cron_expression` equal to `CRON_TZ=<timezone> <cron>`; the validator checks this). Commit.
2. Ask Claude: *"Apply the changes in tasks/my-task to the live scheduled task."* Claude updates the task with that ID in place. It should confirm with you before changing anything about execution (schedule, approval setting, connectors), and never creates a second copy.

### Back up (Claude → GitHub)
Ask Claude: *"Back up my scheduled tasks to Scheduled-claude-tasks."* Claude lists your live tasks and, for each one, writes the current prompt to `instructions.md` and the schedule and settings snapshot to `task.yaml`, then shows you the diff before committing. Any difference from the last commit means a task was changed in Claude outside this repo.

Do this after any edit made directly in Claude, and periodically (e.g. monthly).

### Restore (GitHub → Claude)
Use when a task was deleted or you're moving to a new account.
1. Ask Claude: *"Restore tasks/my-task from Scheduled-claude-tasks."*
2. Claude lists existing tasks first. If one with the same name or ID still exists, it stops and asks whether to update it instead; it does not create a duplicate.
3. Otherwise it creates the task from `instructions.md` and `claude_cron_expression`. Approval mode, connectors and notifications can't all be set from the file; re-apply them in Claude's task settings using the snapshot as a checklist.
4. A restored task gets a **new** task ID; record it and commit.

### Save a draft
See [docs/commit-draft-workflow.md](docs/commit-draft-workflow.md):

```bash
scripts/commit-draft.sh --task automated-product-tech-post --file /path/to/draft.md
```

## Secrets policy

> **This repository is public.** Everything committed here, including task prompts and drafts, is visible to anyone. Make it private in GitHub → Settings → General → Danger Zone → Change visibility if that isn't what you want.


- Never commit API keys, access tokens, passwords, cookies or private keys. Authentication belongs to your Claude connectors and your local git credential helper, never to files here.
- Three layers enforce this: `.gitignore` excludes common secret files, the pre-commit hook scans staged changes, and CI scans the whole repo on every push.
- `claude_task_id` values (`trig_…`) and connector names are identifiers, not credentials.
- If a secret is ever pushed: **rotate it first**, then remove it from history. Deleting the file in a new commit is not enough.

## Validation

```bash
python3 scripts/validate_tasks.py      # task metadata
scripts/check-secrets.sh --all         # whole repo
```
