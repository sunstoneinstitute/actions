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

@test "select_target returns the oldest candidate as number then branch" {
  candidates="$(filter_candidates "$PRS" "dependabot")"
  run select_target "$candidates"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\tdependabot/github_actions/a' ]
}

@test "other_candidates excludes the target PR number" {
  candidates="$(filter_candidates "$PRS" "dependabot")"
  run other_candidates "$candidates" 1
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].number' <<<"$output")" -eq 3 ]
}

@test "build_body lists bundled PRs and a conflict section when present" {
  combined='[{"number":3,"title":"bump b"}]'
  skipped='[{"number":5,"title":"bump c"}]'
  run build_body 1 "$combined" "$skipped"
  [ "$status" -eq 0 ]
  [[ "$output" == *"into #1"* ]]
  [[ "$output" == *"- #3 bump b"* ]]
  [[ "$output" == *"Left open (merge conflict)"* ]]
  [[ "$output" == *"- #5 bump c"* ]]
}

@test "build_body omits the conflict section when nothing was skipped" {
  run build_body 1 '[{"number":3,"title":"bump b"}]' '[]'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Left open (merge conflict)"* ]]
}

@test "build_body shows _none_ when nothing was bundled" {
  run build_body 1 '[]' '[]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"_none_"* ]]
}
