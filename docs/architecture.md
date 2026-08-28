# Architecture

`flyology_cbor` is a byte-syntax crate. It exposes caller-driven RFC 8949 events and transactional writers without
owning a logical data model. The exact frozen contract is in `docs/api-draft`; the implementation specifications in
`src` preserve that visible declaration set and add only private state.

## Parser

`Flyology_CBOR.Parsing.Parser` stores a fixed syntax stack selected by `Maximum_Syntax_Depth`, a nine-byte CBOR-head
carry, and a four-byte UTF-8 scalar carry. It has no access values, containers, heap objects, input references, or
finalizer. `Step` admits at most one event and never consumes beyond it. `Drain` repeats the same admission operation
and leaves every event-array suffix component unchanged.

Arrays, maps, tags, and indefinite strings consume syntax frames. Definite map counts are pairs. Tags close after
exactly one nested item. Definite strings are bounded leaves; indefinite chunks are definite same-major strings.
Text is validated scalar by scalar. A scalar split between transport windows is returned as owned inline carry;
otherwise fragments may borrow coordinates in the exact producing input actual.

The parser first proves a final definite payload span, then validates UTF-8. This preserves the Serde oracle's
truncation precedence. Diagnostics keep the proving offset and, when required, the legacy construct anchor.

## Writer

`Flyology_CBOR.Writer_Engine` is a private generic engine. It retains grammar/profile/lifecycle state but no target
or target reference. Every destination operation receives the target synchronously. A private assertion guard
detects re-entry while a destination callback is active; violating callback, concurrency, or task-abort contracts
requires discarding both objects.

The bounded facade embeds a fixed buffer and exposes unpublished `Staged_Length` in every state. The allocating
facade embeds its vector. Neither facade retains a self-reference or uses controlled finalization. Destination writes
remain unpublished; only successful commit makes output eligible. Abort or cleanup failure never replaces an earlier
primary diagnostic.

Ordinary compact writing selects shortest integer/length/tag/simple heads and preserves requested float width/bits
and caller order. It is not canonical CBOR and performs no key ordering.

## Bounds and dependencies

Parser work is linear in admitted bytes plus events; each byte enters fixed head/UTF-8 state once. Writer validation
is linear in supplied text bytes plus synchronous destination work. Syntax-stack storage is exactly proportional to
the caller-selected maximum depth. Only the explicitly allocating facade uses `Ada.Containers`.

The runtime manifest depends only on indexed GNAT. Runtime units import Ada, Interfaces, and `Flyology_CBOR`
children; there is no Serde, Type IR, Reflection, Wire, JSON, tasking, OS, or C dependency.
