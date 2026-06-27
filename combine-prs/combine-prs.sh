#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
# shellcheck disable=SC1091  # lib.sh is co-located; path resolves at runtime
source "${SCRIPT_DIR}/lib.sh"

# ---- IO seam: every `gh` call lives here; stubbed in tests via PATH ----

list_dependabot_prs() {
  gh pr list --state open --search "author:app/dependabot" \
    --json number,headRefName,title,createdAt,url
}

# merge_branch <base> <head> -> 0 success, 2 conflict, 1 other error
merge_branch() {
  local out
  if out="$(gh api -X POST "repos/${GITHUB_REPOSITORY}/merges" \
             -f base="$1" -f head="$2" 2>&1)"; then
    return 0
  fi
  if grep -qiE '409|merge conflict' <<<"$out"; then
    return 2
  fi
  echo "$out" >&2
  return 1
}

edit_target_pr() { gh pr edit "$1" --title "$2" --body "$3"; }
close_pr()       { gh pr close "$1" --comment "$2"; }

main() {
  local prefix="${INPUT_BRANCH_PREFIX:-dependabot}"
  local min="${INPUT_MIN_COMBINE:-2}"

  local prs candidates count
  prs="$(list_dependabot_prs)"
  candidates="$(filter_candidates "$prs" "$prefix")"
  count="$(jq 'length' <<<"$candidates")"

  if (( count < min )); then
    echo "combine-prs: ${count} candidate PR(s); need ${min}. Nothing to do."
    return 0
  fi

  local target_num target_branch
  IFS=$'\t' read -r target_num target_branch < <(select_target "$candidates")

  local others combined='[]' skipped='[]' n head title rc
  others="$(other_candidates "$candidates" "$target_num")"

  while IFS=$'\t' read -r n head title; do
    set +e; merge_branch "$target_branch" "$head"; rc=$?; set -e
    case "$rc" in
      0) combined="$(jq --argjson n "$n" --arg t "$title" \
             '. + [{number:$n,title:$t}]' <<<"$combined")" ;;
      2) skipped="$(jq --argjson n "$n" --arg t "$title" \
             '. + [{number:$n,title:$t}]' <<<"$skipped")"
         echo "combine-prs: #${n} conflicts; left open." ;;
      *) echo "combine-prs: merge of #${n} failed." >&2; return 1 ;;
    esac
  done < <(jq -r '.[] | "\(.number)\t\(.headRefName)\t\(.title)"' <<<"$others")

  edit_target_pr "$target_num" "Combined dependabot updates" \
    "$(build_body "$target_num" "$combined" "$skipped")"

  local c
  for c in $(jq -r '.[].number' <<<"$combined"); do
    close_pr "$c" "Combined into #${target_num}."
  done

  echo "combine-prs: target #${target_num}; combined $(jq length <<<"$combined"); skipped $(jq length <<<"$skipped")."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
