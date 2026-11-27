# Benchmark: with vs without the skill

**Task (same prompt for both runs):**
> We want to turn off the `new_checkout` feature flag in the Production environment of this repo's Flagsmith project. Before anything changes, tell me the impact: what code, CI, users/segments and experiments are affected, how risky it is, and the exact command to apply it and to roll it back. Do NOT change any flags or Flagsmith state. Analysis only.

**Setup:** Claude Code 2.1.332, headless (`claude -p … --output-format json`), model `claude-opus-5-5`, 28 Nov 2026. Two identical copies of the seeded demo workspace, one of them with `.claude/skills/flagsmith-change-plan` installed. The same tool allowlist for both, with raw flag mutations disallowed. The flag state was checked before and after: **no flag changed in either run**.

## Results

| | Without skill | **With skill** | |
|---|---:|---:|---|
| Turns | 12 | **5** | 2.4× fewer |
| Output tokens | 4,485 | **1,851** | 2.4× fewer |
| Total tokens processed¹ | 446,509 | **182,895** | **2.4× fewer** |
| Uncached input + output² | 47,954 | **37,997** | 21% fewer |
| Cost (list price) | $0.517 | **$0.355** | 31% less |
| Wall time | 66.5 s | **33.0 s** | 2× faster |
| Found CI gate, both code paths, co-located `express_pay`, no overrides, no experiment | ✅ | ✅ | |
| Risk level | "High" (free text) | **HIGH** (scored, rules in RISK.md) | |
| Apply path | raw `flag update` | plan id + typed approval + stale-plan guard + verify + journal | |
| Rollback path | raw `flag update` | `undo.sh` / `git revert`, drift-checked | |
| **Undo cost** | another agent session | **0 tokens** (plain bash) | |

¹ input + cache creation + cache reads + output, as reported by `usage`. Both runs carry Claude Code's fixed system context (~36k tokens), which the skill can't reduce.
² Excludes cache reads, which are billed at a fraction of the price.

## Reading it honestly

- With one run each, this is an indication rather than a statistic. The direction matches what the design predicts: the scripts do the graph walk, so the agent reads one 8-line report instead of exploring with a dozen CLI calls.
- The baseline was **thorough**. It also spotted that the CI gate doesn't pin an environment (no `-e`, `flagsmith.json` untracked), which the skill's report did not flag. **Added right after this benchmark:** CI gates now show `env not pinned`.
- The skill's main value isn't the analysis alone. It's what comes after: the same report every time, an enforced approval, a verified apply, and an **undo that needs no agent at all**.

## Reproduce

```bash
cp -R .demo-workspace /tmp/ws && mkdir -p /tmp/ws/.claude/skills && cp -R skills/flagsmith-change-plan /tmp/ws/.claude/skills/
cd /tmp/ws && claude -p "<task prompt above>" --output-format json \
  --allowedTools Bash Read Grep Glob Skill \
  --disallowedTools "Bash(flagsmith flag update:*)" "Bash(flagsmith feature update:*)" Write Edit
```
Run the same command in a copy without `.claude/skills/` for the baseline.
