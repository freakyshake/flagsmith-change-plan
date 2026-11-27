#!/usr/bin/env bash
# Flagsmith CLI adapters: the only place that knows JSON field names.
# Field names are verified against Flagsmith Cloud + CLI v2.0.0, see references/CLI-FIELDS.md. Sourced after lib.sh.

# safe_name <value>: names are interpolated into --jq filters, so only allow a strict charset
safe_name() { [[ $1 =~ ^[A-Za-z0-9_.:-]+$ ]] || die "unsupported characters in '$1'"; }

# resolve_env <key-or-name> -> "api_key<TAB>name" (flagsmith.json accepts either)
resolve_env() {
  safe_name "$1"
  fs environment list --jq ".[] | select(.api_key == \"$1\" or .name == \"$1\") | \"\(.api_key)\t\(.name)\""
}

# current_env: the environment in effect (FLAGSMITH_ENVIRONMENT, -e or flagsmith.json)
current_env() { fs config --jq '.environment.value // empty' 2>/dev/null || true; }

project_id() { fs config --jq '.project.value // empty'; }

# feature_id <feature>: works for archived features too
feature_id() {
  safe_name "$1"
  fs feature list --include-archived --jq ".[] | select(.name == \"$1\") | .id"
}

# feature_archived <feature_id> -> true|false (not exposed by `feature get`, so read the API)
feature_archived() { fs api "api/v1/projects/$(project_id)/features/$1/" --jq '.is_archived'; }

# flag_enabled <feature> <env_key> -> true|false
flag_enabled() { fs flag get "$1" -e "$2" --jq '.enabled'; }

# flag_weights <feature> <env_key> -> "key=pct,key=pct" sorted (control gets the rest)
flag_weights() { fs flag get "$1" -e "$2" --jq '[.variants[]? | "\(.key)=\(.weight)"] | sort | join(",")'; }

# override_counts <feature> <env_key> -> "<segments> <identities>"
override_counts() { fs flag get "$1" -e "$2" --jq '"\(.segment_overrides) \(.identity_overrides)"'; }

# segment_overrides <feature> <env_key> -> lines: name<TAB>enabled
segment_overrides() {
  fs flag list --feature "$1" -e "$2" --jq '.[] | "\(.segment.name)\t\(.enabled)"' 2>/dev/null || true
}

# running_experiments <feature_id> <env_key> -> lines: id<TAB>name
running_experiments() {
  fs api "api/v1/environments/$2/experiments/" \
    --jq ".results[] | select((.feature.id? // .feature) == $1 and .status == \"running\") | \"\(.id)\t\(.name)\"" 2>/dev/null || true
}

# all_feature_names -> one per line
all_feature_names() { fs feature list --jq '.[].name'; }

# transition <feature> <feature_id> <env_key> <target_state>: apply = after, undo = before. No eval.
# --yes: the CLI's own prompt is replaced by this skill's approval step (confirm_change).
transition() {
  local feature=$1 env_key=$3 target=$4 out
  local -a cmd
  case $target in
    enabled=true)   cmd=(flag update "$feature" --enable -e "$env_key") ;;
    enabled=false)  cmd=(flag update "$feature" --disable -e "$env_key") ;;
    weights=*)      cmd=(flag update "$feature" --weight "${target#weights=}" -e "$env_key") ;;
    archived=true)  cmd=(feature update "$feature" --archive) ;;
    archived=false) cmd=(feature update "$feature" --unarchive) ;;
    *) die "unknown target state '$target'" ;;
  esac
  out=$(fs --yes "${cmd[@]}" 2>&1) || { printf '%s\n' "$out" | head -n 5 >&2; die "flagsmith ${cmd[*]:0:2} failed"; }
}

# state_of <action> <feature> <feature_id> <env_key> -> canonical state string
state_of() {
  case $1 in
    enable|disable) printf 'enabled=%s' "$(flag_enabled "$2" "$4")" ;;
    set-weights)    printf 'weights=%s' "$(flag_weights "$2" "$4")" ;;
    archive)        printf 'archived=%s' "$(feature_archived "$3")" ;;
  esac
}

# verify_state <action> <feature> <feature_id> <env_key> <expected>: retries for eventual consistency
verify_state() {
  local got
  for _ in 1 2 3 4 5; do
    got=$(state_of "$1" "$2" "$3" "$4")
    [[ $got == "$5" ]] && return 0
    sleep 2
  done
  warn "verify: expected '$5', got '$got'"
  return 1
}

# verify_sdk <feature> <env_key> <enabled=true|false>: what an SDK sees (edge API); exit 0 = enabled
verify_sdk() {
  local want=$3
  for _ in 1 2 3 4 5 6; do
    if fs eval "$1" -e "$2" --test >/dev/null 2>&1; then [[ $want == enabled=true ]] && return 0
    else [[ $want == enabled=false ]] && return 0; fi
    sleep 3
  done
  return 1
}
