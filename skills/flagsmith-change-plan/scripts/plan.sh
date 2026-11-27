#!/usr/bin/env bash
# plan.sh <enable|disable|set-weights|archive> <feature> [-e ENV_KEY] [--weight key=pct ...] [--depth N]
# Read-only. Builds the impact graph, scores risk, writes .flagsmith/plans/<id>.plan, prints a one-screen report.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=fsapi.sh
. "$here/fsapi.sh"

usage() { sed -n '2,3s/^# //p' "${BASH_SOURCE[0]}"; exit 2; }

[[ $# -ge 2 ]] || usage
action=$1 feature=$2; shift 2
env_key="" depth=2 weights=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment) env_key=$2; shift 2 ;;
    --weight) IFS=',' read -r -a w <<< "$2"; weights+=("${w[@]}"); shift 2 ;;
    --depth) depth=$2; shift 2 ;;
    *) usage ;;
  esac
done
case $action in enable|disable|set-weights|archive) ;; *) die "unsupported action '$action' (enable|disable|set-weights|archive)";; esac
[[ $action != set-weights || ${#weights[@]} -gt 0 ]] || die "set-weights needs --weight key=pct"

cd "$(repo_root)"
[[ -n $env_key ]] || env_key=$(current_env_key)
[[ -n $env_key ]] || die "no environment: pass -e <client-side env key> or run 'flagsmith init'"
env_nm=$(env_name "$env_key"); [[ -n $env_nm ]] || die "environment key not found in this project"
protected=0; is_protected_env "$env_nm" && protected=1

fid=$(feature_id "$feature") || die "feature '$feature' not found"
before=$(state_of "$action" "$feature" "$env_key")
case $action in
  enable)      after="enabled=true" ;;
  disable)     after="enabled=false" ;;
  archive)     after="archived=true" ;;
  set-weights) after="weights=$(printf '%s\n' "${weights[@]}" | sort | paste -sd, -)" ;;
esac

edges=$(mktemp); trap 'rm -f "$edges"' EXIT
F="flag:$feature"
emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$edges"; }

emit "$F" state "env:$env_nm" "${before#*=} -> ${after#*=}"
[[ $before == "$after" ]] && emit "$F" noop "env:$env_nm"

while IFS=$'\t' read -r xid xname; do
  [[ -n $xid ]] && emit "$F" experiment_running "experiment:$xid" "$xname"
done < <(running_experiments "$fid" "$env_key")

if [[ $action != archive ]]; then
  while IFS=$'\t' read -r seg en; do
    [[ -n $seg ]] && emit "$F" segment_override "segment:$seg" "enabled=$en"
  done < <(segment_overrides "$feature" "$env_key")
  n_id=$(identity_override_count "$feature" "$env_key")
  [[ ${n_id:-0} -gt 0 ]] && emit "$F" identity_overrides "identities:$n_id" "$n_id identity override(s)"
fi

names=$(mktemp); trap 'rm -f "$edges" "$names"' EXIT
all_feature_names | grep -vxF -- "$feature" > "$names" || true

while IFS=: read -r path line _; do
  [[ -n $path ]] || continue
  case $path in
    .github/workflows/*) ;;
    .flagsmith/*) continue ;;
    *) emit "$F" code_ref "file:$path" "$line"; continue ;;
  esac
  sed -n "${line}p" "$path" | grep -qE 'eval(uate)?[^|;&]*--test|--test[^|;&]*eval' \
    && emit "$F" ci_gate "ci:$path" "$line"
done < <(git grep -n -w -F -- "$feature" 2>/dev/null | head -n 200 || true)

if [[ -s $names ]]; then
  while read -r path; do
    [[ $path == .flagsmith/* || $path == .github/* ]] && continue
    grep -o -w -F -f "$names" "$path" 2>/dev/null | sort -u | while read -r other; do
      emit "file:$path" co_located "flag:$other"
    done
  done < <(git grep -l -w -F -- "$feature" 2>/dev/null || true)
fi

result=$(awk -v start="$F" -v maxdepth="$depth" -v action="$action" -v protected="$protected" \
  -f "$here/graph.awk" "$edges")
risk=$(printf '%s\n' "$result" | awk -F'\t' '$1=="RISK"{print $2}')
reasons=$(printf '%s\n' "$result" | awk -F'\t' '$1=="RISK"{print $3}')

case $action in
  enable)      fwd="flagsmith flag update $feature --enable -e $env_key";  rev="flagsmith flag update $feature --disable -e $env_key" ;;
  disable)     fwd="flagsmith flag update $feature --disable -e $env_key"; rev="flagsmith flag update $feature --enable -e $env_key" ;;
  set-weights) fwd="flagsmith flag update $feature --weight ${after#weights=} -e $env_key"
               rev="flagsmith flag update $feature --weight ${before#weights=} -e $env_key" ;;
  archive)     fwd="flagsmith feature update $feature --archive"; rev="flagsmith feature update $feature --unarchive" ;;
esac

id=$(new_id "$action" "$feature")
mkdir -p "$PLANS_DIR"
[[ -f $FCP_DIR/.gitignore ]] || printf 'plans/\n' > "$FCP_DIR/.gitignore"
pf="$PLANS_DIR/$id.plan"
{
  printf 'id=%s\naction=%s\nfeature=%s\nfeature_id=%s\n' "$id" "$action" "$feature" "$fid"
  printf 'env_key=%s\nenv_name=%s\nprotected=%s\n' "$env_key" "$env_nm" "$protected"
  printf 'before=%s\nafter=%s\nrisk=%s\nreasons=%s\n' "$before" "$after" "$risk" "$reasons"
  printf 'forward=%s\nreverse=%s\ncreated=%s\n' "$fwd" "$rev" "$(date -u +%FT%TZ)"
} > "$pf"

# ---- report --------------------------------------------------------------------
show() {  # show <kind> <label>: up to 3 items, then "+N more"
  printf '%s\n' "$result" | awk -F'\t' -v k="$1" -v label="$2" '
    $1=="N" && $3==k { n++; d=$4; sub(/^[a-z_]+:/, "", d); if (n<=3) items = items (n>1?", ":"") d ($5!=""?" ("$5")":"") }
    END { if (n) printf "  %-11s %s%s\n", label, items, (n>3?" (+" n-3 " more)":"") }'
}
printf 'PLAN %s\n' "$id"
printf '  %-11s %s %s in %s%s  [%s -> %s]\n' change "$action" "$feature" "$env_nm" \
  "$([[ $protected == 1 ]] && printf ' (protected)')" "$before" "${after#*=}"
printf '  %-11s %s  (%s)\n' risk "$risk" "$reasons"
show experiment_running experiment
show code_ref code
show ci_gate ci-gate
show segment_override overrides
show identity_overrides identities
show co_located related
case $risk in
  NOOP|BLOCKED) printf '  %-11s nothing to apply\n' next ;;
  *) printf '  %-11s %s\n  %-11s %s\n' will-run "$fwd" rollback "$rev"
     printf '  %-11s bash %s/apply.sh %s --confirm %s\n' next "${here#"$PWD"/}" "$id" \
       "$([[ $protected == 1 ]] && printf '%q' "$env_nm" || printf yes)" ;;
esac
