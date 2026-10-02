#!/usr/bin/env bash
#
# Regression test for the source-SHA trailer on update-deploy-branch.
#
# A deploy-only commit on main with no image tag (build skipped) leaves
# nothing to stage after the cherry-pick. The action used to skip the trailer
# commit then, so the deploy branch's newest trailer stayed stale and
# promote-images promoted an older main SHA.
#
# Runs the action's real script (extracted from action.yml) against a local
# bare origin. Requires mikefarah yq v4.
# Run: bash update-deploy-branch/test-trailer.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL - ${desc} (expected '${expected}', got '${actual}')"
    FAIL=$((FAIL + 1))
  fi
}

# Turn `${{ inputs.x }}` into `${INPUT_X:-}` so the script runs outside Actions.
yq '.runs.steps[] | select(.id == "update") | .run' "$HERE/action.yml" \
  | perl -pe 's/\$\{\{ inputs\.([a-z-]+) \}\}/"\${INPUT_" . uc($1 =~ tr|-|_|r) . ":-}"/ge' \
  > "$WORK/run.sh"

run_action() {
  (cd "$WORK/repo" && bash "$WORK/run.sh") > "$WORK/last.log" 2>&1 || {
    cat "$WORK/last.log"
    return 1
  }
}

newest_trailer() {
  git -C "$WORK/repo" fetch -q origin last-deploy/dev
  git -C "$WORK/repo" log --format=%B -20 origin/last-deploy/dev \
    | awk 'index($0, "main-sha:") == 1 { print $2; exit }'
}

git init -q --bare "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
cd "$WORK/repo"
git config user.name test
git config user.email test@example.com
mkdir -p deploy/overlays/dev/app
cat > deploy/overlays/dev/app/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
images:
  - name: app
    newName: ghcr.io/example/app
    newTag: base
EOF
git add -A && git commit -q -m "initial"
git push -q origin HEAD:main

export INPUT_ENV=dev INPUT_IMAGES=app INPUT_REGISTRY=ghcr.io/example

# ── Case 1: image build creates the deploy branch ──
MAIN_SHA=$(git rev-parse HEAD)
INPUT_TAG=aaa1111 run_action
check "image deploy writes trailer" "$MAIN_SHA" "$(newest_trailer)"

# ── Case 2: deploy-only change, no image tag ──
git checkout -q main
echo "host: cms.example" > deploy/overlays/dev/app/host.txt
git add -A && git commit -q -m "deploy-only change"
INFRA_SHA=$(git rev-parse HEAD)
INPUT_TAG="" run_action
check "deploy-only change advances trailer" "$INFRA_SHA" "$(newest_trailer)"
check "preserved image tag kept" "aaa1111" \
  "$(git show origin/last-deploy/dev:deploy/overlays/dev/app/kustomization.yaml | yq '.images[0].newTag')"

# ── Case 3: rerun at the same SHA adds no commit ──
BEFORE=$(git rev-parse origin/last-deploy/dev)
git checkout -q "$INFRA_SHA"
INPUT_TAG="" run_action
git fetch -q origin last-deploy/dev
check "rerun at same SHA is a no-op" "$BEFORE" "$(git rev-parse origin/last-deploy/dev)"

echo
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
