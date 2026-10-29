#!/usr/bin/env bash
# Scan files for credentials before they reach GitHub.
#
# Usage:
#   scripts/check-secrets.sh --staged      # files staged for commit (pre-commit hook)
#   scripts/check-secrets.sh --all         # every tracked file (CI)
#   scripts/check-secrets.sh FILE [FILE…]  # specific files
#
# Uses gitleaks as well when it is installed; the built-in patterns always run.
# Exit code 1 means a likely secret was found and the commit should not proceed.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${1:---staged}"
files=()
case "$mode" in
  --staged) mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR) ;;
  --all)    mapfile -t files < <(git ls-files) ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
  *)        files=("$@") ;;
esac

[ "${#files[@]}" -eq 0 ] && { echo "check-secrets: nothing to scan"; exit 0; }

# High-signal token formats plus generic "key = long value" assignments.
patterns=(
  'sk-ant-[A-Za-z0-9_-]{20,}'                              # Anthropic
  'sk-(proj-)?[A-Za-z0-9_-]{32,}'                          # OpenAI-style
  'gh[pousr]_[A-Za-z0-9]{36,}'                             # GitHub tokens
  'github_pat_[A-Za-z0-9_]{60,}'                           # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                                       # AWS access key id
  'AIza[0-9A-Za-z_-]{35}'                                  # Google API key
  'ya29\.[0-9A-Za-z_-]{20,}'                               # Google OAuth access token
  'xox[abprs]-[A-Za-z0-9-]{10,}'                           # Slack
  'sk_live_[0-9a-zA-Z]{24,}'                               # Stripe live key
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                     # Private keys
  '(api[_-]?key|secret|token|passw(or)?d|bearer)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_./+=-]{16,}["'"'"']'
)
combined="$(IFS='|'; echo "${patterns[*]}")"

found=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  # In --staged mode scan the staged blob, not the working copy.
  if [ "$mode" = "--staged" ]; then
    content="$(git show ":$f" 2>/dev/null || true)"
  else
    content="$(cat -- "$f")"
  fi
  # Skip binary content.
  if printf '%s' "$content" | grep -qI . 2>/dev/null || [ -z "$content" ]; then :; else continue; fi
  if hits="$(printf '%s\n' "$content" | grep -nEi -- "$combined" | grep -v 'check-secrets: allow')"; then
    # Print line numbers only, never the matched value.
    while IFS= read -r line; do
      echo "check-secrets: possible secret in $f:${line%%:*}" >&2
    done <<<"$hits"
    found=1
  fi
done

if command -v gitleaks >/dev/null 2>&1; then
  if [ "$mode" = "--staged" ]; then
    gitleaks protect --staged --redact --no-banner || found=1
  else
    gitleaks detect --no-git --source . --redact --no-banner || found=1
  fi
fi

if [ "$found" -ne 0 ]; then
  cat >&2 <<'EOF'
check-secrets: blocked. Remove the secret (and rotate it if it was ever pushed).
If a line is a deliberate, harmless example, append the comment "check-secrets: allow".
EOF
  exit 1
fi
echo "check-secrets: clean (${#files[@]} file(s))"
