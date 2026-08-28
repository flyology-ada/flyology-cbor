# Public API draft

These specifications are the sole declaration authority for the proposed public API. They are compile-checked
architecture proposals, not installed sources. They become `src/` units only after the preimplementation P0/P1/P2
review closes and the declaration freeze is recorded. The architecture review remains normative for behavioral
contracts that these specifications document in prose, but an explanatory declaration excerpt cannot override them.

Eligibility rules omitted from Ada preconditions remain normative in the architecture proposal. In particular:

- `Values.Length` is eligible only for `Definite_Length`.
- `Values.Make_Float` rejects set high bits for shorter widths; private `Float_Value` cannot bypass that check.
- `Numbers.Binary64.Value` is eligible only for `Converted_Finite`.
- numeric `Value` accessors are eligible only for `Converted`.
- `Parsing.Drain` preserves every event-array component after the returned `Produced` prefix.
- `Bounded_Writing.Copy_Output` publishes zero length and leaves its target unchanged on every failure.
- raw simple values 24 through 31 are rejected; Boolean, null, and undefined use their specialized writer calls.
