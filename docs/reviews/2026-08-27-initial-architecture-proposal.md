# Initial architecture proposal — 2026-08-27

Status: preimplementation review. No declaration in this document is frozen or installed.

The compile-checked specifications under [`docs/api-draft`](../api-draft/README.md) are the sole declaration
authority. This proposal is normative for behavior and architecture only; any declaration excerpt is an explanatory
summary and cannot override those specifications.

Serde consumer review returned P0 none. Its P1 and P2 conditions are incorporated below; the declaration freeze
still awaits the final independent API review and narrow re-review of these fixes.

## Authority and references

- Source oracle: `flyology-ada/flyology-serde` commit
  `1106d4ee6a0bc82e98808b5dbc56fd7f052ba386`, tree
  `17b82a30e04273db7c3ec3be5053adad63ce9a31`.
- Current structural/API reference: `flyology-ada/flyology-json` commit
  `a9924828840d3617492c4e473b8b87d3bf0a011f`.
- Historical JSON indexed-release evidence only: source
  `f8a4a0331a03552733e7bd8531552ba0c21f8997`, Flyology index
  `5693988242276f7a93b5034383764f87f5a42890`.
- Format authority: RFC 8949. Protocol numbers, head widths, major types, additional information, and IEEE 754
  interchange widths are externally defined by that standard. No private tag is allocated.

The current JSON head is newer than its indexed development snapshot. It is an API and repository-shape reference,
not evidence that its current head has been indexed.

## Review rubric

- P0: memory unsafety, value corruption, publication of incomplete output, or coupling CBOR to Serde/Wire/Type IR.
- P1: supported CBOR cannot be represented losslessly, malformed input bypasses a bound, lifecycle is ambiguous, or
  the proposed API cannot preserve the Serde oracle behavior.
- P2: an important diagnostic, work bound, ownership rule, release gate, or test obligation is underspecified.

Every P0 and P1 is fix-before-freeze. P2 is also fix-by-default. A P2 may be deferred only with explicit user
authorization after its impact and proposed disposition are recorded.

## Scope boundary

`flyology_cbor` owns:

- RFC 8949 byte syntax, heads, arguments, definite and indefinite forms, breaks, and exact byte offsets;
- a closed provisional syntax-event grammar;
- unsigned and negative integer arguments, simple values, raw float widths/bits, and checked conversions;
- UTF-8 validation, text/byte fragments, and indefinite-string chunk grammar;
- array, map, tag, and string syntax depth;
- explicit parser/writer profiles, lifecycle, and syntax-level diagnostics;
- ordinary compact output and transactional publication by the supplied facades.

It does not own:

- optional, variant, record, enumeration, or map presentation envelopes;
- Serde logical values, paths, budgets, aliases, duplicate policy, construction, candidates, or error translation;
- Type IR, Reflection, Wire identity, private tags, schema evolution, framing, transport, or tasking;
- a DOM, generalized application data model, or canonical map ordering.

The Serde backend remains the oracle until a separately reviewed Serde migration. This repository does not modify
or depend on Serde.

## Dependency and installed-unit proposal

The root runtime manifest depends only on indexed GNAT `>=13 & <17`. The initial installed units are proposed as:

```text
Flyology_CBOR
Flyology_CBOR.Errors
Flyology_CBOR.Profiles
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

The parser core, writer engine, UTF-8 DFA, and test hooks are private implementation units and must not appear in
the installed public-unit whitelist. Oracle tooling is isolated under tests and is never a crate dependency.

## Explicit profiles

Profiles have no default, factory, or visible policy constant. The proposal uses version values rather than `_V1`
declaration suffixes. The exact declaration is
[`flyology_cbor-profiles.ads`](../api-draft/flyology_cbor-profiles.ads); it uses `Unicode_Family`,
`Versioned_Unicode`, and the `Unicode`/`Formatting` record fields.

The sole supported initial aggregate uses numeric version `1` for `RFC_8949`, `Unicode_Scalars`, and
`Well_Formed_CBOR`; callers construct those fields directly because no factory or constant exists. Every other
version is `Profile_Unsupported`; incompatible supported-family combinations are `Profile_Incompatible` before byte
zero.

The parser profile accepts well-formed RFC 8949 data items, including nonpreferred argument widths, semantic tags,
float16/32/64, indefinite arrays/maps, and correctly chunked indefinite strings. Exposing a tag event does not
accept or interpret the tag's semantics.

`Ordinary_Compact` emits the shortest head width for unsigned arguments and lengths. It emits the exact requested
float width/bits, follows caller order, and permits caller-selected indefinite arrays, maps, text strings, and byte
strings. It is not canonical CBOR, does not claim whole-output preferred serialization, and does not claim
deterministic application ordering. A canonical profile requires a separate architecture and API review.

## Common syntax values

No CBOR structural length narrows to `Natural` in the public boundary. Exact private validated length, integer, and
float declarations and their accessors are in
[`flyology_cbor-values.ads`](../api-draft/flyology_cbor-values.ads).

`Make_Float` rejects set bits outside the selected width. Bit numbering is numeric interchange bit numbering and is
independent of host byte order. Parser events preserve the exact encoded width and payload bits.

## Diagnostics

The exact diagnostic declaration is
[`flyology_cbor-errors.ads`](../api-draft/flyology_cbor-errors.ads). Every result is nonraising and definite.

Parser failures report the first proving byte. Truncation reports the first missing offset. A reserved additional
information value blames the initial byte. An incorrect indefinite-string chunk blames its head. A legal break that
closes an odd map reports `Odd_Map`; a break outside a permitted indefinite construct reports `Unexpected_Break`.
Serde separately translates syntax diagnostics and typed-envelope failures to its existing `Error_Info` precedence.

An earlier primary remains primary if abort cleanup also fails. Both offsets are eligible only under their documented
coordinates. Offset overflow is detected before arithmetic and never wraps.

`Construct_Offset` preserves the start of the checked CBOR construct when it differs from the proving byte. It is
eligible only when `Has_Construct_Offset`. A truncated multibyte head anchors at its initial byte; a truncated
definite payload anchors at its first payload byte; a missing child anchors at the first missing child offset; an
an invalid UTF-8 lead anchors at that lead. For an invalid continuation, completed overlong sequence, surrogate, or
out-of-range scalar, the construct anchor equals the primary proving byte, matching the oracle. Only an incomplete
scalar at a CBOR chunk or payload end anchors at its retained lead. Misplaced break and trailing input use that byte
as both positions. Serde translates syntax errors with these failure-class-specific anchors. Split tests assert both
coordinates at every failure position of every two-, three-, and four-octet sequence.

## Parser event grammar

The parser exposes CBOR surface syntax rather than Serde operations:

```ada
type Event_Kind is
  (Document_Begin,
   Document_End,
   Unsigned_Value,
   Negative_Integer_Value,
   Byte_String_Begin,
   Byte_String_Chunk_Begin,
   Byte_String_Fragment,
   Byte_String_Chunk_End,
   Byte_String_End,
   Text_String_Begin,
   Text_String_Chunk_Begin,
   Text_String_Fragment,
   Text_String_Chunk_End,
   Text_String_End,
   Array_Begin,
   Array_End,
   Map_Begin,
   Map_End,
   Tag_Begin,
   Tag_End,
   Simple_Value,
   False_Value,
   True_Value,
   Null_Value,
   Undefined_Value,
   Float_Value);
```

Grammar:

```text
document = Document_Begin, value, Document_End, acceptance
value = unsigned | negative | bytes | text | array | map | tag |
        simple | Boolean | null | undefined | float
bytes = Byte_String_Begin,
        (Byte_String_Fragment* |
         {Byte_String_Chunk_Begin, Byte_String_Fragment*, Byte_String_Chunk_End}*),
        Byte_String_End
text = the analogous Text_String events
array = Array_Begin, value*, Array_End
map = Map_Begin, {value, value}*, Map_End
tag = Tag_Begin, value, Tag_End
```

The begin event carries definite or indefinite length information. Chunk events occur only for an indefinite string
and carry a definite chunk length. Definite strings emit fragments directly. Empty definite strings and empty chunks
emit no fragment. Every text chunk is independently valid UTF-8; a scalar cannot cross a CBOR chunk boundary.

A definite map length is a count of key/value pairs, never a child count. The grammar enforces exactly twice that
many nested data items using checked unsigned arithmetic without computing `2 * N` when it would overflow. An
indefinite map rejects a break while a value is pending.

`Unsigned_Value`, `Negative_Integer_Value`, `Tag_Begin`, and `Simple_Value` expose the full unsigned argument. A negative
event represents the exact CBOR argument `n`; its mathematical value is `-1-n`. `Float_Value` exposes its exact
validated width and bits. Boolean truth is represented by `False_Value` or `True_Value`. Container and string begin
events expose length information.
Text lengths are encoded UTF-8 octet counts, never Unicode scalar counts.

The parser emits specialized Boolean/null/undefined events for simple codes 20 through 23. `Simple_Value` carries
only 0 through 19 or 32 through 255. The well-formed profile rejects additional-information 24 followed by a value
below 32 and rejects reserved additional-information 28 through 30. The ordinary writer uses specialized calls for
20 through 23, accepts raw simple 0 through 19 or 32 through 255, and rejects 24 through 31.

Tags are neutral wrappers. Every `Tag_Begin` is followed by exactly one complete nested data item and one synthetic
`Tag_End`; stacked tags nest normally. EOF, a legal outer break, or another structural end before the tagged item is
complete is a syntax error. EOF reports `Truncated_Input` with proving and construct offsets at the first missing child
byte. A break while the tag awaits its child reports `Unexpected_Break`, with both offsets at the break. A generic
consumer may process, preserve, ignore, or
reject tags. The planned Serde
adapter rejects a tag at a typed position but allows syntactically valid tag chains while skipping an unknown value.
No tag number is a schema, Wire, or Type IR identity.

Arrays, maps, tags, and indefinite strings each consume one syntax-depth frame. Definite strings are bounded leaves.
This matches the current Serde raw-skip depth model and prevents tag or indefinite-string chains from bypassing the
caller-supplied maximum.

## Parser transport and lifecycle

The proposed parser follows the reviewed JSON count-based transport, minus duplicate-name storage:

```ada
type Parser_State is
  (Uninitialized, Ready, Active, Failure_Pending, Completed, Failed, Aborted);

type Parser (Maximum_Syntax_Depth : Natural) is limited private;

procedure Initialize
  (Self       : in out Parser;
   Profile    : Profiles.Parser_Profile;
   Diagnostic : out Errors.Diagnostic);

procedure Step
  (Self         : in out Parser;
   Input        : Ada.Streams.Stream_Element_Array;
   End_Of_Input : Boolean;
   Result       : out Step_Result);

procedure Drain
  (Self         : in out Parser;
   Input        : Ada.Streams.Stream_Element_Array;
   End_Of_Input : Boolean;
   Events       : in out Event_Array;
   Result       : out Drain_Result);

procedure Abort_Document (Self : in out Parser);

procedure Reset
  (Self       : in out Parser;
   Profile    : Profiles.Parser_Profile;
   Diagnostic : out Errors.Diagnostic);
```

`Step_Result` contains outcome, absolute input origin, consumed count, one event, and a diagnostic. `Drain_Result`
contains stop, absolute input origin, consumed and produced counts, and a diagnostic. Result records are definite;
payload eligibility is controlled by their outcome fields. `Need_Input` consumes all supplied input. A
rejected call consumes and produces zero. A null event array is a nonmutating output-full stop.

An admitted true `End_Of_Input` is latched. Retraction is rejected. `Document_Complete`, after the provisional
`Document_End`, is the only complete-item acceptance gate. Trailing input fails before acceptance. Reset is admitted
from `Failure_Pending` or terminal states and revalidates the complete next profile. Abort is nonraising and idempotent.

Input arrays may have arbitrary bounds. Counts are from `Input'First`, not Ada indices. The parser retains no access
to `Input` after return. Fragment representation is total: every fragment is explicitly either a count-based borrowed
range into the exact unchanged input actual of the returning call, or an owned inline payload copied into the event.
No third or ineligible fragment form exists. A text scalar split across calls is copied into an inline four-octet
event payload; its source range still identifies the complete absolute provenance. Definite text validates UTF-8
across transport fragments through `Text_String_End`. Indefinite text also validates across transport fragments, but
resets the UTF-8 boundary only after proving the current CBOR chunk ends at a scalar boundary. A returned coordinate
borrow remains eligible against the exact unchanged producing input actual until that actual is mutated, reused, or
released. A later parser call alone does not invalidate the range.

`Step` never consumes beyond the returned event. A private consumer may retain only owned classification/header
state after admitting one event; it cannot retain a borrowed fragment. A nonnull `Drain` publishes only the first
`Produced` events. If a failure follows a provisional prefix, the result preserves the exact consumed count and that
prefix; no suffix element is mutated. A pending failure is reported on the next call with zero consumption and
production when the output became full first. These rules apply equally to resource denial.

Parser state is allocation-free. `Maximum_Syntax_Depth` is an explicit discriminant with no default. All retained
head and UTF-8 carry is fixed by RFC 8949 and UTF-8 protocol widths rather than caller policy; no unbounded token
payload is retained. At most three prior UTF-8 octets are carried and at most four octets are copied into one inline
scalar event. State contains only that fixed carry, structural frames, event-pending state, profile, lifecycle, and
diagnostic. Each source octet is inspected a constant number of times. No string or nested item is rescanned; work is
linear in consumed octets plus produced events.

## Checked numeric conversion

Conversion is separate from parsing and publishes no value on failure. The exact generic signed/unsigned and
binary64 declarations are the compile-checked specifications under [`docs/api-draft`](../api-draft/README.md).

Signed conversion accepts major type 0 through `Integer_64'Last` and major type 1 through `Integer_64'First` using
checked unsigned-domain arithmetic. Unsigned conversion rejects every negative kind. Float16 and float32 finite
values promote exactly to binary64 bits. Infinity, signed zero, and NaN category are preserved; no NaN payload or
signaling-state promise is made by category conversion. Classification occurs before any Ada floating conversion,
so hostile nonfinite bits never materialize an invalid floating object.

The writer accepts validated raw float values. The neutral binary64 helper exposes finite interchange bits and
nonfinite categories; Serde separately selects its existing binary64 infinity and quiet-NaN output bits.

## Writer engine and facades

The private engine is targetless: it stores grammar, profile, lifecycle, and transaction ownership, but no target,
sink access value, callback access, or self-reference. Every internal mutation receives a destination as a synchronous
`in out` parameter. The caller cannot access the engine directly.

`Flyology_CBOR.Writing` is a generic external-target facade over that engine. Its destination formals are synchronous
`Begin`, prefix-reporting `Write`, `Commit`, and `Abort`, using the status types in `Flyology_CBOR.Destinations`. Every
mutation receives `Target : in out Destination_Type`; no call retains it. The Ada type system cannot authenticate
that successive calls receive the same object, so passing the same exclusive target throughout one active
transaction is an explicit caller obligation. This facade is installed for consumer-neutral destinations, but Serde
does not use it.

All destination formals are synchronous, finite, nonreentrant, and nonraising generic contracts. A raising formal is
an instantiation contract violation: its exception propagates and the caller discards both writer and target; no
ordinary recovery state is promised. `Begin_Failed` owns no transaction. `Write_Failed` accepts none and
`Write_Exhausted` accepts exactly the reported longest prefix, all unpublished. `Commit_Failed` guarantees nothing
was published and the transaction remains abortable; `Commit_Succeeded` publishes exactly once. Abort ends the
unpublished transaction for either status and can report cleanup failure only as a secondary diagnostic. Commit
status therefore never leaves publication indeterminate.

Two public self-owned facades are proposed. Their complete exact surfaces are
[`flyology_cbor-bounded_writing.ads`](../api-draft/flyology_cbor-bounded_writing.ads) and
[`flyology_cbor-allocating_writing.ads`](../api-draft/flyology_cbor-allocating_writing.ads). The generic external
facade is [`flyology_cbor-writing.ads`](../api-draft/flyology_cbor-writing.ads).

All calls are status-returning and nonraising in the bounded facade. Each fragment array may have arbitrary bounds,
is consumed synchronously, and is not retained. Declared definite string lengths and container item/pair counts are
checked before publication. An indefinite string accepts only explicit definite chunks of its own major type. Text
is validated incrementally, including across caller fragments but never across a CBOR chunk boundary.

The allocating facade is explicitly allocating. `Storage_Error` may propagate from buffer growth only after the
engine is poisoned and before publication. `Output` makes a separate copy after completion; copy failure leaves the
completed writer retryable. The bounded facade reports exhaustion as a diagnostic and exposes no output as complete.

`Bounded_Writing.Staged_Length` is eligible in every lifecycle state and reports the unpublished retained-prefix
length. It may remain nonzero after a later failure or abort, matching the information exposed by Serde's current
`Written_Length`; it never makes bytes copyable as successful output. `Committed_Length`, `Copy_Output`, and output
eligibility remain separate and require `Completed`. Failed `Copy_Output` publishes length zero and leaves the target
unchanged. The allocating facade has no staged-length query in the initial surface.

The destination contract states that begin starts unpublished staging, write only extends unpublished
staging, commit is the sole publication operation, and abort ends staging without publication. No accepted write
prefix is externally published. This contract is verified through destination fault-injection tests. The external
facade is limited but not controlled: because it retains no target, active scope exit cannot call abort.
The caller must explicitly abort the same target or unwind/discard both writer and target together.

The engine owns an internal destination-call guard for assertions, but callback re-entry violates the generic
nonreentrancy contract and has no ordinary recovery claim. Raising callbacks, concurrent use, task abort, and ATC
during a call are likewise contract violations: any exception propagates and the caller discards writer and target.
The engine never recursively calls abort from inside another destination formal. Tests probe these violations only
to verify that no target reference is retained and no successful-output claim is made.

Lifecycle is `Uninitialized`, `Ready`, `Active`, `Completed`, `Failed`, `Aborted`. `Begin_Document`
starts unpublished staging. `Finish_Document` validates one balanced root and is the only publication point. Every
ordinary failure aborts staging, preserves the primary diagnostic, and suppresses output. Abort is nonraising and
idempotent. Reset is terminal-only. The self-owned facades have no external transaction to recover during
finalization; leaving scope drops unpublished embedded storage and cannot publish. No finalizer dereferences a target.

The allocating facade maps mutation-time `Storage_Error` to `Failed`, retains a destination failure diagnostic,
then re-raises after its embedded unpublished staging is no longer eligible. No ordinary `Interrupted` state exists.

After `Completed`, a second finish or value call reports `Invalid_State` without revoking published output. Parser
calls after `Completed` likewise reject without changing completion. Serde may retain any legacy facade-specific
query behavior in its wrapper, but the neutral lifecycle never poisons an already accepted document.

## Serde behavior-preservation ledger

The future private Serde adapter, not this crate, will preserve:

- `[0]` / `[1, value]` optional envelopes;
- `[alternative-name, payload-map]` variant envelopes;
- record text keys, enumeration text, map source order, aliases, and duplicate policy;
- exact current logical budget charges and paths;
- `Unsupported_Value` for tags at typed positions, but structural tag acceptance during skip;
- `Unexpected_Kind` versus `Invalid_Value` typed-envelope precedence;
- unpublished candidates and commit/abort/error translation;
- current writer choice of binary64, canonical quiet-NaN bits, definite known containers, and indefinite unknown
  arrays/maps;
- every current JSON and CBOR fixture unchanged.

Serde selects an explicit parser `Maximum_Syntax_Depth` separately from its logical depth and item budgets. The two
must never be silently equated. Any Serde-private formula that admits additional tag or indefinite-string wrapper
depth is checked for overflow and rejected before parser initialization; it does not become a CBOR profile or default.

The neutral parser provides enough syntax and offset information for this translation but does not implement it.

| Neutral observation and private typed context | Serde result and legacy anchor |
| --- | --- |
| malformed head/payload/UTF-8 or misplaced break | `Syntax_Error`; use `Construct_Offset` according to the rules above |
| legal leading tag at any typed value position | `Unsupported_Value` at the tag head; cleanup retains it as primary |
| same well-formed tag while `Skip_Value` owns the subtree | drain tag plus its one child; charge syntax depth/work only |
| well-formed wrong major type for a typed operation | `Unexpected_Kind` at the admitted head |
| legal early indefinite end violating optional/variant cardinality | `Invalid_Value` at the break |
| wrong discriminator, extra child, or wrong typed envelope member | `Invalid_Value` at the offending admitted event |
| signed/unsigned checked conversion denial | existing `Out_Of_Range` at the integer head |
| caller text/byte buffer denial | existing `Capacity_Exceeded` without candidate publication |
| trailing byte after provisional `Document_End` | `Syntax_Error` at the first trailing byte; root remains unpublished |
| CBOR syntax-depth denial | translated resource failure at the denied opener; Serde logical depth is unchanged |

Transcript parity compares values, returned lengths and availability flags, exact codes/anchors/paths, logical budget
counters, cursor and lifecycle state, candidate/output publication, and writer bytes. A success/error-only comparison
is insufficient.

## Required verification before a milestone

- Direct golden writer bytes and parser transcripts for all oracle scalars and structural forms.
- Differential `Step` versus `Drain` tapes for every small split, every one-byte schedule, deterministic randomized
  schedules, null/full event arrays, pending failure after output-full, final-input latching/retraction, resubmitted
  unconsumed suffixes, borrowed/inline fragment eligibility, no-progress invariants, and arbitrary Ada bounds.
- Float16/32/64 endpoints, subnormals, signed zero, infinities, NaNs, and signed/unsigned 64-bit boundaries.
- Definite and indefinite arrays/maps/strings, empty chunks, wrong chunks, split UTF-8, nested tags/strings, odd maps,
  reserved additional information, misplaced breaks, truncation, trailing bytes, and 64-bit lengths.
- Exact syntax-depth, offset-overflow, destination-capacity, declared-length, and work-bound cases.
- Initialize/reject/complete/fail/abort/reset/reuse, contract-violation discard, finalization, allocation failure,
  commit denial, and
  output-copy retry tests.
- Every destination accepted-prefix point and every status failure at begin/write/commit/abort, re-entry at every
  multi-slice boundary, same-target-obligation misuse probes, and raising-formal contract-violation propagation.
- Restricted-pool/allocation instrumentation for the core and explicit work counters for tag chains, indefinite
  strings, hostile lengths, and maximum-depth arrays/maps.
- Oracle transcript comparison without adding Serde as a published dependency.
- Source scans proving no imports of Serde, JSON, Type IR, Reflection, Wire, tasking, OS, or C.
- GNATformat, 110-column scan, `alr build`, `alr -C tests run`, GNAT 13–16/macOS/Linux CI, GNATdoc public-unit
  whitelist, APM 0.28.0 frozen audit, pristine archive reproduction, and exact source/index reproduction.
- A separate installed downstream client resolving `flyology_cbor=0.1.0-dev` from an isolated exact index commit,
  with no Git/path pin and no private units.

## Publication boundary

This task may initialize and commit the local repository. It must not create or push a GitHub repository, tag,
release, or Alire-index entry without explicit user authorization. Before public origin exists, release scripts must
distinguish local candidate reproduction from the later origin-ancestry gate. Pages deployment is out of scope.

A reviewed indexed milestone handoff must name the exact source commit and exact index commit, installed public
units, profiles and API, lock metadata, verification commands, and migration risks. Because no publication is
authorized, those identities cannot exist yet and must not be fabricated.

## Open consumer questions sent to Serde

1. Are neutral `Tag_Begin`/`Tag_End` events acceptable for typed rejection and skip acceptance?
2. Does Serde require a direct `Peek` helper, or can it classify the next provisional event?
3. Can Serde collect text/byte fragments itself, or should this crate expose a bounded transactional collector?
4. Can richer syntax diagnostics preserve current tag/kind/break precedence through Serde translation?
5. Is negative argument `n` plus checked `-1-n` conversion the preferred neutral representation?
6. Should raw float widths/bits plus binary64 helpers be the only initial floating interface?
7. Is the self-owned bounded facade sufficient for Serde embedding, avoiding a public external-destination API?

## Serde consumer review disposition

The Serde task reported P0 none. All four P1 conditions are normative above:

- the targetless engine remains private; the reviewed external destination contract is optional, while Serde embeds
  a self-owned facade;
- every fragment is borrowed-current-window or owned-inline, and UTF-8 completion is checked at both string and
  CBOR-chunk boundaries;
- syntax depth/carry are explicit or externally fixed, Step/Drain publication rules are exact, and map lengths are
  pair counts with `2*N` grammar enforcement;
- each raw unsigned-64 tag wraps exactly one item, including stacked tags.

Its P2 asks for the private Serde translation table and transcript-parity gate to remain documented without moving
them into the CBOR runtime. The behavior-preservation ledger and test plan above satisfy that boundary. Answers also
close the questions: no public Peek, no CBOR collector helper, raw negative argument plus checked conversion, raw
float bits plus checked helpers, and the self-owned facade are the accepted consumer shape.

The narrow Serde follow-up also requires `Bounded_Writing.Staged_Length` as unpublished information available in
every state and confirms separate explicit syntax-depth selection. With those additions, Serde reports no remaining
P0/P1 boundary objection to declaration freeze.

No public declaration freezes until the remaining independent P0/P1/P2 review and a narrow fix review are resolved.
