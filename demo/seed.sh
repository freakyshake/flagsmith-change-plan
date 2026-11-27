#!/usr/bin/env bash
# seed.sh: builds the demo Flagsmith state (run inside .demo-workspace, bound with `flagsmith init`).
# Idempotent: existing features/segments are kept. Uses only the Flagsmith CLI.
set -euo pipefail
fs() { flagsmith --no-input --yes "$@"; }
say() { printf '  %s\n' "$*"; }

[[ -f flagsmith.json ]] || { echo "run inside .demo-workspace after: flagsmith init --create-project change-plan-demo" >&2; exit 1; }

env_key() { fs environment list --jq ".[] | select(.name == \"$1\") | .api_key"; }
for e in Development Production; do
  [[ -n $(env_key "$e") ]] || { fs environment create "$e" >/dev/null; say "created environment $e"; }
done
DEV=$(env_key Development) PROD=$(env_key Production)
has_feature() { [[ -n $(fs feature list --include-archived --jq ".[] | select(.name == \"$1\") | .id") ]]; }
feature() {  # feature <name> [create args...]
  local name=$1; shift
  has_feature "$name" || { fs feature create "$name" "$@" >/dev/null; say "created $name"; }
}

feature new_checkout --enabled
feature express_pay --enabled
feature search_v2
feature holiday_banner --enabled
feature old_onboarding
feature pricing_copy --value control --enabled
feature cta_copy --value control --enabled

has_variant() { [[ -n $(fs feature get "$1" --jq ".variants[]? | select(.key == \"$2\") | .id") ]]; }
has_variant pricing_copy outcome || fs feature variant add pricing_copy --value "Pay less, ship more" --key outcome --weight 0 >/dev/null
has_variant cta_copy start_free  || fs feature variant add cta_copy --value "Start free" --key start_free --weight 0 >/dev/null

# Make sure the starting states are the ones the demo expects (both environments).
for e in "$DEV" "$PROD"; do
  fs flag update new_checkout --enable -e "$e" >/dev/null
  fs flag update holiday_banner --enable -e "$e" >/dev/null
  fs flag update search_v2 --disable -e "$e" >/dev/null
done

# search_v2: segment override + identity override in Production -> MEDIUM
if [[ -z $(fs segment list --jq '.[] | select(.name == "beta_users") | .id') ]]; then
  fs segment create beta_users \
    --rules '{"type":"ALL","rules":[{"type":"ANY","conditions":[{"property":"plan","operator":"EQUAL","value":"beta"}]}]}' >/dev/null
  say "created segment beta_users"
fi
fs flag update search_v2 --enable --segment beta_users -e "$PROD" >/dev/null 2>&1 || true
fs flag update search_v2 --enable --identifier qa-user-1 -e "$PROD" >/dev/null 2>&1 || true

# cta_copy: running experiment in Production -> BLOCKED
xp=$(fs api "api/v1/environments/$PROD/experiments/" --jq '.results[] | select(.name == "cta-copy-test") | "\(.id) \(.status)"' || true)
if [[ -z $xp ]]; then
  fid=$(fs feature get cta_copy --jq .id)
  vid=$(fs feature get cta_copy --jq '.variants[] | select(.key == "start_free") | .id')
  mid=$(fs api "api/v1/environments/$PROD/experiment-metrics/" --jq '.results[] | select(.name == "signup") | .id' || true)
  if [[ -z $mid ]]; then
    mid=$(printf '{"name":"signup","aggregation":"occurrence","direction":"up","definition":{"version":1,"event":"signup"}}' |
      fs api "api/v1/environments/$PROD/experiment-metrics/" -X POST --input - --jq .id)
  fi
  xid=$(printf '{"feature":%s,"name":"cta-copy-test","hypothesis":"Start free beats control on signups","metrics":[{"metric":%s,"expected_direction":"increase"}],"experiment_rollout":{"enabled":true,"rollout_percentage":100,"feature_state_value":{"type":"string","value":"control"},"multivariate_feature_state_values":[{"multivariate_feature_option":%s,"percentage_allocation":50}]}}' \
    "$fid" "$mid" "$vid" | fs api "api/v1/environments/$PROD/experiments/" -X POST --input - --jq .id)
  fs api "api/v1/environments/$PROD/experiments/$xid/start/" -X POST >/dev/null
  say "started experiment cta-copy-test ($xid)"
fi

printf 'seeded. Development=%s Production=%s\n' "$DEV" "$PROD"
