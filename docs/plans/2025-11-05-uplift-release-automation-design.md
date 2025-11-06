# Uplift Release Automation Design

**Date:** 2025-11-05
**Status:** Approved

## Overview

Integrate Uplift to automate semantic versioning, changelog generation, git tagging, and GitHub releases. Design mirrors GitLab pipeline structure with staged jobs and manual release trigger.

## Goals

- **Automated version bumping**: Analyze conventional commits to determine semver bump
- **Changelog generation**: Create/update CHANGELOG.md from commit messages
- **Git tag management**: Create annotated tags for releases
- **GitHub releases**: Publish release notes with changelog
- **Quality gates**: Test and build before allowing release
- **Manual control**: Release only when explicitly triggered

## Architecture

### Workflow Structure

**Single CI/CD Pipeline** (`.github/workflows/ci.yaml`)

```
Push to main → test → build (docker + chart) → [manual] release → tag created → publish
```

**Stages:**
1. **test**: Validate Helm chart
2. **build-docker**: Build downloader image with commit SHA
3. **build-chart**: Package chart (not published yet)
4. **release**: Manual trigger - Uplift creates version, changelog, tag, GitHub release
5. **publish**: Existing docker.yaml and chart.yaml trigger on tags to publish versioned artifacts

### Design Principles

- **Single workflow file**: Easier to understand than workflow_run triggers
- **Explicit dependencies**: Each job declares what it needs via `needs:`
- **Manual release gate**: Release job uses `workflow_dispatch` + `if: manual`
- **Tag-based publishing**: Versioned artifacts only published after tag created
- **Full history**: Checkout with `fetch-depth: 0` for changelog generation

## Components

### 1. Test Job

**Purpose:** Validate Helm chart before any builds

**Steps:**
- Checkout code
- Install Helm
- Update dependencies (`helm dependency update`)
- Lint chart (`helm lint .`)
- Template validation (`helm template test .`)
- Schema validation (kubeconform or helm-docs)
- Test both modes:
  - Job mode (empty schedule)
  - CronJob mode (schedule set)

**Validation:**
- Chart.yaml syntax and metadata
- Template rendering without errors
- All 5 resources render correctly (ConfigMap, PVC, Service, Deployment, Job/CronJob)
- ConfigMap JSON generation is valid
- Values schema compliance

**Failure behavior:**
- Test fails → build jobs don't run
- Prevents releasing broken charts

### 2. Build-Docker Job

**Purpose:** Build and validate downloader image

**Configuration:**
- Depends on: `test`
- Runs on: `main` branch pushes
- Platform: linux/amd64, linux/arm64
- Cache: GitHub Actions cache

**Steps:**
- Checkout code
- Set up Docker Buildx
- Login to GHCR
- Extract commit SHA
- Build multi-arch image
- Push with commit SHA tag: `ghcr.io/jacaudi/kiwix-downloader:<sha>`
- **Does NOT push `latest` tag** (published after release)

**Why commit SHA only:**
- Validates build succeeds before release
- Provides testable image pre-release
- `latest` published only after Uplift creates tag

### 3. Build-Chart Job

**Purpose:** Package Helm chart for validation

**Configuration:**
- Depends on: `test`
- Runs on: `main` branch pushes

**Steps:**
- Checkout code
- Install Helm
- Update dependencies
- Lint chart (redundant safety check)
- Template chart
- Package chart as `.tgz`
- Store as GitHub Actions artifact

**Why not publish:**
- Validates packaging succeeds before release
- Chart published to GHCR OCI registry only after tag created
- Artifact available for manual inspection

### 4. Release Job (Uplift)

**Purpose:** Create semantic version release with changelog

**Configuration:**
- Depends on: `[test, build-docker, build-chart]`
- Trigger: `workflow_dispatch` (manual only)
- Constraint: `if: github.ref == 'refs/heads/main'`
- Environment: `production` (requires manual approval in GitHub)

**Steps:**
1. Checkout with full history (`fetch-depth: 0`)
2. Configure git user for commits
3. Run Uplift container:
   - Analyze commits since last tag
   - Parse conventional commits (feat:, fix:, chore:, etc.)
   - Determine semver bump (major/minor/patch)
   - Update `Chart.yaml` version and appVersion
   - Generate/update `CHANGELOG.md`
   - Create git commit with changes
   - Create annotated git tag (e.g., `v0.2.0`)
   - Push commit and tag to origin
   - Create GitHub release with changelog

**Uplift outputs:**
- Updated `Chart.yaml` (committed)
- Updated/created `CHANGELOG.md` (committed)
- Git tag (pushed)
- GitHub release (created)

**Authentication:**
- Uses `GITHUB_TOKEN` with enhanced permissions
- Requires `contents: write` and `pull-requests: write`

### 5. Publish Workflows (Tag-Triggered)

**docker.yaml** (modified):
```yaml
on:
  push:
    tags:
      - 'v*'
```
- Triggered when Uplift creates tag
- Builds multi-arch image
- Pushes versioned tag: `ghcr.io/jacaudi/kiwix-downloader:v0.2.0`
- Pushes `latest` tag: `ghcr.io/jacaudi/kiwix-downloader:latest`

**chart.yaml** (modified):
```yaml
on:
  push:
    tags:
      - 'v*'
```
- Triggered when Uplift creates tag
- Updates Chart.yaml from tag
- Packages chart
- Pushes to GHCR OCI: `oci://ghcr.io/jacaudi/charts/kiwix:0.2.0`

**Why separate publish:**
- CI validates on main
- Release creates tag
- Tag triggers immutable versioned artifacts
- Clear separation between testing and publishing

## Uplift Configuration

**File:** `.uplift.yml`

```yaml
git:
  message: "chore: release version $VERSION"

bumps:
  - file: Chart.yaml
    regex:
      pattern: 'version: ([0-9]+\.[0-9]+\.[0-9]+)'
      count: 1
  - file: Chart.yaml
    regex:
      pattern: 'appVersion: "([0-9]+\.[0-9]+\.[0-9]+)"'
      count: 1

changelog:
  sort: asc

commits:
  types:
    feat: "Features"
    fix: "Bug Fixes"
    docs: "Documentation"
    chore: "Maintenance"
    refactor: "Refactoring"

github:
  releases:
    enabled: true
    changelog: true
```

**Configuration explained:**
- **git.message**: Commit message for version bump
- **bumps**: Files to update with new version
  - Chart.yaml version field
  - Chart.yaml appVersion field
- **changelog**: Sort commits ascending (oldest first)
- **commits.types**: Map conventional commit types to changelog sections
- **github.releases**: Create GitHub release with changelog

## Workflow Sequence

### 1. Development Flow

```
Developer → Commits with conventional commits → Push to main
  ↓
CI workflow triggers automatically
  ↓
test job runs (helm lint, template, validate)
  ↓ (if success)
build-docker and build-chart run in parallel
  ↓
Commit SHA image available for testing
Chart packaged as artifact
```

### 2. Release Flow (Manual Trigger)

```
Developer → GitHub Actions UI → Run workflow → Trigger "release" job
  ↓
Uplift analyzes commits since last tag
  ↓
Determines version bump from commit types:
  - feat: → minor bump (0.1.0 → 0.2.0)
  - fix: → patch bump (0.1.0 → 0.1.1)
  - BREAKING CHANGE: → major bump (0.1.0 → 1.0.0)
  ↓
Updates Chart.yaml version and appVersion
  ↓
Generates/updates CHANGELOG.md
  ↓
Commits changes to main
  ↓
Creates git tag (v0.2.0)
  ↓
Pushes tag to origin
  ↓
Creates GitHub release with changelog
  ↓
Tag triggers docker.yaml and chart.yaml
  ↓
Versioned artifacts published to GHCR
```

## Conventional Commit Examples

**Feature (minor bump):**
```
feat: add support for custom ZIM file checksums
```

**Bug fix (patch bump):**
```
fix: correct CronJob schedule parsing logic
```

**Breaking change (major bump):**
```
feat!: restructure values.yaml for better organization

BREAKING CHANGE: zimFiles moved to downloads.files
```

**Multiple types in one release:**
- 3 feat commits + 2 fix commits → minor bump (features take precedence)
- 1 BREAKING CHANGE commit → major bump (always takes precedence)

## File Changes

**New files:**
- `.github/workflows/ci.yaml` - Main CI/CD pipeline
- `.uplift.yml` - Uplift configuration
- `CHANGELOG.md` - Generated by Uplift (first run)

**Modified files:**
- `.github/workflows/docker.yaml` - Remove `main` branch trigger, keep only tags
- `.github/workflows/chart.yaml` - Remove `main` branch trigger, keep only tags

**Unchanged:**
- `.github/workflows/renovate.yaml` - Continues running daily independently

## Testing Strategy

**Before deployment:**
1. Create `.uplift.yml` with configuration
2. Test Uplift locally with dry-run mode
3. Verify Chart.yaml regex patterns match correctly
4. Validate conventional commit parsing

**After deployment:**
1. Trigger test job manually - verify all validations pass
2. Make test commit to main - verify build jobs run
3. Manually trigger release job - verify Uplift creates tag
4. Verify tag triggers docker and chart publish workflows
5. Check GitHub release created with proper changelog

## Rollback Plan

**If Uplift creates bad release:**
1. Delete git tag: `git push --delete origin v0.x.x`
2. Delete GitHub release via UI
3. Revert version commit on main
4. Fix issue, re-release

**If workflow fails:**
- All jobs are idempotent
- Re-run failed job from GitHub Actions UI
- Uplift won't create duplicate tags (checks existing tags first)

## Benefits

1. **Automated versioning**: No manual version bumps in Chart.yaml
2. **Consistent releases**: Conventional commits enforce standards
3. **Changelog maintenance**: Always up-to-date from commits
4. **Quality gates**: Can't release broken code
5. **Manual control**: Release only when ready
6. **Immutable artifacts**: Versioned images and charts never change
7. **GitLab parity**: Similar workflow structure to existing pipeline

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Uplift creates wrong version | Dry-run testing, review commits before release |
| Push fails due to permissions | Enhanced GITHUB_TOKEN permissions, verify in settings |
| Tag conflicts with existing | Uplift checks existing tags, won't overwrite |
| Changelog has breaking changes not caught | Manual review of commits before triggering release |
| Build succeeds but artifacts broken | Test stage validates, commit SHA images testable pre-release |

## Future Enhancements

**Optional improvements:**
- Add integration tests to test stage
- Slack/Discord notifications on release
- Automatic PR labeling with conventional commit type
- Release notes template customization
- Multi-chart support (if repository grows)
