# Agent files

`AGENTS.md` at the repo root is the entry point for every agent: Codex reads it directly and
`CLAUDE.md` imports it.

| Path | Holds |
|---|---|
| `.agents/rules/` | Conventions and gotchas, each scoped to the files it applies to by `paths:` frontmatter |
| `.agents/skills/` | Procedures, one folder per skill with a `SKILL.md` |
| `agent-artifacts/` | Untracked output of agents and skills |

## Setup

The first rule added here also needs its link for Claude Code: `ln -s ../.agents/rules .claude/rules`, with
`.claude/rules` tracked by git. `.agents/skills` works the same way.

## What belongs here

Only what is true for anyone working in this repo. Personal notes go in `.agents/rules/personal-*`
or `.agents/skills/personal-*`, which git ignores.
