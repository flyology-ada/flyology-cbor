# Flyology CBOR

`flyology_cbor` is an experimental Ada-first RFC 8949 CBOR parser and writer. Its bounded core is incremental,
caller-driven, allocation-free, and independent of Serde, Type IR, Reflection, Wire, Flyology tasking, operating
system APIs, and C.

The `0.1.0-dev` declarations are frozen and the implementation is undergoing oracle and release review. The crate
is not published to GitHub or the Alire index. The exact declaration freeze is recorded in
[`docs/reviews/2026-08-27-declaration-freeze.md`](docs/reviews/2026-08-27-declaration-freeze.md).

## License

MIT OR Apache-2.0, at your option.
