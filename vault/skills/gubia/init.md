# gubia / init

Action `/gubia init` (explicit user invocation, never proactive): drafts
`plan/plan.md` from an open question to the user (what they want to
achieve + what context they can provide) combined with a deterministic
repo scan (`scripts/scan-init-context.sh`) that locates candidate written
context (`prd|spec|rfc|design|readme|index`, or anything under
`vault/`/`docs/`) and a bounded read (8-10 files at most) of the highest
priority ones.

Optional use: whoever already knows what they want can write the plan by
hand and jump straight to `/gubia phase0`.

## Key rules

- Hard precondition: if `plan/plan.md` already exists, abort without
  touching it.
- Writes directly (no confirmation gate) and reports afterward; never the
  other way around.
- At most one retry of the question to the user if the answer is too
  brief; after that, continue with whatever there is and state the gaps
  in the final report.
- Doesn't touch `## Tasks` in the plan or create anything under `task/`:
  that's `/gubia phase0`'s job, which also doesn't launch on its own.
