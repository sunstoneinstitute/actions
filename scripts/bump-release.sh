#!/usr/bin/env bash
set -euo pipefail

# Tag-only release helper for this actions repo. On merge, create a new
# vX.Y.Z tag and slide the floating major tag vN to the same commit.

# latest_semver_tag
# Read newline-separated tags on stdin; echo the highest vX.Y.Z (ignores the
# floating vN tags). Empty output if there are no vX.Y.Z tags.
latest_semver_tag() {
  { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -1
}

# next_version <version> <major|minor|patch>
# <version> is bare semver (no leading v). Echo the bumped version.
next_version() {
  local v="$1" bump="$2" major minor patch
  IFS=. read -r major minor patch <<<"$v"
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "ERROR: unknown bump type: ${bump}" >&2; return 1 ;;
  esac
}

# main <major|minor|patch>
# Compute the next version from existing git tags, then tag the release commit
# (RELEASE_SHA, default HEAD) and slide the major tag. Idempotent: if the
# computed tag already exists, do nothing.
main() {
  local bump="${1:?usage: bump-release.sh <major|minor|patch>}"
  git fetch --tags --force >/dev/null 2>&1 || true

  local latest base new newtag major sha
  latest="$(git tag | latest_semver_tag || true)"
  base="${latest#v}"
  base="${base:-0.0.0}"
  new="$(next_version "$base" "$bump")"
  newtag="v${new}"

  if git rev-parse "$newtag" >/dev/null 2>&1; then
    echo "::notice::Tag ${newtag} already exists; nothing to do."
    return 0
  fi

  major="${new%%.*}"
  sha="${RELEASE_SHA:-HEAD}"

  git tag "$newtag" "$sha"
  git tag -f "v${major}" "$sha"
  git push origin "$newtag"
  git push -f origin "v${major}"
  echo "::notice::Released ${newtag} and slid v${major} to ${sha}."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
