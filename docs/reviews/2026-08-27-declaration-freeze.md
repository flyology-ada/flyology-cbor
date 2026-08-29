# Public declaration freeze — 2026-08-27

Status: frozen for initial implementation. Public repository and Pages publication were authorized later; Alire
publication and downstream migration remain unauthorized.

## Exact authority

The frozen declarations and architecture are recorded by source commit
`a7e8de311bb17719643151600c3ff11b9b1bbca8`, tree
`77eba811941d3b8eebf830c09185808c1e9a97d2`. The declaration authority is the complete set of Ada
specifications under `docs/api-draft`; the behavioral authority is
`docs/reviews/2026-08-27-initial-architecture-proposal.md`.

Implementation may add private declarations and bodies without reopening this freeze. Any change to a frozen
public declaration, its documented eligibility rules, ownership rules, coordinates, lifecycle, or profile
semantics requires a new consumer and oracle P0/P1/P2 review before implementation.

## Reviewed references

- Serde CBOR oracle: source commit `1106d4ee6a0bc82e98808b5dbc56fd7f052ba386`, tree
  `17b82a30e04273db7c3ec3be5053adad63ce9a31`.
- Flyology JSON structural reference reviewed at declaration freeze: source commit
  `a9924828840d3617492c4e473b8b87d3bf0a011f`.
- Historical indexed JSON evidence only: source commit
  `f8a4a0331a03552733e7bd8531552ba0c21f8997`, index commit
  `5693988242276f7a93b5034383764f87f5a42890`.
- APM dependency resolution: `flyology-ada/agents` commit
  `6a97e7ad286a7722e6a2a6ccf782bac73fecb9e9` under APM 0.28.0.

## Review results

The independent exact-declaration consumer review completed with P0 0, P1 0, and P2 0. The independent
exact-file oracle review completed with P0 0, P1 0, and P2 0. Both reviews explicitly cleared declaration freeze.

The coordinated Serde consumer review reports P0 none and P1 none at this boundary. It confirms:

- only self-owned writer facades are a permitted later Serde integration path;
- bounded `Staged_Length` is eligible in every state while committed output is Completed-only;
- CBOR syntax depth remains separate from Serde logical depth and budgets;
- parser fragments are total across arbitrary transport chunks and never retain input access;
- tags remain raw syntax wrappers around exactly one data item;
- proving and optional construct offsets are sufficient for legacy error translation; and
- suffix-preserving `Drain` supports caller-owned provisional replay.

The release-shape review identified publication and reproduction gates, not declaration defects. At declaration
freeze, those gates remained implementation obligations and required their own P0/P1/P2 review before the
implementation candidate could be frozen.

## Verification at freeze

The exact declarations compile with:

```sh
alr exec -- gprbuild -P docs/api-draft/api_draft.gpr -c -f
```

The repository agent context was generated with APM 0.28.0. `apm audit --ci` passed all ten locally applicable
checks. Organization-policy enforcement was unavailable because the repository has no configured public remote;
that limitation is recorded rather than inferred as a pass.

## Frozen boundary

The installed public unit proposal is:

```text
Flyology_CBOR
Flyology_CBOR.Profiles
Flyology_CBOR.Errors
Flyology_CBOR.Values
Flyology_CBOR.Parsing
Flyology_CBOR.Numbers
Flyology_CBOR.Numbers.Signed_Integers
Flyology_CBOR.Numbers.Unsigned_Integers
Flyology_CBOR.Numbers.Binary64
Flyology_CBOR.Destinations
Flyology_CBOR.Writing
Flyology_CBOR.Bounded_Writing
Flyology_CBOR.Allocating_Writing
```

The targetless writer engine, parser machinery, UTF-8 validator, and test hooks are private. The root crate has
no Serde, Type IR, Reflection, Wire, JSON, tasking, or oracle dependency. Canonical CBOR is unsupported and
outside the ordinary compact profile.

At the time of this freeze, no GitHub repository, pushed commit, Alire index entry, or index identity existed. A
later user authorization permits creation and push of the public repository and publication of its Pages website.
This freeze still does not authorize an Alire index entry or a Serde dependency change.
