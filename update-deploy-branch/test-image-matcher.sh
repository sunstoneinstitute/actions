#!/usr/bin/env bash
#
# Regression test for update-deploy-branch image-tag pinning.
#
# Covers issue #5: the action produced a "deploy: <env> v<tag>" commit while
# the overlay's image newTag was left at the previous version (silent
# ship-old-image bug) when the overlay entry was registry-prefixed
# (".name: ghcr.io/sunstoneinstitute/<app>") because the base sets newName.
#
# Mirrors the matcher and pin logic from action.yml. Requires mikefarah yq v4.
# Run: bash update-deploy-branch/test-image-matcher.sh
set -euo pipefail

YQ="${YQ:-yq}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# Matcher — kept in sync with img_selector() in action.yml.
img_selector() {
  local img="$1"
  printf 'select(.name == "%s" or (.name | test("/%s$")))' "$img" "$img"
}

# pin_one: replicate the action's update path for a single overlay/image.
# Returns 0 on a successful pin, non-zero if the post-condition assertion
# fires (no match, or rewrite did not take effect).
pin_one() {
  local overlay="$1" img="$2" registry="$3" tag="$4"
  local sel match after
  sel="$(img_selector "$img")"
  match=$("$YQ" ".images[] | ${sel} | .name" "$overlay" 2>/dev/null || true)
  if [ -z "$match" ] || [ "$match" = "null" ]; then
    return 2  # no match
  fi
  "$YQ" -i "(.images[] | ${sel}) |= (.newName = \"${registry}/${img}\" | .newTag = \"${tag}\")" "$overlay"
  after=$("$YQ" ".images[] | ${sel} | .newTag" "$overlay" 2>/dev/null || true)
  [ "$after" = "$tag" ]
}

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

# ── Case 1: registry-prefixed entry (the reported failure) ──
cat > "$WORK/prefixed.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: ghcr.io/sunstoneinstitute/api-token-broker
    newTag: v1.0.0
EOF
pin_one "$WORK/prefixed.yaml" api-token-broker ghcr.io/sunstoneinstitute v1.0.1
check "registry-prefixed entry is pinned to new tag" \
  "v1.0.1" "$("$YQ" '.images[0].newTag' "$WORK/prefixed.yaml")"

# ── Case 2: bare-name entry ──
cat > "$WORK/bare.yaml" <<'EOF'
images:
  - name: api-token-broker
    newTag: v1.0.0
EOF
pin_one "$WORK/bare.yaml" api-token-broker ghcr.io/sunstoneinstitute v1.0.1
check "bare-name entry is pinned to new tag" \
  "v1.0.1" "$("$YQ" '.images[0].newTag' "$WORK/bare.yaml")"

# ── Case 3: no false positives across distinct images sharing a suffix-ish name ──
cat > "$WORK/multi.yaml" <<'EOF'
images:
  - name: ghcr.io/sunstoneinstitute/api-token-broker
    newTag: v1.0.0
  - name: ghcr.io/sunstoneinstitute/api-token-broker-migrations
    newTag: v2.0.0
EOF
pin_one "$WORK/multi.yaml" api-token-broker ghcr.io/sunstoneinstitute v1.0.1
check "sibling image (api-token-broker-migrations) is NOT touched" \
  "v2.0.0" "$("$YQ" '.images[] | select(.name | test("migrations$")) | .newTag' "$WORK/multi.yaml")"
check "exact-suffix image (api-token-broker) IS pinned" \
  "v1.0.1" "$("$YQ" '.images[] | select(.name | test("/api-token-broker$")) | .newTag' "$WORK/multi.yaml")"

# ── Case 4: assertion fires when the image is absent (no-op guard) ──
cat > "$WORK/absent.yaml" <<'EOF'
images:
  - name: ghcr.io/sunstoneinstitute/some-other-app
    newTag: v3.0.0
EOF
rc=0; pin_one "$WORK/absent.yaml" api-token-broker ghcr.io/sunstoneinstitute v1.0.1 || rc=$?
check "absent image returns no-match (rc=2)" "2" "$rc"

echo
echo "Passed: ${PASS}  Failed: ${FAIL}"
[ "$FAIL" -eq 0 ]
