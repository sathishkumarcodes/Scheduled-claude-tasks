#!/usr/bin/env bash
# One-time per clone: point git at the repo's versioned hooks (secret scan + task validation).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chmod +x hooks/* scripts/*.sh
git config core.hooksPath hooks
echo "Hooks installed (core.hooksPath=hooks)."
