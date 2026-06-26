#!/usr/bin/env bats

# Stubs `gh` on PATH: records argv to a log, emits canned output, and
# simulates a 409 conflict for any head branch containing "conflict".
setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_STUB_LOG"
case "$1 $2" in
  "pr list") cat "$GH_STUB_PRS" ;;
  "api -X")
    head=""
    for a in "$@"; do [[ "$a" == head=* ]] && head="${a#head=}"; done
    if [[ "$head" == *conflict* ]]; then
      echo "gh: Merge conflict (HTTP 409)" >&2
      exit 1
    fi
    echo '{"sha":"deadbeef"}' ;;
  "pr edit") : ;;
  "pr close") : ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 99 ;;
esac
STUB
  chmod +x "$TMP/bin/gh"
  export GH_STUB_LOG="$TMP/log"; : > "$GH_STUB_LOG"
  export GH_STUB_PRS="$TMP/prs.json"
  export PATH="$TMP/bin:$PATH"
  export GITHUB_REPOSITORY="sunstoneinstitute/example"
  export GH_TOKEN="x"
}

teardown() { rm -rf "$TMP"; }

write_prs() { cat > "$GH_STUB_PRS"; }

@test "no-op when fewer than min-combine candidates" {
  write_prs <<'JSON'
[{"number":1,"headRefName":"dependabot/a","title":"a","createdAt":"2026-06-01T00:00:00Z","url":"u"}]
JSON
  run "${BATS_TEST_DIRNAME}/../combine-prs.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to do"* ]]
  run grep -c "api -X" "$GH_STUB_LOG"
  [ "$output" -eq 0 ]
}

@test "merges others into oldest, closes merged, leaves conflicts open" {
  write_prs <<'JSON'
[
 {"number":10,"headRefName":"dependabot/oldest","title":"oldest","createdAt":"2026-06-01T00:00:00Z","url":"u"},
 {"number":11,"headRefName":"dependabot/clean","title":"clean","createdAt":"2026-06-02T00:00:00Z","url":"u"},
 {"number":12,"headRefName":"dependabot/conflict","title":"conflict","createdAt":"2026-06-03T00:00:00Z","url":"u"}
]
JSON
  run "${BATS_TEST_DIRNAME}/../combine-prs.sh"
  [ "$status" -eq 0 ]
  grep -q "head=dependabot/clean" "$GH_STUB_LOG"
  grep -q "head=dependabot/conflict" "$GH_STUB_LOG"
  grep -q "pr edit 10" "$GH_STUB_LOG"
  grep -q "pr close 11" "$GH_STUB_LOG"
  ! grep -q "pr close 12" "$GH_STUB_LOG"
}
