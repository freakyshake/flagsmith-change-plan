---
name: flagsmith-change-plan
description: Plan, approve, apply and undo Flagsmith feature flag changes safely with the Flagsmith CLI. Use before enabling, disabling, re-weighting (multivariate) or archiving a Flagsmith flag, especially in production; when asked about the impact or blast radius of a flag change; or to undo or roll back a flag change. Maps environments, segment/identity overrides, running experiments, code references and CI gates, scores risk, waits for human approval, verifies, journals to git, and offers zero-token undo via script or git revert.
license: MIT
compatibility: Requires Flagsmith CLI v2+, git and bash (Git Bash on Windows). gh optional.
metadata:
  author: freakyshake
  version: "0.1.0"
---

# Flagsmith change plan

Treat every flag change like `terraform plan` → `apply`. **Never change a flag with raw `flagsmith flag update` / `feature update`.** Use these scripts. Run them from inside the target repo. `$S` = this skill's `scripts/` directory.

## Workflow

1. **Preflight** (once per session): `bash $S/preflight.sh`. If `flagsmith login` fails, ask the human to run `flagsmith login`. Never ask for or handle keys yourself.
2. **Plan** (read-only, safe to run any time):
   `bash $S/plan.sh <enable|disable|set-weights|archive> <feature> [-e <env key>] [--weight key=pct,key=pct]`
   It prints a one-screen report: change, risk, impact (experiment, code, CI gates, overrides, related flags), the exact command, the rollback, and the plan id.
3. **Show the report to the human verbatim and ask for approval.** Explain the risk reasons in one or two sentences. Don't re-derive the impact yourself.
   - `BLOCKED`: stop. A running experiment locks the flag. Tell the human to end the experiment first.
   - `NOOP`: stop. Nothing to change.
   - `HIGH`: point out each reason (CI gates that will fail, code still referencing an archived flag). Suggest a safer alternative if there's an obvious one (a non-production environment first, or removing the code reference before archiving).
4. **Apply only after explicit approval in the conversation:**
   `bash $S/apply.sh <plan-id> --confirm <value>`
   - Unprotected environment: `--confirm yes`, only after the human says yes.
   - **Protected environment** (production, or not on the allowlist): the human must type the environment name, and you pass **exactly what they typed**. Never fill it in yourself.
   - `apply` refuses if the state changed since the plan (re-plan) or an experiment started since. It verifies through the API and the SDK, then commits a journal record `flag-change(<id>)`.
5. **Report** the three lines `apply` prints (verified, journal, undo) and stop.

## Undo (zero tokens)

- `bash $S/undo.sh [last|<id>] --confirm <value>`: the same approval rules as apply.
- `git revert <flag-change commit>` also works. The post-commit hook (`bash $S/install-hooks.sh`, once per repo) offers to restore Flagsmith.
- Undo refuses when someone changed the flag since (**drift**) or an experiment is running. Show the human the DRIFT line and don't force it.
- Tell humans they can run undo themselves without an agent. That's the point.

## Rules

- One flag change per plan. For several flags, plan each one and present them together.
- Don't edit `.flagsmith/changes/` or `.flagsmith/undone/` by hand. Plans in `.flagsmith/plans/` are local and gitignored.
- Don't print or commit keys. Client-side environment keys in plan output are public by design.
- If a script fails, show its `error:` line and stop. Don't work around it with raw CLI mutations.
- Keep your own output short. The scripts' output is the report.

## References (read only when needed)

- [references/RISK.md](references/RISK.md): how risk levels are scored and what each impact edge means.
- [references/JOURNAL.md](references/JOURNAL.md): journal record format, policy file, protected environments.
- [references/CLI-FIELDS.md](references/CLI-FIELDS.md): verified Flagsmith CLI JSON fields the scripts rely on.
