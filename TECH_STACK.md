# Track 04 tech stack

The goal is **zero install friction**. The skill must run anywhere a coding agent has a shell. Don't add anything that isn't listed here without the owner's approval.

## Runtime (what the skill needs)

| Tool | Version | Used for | Notes |
|---|---|---|---|
| **Flagsmith CLI** | v2.0.0+ | All Flagsmith reads and writes, `eval --test` verification, `api` for experiments | Built-in `--json` / `--jq` replaces an external `jq` |
| **bash** | 4+ (Git Bash on Windows) | All scripts (`preflight`, `plan`, `apply`, `undo`, hooks) | POSIX-leaning. No bash-5-only features |
| **awk / sed / grep / coreutils** | Bundled with Git Bash / any Unix | Graph walk (BFS over TSV edges), risk scoring, report formatting | No `gawk`-only extensions |
| **git** | 2.30+ | `git grep` code references, journal commits, `core.hooksPath`, revert detection | Installed locally (2.56.1) |
| **gh** | 2.x | *Optional*: trail as an issue or PR comment | Installed and logged in locally |

## Platform

| Item | Choice | Why |
|---|---|---|
| Flagsmith | **Cloud (free)**, a demo-only project | Managed, no Docker needed. Flag mutations need ≥ 2.263.0 (Cloud is fine) |
| Agent | **Claude Code** (primary, tested) | Skill follows the open Agent Skills spec, so it should work in other spec-compliant agents |
| CI | **GitHub Actions** | `shellcheck` + `skills-ref validate` on push. Stretch: `flag-undo.yml` using `Flagsmith/setup-cli@v1` (OIDC) |

## Dev and quality tools

| Tool | Used for |
|---|---|
| `shellcheck` | Lint every script (runs in CI. Install locally if possible) |
| `skills-ref` | Validate the `SKILL.md` frontmatter and naming (https://github.com/agentskills/agentskills/tree/main/skills-ref). Runs in CI if it can't run locally |
| `tests/run.sh` | Plain-bash end-to-end test against the demo project (no test framework dependency) |
| `claude -p … --output-format json` | Token benchmark: with the skill vs without it |
| Screen recorder (OBS or the Windows Game Bar) | Demo video |

## Data formats

- **Graph edges:** TSV `src<TAB>kind<TAB>dst`, generated per run and never committed.
- **Journal records:** `key=value` lines in `.flagsmith/changes/<id>.change` in the target repo (schema in `references/JOURNAL.md`). Written with `printf`, read with `sed`. No JSON parsing in bash.
- **Policy:** `.flagsmith/policy`, a plain `key=value` file (environment allowlist, production patterns).

## Deliberately NOT used

| Not used | Reason |
|---|---|
| LangGraph / Pregel frameworks | The graph is small. A framework adds Python and dependencies, and costs tokens. The same propagation model is done in `awk` |
| Python / Node | Not installed on the dev machine, and they make the skill harder to drop into any repo |
| External `jq` | The CLI has `--jq` built in |
| Docker / self-hosted Flagsmith | Not needed for Track 04. Cloud is faster to set up |
| Flagsmith MCP server | The track is judged on the CLI, and MCP can't start or read experiments as fully |
