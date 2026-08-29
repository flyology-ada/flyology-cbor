#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

if command -v rg >/dev/null 2>&1; then
  scan_backend() {
    rg -n "$@"
  }
else
  scan_backend() {
    pattern=$1
    shift
    grep -En "$pattern" "$@"
  }
fi

scan() {
  if scan_backend "$@"; then
    return 0
  else
    status=$?
    if [ "$status" -eq 1 ]; then
      return 1
    fi
    echo "release-policy scan failed with status $status" >&2
    exit "$status"
  fi
}

alr build
alr exec -- gprbuild -f -p -j0 -P tests/flyology_cbor_tests.gpr
"$project_root/tests/bin/flyology_cbor_tests"

alr exec -- gprbuild -f -p -j0 \
  -P tests/installed-client/flyology_cbor_installed_client.gpr
"$project_root/tests/installed-client/bin/flyology_cbor_installed_client"
alr exec -- gprbuild -f -p -j0 \
  -P tests/no-allocation/flyology_cbor_no_allocation.gpr
"$project_root/tests/no-allocation/bin/flyology_cbor_no_allocation"
"$project_root/scripts/test-examples.sh"
"$project_root/scripts/check-public-units.sh"

if scan 'Flyology_Serde|Type_IR|Reflection|Flyology_Wire|Flyology_JSON|Ada\.Task' \
  src/*.ad? alire.toml flyology_cbor.gpr; then
  echo "forbidden downstream dependency or semantic coupling in runtime sources" >&2
  exit 1
fi

os_import_pattern='^[[:space:]]*((limited|private)[[:space:]]+)?with[[:space:]]+(Interfaces\.C|GNAT\.OS_Lib|System\.(OS|Tasking)|Ada\.Task)'
if scan "$os_import_pattern" src/*.ad?; then
  echo "OS, C, or tasking import entered the runtime sources" >&2
  exit 1
fi

if scan '^[[:space:]]*type .* access|:=[[:space:]]*new |^with Ada\.Containers' \
  src/flyology_cbor-parsing.ad? src/flyology_cbor-writer_engine.ad?; then
  echo "allocation-capable construct entered the no-allocation parser/writer core" >&2
  exit 1
fi

if scan '^\[\[pins\]\]' alire.toml tests/installed-client/alire.toml; then
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
