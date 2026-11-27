#!/usr/bin/env bash
# Flagsmith CLI adapters: the only place that knows JSON field names.
# Field names are recorded in references/CLI-FIELDS.md. Sourced after lib.sh.

# env_name <env_key>
env_name() {
  fs environment list --jq ".[] | select(.api_key == \"$1\") | .name"
}

# current_env_key: the -e value in effect (FLAGSMITH_ENVIRONMENT or flagsmith.json)
current_env_key() {
  fs config --json --jq '.environment.value // empty' 2>/dev/null
}

# feature_id <feature>
feature_id() { fs feature get "$1" --jq '.id'; }

# feature_archived <feature> -> true|false
feature_archived() { fs feature get "$1" --jq '.is_archived // false'; }

# flag_enabled <feature> <env_key> -> true|false
flag_enabled() { fs flag get "$1" -e "$2" --jq '.enabled'; }

# flag_weights <feature> <env_key> -> "key=pct,key=pct" (sorted) or empty
flag_weights() {
  fs flag get "$1" -e "$2" --jq '[.variants[]? | "\(.key)=\(.weight)"] | sort | join(",")'
}

# segment_overrides <feature> <env_key> -> lines: name<TAB>enabled
segment_overrides() {
  fs flag list --feature "$1" -e "$2" --jq '.[] | "\(.segment.name // .segment)\t\(.enabled)"' 2>/dev/null || true
}

# identity_override_count <feature> <env_key>
identity_override_count() {
  fs flag list --feature "$1" --identities -e "$2" --jq 'length' 2>/dev/null || printf 0
}

# running_experiments <feature_id> <env_key> -> lines: id<TAB>name
running_experiments() {
  fs api "api/v1/environments/$2/experiments/" \
    --jq "(.results? // .)[] | select(.feature == $1 and .status == \"running\") | \"\(.id)\t\(.name)\"" 2>/dev/null || true
}

# all_feature_names -> one per line
all_feature_names() { fs feature list --jq '.[].name'; }

# transition <feature> <env_key> <target_state>: apply = after, undo = before. No eval.
transition() {
  local feature=$1 env_key=$2 target=$3
  case $target in
    enabled=true)   fs flag update "$feature" --enable -e "$env_key" >/dev/null ;;
    enabled=false)  fs flag update "$feature" --disable -e "$env_key" >/dev/null ;;
    weights=*)      fs flag update "$feature" --weight "${target#weights=}" -e "$env_key" >/dev/null ;;
    archived=true)  fs feature update "$feature" --archive >/dev/null ;;
    archived=false) fs feature update "$feature" --unarchive >/dev/null ;;
    *) die "unknown target state '$target'" ;;
  esac
}

# verify_state <action> <feature> <env_key> <expected>: retries for eventual consistency
verify_state() {
  local i got
  for i in 1 2 3 4 5; do
    got=$(state_of "$1" "$2" "$3")
    [[ $got == "$4" ]] && return 0
    sleep 2
  done
  warn "verify: expected '$4', got '$got'"
  return 1
}

# verify_sdk <feature> <env_key> <enabled=true|false>: what an SDK sees (edge API)
verify_sdk() {
  local i want=$3
  for i in 1 2 3 4 5 6; do
    if fs eval "$1" -e "$2" --test >/dev/null 2>&1; then [[ $want == enabled=true ]] && return 0
    else [[ $want == enabled=false ]] && return 0; fi
    sleep 3
  done
  return 1
}

# state_of <action> <feature> <env_key> -> canonical state string
state_of() {
  case $1 in
    enable|disable) printf 'enabled=%s' "$(flag_enabled "$2" "$3")" ;;
    set-weights)    printf 'weights=%s' "$(flag_weights "$2" "$3")" ;;
    archive)        printf 'archived=%s' "$(feature_archived "$2")" ;;
  esac
}
