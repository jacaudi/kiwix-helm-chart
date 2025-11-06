# Renovate Integration and GitHub Actions Updates Design

**Date:** 2025-11-05
**Status:** Approved

## Overview

Add automated dependency management using self-hosted Renovate via GitHub Actions. Update existing workflows to use latest action versions and modern best practices.

## Goals

- **Automated updates**: Keep GitHub Actions, Docker images, and Helm dependencies current
- **Aggressive schedule**: Daily dependency checks
- **Smart auto-merge**: Patch updates auto-merge after stability period
- **Reduced noise**: Group related updates into single PRs
- **Full control**: Self-hosted workflow for complete customization

## Architecture

### Three-Component Solution

1. **renovate.json** - Configuration defining update rules and policies
2. **renovate.yaml** - GitHub Actions workflow running Renovate daily
3. **Updated workflows** - Existing docker.yaml and chart.yaml updated to latest versions

```
Daily at 2am UTC
       ↓
Renovate workflow runs
       ↓
Checks for updates (GitHub Actions, Docker, Helm)
       ↓
Creates PRs with grouping
       ↓
CI runs tests
       ↓
Patch updates auto-merge after 3 days
Major/minor require manual review
```

## Components

### 1. Renovate Configuration (renovate.json)

**File location:** `/renovate.json` (repository root)

**Base configuration:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "schedule": ["at 2am"],
  "dependencyDashboard": true,
  "labels": ["dependencies", "renovate"],
  "assignees": ["@jacaudi"]
}
```

**Package rules:**

**1. GitHub Actions grouping:**
```json
{
  "matchManagers": ["github-actions"],
  "groupName": "GitHub Actions",
  "automerge": false
}
```
Groups all action updates (checkout, build-push-action, etc.) into single PR for easier review.

**2. Patch auto-merge:**
```json
{
  "matchUpdateTypes": ["patch"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days"
}
```
Automatically merges patch updates (1.0.x) after:
- All CI checks pass
- 3-day stability period (ensures version is stable)
- Creates PR first (not direct merge)

**3. Docker base images:**
```json
{
  "matchDatasources": ["docker"],
  "matchPackageNames": ["alpine"],
  "groupName": "Docker base images"
}
```
Tracks Alpine Linux version in `docker/Dockerfile`.

**4. Helm dependencies:**
```json
{
  "matchManagers": ["helmv3"],
  "matchPackageNames": ["common"],
  "groupName": "Helm dependencies"
}
```
Monitors bjw-s common library in `Chart.yaml`.

**5. Docker images in values.yaml:**
```json
{
  "matchManagers": ["helm-values"],
  "matchPackageNames": ["ghcr.io/kiwix/kiwix-serve"],
  "groupName": "Container images"
}
```
Tracks kiwix-serve image version in `values.yaml`.

### 2. Renovate GitHub Actions Workflow

**File location:** `.github/workflows/renovate.yaml`

**Workflow structure:**
```yaml
name: Renovate

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2am UTC
  workflow_dispatch:      # Manual trigger

permissions:
  contents: write         # Create branches/commits
  pull-requests: write    # Create PRs
  issues: write          # Update dependency dashboard

jobs:
  renovate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Run Renovate
        uses: renovatebot/github-action@v40
        with:
          configurationFile: renovate.json
          token: ${{ secrets.RENOVATE_TOKEN }}
```

**Required secret:** `RENOVATE_TOKEN`
- GitHub Personal Access Token (classic)
- Scopes: `repo`, `workflow`
- Allows Renovate to create PRs and trigger workflows

**Manual trigger:** Workflow can be run on-demand via GitHub UI for immediate updates.

### 3. Updated Existing Workflows

#### docker.yaml Updates

**Current → Updated:**
- `actions/checkout@v4` → `@v5`
- `docker/build-push-action@v5` → `@v6`

**Changes:**
```yaml
# Before
- uses: actions/checkout@v4
- uses: docker/build-push-action@v5

# After
- uses: actions/checkout@v5
- uses: docker/build-push-action@v6
```

**Benefits:**
- checkout@v5: Node.js 20 runtime, better performance
- build-push-action@v6: Improved caching, better multi-platform support

#### chart.yaml Refactor

**Current approach:** Manual helm commands
```yaml
- run: helm dependency update
- run: helm lint .
- run: helm package .
- run: helm registry login ...
- run: helm push ...
```

**New approach:** Use dedicated action
```yaml
- name: Update dependencies
  run: helm dependency update

- name: Lint chart
  run: helm lint .

- name: Test template
  run: helm template test .

- name: Release to OCI registry
  uses: appany/helm-oci-chart-releaser@v0.5.0
  with:
    name: kiwix
    repository: jacaudi/charts
    tag: ${{ github.ref_name }}
    registry: ghcr.io
    registry_username: ${{ github.actor }}
    registry_password: ${{ secrets.GITHUB_TOKEN }}
```

**Benefits:**
- Simplified workflow (15 lines vs 30 lines)
- Built-in retry logic and error handling
- Automatic version extraction from git tags
- Renovate will update action version
- Standard approach (follows Docker workflow pattern)

**Action features:**
- Handles registry login automatically
- Creates chart package
- Pushes to OCI registry
- Supports custom registry URLs
- Retries on transient failures

## Update Workflow

### Typical Update Cycle

**1. Renovate runs daily at 2am:**
- Scans for GitHub Actions updates
- Checks Docker Hub for Alpine releases
- Monitors Helm registry for common library updates
- Checks GHCR for kiwix-serve updates

**2. Creates grouped PRs:**
- "Update GitHub Actions" - All action updates together
- "Update Docker base images" - Alpine version
- "Update Helm dependencies" - bjw-s common library
- "Update container images" - kiwix-serve

**3. CI runs automatically:**
- Helm lint and template tests
- Docker build verification
- Any custom tests

**4. Auto-merge or manual review:**
- **Patch updates** (1.0.x): Auto-merge after 3 days if CI passes
- **Minor updates** (1.x.0): Manual review required
- **Major updates** (x.0.0): Manual review required

### Dependency Dashboard

Renovate creates an issue titled "Dependency Dashboard" showing:
- Pending updates awaiting approval
- Rate-limited updates
- Errored updates
- Auto-merge queue status

## Security Considerations

**Token permissions:**
- RENOVATE_TOKEN requires `repo` and `workflow` scopes
- Minimum necessary permissions
- Stored as GitHub secret (encrypted)

**Auto-merge safety:**
- Only patch updates auto-merge
- 3-day minimum release age prevents zero-day issues
- All CI checks must pass
- Can be disabled per package if needed

**Supply chain security:**
- Action versions pinned (Renovate updates them)
- Docker digests can be enabled (optional)
- Helm chart checksums verified
- GitHub's dependency graph integration

## Configuration Examples

### Disable auto-merge for specific package:
```json
{
  "packageRules": [
    {
      "matchPackageNames": ["alpine"],
      "automerge": false
    }
  ]
}
```

### Change schedule to weekly:
```json
{
  "schedule": ["before 5am on Monday"]
}
```

### Enable Docker digest pinning:
```json
{
  "extends": ["docker:pinDigests"]
}
```

### Group all dependencies:
```json
{
  "packageRules": [
    {
      "matchPackagePatterns": ["*"],
      "groupName": "all dependencies"
    }
  ]
}
```

## Testing Strategy

**Before deployment:**
1. Validate renovate.json schema
2. Test workflow with `workflow_dispatch`
3. Verify RENOVATE_TOKEN has correct scopes
4. Check dependency dashboard creation

**After deployment:**
1. Monitor first Renovate run
2. Verify PRs are created correctly
3. Confirm CI runs on Renovate PRs
4. Test auto-merge after 3-day period

## Rollout Plan

**Phase 1: Setup**
1. Create RENOVATE_TOKEN secret
2. Add renovate.json to repository
3. Add renovate.yaml workflow
4. Commit changes

**Phase 2: Workflow Updates**
1. Update docker.yaml to latest actions
2. Refactor chart.yaml to use helm-oci-chart-releaser
3. Test both workflows manually

**Phase 3: Validation**
1. Trigger Renovate manually via workflow_dispatch
2. Verify PRs are created
3. Check grouping works correctly
4. Confirm CI passes

**Phase 4: Monitor**
1. Watch first auto-merge cycle
2. Review dependency dashboard
3. Adjust configuration as needed

## Maintenance

**Ongoing:**
- Review dependency dashboard weekly
- Approve major/minor updates promptly
- Monitor auto-merge success rate
- Adjust schedules if too noisy

**Renovate itself:**
- Renovate will auto-update its own action version
- GitHub will notify of action deprecations
- Schema updates happen automatically

## Future Enhancements

**Optional improvements:**
- Enable Docker digest pinning for reproducibility
- Add vulnerability scanning integration
- Configure semantic commit messages
- Set up Slack/Discord notifications for updates
- Add custom update rules per environment

## Benefits

1. **Always current**: Dependencies stay up-to-date automatically
2. **Security**: Quick security patch application
3. **Reduced toil**: No manual dependency tracking
4. **Consistency**: Standard process across all dependency types
5. **Visibility**: Dependency dashboard shows status at a glance
6. **Safety**: Auto-merge with testing reduces risk
7. **Flexibility**: Self-hosted = full customization

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking changes in patches | 3-day stability period, CI testing |
| Too many PRs | Grouping strategy reduces noise |
| Auto-merge failures | Renovate stops auto-merge if CI fails |
| Token exposure | GitHub secrets encryption, minimum scopes |
| Workflow changes break CI | Renovate doesn't modify CI, only versions |

## Documentation

**README additions needed:**
- Mention Renovate in features section
- Link to dependency dashboard
- Explain auto-merge policy

**Contributing guide:**
- How to disable auto-merge for specific update
- How to trigger Renovate manually
- How to read dependency dashboard
