#!/usr/bin/env bash
# bootstrap.sh: creates .demo-workspace/ (a fresh git repo from app-template) with the undo hook installed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ws="$root/.demo-workspace"

[[ ! -e $ws ]] || { printf 'exists: %s (delete it to start over)\n' "$ws"; exit 1; }
cp -R "$root/demo/app-template" "$ws"
cd "$ws"
git init -q -b main
git config user.name "demo"
git config user.email "demo@example.invalid"
mkdir -p .flagsmith
printf 'prod_pattern=prod|live\n' > .flagsmith/policy
git add -A
git commit -q -m "demo shop"
bash "$root/skills/flagsmith-change-plan/scripts/install-hooks.sh"
printf 'ready: %s\nnext:  cd .demo-workspace && bash ../demo/seed.sh\n' "$ws"
