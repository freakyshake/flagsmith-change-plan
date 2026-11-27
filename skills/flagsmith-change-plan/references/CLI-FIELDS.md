# Verified Flagsmith CLI fields

Checked against Flagsmith Cloud with CLI v2.0.0 (28 Nov 2026). The only file that uses these fields is `scripts/fsapi.sh`.

| Call | Fields used |
|---|---|
| `environment list` | `[].api_key`, `[].name` |
| `config` | `.environment.value` (a key **or** a name), `.project.value` |
| `feature list --include-archived` | `[].name`, `[].id` (archived features included) |
| `flag get <f> -e <env>` | `.enabled`, `.segment_overrides` (count), `.identity_overrides` (count), `.variants[].key`, `.variants[].weight` (per environment, control gets the rest) |
| `flag list --feature <f> -e <env>` | `[].segment.name`, `[].enabled` |
| `api api/v1/projects/<p>/features/<id>/` | `.is_archived`. **Not** exposed by `feature get` |
| `api api/v1/environments/<env>/experiments/` | `.results[].feature.id` (the feature is an **object**), `.results[].status` (`running`), `.id`, `.name` |
| `eval <f> -e <env> --test` | exit 0 = enabled, 1 = disabled |

Gotchas found while verifying:
- Every mutation needs `--yes` with `--no-input` (the CLI's own prompt). The skill's `confirm_change` takes its place.
- `✓ …` success lines go to **stderr**. `transition` captures them so they don't cost tokens.
- `segment create --rules` takes a single rule **object**, not an array.
- A running experiment adds a segment override named `experiment-<id>-rollout`.
