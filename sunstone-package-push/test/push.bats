#!/usr/bin/env bats
# Tests for push.sh with a fake sunstone CLI that logs its calls.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../push.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  export LOG="$BATS_TEST_TMPDIR/calls.log"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  : >"$LOG"
  : >"$GITHUB_OUTPUT"

  FAKE="$BATS_TEST_TMPDIR/sunstone"
  cat >"$FAKE" <<'SH'
#!/usr/bin/env bash
echo "$(basename "$PWD"): $*" >>"$LOG"
if [ "$1 $2" = "package changed" ]; then
  printf '%s' "${FAKE_CHANGED:-}"
  exit "${FAKE_CHANGED_EXIT:-0}"
fi
[ "$1 $2 $(basename "$PWD")" != "${FAKE_FAIL:-}" ]
SH
  chmod +x "$FAKE"
  export INPUT_COMMAND="$FAKE"
  export INPUT_BRANCH="feature/x"
  unset GITHUB_HEAD_REF GITHUB_REF_NAME SUNSTONE_CLIENT_ID SUNSTONE_CLIENT_SECRET SUNSTONE_ACCESS_TOKEN

  mkdir -p "$REPO/A" "$REPO/B"
  touch "$REPO/datasets.yaml" "$REPO/A/datasets.yaml" "$REPO/B/datasets.yaml"
  cd "$REPO"
  git init -q -b main
  git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
  git update-ref refs/remotes/origin/main HEAD
  export DEFAULT_BRANCH=main
}

@test "always: defaults to the top-level datasets.yaml, builds then pushes" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "repo: package build -f datasets.yaml
repo: package push --env prod --branch feature/x -f datasets.yaml --namespaces-only" ]
  grep -qx "count=1" "$GITHUB_OUTPUT"
}

@test "always: pushes each listed path from its own directory" {
  INPUT_PATHS=$'  A/datasets.yaml\n\nB/datasets.yaml  ' INPUT_BUILD=false INPUT_ENV=dev run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "A: package push --env dev --branch feature/x -f datasets.yaml --namespaces-only
B: package push --env dev --branch feature/x -f datasets.yaml --namespaces-only" ]
  grep -qx "count=2" "$GITHUB_OUTPUT"
  grep -qx "A/datasets.yaml" "$GITHUB_OUTPUT"
}

@test "always: a missing path fails before anything is pushed" {
  INPUT_PATHS=$'A/datasets.yaml\nnope/datasets.yaml' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"datasets file not found: nope/datasets.yaml"* ]]
  [ ! -s "$LOG" ]
}

@test "push-args and namespaces-only=false reach the push command" {
  INPUT_PUSH_ARGS="--yes --force" INPUT_NAMESPACES_ONLY=false INPUT_BUILD=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "repo: package push --env prod --branch feature/x -f datasets.yaml --yes --force" ]
}

@test "branch falls back to GITHUB_HEAD_REF, then GITHUB_REF_NAME" {
  INPUT_BRANCH="" GITHUB_HEAD_REF=pr-head GITHUB_REF_NAME=7/merge INPUT_BUILD=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "--branch pr-head " "$LOG"
}

@test "no branch at all is an error" {
  INPUT_BRANCH="" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No branch to push to"* ]]
}

@test "a failed build skips that push, the rest still run, and the action fails" {
  INPUT_PATHS=$'A/datasets.yaml\nB/datasets.yaml' FAKE_FAIL="package build A" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Build or push failed: A/datasets.yaml"* ]]
  ! grep -q "^A: package push" "$LOG"
  grep -q "^B: package push" "$LOG"
  grep -qx "count=1" "$GITHUB_OUTPUT"
}

@test "changed: pushes what 'package changed' lists, compared with the PR base" {
  base="$(git rev-parse HEAD)"
  INPUT_MODE=changed EVENT_NAME=pull_request PR_BASE_SHA="$base" BEFORE_SHA="" \
    FAKE_CHANGED=$'B/datasets.yaml\n' INPUT_BUILD=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "repo: package changed --since $base --namespaces-only
B: package push --env prod --branch feature/x -f datasets.yaml --namespaces-only" ]
}

@test "changed: push event compares with the previous head" {
  before="$(git rev-parse HEAD)"
  INPUT_MODE=changed EVENT_NAME=push BEFORE_SHA="$before" INPUT_NAMESPACES_ONLY=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "repo: package changed --since $before" ]
  [[ "$output" == *"No datasets.yaml to push."* ]]
  grep -qx "count=0" "$GITHUB_OUTPUT"
}

@test "changed: a new branch (all-zero before) compares with the default branch" {
  INPUT_MODE=changed EVENT_NAME=push BEFORE_SHA=0000000000000000000000000000000000000000 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "package changed --since origin/main " "$LOG"
}

@test "changed: an unavailable base falls back to the default branch with a warning" {
  INPUT_MODE=changed EVENT_NAME=push BEFORE_SHA=1111111111111111111111111111111111111111 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Base 1111111111111111111111111111111111111111 is not available"* ]]
  grep -q "package changed --since origin/main " "$LOG"
}

@test "changed: the base input wins, and paths limit the candidates" {
  INPUT_MODE=changed INPUT_BASE=main INPUT_PATHS=$'A/datasets.yaml\nB/datasets.yaml' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "repo: package changed --since main --namespaces-only -f A/datasets.yaml -f B/datasets.yaml" ]
}

@test "changed: a failing 'package changed' fails the action without pushing" {
  INPUT_MODE=changed INPUT_BASE=main FAKE_CHANGED_EXIT=2 run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  ! grep -q "package push" "$LOG"
}

@test "invalid mode is an error" {
  INPUT_MODE=sometimes run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid mode: sometimes"* ]]
}

@test "credential inputs are exported, and empty ones keep the job's own" {
  cat >"$INPUT_COMMAND" <<'SH'
#!/usr/bin/env bash
echo "${SUNSTONE_CLIENT_ID:-}/${SUNSTONE_CLIENT_SECRET:-}/${SUNSTONE_ACCESS_TOKEN:-}" >>"$LOG"
SH
  SUNSTONE_CLIENT_SECRET=from-job INPUT_CLIENT_ID=ci-bot INPUT_CLIENT_SECRET="" INPUT_BUILD=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "ci-bot/from-job/" ]
}
