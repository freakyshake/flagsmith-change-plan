#!/usr/bin/env bash
# undo.sh [last|<change-id>] [--confirm yes|<env name>] [--no-commit]
# Zero-token undo of a journaled change: drift check -> experiment check -> approval -> restore -> verify -> commit.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=fsapi.sh
. "$here/fsapi.sh"

id=${1:-last}; [[ $# -gt 0 ]] && shift
supplied="" commit=1
while [[ $# -gt 0 ]]; do
  case $1 in --confirm) supplied=$2; shift 2 ;; --no-commit) commit=0; shift ;; *) die "unknown option '$1'" ;; esac
done

cd "$(repo_root)"
undone() { [[ -f $UNDONE_DIR/$1.undo ]] || git log -1 --format=%H --grep="^flag-undo($1)" | grep -q .; }

if [[ $id == last ]]; then
  id=""
  for f in $(ls -1 "$CHANGES_DIR"/*.change 2>/dev/null | sort -r); do
    c=$(basename "$f" .change); undone "$c" || { id=$c; break; }
  done
  [[ -n $id ]] || die "no journaled change left to undo"
fi
undone "$id" && die "change $id was already undone"

rec="$CHANGES_DIR/$id.change" tmp=""
if [[ ! -f $rec ]]; then  # reverted away: read it from history
  h=$(git log -1 --format=%H --diff-filter=A -- "$rec")
  [[ -n $h ]] || die "no journal record for $id"
  tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
  git show "$h:$rec" > "$tmp"; rec=$tmp
fi

action=$(rec_get "$rec" action) feature=$(rec_get "$rec" feature) fid=$(rec_get "$rec" feature_id)
env_key=$(rec_get "$rec" env_key) env_nm=$(rec_get "$rec" env_name) protected=$(rec_get "$rec" protected)
before=$(rec_get "$rec" before) after=$(rec_get "$rec" after)

now=$(state_of "$action" "$feature" "$env_key")
if [[ $now != "$after" ]]; then
  printf 'DRIFT %s: %s in %s is now [%s], journal left it at [%s]\n' "$id" "$feature" "$env_nm" "$now" "$after" >&2
  die "someone changed it since: refusing to overwrite. Review, then plan a new change"
fi
[[ -z $(running_experiments "$fid" "$env_key") ]] || die "an experiment is running on '$feature': refusing"

printf 'UNDO %s: %s in %s  [%s -> %s]\n' "$id" "$feature" "$env_nm" "$after" "${before#*=}"
confirm_change "$protected" "$env_nm" "$supplied"

transition "$feature" "$env_key" "$before"
verified=api
verify_state "$action" "$feature" "$env_key" "$before" || verified=failed

mkdir -p "$UNDONE_DIR"
out="$UNDONE_DIR/$id.undo"
printf 'id=%s\nfeature=%s\nenv_name=%s\nrestored=%s\nundone=%s\nverified=%s\n' \
  "$id" "$feature" "$env_nm" "$before" "$(date -u +%FT%TZ)" "$verified" > "$out"
if [[ $commit == 1 ]]; then
  git add -- "$out"
  git commit -q -m "flag-undo($id): restore $feature in $env_nm to ${before#*=}" -m "verified: $verified" -- "$out"
fi
printf '  %-9s %s\n  %-9s %s\n  %-9s 0 (no agent involved)\n' restored "$before" verified "$verified" tokens
[[ $verified != failed ]] || exit 1
