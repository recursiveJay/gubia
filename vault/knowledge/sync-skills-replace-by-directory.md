---
name: sync-skills-replace-by-directory
description: "Overwriting installed skills is implemented as rm -rf of the destination directory + full cp -R, not as an incremental copy, so as not to leave orphaned files from previous versions."
type: decision
---

Overwriting installed skills is implemented as `rm -rf` of the destination
directory + full `cp -R`, not as an incremental copy: this way no orphaned
files from previous versions remain and it literally materializes "the repo's
skills are the truth" (`destilado/instalacion.md`). An incremental copy — only
updating existing files — can leave leftovers (e.g. files renamed between
versions) that the judge of a later task would detect as installed-vs-repo
divergence.

Evidence: the repo's `justfile` — `rm -rf "$dst/$name"` followed by `cp -R` in
the `sync-skills` target; `.ralph/logs/plan/iteration-000347-20260829-211130.log`
(text: "removing the destination directory first so the copy is exact, with no
old orphaned files").
