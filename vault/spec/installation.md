# Installation — skills sync and engine config

The only piece of the spec that talks about the user's machine instead of the loop. It exists because the contract injected by the engine assumes something nobody guaranteed: that the `judge` skill (and `gubia`) is available in the harness running the iteration.

## The problem

The catalog (`config/agents.sh`) rotates among four CLIs — `claude`, `codex`, `omp`, `devin` — and the fixed header tells each one "invoke the `judge` skill". A `[judge]` that runs in a harness where that skill is not installed does not fail: the agent improvises, approves the checkpoint without judging anything, and does so silently. That is exactly the failure the checkpoint exists to catch, so the failure mode is the worst possible — invisible until the whole plan is marked `[x]` over unverified work.

The same applies to the `gubia` skill: the rotation can land on any model in the active list, and an `[effort …]` that asks for `gubia effort set` in a harness without the `gubia` skill resolves just as badly — the agent improvises silently.

## Two recipes, two responsibilities

The `justfile` defines two recipes the human runs by hand (never from the loop or an iteration):

- **`just sync-skills`** — projects the repo's skills (`skills/gubia/`, `skills/judge/`, `skills/scribe/`) onto each harness's layout detected on the machine. It overwrites whatever is installed under that name: the repo's skills are the source, local versions are not preserved. Run after cloning and after every `pull` that touches `skills/`.

- **`just install-config`** — installs what `gubia config validate` requires before `gubia run` can start: symlinks the `gubia` binary at `~/.local/bin/gubia` (a symlink so a later `git pull` doesn't require reinstalling) and copies `config/agents.sh` to `~/.config/gubia/agents.sh` (a copy, not a symlink, because that file is the user's editable catalog config on that machine, not an artifact that should track the live repo). Warns if `~/.local/bin` is not on the PATH.

Both overwrite whatever is installed under that name — the repo is the source. Neither is triggered from the loop: the human runs them.

## Layouts per harness

Each harness uses one directory per skill with `SKILL.md` inside, overwritable by copy:

| Harness | Layout |
|---------|-------|
| `claude` | `~/.claude/skills/<name>/SKILL.md` |
| `codex`  | `~/.codex/skills/<name>/SKILL.md` |
| `devin`  | `~/.config/devin/skills/<name>/SKILL.md` |
| `omp`    | `~/.omp/agent/skills/<name>/SKILL.md` (user/global level; `~/.omp/skills/<name>/SKILL.md` is the project-level equivalent) |

The layout resolution used by `config validate` (`config_harness_skills_dir` in `gubia`) matches this table: the catalog's four harnesses are the only ones with a known layout. A catalog agent that isn't one of those four is not a harness the sync knows how to install into.

## Detection

`sync-skills` detects which harnesses are present on the machine with `command -v <binary>` on the PATH. If a binary is not found, the harness is skipped with a message ("skipped: \<harness\> is not present on this machine") and the rest continue. Missing harnesses are not an error: the sync installs only where it can.

## `gubia config validate`

An executable check that turns the contract's availability guarantee into something verified instead of assumed. Three cumulative checks (returns the full verdict, not one per key):

1. **Agent functions** (`config_validate_agent_functions`): the catalog must define the four agent functions (`agent_claude`, `agent_codex`, `agent_omp`, `agent_devin`) via `declare -F`. If any is missing, the catalog is incomplete.
2. **Installed skills** (`config_validate_skills`): walks the active level's fallback list, resolves each model's agent, and verifies that `<layout>/<skill>/SKILL.md` exists for each required skill. The required skills are `gubia` and `judge` (`config_required_skills=(gubia judge)` in `gubia`): `gubia` is included alongside `judge` because the rotation can land on any model and an `[effort …]` without `gubia` improvises just like a `[judge]` without `judge`. `scribe` is synced but not required by `config validate` — the injected contract never invokes it.
3. **State scalars** (`config_validate_scalars`): the local state file (`.gubia/state.env`) must exist, be readable, and contain the expected keys with valid values.

`gubia run`'s preflight invokes `config validate` before starting; if it fails, the loop does not launch.

## Invariants / hard rules

- **The sync copies, it does not translate.** If a harness shows up whose skill format isn't an equivalent file layout, translating it is a project of its own, not an extension of the `justfile`.
- **The sync and `install-config` never run on their own**: they are not triggered from the loop or from an iteration. The human runs them.
- **No iteration agent touches `skills/`** or the installed layout. It's the same boundary that protects `config/agents.sh`.
- **The versioned source rules over the machine**: the artifact lives in the repo and is projected onto the machine by one-way sync. This eliminates silent drift between what the spec says and what actually runs.

## Pitfalls (with observable symptom)

- **Running the loop without having synced after a `pull`**: the harnesses have the previous version of the skills while the repo has already changed. Symptom: the judge applies rules the repo's spec no longer states, and the disagreement shows up in no log — only in checkpoints that approve or reject by stale criteria.
- **Skills installed on some harnesses and not others**: the loop works until the fallback rotation reaches the harness without the install. Symptom: a `[judge]` approves without evidence right after a model rotation. This is what `gubia config validate` prevents.
- **`install-config` not run after cloning**: `gubia` is not on the PATH or the global catalog doesn't exist. Symptom: `gubia run` aborts in preflight with "agent catalog not found", or `gubia` itself is never invoked.
