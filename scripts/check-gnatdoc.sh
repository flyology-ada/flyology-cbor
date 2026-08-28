#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -x "$1" ]; then
  echo "usage: check-gnatdoc.sh /path/to/gnatdoc" >&2
  exit 2
fi

gnatdoc=$1
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=$(mktemp -d "${TMPDIR:-/tmp}/flyology-cbor-gnatdoc.XXXXXX")
generated="$output/generated-units"
expected="$output/expected-units"
log="$output/gnatdoc.log"
cleanup() {
  rm -rf -- "$output"
}
trap cleanup EXIT HUP INT TERM

(cd "$project_root" && alr exec -- "$gnatdoc" --backend html --generate public \
  -O "$output/html" -P docs/gnatdoc.gpr >"$log" 2>&1)

if rg -n 'internal error|ignore file due to missing dependencies|file .* is not found' "$log"; then
  echo "GNATdoc did not analyze the complete public source closure" >&2
  exit 1
fi

grep -o 'target=document-content>[^<]*' "$output/html/index.html" |
  sed 's/^target=document-content>//' |
  LC_ALL=C sort >"$generated"
LC_ALL=C sort "$project_root/docs/gnatdoc-public-units.txt" >"$expected"

if ! cmp -s "$expected" "$generated"; then
  echo "GNATdoc public-unit inventory differs from the reviewed whitelist" >&2
  diff -u "$expected" "$generated" >&2 || true
  exit 1
fi
