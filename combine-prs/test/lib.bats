#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../lib.sh"
}

PRS='[
  {"number":1,"headRefName":"dependabot/github_actions/a","title":"bump a","createdAt":"2026-06-01T00:00:00Z"},
  {"number":2,"headRefName":"feature/x","title":"feature x","createdAt":"2026-06-02T00:00:00Z"},
  {"number":3,"headRefName":"dependabot/npm_and_yarn/b","title":"bump b","createdAt":"2026-06-03T00:00:00Z"}
]'

@test "filter_candidates keeps only branches matching the prefix" {
  run filter_candidates "$PRS" "dependabot"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[].number' <<<"$output" | sort | tr '\n' ' ')" = "1 3 " ]
}

@test "select_target returns number	branch of the oldest candidate" {
  candidates="$(filter_candidates "$PRS" "dependabot")"
  run select_target "$candidates"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\tdependabot/github_actions/a' ]
}
