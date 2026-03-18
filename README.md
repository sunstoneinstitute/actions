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
    project-type: python  # or "npm", or "auto" (default)
# outputs: tag (e.g. "v1.3.6"), major-minor (e.g. "1.3")
```

### `image-tag`

Computes the short SHA image tag from the current commit.

```yaml
- uses: sunstoneinstitute/actions/image-tag@v1
# outputs: tag (e.g. "a1b2c3d")
```

## Usage

Since this is a private repo, calling workflows must have `actions: read`
permission on this repo, or the org must allow actions from internal repos.
Configure in org settings under Actions > General > Allow actions from
internal repositories.

## Versioning

Tags follow `v1`, `v1.0.0` convention. Use `@v1` for latest compatible.
