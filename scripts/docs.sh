#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
api_output="$project_root/docs/api"
theme_output="$project_root/docs/gnatdoc/html"
website_kit="$project_root/vendor/website-kit"
gnatdoc=${GNATDOC:-/Users/yrashk/.alire/bin/gnatdoc}

case "$api_output:$theme_output" in
   "$project_root/docs/api:$project_root/docs/gnatdoc/html") ;;
   *) printf '%s\n' "refusing unexpected documentation output" >&2; exit 1 ;;
esac

test -x "$gnatdoc" || {
   printf '%s\n' "GNATdoc 26.0.0 is required at $gnatdoc or through GNATDOC" >&2
   exit 1
}
test -f "$website_kit/scripts/render-gnatdoc-theme.mjs" || {
   printf '%s\n' "website-kit is missing; initialize vendor/website-kit" >&2
   exit 1
}

case $("$gnatdoc" --version 2>&1 | sed -n '1p') in
   "GNATdoc 26.0.0 "*) ;;
   *) printf '%s\n' "GNATdoc 26.0.0 is required" >&2; exit 1 ;;
esac

cd "$project_root"
alr build
rm -rf "$api_output" "$theme_output"
node "$website_kit/scripts/render-gnatdoc-theme.mjs" \
  "$project_root/docs/gnatdoc-theme.json" "$theme_output"
alr exec -- "$gnatdoc" --backend=html --generate=public --warnings \
  --style=leading -P docs/gnatdoc.gpr -O docs/api

node "$project_root/scripts/normalize-gnatdoc-html.mjs" "$api_output"
node "$project_root/scripts/exclude-gnatdoc-units.mjs" \
  "$api_output" "$project_root/docs/gnatdoc-excluded-units.txt"
mkdir -p "$api_output/fonts"
cp "$website_kit/assets/fonts/geologica-latin-variable.woff2" "$api_output/fonts/"
cp "$project_root/website/assets/brand/flyology-mark-transparent.svg" "$api_output/flyology-mark.svg"
cp "$website_kit/assets/scripts/ada-highlight.js" "$api_output/ada-highlight.js"
node "$website_kit/scripts/build-api-search-index.mjs" "$api_output"
if grep -q 'FlyologyApiSearch = \[\];' "$api_output/search-index.js"; then
   node "$project_root/scripts/build-legacy-api-index.mjs" "$api_output"
fi
node "$project_root/scripts/check-gnatdoc-public-units.mjs" \
  "$api_output" "$project_root/docs/gnatdoc-public-units.txt"

test -s "$api_output/index.html"
test -s "$api_output/search-index.js"
