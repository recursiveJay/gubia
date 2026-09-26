# scribe / review

"Review" action: distills the accumulated learning from a completed task —
what worked, what pitfall recurred, what local decision was made and why —
into reusable knowledge. Launches three read-only subagents in parallel
(LOGS, PLAN, INVENTORY) that return findings with anchored evidence, never
synthesis: the synthesis (deduplicating, classifying, deciding
create/extend/delete) is done by `review` itself.

## When it fires

Pending `[scribe]` subtask, last one in the task file with everything else
`[x]`; or manual invocation `/scribe review`.

## Key rules

- Decides the destination on each invocation (never assumes it):
  `vault/knowledge/` (one entry = one file) if `vault/` exists, otherwise
  the single skill `skills/<repo>/SKILL.md` (one entry = one section).
- Each surviving finding is classified as create / extend / delete, always
  checked against the existing inventory to avoid duplicating.
- Builders run in parallel only in `vault/` mode; in sequence in single-skill
  mode (same file, risk of collision).
- If after applying changes `vault/knowledge/` has >10 files, chains into
  `consolidate.md` in the same invocation.
- LOGS subagent orders `.gubia/logs/*.out` by modification time newest-first:
  `ls -t .gubia/logs/*.out`. Never by the numeric prefix — `log_seq` is
  monotonic across relaunches in the current engine, but mtime stays the
  anchor as a defensive fallback for logs left by an older engine or copied
  in by hand.
- Doesn't implement product code or fix task files; only distills. Only
  writes under `vault/knowledge/`.
