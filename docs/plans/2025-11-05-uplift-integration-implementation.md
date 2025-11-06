# Uplift Release Automation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Implement automated semantic versioning and release management using Uplift with staged CI/CD workflow mirroring GitLab pipeline structure.

**Architecture:** Single CI/CD workflow with test → build (docker + chart) → release (manual) → publish (tag-triggered) stages. Uplift analyzes conventional commits, bumps versions in Chart.yaml, generates changelog, creates tags and GitHub releases.

**Tech Stack:** GitHub Actions, Uplift, Helm, Docker, semantic versioning, conventional commits

---

## Task 1: Create Uplift Configuration

**Files:**
- Create: `.uplift.yml`

### Step 1: Create Uplift configuration file

Create `.uplift.yml`:

```yaml
# Uplift configuration for semantic versioning and changelog generation
git:
  message: "chore: release version $VERSION"

bumps:
  # Update Chart.yaml version field
  - file: Chart.yaml
    regex:
      pattern: 'version: ([0-9]+\.[0-9]+\.[0-9]+)'
      count: 1
  # Update Chart.yaml appVersion field
  - file: Chart.yaml
    regex:
      pattern: 'appVersion: "([0-9]+\.[0-9]+\.[0-9]+)"'
      count: 1

changelog:
  sort: asc
  skip:
    - chore
    - ci
    - docs
    - style
    - test

commits:
  types:
    feat: "Features"
    fix: "Bug Fixes"
    perf: "Performance Improvements"
    refactor: "Code Refactoring"
    build: "Build System"

github:
  releases:
    enabled: true
    changelog: true
```

### Step 2: Verify configuration syntax

Run: `cat .uplift.yml | grep -q "git:" && echo "YAML valid"`
Expected: YAML valid

### Step 3: Commit

```bash
git add .uplift.yml
git commit -m "feat: add Uplift configuration for semantic versioning

- Configure Chart.yaml version and appVersion bumping
- Enable changelog generation from conventional commits
- Configure GitHub release creation
"
```

---

## Task 2: Create CI/CD Workflow - Test Job

**Files:**
- Create: `.github/workflows/ci.yaml`

### Step 1: Create CI workflow with test job

Create `.github/workflows/ci.yaml`:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      release:
        description: 'Trigger release job'
        required: false
        type: boolean
        default: false

permissions:
  contents: write
  packages: write
  pull-requests: write
  issues: write

jobs:
  test:
    name: Test Helm Chart
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: 'latest'

      - name: Update dependencies
        run: helm dependency update

      - name: Lint chart
        run: helm lint .

      - name: Template chart (default values)
        run: helm template test . > /dev/null

      - name: Create test values for Job mode
        run: |
          cat > /tmp/test-job.yaml << 'EOF'
          zimFiles:
            - url: https://example.com/test.zim
          downloader:
            schedule: ""
          EOF

      - name: Template chart (Job mode)
        run: |
          helm template test . -f /tmp/test-job.yaml > /tmp/output-job.yaml
          grep -q "kind: Job" /tmp/output-job.yaml && echo "✓ Job mode validated"

      - name: Create test values for CronJob mode
        run: |
          cat > /tmp/test-cronjob.yaml << 'EOF'
          zimFiles:
            - url: https://example.com/test.zim
          downloader:
            schedule: "0 2 * * *"
          EOF

      - name: Template chart (CronJob mode)
        run: |
          helm template test . -f /tmp/test-cronjob.yaml > /tmp/output-cronjob.yaml
          grep -q "kind: CronJob" /tmp/output-cronjob.yaml && echo "✓ CronJob mode validated"

      - name: Verify resource count
        run: |
          RESOURCES=$(helm template test . | grep -E "^kind:" | wc -l)
          if [ "$RESOURCES" -ge 5 ]; then
            echo "✓ Expected resources rendered: $RESOURCES"
          else
            echo "✗ Insufficient resources: $RESOURCES (expected ≥5)"
            exit 1
          fi
```

### Step 2: Verify workflow syntax

Run: `cat .github/workflows/ci.yaml | grep -q "name: CI/CD Pipeline" && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/ci.yaml
git commit -m "feat: add CI workflow with test job

- Helm lint and template validation
- Test both Job and CronJob modes
- Verify resource rendering count
"
```

---

## Task 3: Add Build Jobs to CI Workflow

**Files:**
- Modify: `.github/workflows/ci.yaml`

### Step 1: Add build-docker job

Append to `.github/workflows/ci.yaml` after the `test` job:

```yaml
  build-docker:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main'
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

      - name: Extract commit SHA
        id: sha
        run: echo "sha=${GITHUB_SHA:0:7}" >> $GITHUB_OUTPUT

      - name: Build and push (commit SHA)
        uses: docker/build-push-action@v6
        with:
          context: ./image
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/kiwix-downloader:${{ steps.sha.outputs.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Step 2: Add build-chart job

Append to `.github/workflows/ci.yaml` after the `build-docker` job:

```yaml
  build-chart:
    name: Build Helm Chart
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: 'latest'

      - name: Update dependencies
        run: helm dependency update

      - name: Lint chart
        run: helm lint .

      - name: Template chart
        run: helm template test . > /dev/null

      - name: Package chart
        run: helm package .

      - name: Upload chart artifact
        uses: actions/upload-artifact@v4
        with:
          name: helm-chart
          path: "*.tgz"
          retention-days: 7
```

### Step 3: Verify additions

Run: `grep -q "build-docker:" .github/workflows/ci.yaml && grep -q "build-chart:" .github/workflows/ci.yaml && echo "OK"`
Expected: OK

### Step 4: Commit

```bash
git add .github/workflows/ci.yaml
git commit -m "feat: add build jobs to CI workflow

- build-docker: Multi-arch image with commit SHA tag
- build-chart: Package chart and upload as artifact
- Both depend on test job passing
"
```

---

## Task 4: Add Release Job to CI Workflow

**Files:**
- Modify: `.github/workflows/ci.yaml`

### Step 1: Add release job

Append to `.github/workflows/ci.yaml` after the `build-chart` job:

```yaml
  release:
    name: Create Release
    runs-on: ubuntu-latest
    needs: [test, build-docker, build-chart]
    if: github.event.inputs.release == 'true' && github.ref == 'refs/heads/main'
    environment: production
    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Run Uplift
        uses: gembaadvantage/uplift-action@v2
        with:
          args: release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Step 2: Verify additions

Run: `grep -q "name: Create Release" .github/workflows/ci.yaml && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/ci.yaml
git commit -m "feat: add release job to CI workflow

- Manual trigger via workflow_dispatch
- Depends on test and build jobs
- Uses Uplift to create semantic release
- Pushes tags and creates GitHub release
"
```

---

## Task 5: Update Docker Workflow for Tag-Only Triggers

**Files:**
- Modify: `.github/workflows/docker.yaml`

### Step 1: Read current docker workflow

Run: `cat .github/workflows/docker.yaml | head -20`
Expected: Shows current workflow with main branch and tags triggers

### Step 2: Update trigger to tags-only

Find and replace in `.github/workflows/docker.yaml`:

**Find:**
```yaml
on:
  push:
    branches:
      - main
    tags:
      - 'v*'
```

**Replace with:**
```yaml
on:
  push:
    tags:
      - 'v*'
```

### Step 3: Update image tags for release

Find and replace in `.github/workflows/docker.yaml`:

**Find:**
```yaml
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=tag
            type=raw,value=latest,enable={{is_default_branch}}
```

**Replace with:**
```yaml
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/kiwix-downloader
          tags: |
            type=ref,event=tag
            type=raw,value=latest
```

### Step 4: Verify changes

Run: `grep -c "branches:" .github/workflows/docker.yaml`
Expected: 0 (no branch triggers)

### Step 5: Commit

```bash
git add .github/workflows/docker.yaml
git commit -m "refactor: change docker workflow to tag-only triggers

- Remove main branch trigger
- Publish only on version tags
- Tag push publishes versioned + latest images
"
```

---

## Task 6: Update Chart Workflow for Tag-Only Triggers

**Files:**
- Modify: `.github/workflows/chart.yaml`

### Step 1: Read current chart workflow

Run: `cat .github/workflows/chart.yaml | head -20`
Expected: Shows current workflow with main branch and tags triggers

### Step 2: Simplify trigger to tags-only

Find and replace in `.github/workflows/chart.yaml`:

**Find:**
```yaml
on:
  push:
    branches:
      - main
    tags:
      - 'v*'
```

**Replace with:**
```yaml
on:
  push:
    tags:
      - 'v*'
```

### Step 3: Simplify version extraction for tags

Find and replace in `.github/workflows/chart.yaml`:

**Find:**
```yaml
      - name: Extract version
        id: version
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/v* ]]; then
            # Tag push: extract version from tag
            VERSION=${GITHUB_REF#refs/tags/v}
            APP_VERSION=${GITHUB_REF#refs/tags/}
            CHART_TAG=$VERSION
          else
            # Branch push: use Chart.yaml version + commit SHA
            VERSION=$(grep '^version:' Chart.yaml | awk '{print $2}')
            APP_VERSION="${GITHUB_SHA:0:7}"
            CHART_TAG="${VERSION}-${GITHUB_SHA:0:7}"
          fi
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "app_version=$APP_VERSION" >> $GITHUB_OUTPUT
          echo "chart_tag=$CHART_TAG" >> $GITHUB_OUTPUT
```

**Replace with:**
```yaml
      - name: Extract version from tag
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=$VERSION" >> $GITHUB_OUTPUT
```

### Step 4: Update Chart.yaml update step

Find and replace in `.github/workflows/chart.yaml`:

**Find:**
```yaml
      - name: Update Chart.yaml version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.version }}/" Chart.yaml
          sed -i "s/^appVersion:.*/appVersion: \"${{ steps.version.outputs.app_version }}\"/" Chart.yaml
```

**Replace with:**
```yaml
      - name: Update Chart.yaml version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.version }}/" Chart.yaml
          sed -i "s/^appVersion:.*/appVersion: \"${GITHUB_REF#refs/tags/}\"/" Chart.yaml
```

### Step 5: Update OCI tag reference

Find and replace in `.github/workflows/chart.yaml`:

**Find:**
```yaml
          tag: ${{ steps.version.outputs.chart_tag }}
```

**Replace with:**
```yaml
          tag: ${{ steps.version.outputs.version }}
```

### Step 6: Verify changes

Run: `grep -c "branches:" .github/workflows/chart.yaml`
Expected: 0 (no branch triggers)

### Step 7: Commit

```bash
git add .github/workflows/chart.yaml
git commit -m "refactor: change chart workflow to tag-only triggers

- Remove main branch trigger
- Publish only on version tags
- Simplify version extraction for tags only
"
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/RELEASE.md`

### Step 1: Add release workflow section to README

Add after the "Automated Dependency Updates" section in `README.md`:

```markdown
## Release Workflow

This project uses [Uplift](https://upliftci.dev/) for automated semantic versioning and releases.

### Creating a Release

Releases are created manually when ready:

1. Ensure all changes are merged to `main`
2. Go to GitHub Actions → CI/CD Pipeline
3. Click "Run workflow"
4. Check the "Trigger release job" option
5. Click "Run workflow"

Uplift will:
- Analyze commits since the last release
- Determine version bump based on conventional commits
- Update `Chart.yaml` version and appVersion
- Generate/update `CHANGELOG.md`
- Create a git tag (e.g., `v0.2.0`)
- Create a GitHub release with changelog
- Trigger publication of versioned Docker image and Helm chart

### Conventional Commits

Use conventional commit format for automatic version bumping:

- `feat: <message>` - Minor version bump (new feature)
- `fix: <message>` - Patch version bump (bug fix)
- `feat!: <message>` or `BREAKING CHANGE:` - Major version bump
- `chore:`, `docs:`, `ci:` - No version bump

**Examples:**
```bash
feat: add support for multiple ZIM files
fix: correct ConfigMap JSON generation
feat!: restructure values.yaml schema

BREAKING CHANGE: zimFiles moved to downloads.files
```
```

### Step 2: Create release documentation

Create `docs/RELEASE.md`:

```markdown
# Release Process

## Overview

This project uses Uplift for automated semantic versioning and release management. Releases are manually triggered via GitHub Actions.

## Prerequisites

- All changes merged to `main` branch
- CI tests passing
- Docker and Helm chart builds successful

## Creating a Release

### 1. Trigger Release Workflow

**Via GitHub UI:**
1. Navigate to repository → Actions → CI/CD Pipeline
2. Click "Run workflow" button
3. Select branch: `main`
4. Check "Trigger release job" checkbox
5. Click "Run workflow"

**Via GitHub CLI:**
```bash
gh workflow run ci.yaml --ref main -f release=true
```

### 2. Uplift Process

Uplift will automatically:

1. **Analyze commits** since last tag using conventional commit format
2. **Determine version bump**:
   - `feat:` commits → minor bump (0.1.0 → 0.2.0)
   - `fix:` commits → patch bump (0.1.0 → 0.1.1)
   - `BREAKING CHANGE` → major bump (0.1.0 → 1.0.0)
3. **Update Chart.yaml**:
   - `version` field
   - `appVersion` field
4. **Generate CHANGELOG.md** from commit messages
5. **Create git commit** with version changes
6. **Create git tag** (e.g., `v0.2.0`)
7. **Push tag to origin**
8. **Create GitHub release** with changelog

### 3. Automatic Publishing

Once the tag is created, workflows automatically trigger:

**Docker Image** (`.github/workflows/docker.yaml`):
- Builds multi-arch image (amd64, arm64)
- Publishes versioned tag: `ghcr.io/jacaudi/kiwix-downloader:v0.2.0`
- Updates latest tag: `ghcr.io/jacaudi/kiwix-downloader:latest`

**Helm Chart** (`.github/workflows/chart.yaml`):
- Packages chart with version from tag
- Publishes to OCI registry: `oci://ghcr.io/jacaudi/charts/kiwix:0.2.0`

## Conventional Commit Format

### Commit Types

| Type | Version Bump | Example |
|------|--------------|---------|
| `feat:` | Minor | `feat: add CronJob mode for periodic downloads` |
| `fix:` | Patch | `fix: correct ConfigMap JSON generation` |
| `perf:` | Patch | `perf: optimize image build cache` |
| `refactor:` | None | `refactor: simplify workflow structure` |
| `docs:` | None | `docs: update installation instructions` |
| `chore:` | None | `chore: update dependencies` |
| `ci:` | None | `ci: add test coverage reporting` |

### Breaking Changes

For breaking changes, use one of these formats:

**Exclamation mark:**
```bash
feat!: restructure values.yaml schema
```

**Footer:**
```bash
feat: restructure values.yaml schema

BREAKING CHANGE: zimFiles moved to downloads.files. Update your values.yaml accordingly.
```

## Release Checklist

Before triggering release:

- [ ] All changes merged to `main`
- [ ] CI/CD pipeline green (test + build jobs passing)
- [ ] Commits follow conventional commit format
- [ ] No work-in-progress changes on `main`
- [ ] Documentation updated if needed

After release:

- [ ] Verify GitHub release created with proper changelog
- [ ] Verify Docker image published with version tag
- [ ] Verify Helm chart published to OCI registry
- [ ] Test installation with new version

## Troubleshooting

### Release Job Failed

**Issue:** Uplift fails to determine version
- **Cause:** No conventional commits since last release
- **Fix:** Ensure at least one `feat:` or `fix:` commit exists

**Issue:** Git push fails
- **Cause:** Insufficient permissions
- **Fix:** Verify GITHUB_TOKEN has `contents: write` permission

**Issue:** GitHub release not created
- **Cause:** Network error or API rate limit
- **Fix:** Re-run workflow after a few minutes

### Tag Already Exists

**Issue:** Tag `v0.2.0` already exists
- **Fix:** Delete tag and release if needed:
  ```bash
  git tag -d v0.2.0
  git push origin :refs/tags/v0.2.0
  gh release delete v0.2.0
  ```

### Wrong Version Calculated

**Issue:** Uplift calculated patch instead of minor bump
- **Cause:** Missing `feat:` prefix on new features
- **Fix:**
  1. Amend commit message if recent: `git commit --amend`
  2. Or create new `feat:` commit to trigger correct bump

## Manual Release (Emergency)

If Uplift is unavailable, manual release process:

```bash
# 1. Update Chart.yaml manually
vim Chart.yaml  # Update version and appVersion

# 2. Generate changelog entry manually
vim CHANGELOG.md

# 3. Commit changes
git add Chart.yaml CHANGELOG.md
git commit -m "chore: release version 0.2.0"

# 4. Create and push tag
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin main --tags

# 5. Create GitHub release manually via UI
```

## Version History

View release history:

**GitHub Releases:**
https://github.com/jacaudi/kiwix-helm-chart/releases

**Git Tags:**
```bash
git tag -l
```

**Changelog:**
```bash
cat CHANGELOG.md
```
```

### Step 3: Verify documentation

Run: `grep -q "Release Workflow" README.md && echo "README updated"`
Expected: README updated

Run: `test -f docs/RELEASE.md && echo "RELEASE.md created"`
Expected: RELEASE.md created

### Step 4: Commit

```bash
git add README.md docs/RELEASE.md
git commit -m "docs: add release workflow documentation

- Add release workflow section to README
- Create comprehensive RELEASE.md guide
- Document conventional commit usage
- Include troubleshooting steps
"
```

---

## Task 8: Validation and Testing

**Files:**
- No file changes, verification only

### Step 1: Validate workflow syntax

Run: `yamllint .github/workflows/ci.yaml .github/workflows/docker.yaml .github/workflows/chart.yaml 2>/dev/null || echo "Note: yamllint not installed, skipping"`
Expected: No errors or note about yamllint

### Step 2: Verify Uplift configuration

Run: `cat .uplift.yml | grep -E "(git:|bumps:|github:)" && echo "Config structure OK"`
Expected: Config structure OK

### Step 3: Test Chart.yaml regex patterns

Run: `grep "version:" Chart.yaml | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" && echo "Version pattern matches"`
Expected: Version pattern matches (shows current version)

Run: `grep "appVersion:" Chart.yaml | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" && echo "AppVersion pattern matches"`
Expected: AppVersion pattern matches (shows current appVersion)

### Step 4: Verify workflow job dependencies

Run: `grep -A 2 "needs:" .github/workflows/ci.yaml`
Expected: Shows release job needs [test, build-docker, build-chart]

### Step 5: Verify tag-only triggers

Run: `grep -A 5 "^on:" .github/workflows/docker.yaml | grep -c "branches:"`
Expected: 0 (no branch triggers)

Run: `grep -A 5 "^on:" .github/workflows/chart.yaml | grep -c "branches:"`
Expected: 0 (no branch triggers)

### Step 6: Verify manual release trigger

Run: `grep -A 3 "workflow_dispatch:" .github/workflows/ci.yaml | grep -q "release:" && echo "Manual trigger configured"`
Expected: Manual trigger configured

### Step 7: Create summary commit

```bash
git add -A
git commit -m "chore: complete Uplift integration

All components implemented:
- CI/CD workflow with test, build, and release stages
- Uplift configuration for semantic versioning
- Updated docker and chart workflows for tag-only publishing
- Comprehensive release documentation

Ready for testing on main branch
" --allow-empty
```

---

## Post-Implementation Checklist

After all tasks complete, manual steps required:

- [ ] **Merge to main** via Pull Request or direct merge
- [ ] **Verify CI workflow runs** on main branch push
- [ ] **Test manual release trigger**:
  - Go to Actions → CI/CD Pipeline
  - Run workflow with "Trigger release job" checked
  - Verify Uplift creates tag and GitHub release
- [ ] **Verify tag-triggered publishes**:
  - Check Docker image published to GHCR
  - Check Helm chart published to OCI registry
- [ ] **Review generated changelog**:
  - Check CHANGELOG.md formatting
  - Verify commit categorization
- [ ] **Test chart installation**:
  - Install from new OCI version
  - Verify all resources deploy correctly

## Success Criteria

Implementation is complete when:

1. ✅ `.uplift.yml` exists with Chart.yaml regex patterns
2. ✅ `.github/workflows/ci.yaml` exists with 4 jobs (test, build-docker, build-chart, release)
3. ✅ `docker.yaml` triggers only on tags
4. ✅ `chart.yaml` triggers only on tags
5. ✅ Documentation explains release process
6. ✅ All changes committed to feature branch
7. ⏳ Workflow tested on main branch (post-merge)
8. ⏳ Manual release successfully creates tag (post-merge)
9. ⏳ Tag triggers publish versioned artifacts (post-merge)

## Notes

- The feature branch is isolated in worktree for testing
- CI workflow will not run until merged to main
- First release will be triggered manually after merge
- Uplift will analyze all commits since repository creation for first CHANGELOG
- Subsequent releases will only analyze commits since last tag
