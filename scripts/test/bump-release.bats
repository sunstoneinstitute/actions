#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../bump-release.sh"
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
