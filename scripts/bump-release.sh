#!/usr/bin/env bash
set -euo pipefail

# Tag-only release helper for this actions repo. On merge, create a new
# vX.Y.Z tag and slide the floating major tag vN to the same commit.
# Also sourced by compute-version/action.yml; keep top-level side effects out.

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

# next_version_from_tags <major|minor|patch>
# Echo the next bare semver computed from existing vX.Y.Z git tags,
# starting from 0.0.0 when there are none.
next_version_from_tags() {
  local bump="$1" latest base
  latest="$(git tag | latest_semver_tag || true)"
  base="${latest#v}"
  next_version "${base:-0.0.0}" "$bump"
}

# changes_action_code
# Read newline-separated changed paths on stdin. Succeed if any path is in a
# top-level directory holding an action.yml (an action) or in scripts/ outside
# scripts/test/ (sourced by actions). Run from the repo root.
changes_action_code() {
  local path dir
  while IFS= read -r path; do
    [[ "$path" == */* ]] || continue
    dir="${path%%/*}"
    if [ -f "${dir}/action.yml" ] || [ -f "${dir}/action.yaml" ]; then
      return 0
    fi
    if [ "$dir" = scripts ] && [[ "$path" != scripts/test/* ]]; then
      return 0
    fi
  done
  return 1
}

# slide_major
# Move the floating major tag of the latest vX.Y.Z release to the release
# commit (RELEASE_SHA, default HEAD) without cutting a new release. Keeps vN
# on main HEAD after merges that change no action code.
slide_major() {
  git fetch --tags --force >/dev/null 2>&1 || true
  local latest major sha
  latest="$(git tag | latest_semver_tag || true)"
  if [ -z "$latest" ]; then
    echo "::notice::No vX.Y.Z tags; nothing to slide."
    return 0
  fi
  major="${latest#v}"
  major="${major%%.*}"
  sha="${RELEASE_SHA:-HEAD}"
  git tag -f "v${major}" "$sha"
  git push -f origin "v${major}"
  echo "::notice::Slid v${major} to ${sha} (latest release ${latest})."
}

# main <major|minor|patch|slide>
# Compute the next version from existing git tags, then tag the release commit
# (RELEASE_SHA, default HEAD) and slide the major tag. Idempotent: if the
# computed tag already exists, do nothing.
main() {
  local bump="${1:?usage: bump-release.sh <major|minor|patch|slide>}"
  if [ "$bump" = slide ]; then
    slide_major
    return
  fi
  git fetch --tags --force >/dev/null 2>&1 || true

  local new newtag major sha
  new="$(next_version_from_tags "$bump")"
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
