#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep is required for the release-policy scans" >&2
  exit 1
fi

alr build
alr exec -- gprbuild -f -p -j0 -P tests/flyology_cbor_tests.gpr
"$project_root/tests/bin/flyology_cbor_tests"

alr exec -- gprbuild -f -p -j0 \
  -P tests/installed-client/flyology_cbor_installed_client.gpr
"$project_root/tests/installed-client/bin/flyology_cbor_installed_client"
"$project_root/scripts/check-public-units.sh"

if rg -n 'Flyology_Serde|Type_IR|Reflection|Flyology_Wire|Flyology_JSON|Ada\.Task' \
  src alire.toml flyology_cbor.gpr; then
  echo "forbidden downstream dependency or semantic coupling in runtime sources" >&2
  exit 1
fi

if rg -n '^[[:space:]]*type .* access|:=[[:space:]]*new |^with Ada\.Containers' \
  src/flyology_cbor-parsing.ad? src/flyology_cbor-writer_engine.ad?; then
  echo "allocation-capable construct entered the no-allocation parser/writer core" >&2
  exit 1
fi

if rg -n '^\[\[pins\]\]' alire.toml tests/installed-client/alire.toml; then
  echo "published or installed-client manifest contains a pin" >&2
  exit 1
fi

if awk 'length($0) > 110 { print FILENAME ":" FNR ":" length($0); failed = 1 } END { exit failed }' \
  src/*.ad? tests/src/*.adb tests/installed-client/src/*.adb; then
  :
else
  echo "handwritten Ada exceeds 110 columns" >&2
  exit 1
fi
