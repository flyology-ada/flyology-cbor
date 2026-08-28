# Flyology CBOR

`flyology_cbor` is an experimental Ada-first RFC 8949 CBOR parser and writer. Its bounded core is incremental,
caller-driven, allocation-free, and independent of Serde, Type IR, Reflection, Wire, Flyology tasking, operating
system APIs, and C.

The initial `0.1.0-dev` milestone is under architecture review. It is not published to GitHub or the Alire index.
The current design proposal is recorded in
[`docs/reviews/2026-08-27-initial-architecture-proposal.md`](docs/reviews/2026-08-27-initial-architecture-proposal.md).

## License

MIT OR Apache-2.0, at your option.
