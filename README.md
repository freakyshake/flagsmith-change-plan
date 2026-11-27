# flagsmith-change-plan

**`terraform plan` for feature flags, with undo that costs zero tokens.**

An [Agent Skill](https://agentskills.io/specification) for the [Flagsmith CLI](https://github.com/Flagsmith/flagsmith-cli). Before a coding agent enables, disables, re-weights or archives a flag, it maps the blast radius (environments, overrides, running experiments, code references, CI gates), shows a one-screen plan, and waits for a human to approve. After approval it applies the change, verifies it and journals it. Any journaled change can be undone with a plain script, a git hook or CI. Undo needs no agent and spends no tokens.

> 🚧 Under active development for the Toggle Wars hackathon (Track 04). Full docs, demo and benchmark coming.
