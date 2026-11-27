# Risk scoring

`plan.sh` collects edges `src → kind → dst` and `graph.awk` walks them breadth-first from `flag:<feature>` (default depth 2).

## Edges

| Kind | From → to | Source | Meaning |
|---|---|---|---|
| `state` | flag → env | `flag get` / `feature get` | Before → after in the target environment |
| `noop` | flag → env | state compare | Already in the requested state |
| `experiment_running` | flag → experiment | `api …/experiments/` | Flag is locked, and changing it would invalidate results |
| `segment_override` | flag → segment | `flag list --feature` | Segment keeps its own state, so the change is partial |
| `identity_overrides` | flag → identities | `flag list --feature --identities` | Those identities keep their override |
| `code_ref` | flag → file | `git grep -n -w -F` | Code path behind the flag |
| `ci_gate` | flag → workflow | `.github/workflows` lines with `eval … --test` | Pipeline step that fails when the flag is off |
| `co_located` | file → flag | other known flag names in the same file | Worth reviewing. **Not** a proven dependency |

## Levels (first match wins for NOOP/BLOCKED, otherwise the highest applies)

| Level | When |
|---|---|
| `NOOP` | flag already in the requested state |
| `BLOCKED` | a running experiment on the flag in this environment |
| `HIGH` | disable/archive with a CI gate · archive while still referenced in code · disable in a protected environment while code still references the flag |
| `MEDIUM` | protected environment (including archive, which is project-wide) · segment or identity overrides present |

Code references exclude `*.md` and `*.txt` (docs mention flags, but they aren't code paths) and `.flagsmith/`.
| `LOW` | none of the above |

A protected environment is one whose name matches `prod_pattern` (default `prod|live`, case-insensitive), or that is missing from `allow_envs` when an allowlist is set. See JOURNAL.md.
