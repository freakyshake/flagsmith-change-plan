#!/usr/bin/env bash
# preflight.sh: checks tools, login and project binding. Read-only. Prints one line per check.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=fsapi.sh
. "$here/fsapi.sh"

ok=1
check() { if eval "$2" >/dev/null 2>&1; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s  -> %s\n' "$1" "$3"; ok=0; fi; }

check "git repository"      "git rev-parse --show-toplevel"            "run inside the target repo"
check "flagsmith CLI v2+"   "flagsmith --version | grep -qE 'v?([2-9]|[1-9][0-9])\.'" "install: https://docs.flagsmith.com/integrating-with-flagsmith/CLI"
check "flagsmith login"     "fs auth status"                           "ask the human to run: flagsmith login"
check "project bound"       "[[ -n \$(current_env_key) ]]"             "run: flagsmith init  (or pass -e <env key>)"
check "hook installed"      "grep -q flagsmith-change-plan \"\$(git config --get core.hooksPath || git rev-parse --git-path hooks)/post-commit\"" "optional: bash $here/install-hooks.sh"
command -v gh >/dev/null && check "gh (optional)" "gh auth status" "optional, for issue/PR trail"
[[ $ok == 1 ]]
