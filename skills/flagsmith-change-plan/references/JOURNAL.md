# Journal, policy and approvals

## Files (in the target repo)

| Path | Committed | Written by |
|---|---|---|
| `.flagsmith/plans/<id>.plan` | no (gitignored) | `plan.sh` |
| `.flagsmith/changes/<id>.change` | yes, in `flag-change(<id>): …` | `apply.sh` |
| `.flagsmith/undone/<id>.undo` | yes, in `flag-undo(<id>): …` | `undo.sh` |
| `.flagsmith/policy` | yes, optional | the team |

Records are `key=value`, one per line, so they can be read with `sed` and need no `jq`. A change record holds:
`id action feature feature_id env_key env_name protected before after risk reasons forward reverse applied verified`

States are canonical strings: `enabled=true|false`, `weights=key=pct,key=pct` (sorted), `archived=true|false`.
Undo moves the flag from `after` back to `before`, and only if the live state still equals `after` (drift check).

`git revert <flag-change commit>` deletes the record. `undo.sh <id>` then reads it from git history.

## Policy

```
# .flagsmith/policy
prod_pattern=prod|live|main
allow_envs=Development,Staging
```
- `prod_pattern`: environments whose names match need the **environment name typed** to approve.
- `allow_envs`: when set, every environment not listed is treated as protected too.

## Approval

`--confirm yes` for unprotected environments, `--confirm "<exact env name>"` for protected ones. Without `--confirm`, the scripts prompt on the terminal (`/dev/tty`). Agents must pass only what the human typed.
