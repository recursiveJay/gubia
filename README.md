# gubia

An autonomous AI loop based on the [ralph loop](https://ghuntley.com/ralph/)
pattern. Given a goal, gubia carves it into an executable plan and drains it
task by task, injecting a fixed contract into a CLI coding agent each
iteration and rotating models on failure, optimizing for LLM throughput
while minimizing the errors and hallucinations that unattended loops tend to
accumulate.

## How it works

`gubia` is a bash engine that drains a markdown task plan: it locates the
next pending subtask, injects it (with a fixed contract) into a CLI agent,
captures the exit code, and rotates through a fallback list of models on
failure. It has no opinion about the domain, it only finds `- [ ]`, hands
it off, and reads the result. Full spec in `engine.md` (see [Documentation](#documentation)).

## Usage

1. Give gubia a goal, either a file, or written interactively in a session
   with your harness of choice.
2. Run `/gubia init` (optional): the agent interviews you and drafts
   `plan/plan.md`. Skip this if you'd rather write the plan by hand.
3. Run `/gubia phase0`: breaks the plan down into task files automatically.
4. Run `/gubia run` (skill or `gubia run plan/plan.md` from the CLI): after
   a final confirmation, the loop starts.

The loop stops on its own once every subtask is complete, or the moment it
hits an unrecoverable error, and either way it leaves a report next to the
plan explaining why it stopped, for a human to review.

## Requirements

- At least one of the supported CLI agents on `PATH`: `claude`, `codex`,
  `omp`, or `devin`.
- `bash` ≥ 4.4.
- `just`, optional, only to install with the recipes below.

**The harness is optional and pluggable.** gubia doesn't depend on any
specific agent, the four above ship in [`config/agents.sh`](config/agents.sh)
as `agent_*` functions with a common contract. Don't use one? Delete its
entry from your fallback lists in `agents.sh` so `gubia config validate`
doesn't fail preflight expecting it. Want to add another (Gemini, etc.)?
Write an `agent_<name>` function following the same contract and reference
it from a fallback list. Details in `catalog.md` (see [Documentation](#documentation)).

## Installation

With `just` installed, three recipes cover everything needed:

```sh
just install-config   # symlinks the gubia binary + installs the agent catalog
just sync-skills       # projects skills/ onto every harness present on the machine
just test              # optional: runs the bats-core test suite
```

Without `just`, do the equivalent by hand: symlink `gubia` onto your `PATH`,
copy `config/agents.sh` to `~/.config/gubia/agents.sh`, and copy each
`skills/<name>/` directory into your harness's skills layout. Details in
`installation.md` (see [Documentation](#documentation)).

## Documentation

Most of the project's depth lives in `vault/`, written directly against the
live code:

- [`vault/spec/README.md`](vault/spec/README.md), the spec map and the
  engine/skill boundary.
- [`vault/spec/engine.md`](vault/spec/engine.md), the loop engine's full
  contract: CLI, state, rotation, process management.
- [`vault/spec/catalog.md`](vault/spec/catalog.md), the agent catalog and
  how to extend it.
- [`vault/spec/installation.md`](vault/spec/installation.md), sync and
  config install in detail.
- [`vault/knowledge/`](vault/knowledge/), distilled pitfalls and decisions
  accumulated while building gubia with gubia.

## Fallback policy

Each effort level (`low`/`medium`/`high`) has an ordered fallback list of
models. A failed iteration advances to the next model in the list; a
successful one resets the rotation. If the rotation wraps back to the model
that failed first without a success in between, the loop aborts
(`fallback-exhausted`) instead of burning the same failure indefinitely.
This is what catches sustained token/usage exhaustion rather than a single
flaky iteration. Full detail in `engine.md` (see [Documentation](#documentation)).

```
medium level: [codex-medium, omp-medium, claude-medium, devin-medium]

iter 1: codex-medium   -> fails     (mark index 0)
iter 2: omp-medium     -> fails     (index 1, not the marked one)
iter 3: claude-medium  -> succeeds  (streak resets, mark cleared)
iter 4: claude-medium  -> fails     (mark index 2)
iter 5: devin-medium   -> fails     (index 3)
iter 6: codex-medium   -> fails     (index 0)
iter 7: omp-medium     -> fails     (index 1)
iter 8: claude-medium  -> fails     (index 2, back to the mark, no success since) -> fallback-exhausted
```

## Logs

Each iteration writes to `.gubia/logs/<iter>.{prompt,out,err}`:

- `.prompt`: the exact prompt sent to the agent (contract + plan content).
- `.out`: the agent's captured output, checked for the completion token.
- `.err`: the agent's stderr, where provider/CLI errors surface.

After every iteration, `.gubia/logs/` is pruned to the `loop_max_logs` most
recent iteration sets, keyed by the `.prompt` file's mtime (not the numeric
iteration prefix, which resets on every relaunch).

## Skills

Operational knowledge for the agent running inside an iteration, the
engine doesn't read these, only the agent does. `just sync-skills` projects
them onto every installed harness.

| Skill | What it does |
|---|---|
| [`gubia`](skills/gubia/SKILL.md) | Drafts the plan (`init`, optional), breaks it into task files (`phase0`), and launches/monitors the loop (`run`). |
| [`judge`](skills/judge/SKILL.md) | Independent reviewer: judges evidence at `[judge]` checkpoints, unblocks the loop after accumulated rejections. |
| [`scribe`](skills/scribe/SKILL.md) | Distills a finished task's learnings into `vault/knowledge/` and prunes that knowledge once it grows too large. |

## License

Apache License 2.0, see [LICENSE](LICENSE).
