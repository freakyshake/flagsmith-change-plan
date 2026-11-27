#!/usr/bin/env bash
# Shared helpers for flagsmith-change-plan. Sourced, never executed.
# shellcheck disable=SC2034

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FCP_DIR=".flagsmith"
PLANS_DIR="$FCP_DIR/plans"
CHANGES_DIR="$FCP_DIR/changes"
UNDONE_DIR="$FCP_DIR/undone"
POLICY_FILE="$FCP_DIR/policy"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warn: %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH${2:+ ($2)}"; }

fs() { flagsmith --no-input "$@"; }

repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"; }

# ---- policy -----------------------------------------------------------------
# .flagsmith/policy (key=value):
#   prod_pattern=prod|live        regex (case-insensitive) on environment name
#   allow_envs=Development,Staging environments that need only y/N confirmation
policy_get() {
  local key=$1 default=${2:-}
  [[ -f $POLICY_FILE ]] || { printf '%s' "$default"; return; }
  local v
  v=$(sed -n "s/^${key}=//p" "$POLICY_FILE" | tail -n1 | tr -d '\r')
  printf '%s' "${v:-$default}"
}

is_protected_env() {
  local name=$1 pattern allow
  pattern=$(policy_get prod_pattern 'prod|live')
  allow=$(policy_get allow_envs '')
  if [[ -n $allow ]] && printf ',%s,' "$allow" | grep -qiF ",$name,"; then
    return 1
  fi
  printf '%s' "$name" | grep -qiE "$pattern" && return 0
  [[ -n $allow ]] && return 0   # allowlist exists and env is not on it
  return 1
}

# ---- record files (key=value, one per line) -----------------------------------
rec_get() { sed -n "s/^$2=//p" "$1" | head -n1 | tr -d '\r'; }
rec_put() { printf '%s=%s\n' "$2" "$3" >> "$1"; }

new_id() {
  local action=$1 feature=$2
  printf '%s-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$action" \
    "$(printf '%s' "$feature" | tr -c 'A-Za-z0-9_.-' '_' | cut -c1-40)"
}

# ---- confirmation -------------------------------------------------------------
# confirm <protected:0|1> <env_name> <supplied --confirm value or empty>
confirm_change() {
  local protected=$1 env_name=$2 supplied=$3 answer
  if [[ -n $supplied ]]; then
    if [[ $protected == 1 ]]; then
      [[ $supplied == "$env_name" ]] || die "protected environment: --confirm must be exactly '$env_name'"
    else
      [[ $supplied == "yes" || $supplied == "$env_name" ]] || die "--confirm must be 'yes'"
    fi
    return 0
  fi
  { : < /dev/tty; } 2>/dev/null || die "approval required: re-run with --confirm $([[ $protected == 1 ]] && printf '%q' "$env_name" || printf yes) after a human approves"
  if [[ $protected == 1 ]]; then
    printf "Protected environment. Type the environment name (%s) to approve: " "$env_name" > /dev/tty
    read -r answer < /dev/tty
    [[ $answer == "$env_name" ]] || die "not approved"
  else
    printf 'Approve this change? [y/N] ' > /dev/tty
    read -r answer < /dev/tty
    [[ $answer =~ ^[Yy]$ ]] || die "not approved"
  fi
}
