#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

alr build
alr exec -- gprbuild -f -p -j0 -P examples/flyology_cbor_examples.gpr
"$project_root/examples/bin/streaming_parser"
"$project_root/examples/bin/bounded_writer"
