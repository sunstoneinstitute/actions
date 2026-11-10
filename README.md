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

### `setup-kustomize`

Installs a pinned kustomize release and adds it to `PATH`. It downloads the
release asset directly and verifies its checksum, with no GitHub API calls.

```yaml
- uses: sunstoneinstitute/actions/setup-kustomize@v1
  with:
    version: 5.8.3  # default
```

### `validate-kustomize`

Builds all Kustomize overlays to catch errors before deploy. Installs kustomize
with `setup-kustomize`.

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

### `sunstone-package-push`

Builds and pushes Sunstone data packages to the data platform: runs
`sunstone package build`, then `sunstone package push --branch <git branch>`,
in the directory of each `datasets.yaml`. A push from a PR branch lands on the
data branch of the same name, so the datasets can be reviewed before merge.

**Always push** the listed files (default: the top-level `datasets.yaml`):

```yaml
- uses: actions/checkout@v6
  with:
    lfs: true
- uses: sunstoneinstitute/actions/sunstone-package-push@v1
  with:
    paths: |
      datasets.yaml
      FishFarmingProject/datasets.yaml
    client-id: ${{ vars.DATA_PLATFORM_CLIENT_ID }}
    client-secret: ${{ secrets.DATA_PLATFORM_CLIENT_SECRET }}
```

**Push what changed**: only the `datasets.yaml` files whose `datasets.yaml`,
`datasets.lock.yaml` or `include:` files changed. `paths` limits the
candidates and defaults to every tracked `datasets.yaml` in the repository.

```yaml
on:
  pull_request:
  push:
    branches: [main]
jobs:
  push-datasets:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@v6
        with:
          lfs: true
      - uses: sunstoneinstitute/actions/sunstone-package-push@v1
        with:
          mode: changed
          client-id: ${{ vars.DATA_PLATFORM_CLIENT_ID }}
          client-secret: ${{ secrets.DATA_PLATFORM_CLIENT_SECRET }}
# outputs: pushed (datasets.yaml files, one per line), count
```

| Input | Default | Meaning |
|---|---|---|
| `mode` | `always` | `always` or `changed`. |
| `paths` | see above | `datasets.yaml` files, one per line. |
| `base` | auto | `changed` mode: ref to compare HEAD with. Auto is the PR base on `pull_request`, the previous head on `push`, and the default branch for a new branch. |
| `branch` | git branch | Data platform branch. The PR head branch on `pull_request`. |
| `env` | `prod` | `sunstone package push --env`. |
| `build` | `true` | Run `sunstone package build` first. |
| `namespaces-only` | `true` | Skip blob-store destinations (`gs://`, `s3://`, `r2://`). They have no branches, so a PR push would overwrite the published files. |
| `push-args` | | Extra `sunstone package push` arguments, e.g. `--yes`. |
| `command` | `uvx --from sunstone-py --with sunstone-data-platform sunstone` | How to run the CLI. Pin versions here, or use `uv run sunstone` for each project's locked version. |
| `install-uv` | `true` | Install uv with `astral-sh/setup-uv`. |
| `client-id`, `client-secret` | | Keycloak service account for the data platform. |
| `access-token` | | A ready bearer token, used instead of the client credentials. |

Notes:

- Needs a sunstone-py release with `sunstone package changed` and
  `sunstone package push --namespaces-only`.
- `changed` mode compares from the merge base, so the action fetches full
  history when the checkout is shallow. With the automatic base, a `push`
  event sees only the commits of that push. Trigger on `pull_request`, or set
  `base: origin/main`, to push everything the branch changed on every run.
- A package that fails does not stop the others. The step fails at the end.
- Files stored in Git LFS must be checked out (`lfs: true`). Push refuses LFS
  pointer files.
- Pull requests from forks get no secrets, so the push fails on auth.

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
