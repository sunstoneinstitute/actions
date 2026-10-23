#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../bump-release.sh"
}

init_repo() {
  cd "$BATS_TEST_TMPDIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
  git commit -q --allow-empty -m "init"
}

@test "next_version bumps patch" {
  run next_version "1.5.0" patch
  [ "$status" -eq 0 ]
  [ "$output" = "1.5.1" ]
}

@test "next_version bumps minor and zeroes patch" {
  run next_version "1.5.3" minor
  [ "$status" -eq 0 ]
  [ "$output" = "1.6.0" ]
}

@test "next_version bumps major and zeroes minor+patch" {
  run next_version "1.5.3" major
  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "next_version rejects unknown bump type" {
  run next_version "1.5.0" sideways
  [ "$status" -ne 0 ]
}

@test "latest_semver_tag picks the highest, ignoring the floating major tag" {
  run bash -c 'printf "%s\n" v1 v1.0.0 v1.9.0 v1.10.0 v1.5.0 | { source "'"${BATS_TEST_DIRNAME}"'/../bump-release.sh"; latest_semver_tag; }'
  [ "$status" -eq 0 ]
  [ "$output" = "v1.10.0" ]
}

@test "latest_semver_tag emits nothing when there are no semver tags" {
  run bash -c 'printf "%s\n" v1 main | { source "'"${BATS_TEST_DIRNAME}"'/../bump-release.sh"; latest_semver_tag; }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "next_version_from_tags computes next version from existing git tags" {
  init_repo
  git tag v1.2.3
  git tag v1

  run next_version_from_tags patch
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]

  run next_version_from_tags minor
  [ "$status" -eq 0 ]
  [ "$output" = "1.3.0" ]

  run next_version_from_tags major
  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "next_version_from_tags starts from 0.0.0 when there are no tags" {
  init_repo

  run next_version_from_tags patch
  [ "$status" -eq 0 ]
  [ "$output" = "0.0.1" ]
}

@test "next_version_from_tags rejects unknown bump type" {
  init_repo
  run next_version_from_tags sideways
  [ "$status" -ne 0 ]
}

@test "changes_action_code is true for a file in an action directory" {
  init_repo
  mkdir -p foo && touch foo/action.yml
  run bash -c 'printf "%s\n" README.md foo/action.yml | { source "'"${BATS_TEST_DIRNAME}"'/../bump-release.sh"; changes_action_code; }'
  [ "$status" -eq 0 ]
}

@test "changes_action_code is true for shared scripts" {
  init_repo
  run bash -c 'printf "%s\n" scripts/bump-release.sh | { source "'"${BATS_TEST_DIRNAME}"'/../bump-release.sh"; changes_action_code; }'
  [ "$status" -eq 0 ]
}

@test "changes_action_code is false for docs, CI and script tests" {
  init_repo
  mkdir -p foo && touch foo/action.yml
  run bash -c 'printf "%s\n" README.md CLAUDE.md .github/workflows/test.yml scripts/test/x.bats | { source "'"${BATS_TEST_DIRNAME}"'/../bump-release.sh"; changes_action_code; }'
  [ "$status" -ne 0 ]
}

@test "slide_major moves the floating tag without a new release" {
  init_repo
  git tag v1.2.3
  git tag v1
  git commit -q --allow-empty -m "docs"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"

  run slide_major
  [ "$status" -eq 0 ]
  [ "$(git rev-parse v1)" = "$(git rev-parse HEAD)" ]
  [ "$(git rev-parse 'v1.2.3^{commit}')" = "$(git rev-parse HEAD~1)" ]
  [ -z "$(git tag --points-at HEAD | grep -E '^v[0-9]+\.' || true)" ]
}
