# shellcheck shell=bash
# Pure helper functions for combine-prs.
# No `set`, no side effects, no top-level execution — safe to source in tests.

# filter_candidates <prs-json> <branch-prefix>
# Echo a JSON array of PRs whose headRefName starts with <branch-prefix>.
filter_candidates() {
  jq --arg p "$2" '[.[] | select(.headRefName | startswith($p))]' <<<"$1"
}

# select_target <candidates-json>
# Echo "<number>\t<headRefName>" for the oldest candidate (min createdAt).
select_target() {
  jq -r 'sort_by(.createdAt) | .[0] | "\(.number)\t\(.headRefName)"' <<<"$1"
}

# other_candidates <candidates-json> <target-number>
# Echo a JSON array of candidates excluding the target PR number.
other_candidates() {
  jq --argjson t "$2" '[.[] | select(.number != $t)]' <<<"$1"
}

# build_body <target-number> <combined-json> <skipped-json>
# combined/skipped are JSON arrays of {number,title}. Echo a markdown body.
build_body() {
  local combined skipped
  combined="$(jq -r '.[] | "- #\(.number) \(.title)"' <<<"$2")"
  skipped="$(jq -r '.[] | "- #\(.number) \(.title)"' <<<"$3")"
  printf 'Combined dependabot updates into #%s.\n\n' "$1"
  printf '### Bundled\n%s\n' "${combined:-_none_}"
  if [[ -n "$skipped" ]]; then
    printf '\n### Left open (merge conflict)\n%s\n' "$skipped"
  fi
}
