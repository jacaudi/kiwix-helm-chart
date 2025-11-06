# Workflow Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate docker.yaml and chart.yaml into a single publish.yaml with parallel jobs, and simplify CI skipping for Uplift commits.

**Architecture:** Replace two separate tag-triggered workflows (docker, chart) with one workflow containing two parallel jobs. Remove unreliable Uplift pushOptions and use GitHub native paths-ignore instead.

**Tech Stack:** GitHub Actions, Uplift, Helm, Docker

---

## Task 1: Create Consolidated Publish Workflow

**Files:**
- Create: `.github/workflows/publish.yaml`

### Step 1: Create publish.yaml with parallel jobs

Create the new consolidated workflow file:

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
      - name: Checkout
        uses: actions/checkout@v5

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/kiwix-downloader
          tags: |
            type=ref,event=tag
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./image
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  publish-chart:
    name: Publish Helm Chart
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: 'latest'

      - name: Extract version from tag
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Update Chart.yaml version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.version }}/" Chart.yaml
          sed -i "s/^appVersion:.*/appVersion: \"${GITHUB_REF#refs/tags/}\"/" Chart.yaml

      - name: Update dependencies
        run: helm dependency update

      - name: Lint chart
        run: helm lint .

      - name: Template chart
        run: helm template test . > /dev/null

      - name: Release chart to OCI registry
        uses: appany/helm-oci-chart-releaser@v0.5.0
        with:
          name: kiwix-helm-chart
          path: .
          repository: jacaudi
          tag: ${{ steps.version.outputs.version }}
          registry: ghcr.io
          registry_username: ${{ github.actor }}
          registry_password: ${{ secrets.GITHUB_TOKEN }}
```

### Step 2: Verify YAML syntax

Run: `cat .github/workflows/publish.yaml | head -20`

Expected: File displays correctly with proper YAML indentation

### Step 3: Commit the new workflow

```bash
git add .github/workflows/publish.yaml
git commit -m "feat: add consolidated publish workflow with parallel jobs

Combines docker.yaml and chart.yaml into a single workflow with
two parallel jobs for faster publishing."
```

Expected: Commit succeeds

---

## Task 2: Update CI Workflow Paths-Ignore

**Files:**
- Modify: `.github/workflows/ci.yaml:3-8`

### Step 1: Read current CI workflow trigger

Run: `head -20 .github/workflows/ci.yaml`

Expected: Shows current trigger configuration

### Step 2: Add Chart.yaml to paths-ignore

Find the trigger section (lines 3-8) and update:

**Before:**
```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - 'CHANGELOG.md'
```

**After:**
```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - 'CHANGELOG.md'
      - 'Chart.yaml'
```

### Step 3: Verify the change

Run: `grep -A 5 "^on:" .github/workflows/ci.yaml | head -8`

Expected: Shows both CHANGELOG.md and Chart.yaml in paths-ignore

### Step 4: Commit the change

```bash
git add .github/workflows/ci.yaml
git commit -m "fix: add Chart.yaml to CI paths-ignore

Prevents CI from triggering when Uplift updates Chart.yaml
during version bumps."
```

Expected: Commit succeeds

---

## Task 3: Simplify Uplift Configuration

**Files:**
- Modify: `.uplift.yml:2-6`

### Step 1: Read current Uplift configuration

Run: `cat .uplift.yml`

Expected: Shows current configuration with pushOptions

### Step 2: Remove pushOptions from git section

Find the git section (lines 2-6) and simplify:

**Before:**
```yaml
git:
  ignoreDetached: false
  pushOptions:
    - option: "ci.skip"
      skipTag: true
```

**After:**
```yaml
git:
  ignoreDetached: false
```

### Step 3: Verify the change

Run: `grep -A 2 "^git:" .uplift.yml`

Expected: Shows only `ignoreDetached: false`, no pushOptions

### Step 4: Commit the change

```bash
git add .uplift.yml
git commit -m "refactor: remove pushOptions from Uplift config

Using GitHub native paths-ignore instead of unreliable
push options for CI skipping."
```

Expected: Commit succeeds

---

## Task 4: Delete Old Workflow Files

**Files:**
- Delete: `.github/workflows/docker.yaml`
- Delete: `.github/workflows/chart.yaml`

### Step 1: Verify files exist before deletion

Run: `ls -la .github/workflows/*.yaml`

Expected: Shows docker.yaml, chart.yaml, ci.yaml, release.yaml, publish.yaml

### Step 2: Delete docker.yaml

```bash
git rm .github/workflows/docker.yaml
```

Expected: File staged for deletion

### Step 3: Delete chart.yaml

```bash
git rm .github/workflows/chart.yaml
```

Expected: File staged for deletion

### Step 4: Verify only intended workflows remain

Run: `ls -la .github/workflows/*.yaml`

Expected: Shows only ci.yaml, release.yaml, publish.yaml

### Step 5: Commit the deletions

```bash
git commit -m "chore: remove old docker and chart workflows

Replaced by consolidated publish.yaml with parallel jobs."
```

Expected: Commit succeeds

---

## Task 5: Validation and Testing

**Files:**
- Verify: `.github/workflows/publish.yaml`
- Verify: `.github/workflows/ci.yaml`
- Verify: `.uplift.yml`

### Step 1: Verify workflow file count

Run: `ls .github/workflows/*.yaml | wc -l`

Expected: `3` (ci.yaml, release.yaml, publish.yaml)

### Step 2: Verify publish.yaml has parallel jobs

Run: `grep -c "^  publish-" .github/workflows/publish.yaml`

Expected: `2` (publish-docker and publish-chart)

### Step 3: Verify CI paths-ignore includes Chart.yaml

Run: `grep -A 2 "paths-ignore:" .github/workflows/ci.yaml`

Expected: Shows both CHANGELOG.md and Chart.yaml

### Step 4: Verify Uplift config has no pushOptions

Run: `grep -q "pushOptions" .uplift.yml && echo "FOUND" || echo "NOT FOUND"`

Expected: `NOT FOUND`

### Step 5: Verify Helm chart still valid

Run: `helm lint . && helm template test . > /dev/null && echo "✓ Helm validation passed"`

Expected: `✓ Helm validation passed`

### Step 6: Check git status

Run: `git status`

Expected: Working tree clean, 4 commits ahead of main

### Step 7: Review commit history

Run: `git log --oneline -5`

Expected: Shows 4 commits:
1. "chore: remove old docker and chart workflows"
2. "refactor: remove pushOptions from Uplift config"
3. "fix: add Chart.yaml to CI paths-ignore"
4. "feat: add consolidated publish workflow with parallel jobs"

---

## Post-Implementation Checklist

After completing all tasks, verify:

- [ ] Only 3 workflow files exist (ci.yaml, release.yaml, publish.yaml)
- [ ] publish.yaml contains 2 parallel jobs (publish-docker, publish-chart)
- [ ] ci.yaml paths-ignore includes both CHANGELOG.md and Chart.yaml
- [ ] .uplift.yml has no pushOptions section
- [ ] docker.yaml and chart.yaml are deleted
- [ ] All changes committed (4 commits total)
- [ ] Helm chart validation passes
- [ ] Working tree is clean

## Testing After Merge

**Manual tests to perform after merging to main:**

1. **Test CI skipping on Chart.yaml change:**
   ```bash
   # Manually edit Chart.yaml version
   git checkout main
   sed -i 's/version: .*/version: 0.1.2/' Chart.yaml
   git add Chart.yaml
   git commit -m "test: bump chart version"
   git push
   ```
   Expected: CI workflow does not trigger

2. **Test normal CI on code change:**
   ```bash
   echo "# Test" >> README.md
   git add README.md
   git commit -m "docs: test CI trigger"
   git push
   ```
   Expected: CI workflow triggers and runs

3. **Test release flow:**
   - Trigger release workflow via GitHub Actions UI
   - Verify Uplift creates version and tag
   - Verify CI skips on version bump commit
   - Verify publish.yaml triggers on tag push
   - Verify both jobs run in parallel
   - Verify Docker image published to ghcr.io
   - Verify Helm chart published to ghcr.io

## Success Criteria

Implementation is complete when:

1. ✓ All 5 tasks completed
2. ✓ All validation checks pass
3. ✓ 4 commits created with clear messages
4. ✓ Working tree clean
5. ✓ Ready to merge to main via PR
