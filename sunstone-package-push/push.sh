#!/usr/bin/env bash
# Build and push Sunstone data packages. Driven by the INPUT_* variables that
# action.yml sets; see action.yml for what each one means.
set -euo pipefail

MODE="${INPUT_MODE:-always}"
ENV_NAME="${INPUT_ENV:-prod}"
BRANCH="${INPUT_BRANCH:-${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}}"
read -r -a SUNSTONE <<<"${INPUT_COMMAND:-sunstone}"
read -r -a PUSH_ARGS <<<"${INPUT_PUSH_ARGS:-}"

# An empty input must not blank a credential the job already exports.
[ -z "${INPUT_CLIENT_ID:-}" ] || export SUNSTONE_CLIENT_ID="$INPUT_CLIENT_ID"
[ -z "${INPUT_CLIENT_SECRET:-}" ] || export SUNSTONE_CLIENT_SECRET="$INPUT_CLIENT_SECRET"
[ -z "${INPUT_ACCESS_TOKEN:-}" ] || export SUNSTONE_ACCESS_TOKEN="$INPUT_ACCESS_TOKEN"

if [ -z "$BRANCH" ]; then
  echo "::error::No branch to push to. Set the 'branch' input."
  exit 1
fi

# One path per line, surrounding whitespace and blank lines dropped.
paths=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] || paths+=("$line")
done <<<"${INPUT_PATHS:-}"

has_commit() { git cat-file -e "$1^{commit}" 2>/dev/null; }

# The ref "changed" mode compares HEAD with.
resolve_base() {
  local base="${INPUT_BASE:-}" fallback="origin/${DEFAULT_BRANCH:-main}"
  if [ -z "$base" ]; then
    case "${EVENT_NAME:-}" in
      pull_request*) base="${PR_BASE_SHA:-}" ;;
      *) base="${BEFORE_SHA:-}" ;;
    esac
    # A new branch has no previous head: `before` is all zeros.
    case "$base" in "" | *[!0]*) ;; *) base="" ;; esac
    [ -n "$base" ] || base="$fallback"
  fi

  # The merge base needs history that a default (depth 1) checkout lacks.
  if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch --quiet --no-tags --unshallow origin >&2 || true
  fi
  has_commit "$base" || git fetch --quiet --no-tags origin "$base" >&2 || true
  if ! has_commit "$base"; then
    # A force push can drop the previous head from the remote.
    echo "::warning::Base ${base} is not available; comparing with ${fallback} instead." >&2
    base="$fallback"
    has_commit "$base" || git fetch --quiet --no-tags origin "${DEFAULT_BRANCH:-main}" >&2 || true
  fi
  if ! has_commit "$base"; then
    echo "::error::Cannot find a base commit to compare with. Set the 'base' input." >&2
    return 1
  fi
  echo "$base"
}

files=()
case "$MODE" in
  always)
    [ "${#paths[@]}" -gt 0 ] || paths=(datasets.yaml)
    for f in "${paths[@]}"; do
      if [ ! -f "$f" ]; then
        echo "::error::datasets file not found: ${f}"
        exit 1
      fi
    done
    files=("${paths[@]}")
    ;;
  changed)
    base="$(resolve_base)"
    args=(package changed --since "$base")
    [ "${INPUT_NAMESPACES_ONLY:-true}" != "true" ] || args+=(--namespaces-only)
    for f in ${paths[@]+"${paths[@]}"}; do args+=(-f "$f"); done
    echo "Comparing HEAD with ${base}"
    changed="$("${SUNSTONE[@]}" "${args[@]}")"
    while IFS= read -r line; do
      [ -z "$line" ] || files+=("$line")
    done <<<"$changed"
    ;;
  *)
    echo "::error::Invalid mode: ${MODE} (expected always or changed)"
    exit 1
    ;;
esac

pushed=()
failed=()
for f in ${files[@]+"${files[@]}"}; do
  echo "::group::${f} -> ${BRANCH} (${ENV_NAME})"
  dir="$(dirname "$f")"
  name="$(basename "$f")"
  push=(package push --env "$ENV_NAME" --branch "$BRANCH" -f "$name")
  [ "${INPUT_NAMESPACES_ONLY:-true}" != "true" ] || push+=(--namespaces-only)
  push+=(${PUSH_ARGS[@]+"${PUSH_ARGS[@]}"})
  # `set -e` is off inside an `if` condition, so chain the steps with &&.
  if (
    cd "$dir" &&
      { [ "${INPUT_BUILD:-true}" != "true" ] || "${SUNSTONE[@]}" package build -f "$name"; } &&
      "${SUNSTONE[@]}" "${push[@]}"
  ); then
    pushed+=("$f")
  else
    failed+=("$f")
  fi
  echo "::endgroup::"
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "count=${#pushed[@]}"
    echo "pushed<<__SUNSTONE_PUSHED__"
    for f in ${pushed[@]+"${pushed[@]}"}; do echo "$f"; done
    echo "__SUNSTONE_PUSHED__"
  } >>"$GITHUB_OUTPUT"
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No datasets.yaml to push."
fi
if [ "${#failed[@]}" -gt 0 ]; then
  for f in "${failed[@]}"; do echo "::error::Build or push failed: ${f}"; done
  exit 1
fi
echo "Pushed ${#pushed[@]} package source(s) to branch ${BRANCH}."
