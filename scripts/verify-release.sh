#!/bin/sh
# SPDX-License-Identifier: MIT OR Apache-2.0
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: verify-release.sh candidate SOURCE-COMMIT | indexed SOURCE-COMMIT INDEX-COMMIT" >&2
  exit 2
fi

mode=$1
source_commit=$2
index_commit=${3:-}
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$mode" in
  candidate) test -z "$index_commit" ;;
  indexed) test -n "$index_commit" ;;
  *) echo "mode must be candidate or indexed" >&2; exit 2 ;;
esac

canonical_commit=$(git -C "$project_root" rev-parse --verify "$source_commit^{commit}")
if [ "$canonical_commit" != "$source_commit" ] || [ "${#source_commit}" -ne 40 ]; then
  echo "source identity must be a canonical full commit" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-cbor-release.XXXXXX")
cleanup() {
  rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

verify_deployed_source() {
  expected_root=$1
  deployed_root=$2
  archive_file_list=$3
  (
    cd "$expected_root"
    while IFS= read -r relative_path; do
      if [ "$relative_path" = ./alire.toml ]; then
        continue
      fi
      if [ ! -f "$deployed_root/$relative_path" ] ||
         ! cmp -s "$relative_path" "$deployed_root/$relative_path" ||
         { [ -x "$relative_path" ] && [ ! -x "$deployed_root/$relative_path" ]; } ||
         { [ ! -x "$relative_path" ] && [ -x "$deployed_root/$relative_path" ]; }; then
        echo "deployed source differs from pristine archive: $relative_path" >&2
        exit 1
      fi
    done <"$archive_file_list"
  )
}

source_root="$temporary_root/source"
mkdir -p "$source_root"
git -C "$project_root" archive --format=tar "$source_commit" | tar -xf - -C "$source_root"
archive_file_list="$temporary_root/archive-files"
(cd "$source_root" && find . -type f -print | LC_ALL=C sort >"$archive_file_list")

crate_name=$(sed -n 's/^name = "\([^"]*\)"$/\1/p' "$source_root/alire.toml")
version=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' "$source_root/alire.toml")
if [ -z "$crate_name" ] || [ -z "$version" ]; then
  echo "release manifest must declare one literal crate name and version" >&2
  exit 1
fi

if find "$source_root" -name alire.lock -o -name alire.lock.yaml | grep . >/dev/null; then
  echo "release archive contains a host-local Alire lock" >&2
  exit 1
fi
if grep -n '^\[\[pins\]\]' "$source_root/alire.toml" >/dev/null; then
  echo "release manifest contains a pin" >&2
  exit 1
fi

echo "Testing pristine source archive at $source_commit"
(
  cd "$source_root"
  alr --non-interactive test
)

index_source=${FLYOLOGY_ALIRE_INDEX_SOURCE:-https://github.com/flyology-ada/alire-index.git}
index_root="$temporary_root/index"
git clone --quiet "$index_source" "$index_root"
if [ "$mode" = indexed ]; then
  git -C "$index_root" checkout --quiet --detach "$index_commit"
  if [ "$(git -C "$index_root" rev-parse HEAD)" != "$index_commit" ]; then
    echo "index identity did not resolve exactly" >&2
    exit 1
  fi
fi

manifest_directory="$index_root/index/fl/$crate_name"
manifest_path="$manifest_directory/$crate_name-$version.toml"
expected_manifest="$temporary_root/$crate_name-$version.toml"
cp "$source_root/alire.toml" "$expected_manifest"

if [ "$mode" = candidate ]; then
  origin_url=${FLYOLOGY_CBOR_CANDIDATE_ORIGIN:-git+file://$project_root}
else
  origin_url=${FLYOLOGY_CBOR_PUBLIC_ORIGIN:?set exact public git origin for indexed verification}
fi
{
  printf '\n[origin]\n'
  printf 'commit = "%s"\n' "$source_commit"
  printf 'url = "%s"\n' "$origin_url"
} >>"$expected_manifest"

if [ "$mode" = candidate ]; then
  mkdir -p "$manifest_directory"
  cp "$expected_manifest" "$manifest_path"
elif [ ! -f "$manifest_path" ] || ! cmp -s "$expected_manifest" "$manifest_path"; then
  echo "indexed manifest does not identify the reviewed source and origin" >&2
  exit 1
fi

settings_root="$temporary_root/settings"
mkdir -p "$settings_root"
(
  cd "$index_root"
  alr --non-interactive --settings="$settings_root" index --check
)
alr --non-interactive --settings="$settings_root" index --reset-community
alr --non-interactive --settings="$settings_root" index \
  --add="file:$index_root" --name=flyology_cbor_candidate --before=community

gnatdoc_root="$temporary_root/gnatdoc"
mkdir -p "$gnatdoc_root"
(
  cd "$gnatdoc_root"
  gnatdoc_directory=$(alr --non-interactive --settings="$settings_root" \
    get --dirname "gnatdoc_bin=26.0.0")
  alr --non-interactive --settings="$settings_root" get --only "gnatdoc_bin=26.0.0"
  case "$gnatdoc_directory" in
    /*) gnatdoc="$gnatdoc_directory/bin/gnatdoc" ;;
    *) gnatdoc="$gnatdoc_root/$gnatdoc_directory/bin/gnatdoc" ;;
  esac
  "$source_root/scripts/check-gnatdoc.sh" "$gnatdoc"
)

deployment_root="$temporary_root/deployment"
mkdir -p "$deployment_root"
(
  cd "$deployment_root"
  deployment=$(alr --non-interactive --settings="$settings_root" get --dirname "$crate_name=$version")
  alr --non-interactive --settings="$settings_root" get --only "$crate_name=$version"
  case "$deployment" in
    /*) deployed_source=$deployment ;;
    *) deployed_source="$deployment_root/$deployment" ;;
  esac
  verify_deployed_source "$source_root" "$deployed_source" "$archive_file_list"
)

client_root="$temporary_root/installed-client"
cp -R "$source_root/tests/installed-client" "$client_root"
(
  cd "$client_root"
  alr --non-interactive --settings="$settings_root" build
  ./bin/flyology_cbor_installed_client
  if grep -n '^\[\[pins\]\]' alire.toml >/dev/null; then
    echo "installed client gained a source pin" >&2
    exit 1
  fi
)

echo "$mode reproduction passed for source $source_commit${index_commit:+ and index $index_commit}"
