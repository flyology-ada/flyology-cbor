# Serde CBOR oracle ledger

Oracle authority: `flyology-ada/flyology-serde` source commit
`1106d4ee6a0bc82e98808b5dbc56fd7f052ba386`, tree
`17b82a30e04273db7c3ec3be5053adad63ce9a31`.

This corpus copies no third-party data. Hex vectors below are direct behavior cases from the repository's
`cbor_reader_tests.adb`, `cbor_reader_conformance_tests.adb`, and `cbor_writer_tests.adb`. The new crate compares raw
syntax transcripts and bytes; typed-envelope expectations remain Serde-private.

| Oracle family | Preserved vectors/evidence |
|---|---|
| Integer heads | `18 18`, `18 FF`, `19 0100`, `19 FFFF`, `1A 00010000`, full `1B`; negative `38 18`, full `3B` |
| Floats | raw `F9`/`FA`/`FB`; signed zero; minimum subnormal; infinities; NaN category and exact writer bits |
| Strings | `62 C3 A9`; `7F 62 C3 A9 61 78 FF`; `5F 42 0001 41 02 FF`; empty chunks |
| Containers | definite/indefinite arrays, pair-counted maps, nested arrays/maps, odd indefinite map |
| Tags | `D9 D9F7 F6`, stacked `C0 C0 F6`, tag in arrays, orphan tag truncation |
| Simple/break | `F4` through `F7`, `F8 1F` rejection, misplaced `FF`, reserved AI `1C` through `1E` |
| Truncation | split heads, payloads, missing array/map/tag children, `63 C2`, and malformed-plus-truncated `63 C2 20` |
| UTF-8 | valid two/four-octet scalars, invalid lead/continuation, incomplete scalar at exact payload end |
| Transport | arbitrary non-one bounds, one-byte schedule, Step/Drain count and suffix rules |
| Writer lifecycle | capacity prefix retention, abort retention, reset clearing, commit-only publication, cleanup secondary |

`tests/src/flyology_cbor_tests.adb` is the executable ledger. The all-initial-octets campaign terminates every possible
initial byte under true final input, while explicit transcript cases assert semantic events, raw/inline fragment
ownership, offsets, writer bytes, and lifecycle state.
