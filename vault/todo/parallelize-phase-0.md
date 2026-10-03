---
area: phase 0
kind: improvement
---

# Phase 0 runs entirely in series

> Per-file phase 0 work runs one file at a time though the files are independent;
> design a parallel version that keeps the one-action-per-iteration contract.

## Problem

Phase 0 runs entirely in series: one task-00 subtask per
iteration, and the per-file bullets (effort interleaving, and potentially
context validation, judge planning, commits) run one file at a time even
though the files are independent.

## Done when

A design for running the per-file phase 0 work in
parallel (e.g. one agent per task file) without breaking the engine's
one-action-per-iteration contract, and applied to the effort bullets first
(see `vault/spec/effort-placement.md`, "Out of scope").
