#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
list="$project_root/docs/gnatdoc-public-units.txt"
count=0

while IFS= read -r unit; do
  file=$(printf '%s' "$unit" | tr '[:upper:].' '[:lower:]-')
  if [ ! -f "$project_root/src/$file.ads" ]; then
    echo "documented public unit has no specification: $unit" >&2
    exit 1
  fi
  count=$((count + 1))
done <"$list"

actual=$(find "$project_root/src" -maxdepth 1 -name 'flyology_cbor*.ads' \
  ! -name 'flyology_cbor-writer_engine.ads' | wc -l | tr -d ' ')
if [ "$count" -ne 13 ] || [ "$actual" -ne "$count" ]; then
  echo "public-unit whitelist drift: listed=$count source=$actual" >&2
  exit 1
fi
