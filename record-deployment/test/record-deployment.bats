#!/usr/bin/env bats

# Runs record-deployment.sh in a scratch repo laid out like an app repo with
# last-deploy/<env> branches. `gh` is stubbed on PATH: request bodies are
# saved to $TMP/deployment.json and $TMP/status.json.
setup() {
  TMP="$(mktemp -d)"
  SCRIPT="${BATS_TEST_DIRNAME}/../record-deployment.sh"
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"/commits/"*"/pulls"*) echo "$GH_STUB_PR" ;;
  *"/statuses"*) cat > "$GH_STUB_DIR/status.json" ;;
  *"/deployments"*) cat > "$GH_STUB_DIR/deployment.json"; echo 42 ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 99 ;;
esac
STUB
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH" GH_STUB_DIR="$TMP" GH_STUB_PR=7
  export GITHUB_REPOSITORY="sunstoneinstitute/example" GITHUB_RUN_ID=99
  export GITHUB_OUTPUT="$TMP/output"
  export INPUT_ENV=dev INPUT_STATE= INPUT_ENVIRONMENT_URL= INPUT_DESCRIPTION=

  cd "$TMP" && git init -q -b main repo && cd repo
  git config user.name t && git config user.email t@t
  git commit -q --allow-empty -m "Add feature (#7)"
  MAIN_SHA=$(git rev-parse HEAD)
  git checkout -q -b last-deploy/dev
  git commit -q --allow-empty -m "deploy: dev abc123" -m "main-sha: ${MAIN_SHA}"
  DEV_SHA=$(git rev-parse HEAD)
}

teardown() { rm -rf "$TMP"; }

@test "records the main-sha behind a Flux revision" {
  INPUT_REVISION="last-deploy/dev@sha1:${DEV_SHA}" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .ref "$TMP/deployment.json")" = "$MAIN_SHA" ]
  [ "$(jq -r .environment "$TMP/deployment.json")" = dev ]
  [ "$(jq -r .description "$TMP/deployment.json")" = "Add feature (#7)" ]
  [ "$(jq -r .payload.pr "$TMP/deployment.json")" = 7 ]
  [ "$(jq -r .payload.deploy_sha "$TMP/deployment.json")" = "$DEV_SHA" ]
  [ "$(jq -c .required_contexts "$TMP/deployment.json")" = "[]" ]
  [ "$(jq -r .state "$TMP/status.json")" = success ]
  [ "$(jq -r .log_url "$TMP/status.json")" = "https://github.com/sunstoneinstitute/example/actions/runs/99" ]
  [ "$(jq -r 'has("environment_url")' "$TMP/status.json")" = false ]
  grep -qx "main-sha=${MAIN_SHA}" "$GITHUB_OUTPUT"
  grep -qx "deployment-id=42" "$GITHUB_OUTPUT"
  grep -qx "pr-number=7" "$GITHUB_OUTPUT"
}

@test "walks back past commits without a trailer" {
  git commit -q --allow-empty -m "cherry-picked change"
  INPUT_REVISION="$(git rev-parse HEAD)" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .ref "$TMP/deployment.json")" = "$MAIN_SHA" ]
}

@test "follows a dev-sha trailer to last-deploy/dev" {
  git checkout -q -b last-deploy/prod main
  git commit -q --allow-empty -m "deploy: prod v1.0.0" -m "dev-sha: ${DEV_SHA}"
  INPUT_ENV=prod INPUT_REVISION="last-deploy/prod@sha1:$(git rev-parse HEAD)" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .ref "$TMP/deployment.json")" = "$MAIN_SHA" ]
  [ "$(jq -r .environment "$TMP/deployment.json")" = prod ]
}

@test "passes state, environment-url and description through" {
  INPUT_STATE=failure INPUT_ENVIRONMENT_URL=https://app.example.com \
    INPUT_DESCRIPTION="health check failed" INPUT_REVISION="$DEV_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .state "$TMP/status.json")" = failure ]
  [ "$(jq -r .environment_url "$TMP/status.json")" = https://app.example.com ]
  [ "$(jq -r .description "$TMP/status.json")" = "health check failed" ]
}

@test "records a null PR when the commit has no PR" {
  GH_STUB_PR="" INPUT_REVISION="$DEV_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .payload.pr "$TMP/deployment.json")" = null ]
  grep -qx "pr-number=" "$GITHUB_OUTPUT"
}

@test "fails when no main-sha trailer is found" {
  INPUT_REVISION="$MAIN_SHA" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No main-sha trailer"* ]]
  [ ! -e "$TMP/deployment.json" ]
}

@test "rejects an unknown state" {
  INPUT_STATE=done INPUT_REVISION="$DEV_SHA" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid state"* ]]
}
