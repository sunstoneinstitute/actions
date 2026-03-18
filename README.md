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
    registry: europe-central2-docker.pkg.dev/sunstone-devel/my-app
    tag: ${{ steps.tag.outputs.sha }}
```

### `compute-version`

Computes a semver prod tag by reading major.minor from `pyproject.toml` or
`package.json` and auto-incrementing the patch number based on existing git
tags.

```yaml
- uses: sunstoneinstitute/actions/compute-version@v1
  with:
    version-file: hugin/pyproject.toml  # or package.json; auto-detects if omitted
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
    from-registry: europe-central2-docker.pkg.dev/sunstone-devel/my-app
    to-registry: europe-central2-docker.pkg.dev/sunstone-production/my-app
    version-file: hugin/pyproject.toml
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

## Usage

Since this is a private repo, calling workflows must have `actions: read`
permission on this repo, or the org must allow actions from internal repos.
Configure in org settings under Actions > General > Allow actions from
internal repositories.

## Versioning

Tags follow `v1`, `v1.0.0` convention. Use `@v1` for latest compatible.
