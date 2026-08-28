---
description: Preserve Flyology CBOR's streaming, profile, ownership, and review contracts.
---

# Flyology CBOR agent guide

`flyology_cbor` owns RFC 8949 byte syntax, exact offsets, syntax events, checked scalar conversion, explicit profiles,
parser/writer lifecycle, and syntax diagnostics. It does not own Serde traversal, logical envelopes or budgets,
Type IR, Reflection, Wire identity, tasking, transport, or candidate construction.

## Before changing anything

- Run `git status --short --branch` and preserve unrelated work.
- Read `docs/architecture.md`, the relevant public specification, implementation, tests, and maintained runners.
- Use `rg` and `rg --files` for discovery and `apply_patch` for hand edits.
- Keep handwritten Ada to 110 columns and UTF-8. Run GNATformat through the owning GPR project.
- Run `gh` outside the sandbox. Do not create or push a public repository without explicit user authorization.
- Keep every commit focused and use the Flyology Problem/Solution commit format.

## Architecture invariants

- The bounded core performs no heap allocation. Every capacity and profile is explicit and has no public default.
- Parser calls accept arbitrary-bound stream-element arrays and retain no input reference after returning.
- Borrowed event fragments are count-based ranges into the exact current call only.
- Arrays, maps, tags, and indefinite strings all count toward syntax depth.
- Tags remain syntax and never become Flyology Wire or Type IR identity.
- Checked conversion never truncates, wraps, silently rounds, or materializes hostile nonfinite floating values.
- Writer output is unpublished until `Finish_Document`; failure, abort, or finalization cannot publish a prefix.
- Ordinary compact output is neither canonical CBOR nor a complete preferred/deterministic encoding claim.
- Core diagnostics are nonraising and use zero-based unsigned 64-bit byte offsets.

## Verification and review

- Run `alr build` and `alr -C tests run`, plus `./scripts/test-all.sh` for a release candidate.
- Cover exact fixtures, every small split, one-byte and randomized chunks, arbitrary bounds, malformed/adversarial
  input, lifecycle/abort/reset, allocation failure, work bounds, dependency isolation, and an installed client.
- Complete explicit P0/P1/P2 architecture, implementation, change, fix, and final reviews. Fix P0/P1 and P2 by
  default before each freeze.
- Keep compiler-provider locks host-local. Published milestones use indexed dependencies and no downstream Git/path
  pins.
- Never create or move a public GitHub repository, tag, release, or Alire-index entry without explicit authority.

## Commit format

Use one focused commit with this structure:

```text
Problem: <one-line problem statement in the present tense>

<Who is affected, what goes wrong, where it happens, and the impact.>

Solution: <one-line solution statement>

<What changed and why.>
```
