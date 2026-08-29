#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
list="$project_root/docs/gnatdoc-public-units.txt"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-cbor-units.XXXXXX")
expected="$temporary_root/expected"
actual="$temporary_root/actual"
cleanup() {
  rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

while IFS= read -r unit; do
  file=$(printf '%s' "$unit" | tr '[:upper:].' '[:lower:]-')
  if [ ! -f "$project_root/src/$file.ads" ]; then
    echo "documented public unit has no specification: $unit" >&2
    exit 1
  fi
  printf '%s\n' "$file.ads"
done <"$list" | LC_ALL=C sort >"$expected"

find "$project_root/src" -maxdepth 1 -name 'flyology_cbor*.ads' \
  ! -name 'flyology_cbor-writer_engine.ads' -exec basename {} \; |
  LC_ALL=C sort >"$actual"

if [ "$(wc -l <"$expected" | tr -d ' ')" -ne 13 ] || ! cmp -s "$expected" "$actual"; then
  echo "public-unit whitelist drift" >&2
  diff -u "$expected" "$actual" >&2 || true
  exit 1
fi

if [ -n "$(uniq -d "$expected")" ]; then
  echo "public-unit whitelist contains a duplicate" >&2
  exit 1
fi

if ! grep -Eq '^private generic$' "$project_root/src/flyology_cbor-writer_engine.ads" ||
   ! grep -Eq '^package Flyology_CBOR\.Writer_Engine is$' \
      "$project_root/src/flyology_cbor-writer_engine.ads"; then
  echo "targetless writer engine is no longer a private child" >&2
  exit 1
fi
