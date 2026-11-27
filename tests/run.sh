#!/usr/bin/env bash
# tests/run.sh: end-to-end checks against the seeded demo project (needs `flagsmith login`).
# Usage: bash demo/bootstrap.sh && (cd .demo-workspace && flagsmith init ... && bash ../demo/seed.sh) && bash tests/run.sh
# shellcheck disable=SC2015  # ok() always succeeds, so A && ok || bad is safe here
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$root/skills/flagsmith-change-plan/scripts"
cd "$root/.demo-workspace" || { echo "run demo/bootstrap.sh and demo/seed.sh first"; exit 1; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n%s\n' "$1" "${2:-}" | head -n 6; }
expect() {  # expect <name> <regex> <cmd...>
  local name=$1 re=$2 out; shift 2
  out=$("$@" 2>&1) || true
  if grep -qE "$re" <<< "$out"; then ok "$name"; else bad "$name" "$out"; fi
}
risk_of() { bash "$S/plan.sh" "$@" 2>&1 | awk '$1=="risk"{print $2}'; }
expect_risk() { local want=$1; shift; local got; got=$(risk_of "$@"); [[ $got == "$want" ]] && ok "plan $* -> $want" || bad "plan $* -> $want" "got: $got"; }
enabled() { flagsmith flag get "$1" -e "$2" --jq .enabled; }
DEV=$(flagsmith environment list --jq '.[] | select(.name=="Development") | .api_key')
PROD=$(flagsmith environment list --jq '.[] | select(.name=="Production") | .api_key')

# ---- plan: every risk level -------------------------------------------------------
expect_risk HIGH    disable new_checkout -e Production
expect_risk MEDIUM  enable search_v2 -e Production
expect_risk LOW     disable holiday_banner -e Development
expect_risk BLOCKED disable cta_copy -e Production
expect_risk NOOP    enable new_checkout -e Development
expect_risk BLOCKED archive cta_copy
expect "plan finds CI gate"      'ci-gate +\.github/workflows/deploy\.yml' bash "$S/plan.sh" disable new_checkout -e Production
expect "plan finds overrides"    'overrides +beta_users'                  bash "$S/plan.sh" enable search_v2 -e Production
expect "set-weights rejects unknown variant" 'unknown variant key'        bash "$S/plan.sh" set-weights pricing_copy --weight nope=10 -e Development

# ---- approval guards ----------------------------------------------------------------
bash "$S/plan.sh" disable new_checkout -e Production >/dev/null 2>&1
expect "protected env rejects --confirm yes" "must be exactly 'Production'" bash "$S/apply.sh" last --confirm yes
expect "no approval without tty"             'approval required'           bash "$S/apply.sh" last < /dev/null

# ---- apply -> verify -> journal -> undo ----------------------------------------------
bash "$S/plan.sh" disable holiday_banner -e Development >/dev/null 2>&1
expect "apply verifies via api+sdk" 'verified +api\+sdk' bash "$S/apply.sh" last --confirm yes
[[ $(enabled holiday_banner "$DEV") == false ]] && ok "flag is off after apply" || bad "flag is off after apply"
git log -1 --format=%s | grep -q '^flag-change(' && ok "journal commit" || bad "journal commit"
expect "undo restores, 0 tokens" 'tokens +0' bash "$S/undo.sh" last --confirm yes
[[ $(enabled holiday_banner "$DEV") == true ]] && ok "flag is on after undo" || bad "flag is on after undo"

# ---- git revert -> hook -> undo from history ---------------------------------------------
bash "$S/plan.sh" disable new_checkout -e Production >/dev/null 2>&1
bash "$S/apply.sh" last --confirm Production >/dev/null 2>&1
cid=$(git log -1 --format=%s | sed -n 's/^flag-change(\([^)]*\)).*/\1/p')
expect "revert triggers hook" 'Reverted flag change' git revert --no-edit HEAD
expect "undo reads reverted record" 'restored +enabled=true' bash "$S/undo.sh" "$cid" --confirm Production
[[ $(enabled new_checkout "$PROD") == true ]] && ok "production restored" || bad "production restored"
expect "double undo refused" 'already undone' bash "$S/undo.sh" "$cid" --confirm Production

# ---- drift and stale plans -------------------------------------------------------------
bash "$S/plan.sh" disable holiday_banner -e Development >/dev/null 2>&1
bash "$S/apply.sh" last --confirm yes >/dev/null 2>&1
flagsmith --no-input --yes flag update holiday_banner --enable -e "$DEV" >/dev/null 2>&1
expect "undo refuses on drift" 'someone changed it since' bash "$S/undo.sh" last --confirm yes
bash "$S/plan.sh" disable holiday_banner -e Development >/dev/null 2>&1
flagsmith --no-input --yes flag update holiday_banner --disable -e "$DEV" >/dev/null 2>&1
expect "apply refuses stale plan" 'stale plan' bash "$S/apply.sh" last --confirm yes
flagsmith --no-input --yes flag update holiday_banner --enable -e "$DEV" >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail == 0 ]]
