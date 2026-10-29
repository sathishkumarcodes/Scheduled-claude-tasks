#!/usr/bin/env bash
# Scaffold a new task folder from templates/task/.
# Usage: scripts/new-task.sh my-task-slug "My Task Name"
# This only creates files in the repo; it does NOT schedule anything in Claude.
set -euo pipefail
slug="${1:?usage: new-task.sh SLUG \"Task Name\"}"
name="${2:?usage: new-task.sh SLUG \"Task Name\"}"
[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "slug must be kebab-case" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
[ ! -e "tasks/$slug" ] || { echo "tasks/$slug already exists" >&2; exit 1; }

mkdir -p "tasks/$slug" "drafts/$slug"
touch "drafts/$slug/.gitkeep"
cp templates/task/instructions.md "tasks/$slug/instructions.md"
sed -e "s/__SLUG__/$slug/g" -e "s/__NAME__/$name/g" templates/task/task.yaml > "tasks/$slug/task.yaml"
echo "Created tasks/$slug/ and drafts/$slug/. Fill in instructions.md and the schedule, then ask Claude to schedule it."
