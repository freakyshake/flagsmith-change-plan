#!/usr/bin/env bash
# apply.sh <plan-id|last> [--confirm yes|<env name>]
# Applies an approved plan: stale-plan guard -> approval -> change -> verify -> journal commit.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=fsapi.sh
. "$here/fsapi.sh"

[[ $# -ge 1 ]] || { sed -n '2,3s/^# //p' "${BASH_SOURCE[0]}"; exit 2; }
id=$1; shift; supplied=""
while [[ $# -gt 0 ]]; do
  case $1 in --confirm) supplied=$2; shift 2 ;; *) die "unknown option '$1'" ;; esac
done

cd "$(repo_root)"
if [[ $id == last ]]; then
  pf=$(ls -1 "$PLANS_DIR"/*.plan 2>/dev/null | sort | tail -n1) || true
  [[ -n $pf ]] || die "no plans in $PLANS_DIR"
else
  pf="$PLANS_DIR/$id.plan"
fi
[[ -f $pf ]] || die "plan not found: $pf (run plan.sh first)"

id=$(rec_get "$pf" id) action=$(rec_get "$pf" action) feature=$(rec_get "$pf" feature)
fid=$(rec_get "$pf" feature_id) env_key=$(rec_get "$pf" env_key) env_nm=$(rec_get "$pf" env_name)
protected=$(rec_get "$pf" protected) before=$(rec_get "$pf" before) after=$(rec_get "$pf" after)
risk=$(rec_get "$pf" risk)

[[ ! -f $CHANGES_DIR/$id.change ]] || die "plan $id was already applied"
case $risk in NOOP|BLOCKED) die "plan risk is $risk: nothing to apply" ;; esac

now=$(state_of "$action" "$feature" "$env_key")
[[ $now == "$before" ]] || die "stale plan: state is now '$now' (planned from '$before'). Re-run plan.sh"
[[ -z $(running_experiments "$fid" "$env_key") ]] || die "an experiment started on '$feature' since the plan: refusing"

printf 'APPLY %s: %s %s in %s  [%s -> %s]  risk %s\n' "$id" "$action" "$feature" "$env_nm" "$before" "${after#*=}" "$risk"
confirm_change "$protected" "$env_nm" "$supplied"

transition "$feature" "$env_key" "$after"
verified=api
verify_state "$action" "$feature" "$env_key" "$after" || verified=failed
if [[ $verified == api && $action =~ ^(enable|disable)$ ]]; then
  verify_sdk "$feature" "$env_key" "$after" && verified=api+sdk || verified="api (sdk pending)"
fi

mkdir -p "$CHANGES_DIR"
rec="$CHANGES_DIR/$id.change"
{ grep -v '^created=' "$pf"; printf 'applied=%s\nverified=%s\n' "$(date -u +%FT%TZ)" "$verified"; } > "$rec"
git add -- "$rec"
git commit -q -m "flag-change($id): $action $feature in $env_nm" \
  -m "state: $before -> ${after#*=} | risk: $risk | verified: $verified" \
  -m "undo: bash skills/flagsmith-change-plan/scripts/undo.sh $id  (or: git revert this commit)" -- "$rec"

printf '  %-9s %s\n  %-9s %s\n  %-9s %s\n' verified "$verified" journal "$rec ($(git rev-parse --short HEAD))" \
  undo "bash ${here#"$PWD"/}/undo.sh $id   # 0 tokens"
[[ $verified != failed ]] || exit 1
