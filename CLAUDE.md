# Sunstone Actions — Agent Instructions

Reusable composite GitHub Actions for Sunstone CI/CD. Consumers pin to the
major floating tag (`@v1`) or, in production, to an immutable commit SHA with a
trailing `# vX.Y.Z` comment.

## Release process — ALWAYS publish with two tag operations

When you change an action, consumers pinned to `@v1` (or to whatever `@v1`
last resolved to) will NOT receive the change unless the floating major tag is
moved. Forgetting this is the lag bug this doc exists to prevent. Every release
therefore does BOTH of the following:

1. **Cut an immutable semver tag** at the new release commit on `main`:
   - **major** (`vN.0.0`) — breaking change to an action's `inputs`/`outputs`
     or behavior contract.
   - **minor** (`v1.N.0`) — additive, backward-compatible behavior (new input
     with a default, a new safety guard, a dependency bump).
   - **patch** (`v1.4.N`) — bugfix only, no interface change.
2. **Slide the major floating tag** (`v1`) forward to `main` HEAD.

### Invariant

`v1` MUST always point at `main` HEAD. Slide it on every push to `main`,
including docs-only commits (like this file). The newest `vX.Y.Z` tag marks the
latest commit that changed action *code*; a docs-only commit may leave `v1`
one commit ahead of the newest semver tag — that is expected and is NOT a lag.

If `git ls-remote origin v1 refs/heads/main` shows two different SHAs, the
major tag was not slid — fix it.

### Commands

```bash
git fetch origin --tags --force
SHA=$(git rev-parse origin/main)

# 1. Immutable semver tag at the code-change commit (pick the right bump):
git tag -a v1.5.0 -m "<what changed>" "$SHA"
git push origin v1.5.0

# 2. Slide the major tag to main HEAD:
git tag -f v1 "$SHA"
git push --force origin v1
```

### Verify

```bash
git ls-remote origin v1 refs/heads/main
# v1 and main MUST show the same SHA.
git ls-remote origin --tags | grep -E 'v1(\.|$)'
# Confirm the new semver tag is present.
```
