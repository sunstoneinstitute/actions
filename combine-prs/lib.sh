# Pure helper functions for combine-prs.
# No `set`, no side effects, no top-level execution — safe to source in tests.

# filter_candidates <prs-json> <branch-prefix>
# Echo a JSON array of PRs whose headRefName starts with <branch-prefix>.
filter_candidates() {
  jq --arg p "$2" '[.[] | select(.headRefName | startswith($p))]' <<<"$1"
}
