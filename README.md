# Flyology CBOR

`flyology_cbor` is an experimental Ada-first RFC 8949 CBOR parser and writer. Its bounded core is incremental,
caller-driven, allocation-free, and independent of Serde, Type IR, Reflection, Wire, Flyology tasking, operating
system APIs, and C.

The `0.1.0-dev` declarations and implementation are reviewed. Source is available from the
[`flyology-ada/flyology-cbor`](https://github.com/flyology-ada/flyology-cbor) repository, and the guide and API
reference are published at [cbor.flyology.org](https://cbor.flyology.org/). The crate has no Alire index entry, and
no downstream Serde migration is authorized. The exact declaration freeze is recorded in
[`docs/reviews/2026-08-27-declaration-freeze.md`](docs/reviews/2026-08-27-declaration-freeze.md).

`alr test` builds and runs the parser/writer corpus, the external installed-shape client, a partition compiled with
`No_Allocators` and `No_Implicit_Heap_Allocations`, dependency/isolation scans, the exact public-unit inventory, and
the 110-column gate. `scripts/verify-release.sh candidate SOURCE-COMMIT` additionally reproduces a pristine archive,
validates a temporary index, generates GNATdoc with indexed `gnatdoc_bin=26.0.0`, compares the documented public
units, verifies deployed bytes and executable modes, and resolves an isolated no-pin client.

## License

MIT OR Apache-2.0, at your option.
