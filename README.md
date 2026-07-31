# Sunstone Actions

Reusable GitHub Actions for Sunstone Institute CI/CD pipelines.

## Actions

### `update-deploy-branch`

Updates a `last-deploy/<env>` branch using the cherry-pick strategy for Flux
GitOps deployment. Handles cherry-picking new commits from main, updating
image tags in Kustomize overlays, and pushing the deploy branch.

```yaml
- uses: sunstoneinstitute/actions/update-deploy-branch@v1
  with:
    env: dev
    images: app migrations
    registry: ${{ vars.DEV__DOCKER_REGISTRY }}/my-app
    tag: ${{ steps.tag.outputs.sha }}
```

### `compute-version`

Computes a semver prod tag by reading major.minor from `pyproject.toml`,
`package.json`, or a plain-text `VERSION` file, and auto-incrementing the
patch number based on existing git tags. Alternatively, pass
`bump: patch|minor|major` to compute the next version from the highest
existing `vX.Y.Z` tag, ignoring the version file.

```yaml
- uses: sunstoneinstitute/actions/compute-version@v1
  with:
    version-file: hugin/pyproject.toml  # or package.json/VERSION; auto-detects if omitted
    # bump: minor  # optional: compute from git tags instead of version-file
# outputs: tag (e.g. "v1.3.6"), major-minor (e.g. "1.3")
```

### `image-tag`

Computes the short SHA image tag from the current commit.

```yaml
- uses: sunstoneinstitute/actions/image-tag@v1
# outputs: tag (e.g. "a1b2c3d")
```

### `promote-images`

Promotes container images from one environment to another. Resolves the
source deploy branch, computes a semver tag, copies images with crane,
updates the target deploy branch, and creates a git tag.

```yaml
- uses: sunstoneinstitute/actions/promote-images@v1
  with:
    from-env: dev       # default
    to-env: prod        # default
    images: hugin molnir
    from-registry: ${{ vars.DEV__DOCKER_REGISTRY }}/my-app
    to-registry: ${{ vars.PROD__DOCKER_REGISTRY }}/my-app
    version-file: hugin/pyproject.toml
    # bump: minor  # optional: version from git tags instead of version-file
# outputs: from-tag, to-tag, source-sha
```

Caller must: `actions/checkout@v4` with `fetch-depth: 0` and authenticate
to both container registries before calling this action.

### `validate-kustomize`

Builds all Kustomize overlays to catch errors before deploy.

```yaml
- uses: sunstoneinstitute/actions/validate-kustomize@v1
  with:
    environments: dev prod  # default
```

### `combine-prs`

Combines open dependabot PRs into the oldest one nightly using server-side
merges, then closes the superseded PRs. Creates no new PR, so the default
`GITHUB_TOKEN` (with `contents: write` + `pull-requests: write`) is enough.

```yaml
- uses: sunstoneinstitute/actions/combine-prs@v1
  # with:
  #   branch-prefix: dependabot   # default
  #   min-combine: "2"            # default
```

PRs whose branches conflict are left open and listed in the combined PR body.

## Overlay Layouts

The actions support two Kustomize overlay layouts and auto-detect which
one is in use:

**Subdir layout** — one kustomization per image:

```
deploy/overlays/<env>/<image>/kustomization.yaml
```

**Flat layout** — a single kustomization for all images:

```
deploy/overlays/<env>/kustomization.yaml
```

Both `update-deploy-branch` and `promote-images` detect the layout
automatically. You can also override detection with the `overlay-path`
input.

Auto-detection assumes the overlay directory is named after the environment.
When it isn't — e.g. env `dev` living in `deploy/overlays/hzdev` — pass paths
explicitly: `overlay-path` for the target overlay, and, for `promote-images`,
`from-overlay-path` for the source overlay it reads the current tag from.

## Usage

Since this is a private repo, calling workflows must have `actions: read`
permission on this repo, or the org must allow actions from internal repos.
Configure in org settings under Actions > General > Allow actions from
internal repositories.

## Versioning

Tags follow `v1`, `v1.0.0` convention. Use `@v1` for latest compatible.
