# Workflow Consolidation Design

**Date:** 2025-11-05
**Status:** Approved

## Overview

Consolidate Docker and Helm chart publishing workflows into a single parallel-job workflow, and simplify CI skipping for Uplift version bump commits.

## Goals

- Reduce workflow file count from 4 to 3
- Combine similar Docker and Chart publishing workflows
- Ensure Uplift version bump commits don't trigger CI
- Maintain parallel execution for faster publishing
- Simplify Uplift configuration

## Current State

**Workflow files:**
- `.github/workflows/ci.yaml` - Tests and builds on push to main
- `.github/workflows/docker.yaml` - Publishes Docker image on tag push
- `.github/workflows/chart.yaml` - Publishes Helm chart on tag push
- `.github/workflows/release.yaml` - Manual Uplift trigger

**Uplift configuration:**
```yaml
git:
  ignoreDetached: false
  pushOptions:
    - option: "ci.skip"
      skipTag: true
```

**Problem:** `pushOptions: ci.skip` is not reliably supported by GitHub Actions.

## Proposed Changes

### 1. Consolidate Publishing Workflows

**Create:** `.github/workflows/publish.yaml`

**Delete:**
- `.github/workflows/docker.yaml`
- `.github/workflows/chart.yaml`

**Structure:**
```yaml
name: Publish Artifacts

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: read
  packages: write

jobs:
  publish-docker:
    name: Publish Docker Image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      # Same steps as current docker.yaml
      - Checkout
      - Set up Docker Buildx
      - Login to GHCR
      - Extract metadata (versioned tag + latest)
      - Build and push multi-arch image

  publish-chart:
    name: Publish Helm Chart
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      # Same steps as current chart.yaml
      - Checkout
      - Install Helm
      - Extract version from tag
      - Update Chart.yaml version
      - Update dependencies
      - Lint chart
      - Template chart
      - Release to OCI registry
```

**Benefits:**
- Both jobs run in parallel (no dependencies)
- Single workflow file for all publishing
- Faster execution (2-3 minutes saved vs sequential)
- Clearer purpose: "publish.yaml publishes artifacts"

### 2. Simplify Uplift Configuration

**Update:** `.uplift.yml`

**Remove:**
```yaml
pushOptions:
  - option: "ci.skip"
    skipTag: true
```

**New configuration:**
```yaml
git:
  ignoreDetached: false

bumps:
  # ... existing bump configuration

changelog:
  # ... existing changelog configuration
```

**Rationale:** Use GitHub native `paths-ignore` instead of unreliable push options.

### 3. Update CI Workflow Path Ignoring

**Update:** `.github/workflows/ci.yaml`

**Add Chart.yaml to paths-ignore:**
```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - 'CHANGELOG.md'
      - 'Chart.yaml'
```

**Why ignore Chart.yaml:**
- Uplift updates Chart.yaml during version bumps
- Version bump commits don't need CI (tests already passed before release)
- Native GitHub feature, always works reliably

## Workflow Sequence

### Release Flow

1. **Developer triggers release:**
   - Actions → Release → Run workflow
   - Check "Create release" checkbox
   - Workflow: `release.yaml`

2. **Uplift runs:**
   - Analyzes commits since last tag
   - Determines semantic version bump
   - Updates `Chart.yaml` (version and appVersion)
   - Updates `CHANGELOG.md`
   - Commits changes
   - Creates git tag (e.g., `v0.2.0`)
   - Pushes commit and tag using PAT_TOKEN

3. **Commit push to main:**
   - CI workflow checks paths
   - Only `Chart.yaml` and `CHANGELOG.md` changed
   - Both in `paths-ignore`
   - **CI skips** ✓

4. **Tag push:**
   - Triggers `publish.yaml`
   - `publish-docker` and `publish-chart` run in parallel
   - Docker: Builds and pushes `v0.2.0` + `latest` tags
   - Chart: Packages and pushes to OCI registry

### Normal Development Flow

1. **Developer pushes code to main:**
   - Changes to source code, workflows, templates, etc.
   - NOT just CHANGELOG.md or Chart.yaml
   - **CI runs** ✓ (test + build jobs)

2. **No tag created:**
   - Publish workflow does not trigger
   - Only CI runs

## File Changes

**New files:**
- `.github/workflows/publish.yaml`

**Modified files:**
- `.github/workflows/ci.yaml` (add Chart.yaml to paths-ignore)
- `.uplift.yml` (remove pushOptions)

**Deleted files:**
- `.github/workflows/docker.yaml`
- `.github/workflows/chart.yaml`

**Unchanged:**
- `.github/workflows/release.yaml`

## Benefits

1. **Fewer workflow files** - 3 instead of 4
   - ci.yaml: Test and build
   - publish.yaml: Publish artifacts
   - release.yaml: Create releases

2. **Clearer separation of concerns**
   - CI: Validates code changes
   - Publish: Publishes versioned artifacts
   - Release: Creates semantic versions

3. **Faster publishing** - Parallel execution saves 2-3 minutes

4. **Reliable CI skipping** - paths-ignore is native GitHub feature

5. **Simpler Uplift config** - No workarounds or unsupported features

## Risk Mitigation

**Risk:** Docker publish fails but Chart succeeds

**Mitigation:**
- Jobs are independent (both can succeed/fail individually)
- Chart references Docker image by version tag
- If Docker fails, chart will reference non-existent image tag
- Users will see error when deploying chart
- **Acceptable:** Publish failures are visible and fixable via re-run

**Risk:** Paths-ignore doesn't work as expected

**Mitigation:**
- paths-ignore is well-documented GitHub feature
- Tested and reliable
- If it fails, CI runs unnecessarily (not critical)
- Can monitor and adjust if issues arise

## Testing Plan

**After implementation:**

1. **Test CI skipping:**
   - Manually edit Chart.yaml version
   - Push to main
   - Verify CI workflow skips

2. **Test normal CI:**
   - Edit source file (e.g., README.md)
   - Push to main
   - Verify CI workflow runs

3. **Test release flow:**
   - Trigger release workflow
   - Verify Uplift creates version and tag
   - Verify CI skips on version bump commit
   - Verify publish.yaml triggers on tag
   - Verify both Docker and Chart publish successfully

4. **Test parallel execution:**
   - Check workflow run times
   - Verify both jobs start simultaneously
   - Verify completion time is faster than sequential

## Success Criteria

- [ ] Only 3 workflow files exist (ci, publish, release)
- [ ] Uplift commits don't trigger CI
- [ ] Normal code pushes trigger CI
- [ ] Tag pushes trigger both Docker and Chart publishing
- [ ] Publishing jobs run in parallel
- [ ] All existing functionality preserved
