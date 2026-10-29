# Workflow: committing a new draft to GitHub

Use this whenever a draft should land in `drafts/`, either by hand or from inside a scheduled run.

## How authentication works (no tokens in this repo)

Claude sessions reach GitHub through the GitHub connection on your Claude account (claude.ai → Settings → Connectors → GitHub, with the Claude GitHub App given access to `Scheduled-claude-tasks`). When a session attaches the repository with push access, git push works through that connection. Nothing in this repository stores or needs a token, and no step below should ever write one to disk.

If you run the script on your own computer instead, your normal `gh auth login` / git credential helper is used.

## Steps

1. **Get the repo** into the session (Claude: attach `sathishkumarcodes/Scheduled-claude-tasks` with push access), then:
   ```bash
   git clone https://github.com/sathishkumarcodes/Scheduled-claude-tasks.git
   cd Scheduled-claude-tasks && scripts/install-hooks.sh
   ```
2. **Write the draft** to a Markdown file outside the repo, e.g. `/tmp/draft.md`, starting with a `# Headline` line.
3. **Commit it**:
   ```bash
   scripts/commit-draft.sh --task automated-product-tech-post --file /tmp/draft.md
   ```
   The script names the file `drafts/<task>/<YYYY>/<date>-<title>.md`, secret-scans it, commits only that file, and pushes (rebasing and retrying if the remote moved). Re-running with the same draft does nothing; a different draft with the same title gets a `-2` suffix.
4. **Report** the saved path and commit in the run's message.

## Optional: text to add to a scheduled task's instructions

Adding this changes what the task does on every run, so only add it to the live task after you've confirmed you want it (Claude will ask before updating a scheduled task).

```markdown
# 10. Save the draft to GitHub

After the draft is final:
1. Attach the GitHub repository sathishkumarcodes/Scheduled-claude-tasks to this session with push access. If that is refused, skip this section and say so in your message.
2. Clone it and run scripts/install-hooks.sh.
3. Save the complete draft as Markdown to a temporary file outside the repo, with the headline as the first "# " line.
4. Run: scripts/commit-draft.sh --task automated-product-tech-post --file <that file>
5. Include the saved path from the script's output in your delivery message. Never write tokens or credentials to any file.
```
