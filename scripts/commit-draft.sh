#!/usr/bin/env bash
# Save a generated draft into drafts/<task>/<year>/ and commit (and push) only that file.
#
# Usage:
#   scripts/commit-draft.sh --task SLUG --file PATH [--title TITLE] [--date YYYY-MM-DD]
#                           [--trailer "Key: value"]... [--no-push]
#
#   --task     folder name under tasks/ (e.g. automated-product-tech-post)
#   --file     the Markdown draft to save (anywhere on disk)
#   --title    defaults to the first "# " heading in the file
#   --date     defaults to today in the task's timezone
#   --trailer  extra commit trailer, repeatable (e.g. "Co-Authored-By: …")
#   --no-push  commit locally only
#
# Safe to re-run: an identical draft already in the repo is a no-op, and a
# different draft with the same name gets a -2, -3… suffix instead of overwriting.
# The draft is secret-scanned before commit; other staged changes are left alone.
set -euo pipefail

die() { echo "commit-draft: $*" >&2; exit 1; }

task="" src="" title="" date="" push=1
trailers=()
while [ $# -gt 0 ]; do
  case "$1" in
    --task)    task="${2:-}"; shift 2 ;;
    --file)    src="${2:-}"; shift 2 ;;
    --title)   title="${2:-}"; shift 2 ;;
    --date)    date="${2:-}"; shift 2 ;;
    --trailer) trailers+=(--trailer "${2:-}"); shift 2 ;;
    --no-push) push=0; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || die "--task is required"
[ -n "$src" ]  || die "--file is required"
[ -f "$src" ]  || die "file not found: $src"
src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run inside the Scheduled-claude-tasks repo"
cd "$root"
meta="tasks/$task/task.yaml"
[ -f "$meta" ] || die "unknown task '$task' (no $meta)"
[[ "$task" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "task slug must be kebab-case"
[ -s "$src" ] || die "draft is empty: $src"

if [ -z "$date" ]; then
  tz="$(sed -n 's/^[[:space:]]*timezone:[[:space:]]*//p' "$meta" | head -1 | tr -d '"'"'")"
  date="$(TZ="${tz:-UTC}" date +%F)"
fi
[[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--date must be YYYY-MM-DD"

if [ -z "$title" ]; then
  title="$(sed -n 's/^#[[:space:]]\{1,\}//p' "$src" | head -1)"
fi
[ -n "$title" ] || title="draft"
slug="$(printf '%s' "$title" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || printf '%s' "$title")"
slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-60 | sed -E 's/-+$//')"
[ -n "$slug" ] || slug="draft"

dir="drafts/$task/${date:0:4}"
dest="$dir/$date-$slug.md"
n=2
while [ -e "$dest" ]; do
  if cmp -s "$src" "$dest"; then
    echo "commit-draft: identical draft already saved at $dest; nothing to do"
    exit 0
  fi
  dest="$dir/$date-$slug-$n.md"; n=$((n + 1))
done

mkdir -p "$dir"
cp "$src" "$dest"
git add -- "$dest"

if ! scripts/check-secrets.sh "$dest"; then
  git rm --cached --quiet -- "$dest"; rm -f -- "$dest"
  die "secret scan failed; draft NOT saved"
fi

# Fallback identity for unattended runs where git has none configured.
ident=()
git config user.email >/dev/null || ident=(-c "user.name=${GIT_AUTHOR_NAME:-Claude scheduled task}" -c "user.email=${GIT_AUTHOR_EMAIL:-noreply@anthropic.com}")

git "${ident[@]}" commit --quiet -m "draft($task): $title ($date)" "${trailers[@]}" -- "$dest"
echo "commit-draft: committed $dest"

[ "$push" -eq 1 ] || { echo "commit-draft: --no-push, skipping push"; exit 0; }
git remote get-url origin >/dev/null 2>&1 || { echo "commit-draft: no 'origin' remote; committed locally only"; exit 0; }

branch="$(git rev-parse --abbrev-ref HEAD)"
for attempt in 1 2 3; do
  if git push --quiet origin "HEAD:$branch"; then
    echo "commit-draft: pushed to origin/$branch"
    exit 0
  fi
  echo "commit-draft: push failed (attempt $attempt); rebasing on origin/$branch" >&2
  git "${ident[@]}" pull --rebase --quiet origin "$branch" || die "rebase failed; resolve manually"
  sleep $((attempt * 2))
done
die "push failed after 3 attempts; the commit is saved locally"
