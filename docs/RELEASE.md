# Release Guide

This document describes how to create releases for the Kiwix Helm Chart using the automated Uplift workflow.

## Overview

Releases are automated using [Uplift](https://upliftci.dev/), which:
- Analyzes conventional commits since the last release
- Determines the semantic version bump (major/minor/patch)
- Updates `Chart.yaml` version and appVersion fields
- Generates or updates `CHANGELOG.md`
- Creates an annotated git tag (e.g., `v0.2.0`)
- Creates a GitHub release with changelog
- Triggers automated publishing of Docker images and Helm charts

## Prerequisites

Before triggering a release:

1. **All commits must follow [Conventional Commits](https://www.conventionalcommits.org/) format**
2. **All tests must be passing on main branch**
3. **All required builds must be successful**
4. **You must have write access to the repository**

## Creating a Release

### Via GitHub Actions UI

1. Navigate to the repository on GitHub
2. Click **Actions** tab
3. Select **CI/CD Pipeline** workflow
4. Click **Run workflow** button (top right)
5. Ensure `main` branch is selected
6. Check the **Trigger Release** checkbox
7. Click **Run workflow** button

The workflow will:
- Run tests (helm lint, template validation)
- Build Docker image with commit SHA
- Package Helm chart as artifact
- **Wait for your manual trigger of the release job**
- Run Uplift to create version, changelog, and tag
- Publish versioned Docker image and Helm chart

### Via GitHub CLI

```bash
gh workflow run ci.yaml \
  --ref main \
  -f release=true
```

## Version Bump Rules

Uplift determines version bumps from commit message prefixes:

| Commit Type | Version Bump | Example |
|-------------|--------------|---------|
| `feat:` | Minor (0.1.0 → 0.2.0) | `feat: add custom ZIM checksums` |
| `fix:` | Patch (0.1.0 → 0.1.1) | `fix: correct CronJob schedule parsing` |
| `BREAKING CHANGE:` | Major (0.1.0 → 1.0.0) | `feat!: restructure values.yaml` |
| `chore:`, `docs:`, `ci:`, `style:`, `test:` | No release | Excluded from changelog |

**Multiple commit types in one release:**
- Any `BREAKING CHANGE` → major bump (takes precedence)
- Any `feat:` (no breaking changes) → minor bump (takes precedence over fixes)
- Only `fix:` → patch bump
- Only excluded types → no version bump

## Changelog Generation

Uplift automatically generates/updates `CHANGELOG.md`:

- Groups commits by type (Features, Bug Fixes, etc.)
- Includes commit scope if provided: `feat(downloader): ...`
- Excludes maintenance commits (chore, docs, ci, style, test)
- Sorts commits chronologically (oldest first)
- Links to GitHub commits

**Example changelog entry:**
```markdown
## [0.2.0] - 2025-11-05

### Features
- add support for custom ZIM file checksums ([abc123](https://github.com/owner/repo/commit/abc123))

### Bug Fixes
- correct CronJob schedule parsing logic ([def456](https://github.com/owner/repo/commit/def456))
```

## Rollback Procedures

### If Uplift creates an incorrect version:

1. **Delete the git tag:**
   ```bash
   git push --delete origin v0.x.x
   ```

2. **Delete the GitHub release:**
   - Go to repository **Releases** page
   - Click on the incorrect release
   - Click **Delete this release**
   - Confirm deletion

3. **Revert the version bump commit on main:**
   ```bash
   git revert <commit-sha>
   git push origin main
   ```

4. **Fix the commit messages if needed**

5. **Trigger a new release**

### If Docker/Chart publishing fails:

The workflows are idempotent and can be re-run:

1. Navigate to **Actions** → failed workflow
2. Click **Re-run failed jobs**
3. If the issue was transient (network, registry), it should succeed

If the issue persists:
- Check GHCR registry status
- Verify `GITHUB_TOKEN` permissions
- Review workflow logs for specific errors

## Best Practices

### Commit Message Guidelines

**Good commit messages:**
```bash
feat: add support for multi-arch Docker builds
fix: resolve PVC mounting issue in CronJob mode
docs: update installation instructions for OCI registry
chore: update dependencies to latest versions
```

**Bad commit messages:**
```bash
update stuff
fix bug
WIP
asdf
```

### Pre-Release Checklist

Before triggering a release, verify:

- [ ] All commits on main use conventional commit format
- [ ] CI tests are passing
- [ ] Docker image builds successfully
- [ ] Helm chart packages without errors
- [ ] No work-in-progress commits
- [ ] CHANGELOG.md will be meaningful (check commit messages)

### Release Timing

**When to release:**
- After completing a feature or set of related features
- After fixing critical bugs
- On a regular schedule (weekly, monthly)
- When users request a specific fix/feature

**When NOT to release:**
- Immediately after every commit (use batching)
- When tests are failing
- When builds are broken
- During active development of half-finished features

### Testing Before Release

1. **Test locally:**
   ```bash
   helm lint .
   helm template test . --values values.yaml
   helm install test . --dry-run --debug
   ```

2. **Test with commit SHA image:**
   The CI workflow builds images tagged with commit SHA. Test these before releasing:
   ```bash
   # Update values.yaml to use commit SHA
   downloader:
     image:
       tag: "abc1234"  # commit SHA from build job

   # Install and test
   helm install test . --values values.yaml
   ```

3. **Verify functionality:**
   - Downloader Job/CronJob runs successfully
   - ZIM files download correctly
   - Kiwix-serve starts and serves content
   - All resources deploy as expected

## Troubleshooting

### Release job doesn't start

**Cause:** Manual trigger checkbox not checked or tests/builds failed

**Solution:**
- Verify "Trigger Release" checkbox was checked
- Check that test, build-docker, and build-chart jobs completed successfully
- Review job logs for errors

### Version not bumped correctly

**Cause:** Commit messages don't follow conventional format

**Solution:**
- Review commits since last release: `git log v0.1.0..HEAD --oneline`
- Verify commit prefixes match conventional format
- Rollback and fix commit messages if needed

### Changelog is empty or missing commits

**Cause:** Commits use excluded types (chore, docs, ci, style, test)

**Solution:**
- Ensure feature/fix commits use `feat:` or `fix:` prefix
- Check `.uplift.yml` changelog exclude patterns
- If changelog should include docs, update configuration

### GitHub release creation fails

**Cause:** Token permissions or network issues

**Solution:**
- Verify `GITHUB_TOKEN` has `contents: write` permission
- Check GitHub status page for API issues
- Re-run workflow if transient failure

### Docker/Chart publishing triggered prematurely

**Cause:** Tag was pushed without completing release

**Solution:**
- This shouldn't happen with the manual release trigger
- If it does, delete the tag and release, then re-release properly

## Additional Resources

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [Uplift Documentation](https://upliftci.dev/)
- [Semantic Versioning](https://semver.org/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
