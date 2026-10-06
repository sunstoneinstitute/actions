#!/usr/bin/env bash
# Records a GitHub deployment for the main commit behind a deploy-branch
# revision. Inputs come from the environment; see action.yml.
set -euo pipefail

: "${INPUT_ENV:?env is required}"
: "${INPUT_REVISION:?revision is required}"
: "${GITHUB_REPOSITORY:?}"
STATE="${INPUT_STATE:-success}"

case "$STATE" in
  success|failure|error|in_progress|queued|pending|inactive) ;;
  *) echo "::error::Invalid state '${STATE}'"; exit 1 ;;
esac

# Flux revisions look like "last-deploy/dev@sha1:<sha>". Bare SHAs pass through.
DEPLOY_SHA="${INPUT_REVISION##*:}"
DEPLOY_SHA="${DEPLOY_SHA##*@}"

ensure_commit() {
  git cat-file -e "${1}^{commit}" 2>/dev/null || git fetch -q origin "$1"
}

# resolve_main_sha <rev>: value of the newest main-sha trailer within 20
# commits of <rev>. A dev-sha trailer (deploy branch promoted from
# last-deploy/dev) is followed once to the dev deploy commit.
# The log is materialised first: an early-exiting reader on a pipe makes git
# die with SIGPIPE, which pipefail reports as exit 141.
resolve_main_sha() {
  local rev="$1" log key val
  for _ in 1 2; do
    ensure_commit "$rev"
    log=$(git log --format=%B -20 "$rev")
    key="" val=""
    read -r key val < <(awk 'index($0, "main-sha:") == 1 || index($0, "dev-sha:") == 1 { print $1, $2; exit }' <<<"$log") || true
    case "$key" in
      main-sha:) echo "$val"; return 0 ;;
      dev-sha:) rev="$val" ;;
      *) return 1 ;;
    esac
  done
  return 1
}

if ! MAIN_SHA=$(resolve_main_sha "$DEPLOY_SHA"); then
  echo "::error::No main-sha trailer found within 20 commits of ${DEPLOY_SHA}"
  exit 1
fi
ensure_commit "$MAIN_SHA"

PR=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${MAIN_SHA}/pulls" \
       --jq '.[0].number // empty' 2>/dev/null || true)
DESC="${INPUT_DESCRIPTION:-$(git log -1 --format=%s "$MAIN_SHA")}"
DESC="${DESC:0:140}"
LOG_URL=""
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  LOG_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

echo "==> ${INPUT_ENV}: ${DEPLOY_SHA} -> main ${MAIN_SHA}${PR:+ (PR #${PR})}, state ${STATE}"

DEPLOYMENT_ID=$(jq -n \
    --arg ref "$MAIN_SHA" --arg env "$INPUT_ENV" --arg desc "$DESC" \
    --arg deploy_sha "$DEPLOY_SHA" --arg pr "$PR" \
    '{ref: $ref, environment: $env, description: $desc,
      auto_merge: false, required_contexts: [],
      payload: {deploy_sha: $deploy_sha,
                pr: (if $pr == "" then null else ($pr | tonumber) end)}}' \
  | gh api -X POST "repos/${GITHUB_REPOSITORY}/deployments" --input - --jq .id)

jq -n --arg state "$STATE" --arg desc "$DESC" \
    --arg url "${INPUT_ENVIRONMENT_URL:-}" --arg log "$LOG_URL" \
    '{state: $state, description: $desc}
     + (if $url == "" then {} else {environment_url: $url} end)
     + (if $log == "" then {} else {log_url: $log} end)' \
  | gh api -X POST "repos/${GITHUB_REPOSITORY}/deployments/${DEPLOYMENT_ID}/statuses" \
      --input - >/dev/null

echo "==> Recorded deployment ${DEPLOYMENT_ID}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "main-sha=${MAIN_SHA}"
    echo "deployment-id=${DEPLOYMENT_ID}"
    echo "pr-number=${PR}"
  } >> "$GITHUB_OUTPUT"
fi
