# flagsmith-change-plan

**`terraform plan` for feature flags, with undo that costs zero tokens.**

An [Agent Skill](https://agentskills.io/specification) built on the [Flagsmith CLI](https://github.com/Flagsmith/flagsmith-cli). When a coding agent is asked to flip, re-weight or archive a Flagsmith flag, it no longer fires off a raw `flag update`. It runs a whole, safe workflow:

```
preflight → plan (blast-radius graph + risk) → human approval → apply → verify (API + SDK) → journal commit
                                                       later:  undo  — plain bash, 0 LLM tokens, drift-checked
```

```text
$ bash scripts/plan.sh disable new_checkout -e Production
PLAN 20261127T201944Z-disable-new_checkout
  change      disable new_checkout in Production (protected)  [enabled=true -> false]
  risk        HIGH  (protected environment; 1 CI gate(s) will fail; switches off 2 live code path(s); 1 co-located flag(s) to review)
  code        src/cart.js (4), src/checkout.js (4)
  ci-gate     .github/workflows/deploy.yml (15)
  related     express_pay
  will-run    flagsmith flag update new_checkout --disable -e 9DAFVtZYKE2PEwieHu4VKA
  rollback    flagsmith flag update new_checkout --enable -e 9DAFVtZYKE2PEwieHu4VKA
  next        human approves, then: bash scripts/apply.sh 20261127T201944Z-disable-new_checkout --confirm <typed: Production>
```

## Why

Agents can now ship, roll out and clean up features. A flag flip is the smallest change an agent can make in production and one of the easiest to get wrong:
- a deploy pipeline gates on the flag (`flagsmith eval … --test`) and starts failing,
- a running experiment gets invalidated,
- a segment override means the change only half-applies,
- and when it goes wrong at 2 AM, nobody wants to wait for an agent to reason its way back.

`flagsmith-change-plan` makes the agent show its work before it touches anything, and makes the undo deterministic.

## How Flagsmith is used

Flagsmith is the system being changed, and every read and write goes through the **Flagsmith CLI v2**:

| Step | Flagsmith CLI |
|---|---|
| Resolve project and environment | `config --jq`, `environment list --jq` |
| Current state | `flag get --jq` (enabled, variants and weights, override counts), `api …/features/<id>/` (archived) |
| Overrides | `flag list --feature <f> --jq` (segments), `flag get` (identity override count) |
| Experiments | `api api/v1/environments/<env>/experiments/` (a running experiment **blocks** the change) |
| Apply / undo | `flag update --enable/--disable/--weight`, `feature update --archive/--unarchive` |
| Verify | `flag get` (Admin API) **and** `eval <f> --test` (what an SDK actually resolves, through the edge API) |

Everything is filtered with the CLI's built-in `--json --jq`, so there's no `jq`, Python or Node dependency, and the agent only ever reads a one-screen report.

## The blast-radius graph

`plan.sh` collects edges (`src → kind → dst`) and `graph.awk` walks them breadth-first from the target flag. That's the same propagation idea as a Pregel-style graph job, done in a few lines of `awk` because a flag graph is small and tokens matter.

| Edge | Found with | Effect on risk |
|---|---|---|
| running experiment | experiments API | **BLOCKED** |
| CI gate | `.github/workflows` lines with `eval <flag> --test` | **HIGH** when disabling or archiving |
| code reference | `git grep -w` (docs excluded) | **HIGH** when switching off a live path in production, or archiving referenced code |
| segment / identity overrides | `flag list --feature`, `flag get` | **MEDIUM**: the change is partial |
| protected environment | `.flagsmith/policy` (`prod\|live` by default) | **MEDIUM**, plus typed confirmation |
| co-located flag | other flag names in the same files | listed for review (not claimed as a dependency) |

Levels: `NOOP` · `BLOCKED` · `HIGH` · `MEDIUM` · `LOW`. Full rules: [references/RISK.md](skills/flagsmith-change-plan/references/RISK.md).

## Safety model

- **Read-only until approved.** `plan` never mutates anything.
- **Human approval, enforced by the script.** `--confirm yes` for normal environments. For protected environments, the human must type the **environment name**, and the agent is instructed to pass only what the human typed. Without either, the script asks on the terminal, or refuses.
- **Stale-plan guard.** `apply` re-reads the flag and refuses if it changed since the plan, or if an experiment has started.
- **Verify twice.** Through the Admin API, and with `flagsmith eval --test`, which shows what an SDK sees.
- **Journal.** Every apply commits `.flagsmith/changes/<id>.change` (`key=value`, no secrets) as `flag-change(<id>): …`.
- **Reversible over destructive.** Archive, never delete.

## Undo, with zero tokens

Three ways, none of which needs an agent:

```bash
bash scripts/undo.sh last --confirm yes           # or a specific change id
git revert <flag-change commit>                    # post-commit hook offers to restore Flagsmith
```

Before it restores anything, undo checks for:
- **drift**: if someone changed the flag after us, it refuses to overwrite their change and shows the difference.
- **experiment lock**: it refuses while an experiment runs on the flag.
- **double undo**: an already undone change is refused.

After a `git revert` the journal record is gone from the working tree, so undo reads it back from git history.

## Install

Requirements: [Flagsmith CLI v2+](https://docs.flagsmith.com/integrating-with-flagsmith/CLI), git, bash (Git Bash on Windows). `gh` is optional.

```bash
# 1. add the skill to your agent (Claude Code shown; any Agent Skills-compatible agent works)
mkdir -p .claude/skills && cp -R skills/flagsmith-change-plan .claude/skills/

# 2. log in and bind the repo to a project + environment
flagsmith login
flagsmith init

# 3. (optional) turn `git revert` of a flag change into an undo offer
bash .claude/skills/flagsmith-change-plan/scripts/install-hooks.sh
```

Then just ask your agent: *"Turn off new_checkout in Production."* The skill takes it from there.

Optional policy, committed at `.flagsmith/policy`:
```
prod_pattern=prod|live
allow_envs=Development,Staging
```

## Try the demo

```bash
bash demo/bootstrap.sh                       # creates .demo-workspace/ (a git repo of a sample shop + hook)
cd .demo-workspace
flagsmith init --create-project change-plan-demo
bash ../demo/seed.sh                         # Development + Production, 7 flags, overrides, a running experiment
cd .. && bash tests/run.sh                   # 22 end-to-end checks against Flagsmith
```

The seed covers every risk level: `new_checkout` (HIGH in Production: CI gate and code paths), `search_v2` (MEDIUM: overrides), `holiday_banner` (LOW in Development), `cta_copy` (BLOCKED: running experiment), and `pricing_copy` (multivariate `set-weights`).

## Benchmark

See [BENCHMARK.md](BENCHMARK.md): the same request, *"what happens if we turn off new_checkout in Production?"*, run headless in Claude Code with and without the skill.

## Tests

- `tests/run.sh`: 22 end-to-end checks against Flagsmith Cloud (every risk level, approval guards, apply → verify → journal → undo, `git revert` → hook → undo from history, drift and stale-plan refusals).
- CI: `shellcheck` on every script, a `graph.awk` unit check, and `skills-ref validate` against the Agent Skills spec.

## Limitations

- Only changes made through the skill can be undone, because only those have a journal record. Changes made directly in the dashboard are out of scope for now. Flagsmith's audit log is a natural next source.
- "Co-located" flags are a hint, not a proven dependency.
- Four actions are supported: `enable`, `disable`, `set-weights`, `archive`.

## Layout

```
skills/flagsmith-change-plan/   SKILL.md · scripts/ (plan, apply, undo, preflight, install-hooks, graph.awk, hooks/) · references/
demo/                           app-template/ (sample shop) · bootstrap.sh · seed.sh
tests/run.sh                    end-to-end checks
```

MIT licensed.
