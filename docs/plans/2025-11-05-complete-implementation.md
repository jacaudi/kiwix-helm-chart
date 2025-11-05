# Kiwix Chart Completion and Renovate Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete remaining Kiwix Helm chart tasks (chart workflow, README, validation) then add automated dependency management with Renovate and update all workflows to latest versions.

**Architecture:** Complete original chart implementation with GitHub Actions workflow for OCI publishing and comprehensive documentation. Then add self-hosted Renovate via GitHub Actions running daily, updating all workflows to latest action versions in the process.

**Tech Stack:** Helm, GitHub Actions, Renovate, OCI registry, bjw-s common library 4.4.0

**Note:** This plan continues from the original kiwix-implementation.md plan. Tasks 1-5 from that plan are already complete. This plan covers:
- Tasks 6-8 (original plan) renamed as Tasks 1-3 here
- Renovate integration (new work) as Tasks 4-8
- Final verification as Task 9

---

## Task 1: GitHub Actions - Helm Chart Workflow

**Files:**
- Create: `.github/workflows/chart.yaml`

### Step 1: Create Helm chart workflow with latest actions

Create `.github/workflows/chart.yaml`:

```yaml
name: Package and Push Helm Chart

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
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
          name: kiwix
          repository: jacaudi/charts
          tag: ${{ steps.version.outputs.version }}
          registry: ghcr.io
          registry_username: ${{ github.actor }}
          registry_password: ${{ secrets.GITHUB_TOKEN }}
```

### Step 2: Verify workflow syntax

Run: `cat .github/workflows/chart.yaml | grep -q "name: Package and Push Helm Chart" && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/chart.yaml
git commit -m "feat: add GitHub Actions workflow for Helm chart

Packages chart and pushes to GHCR as OCI artifact
- Triggers on git tags (v*)
- Uses appany/helm-oci-chart-releaser@v0.5.0
- Updates Chart.yaml versions from tag
- Latest actions: checkout@v5, setup-helm@v4
"
```

---

## Task 2: Documentation - README

**Files:**
- Create: `README.md`

### Step 1: Create comprehensive README

Create `README.md`:

```markdown
# Kiwix Helm Chart

Helm chart for deploying [kiwix-serve](https://github.com/kiwix/kiwix-tools) with automated ZIM file downloads.

## Features

- 🚀 Automated ZIM file downloads with retry logic and checksum verification
- 🔄 One-time or periodic download modes (Job or CronJob)
- 📦 OCI-based Helm chart distribution via GHCR
- 🛡️ Built on [bjw-s common library](https://github.com/bjw-s-labs/helm-charts)
- 💾 Persistent storage with configurable size and storage class
- 🎯 Keep-all file management strategy for archival use cases
- 🔄 Automated dependency updates with Renovate

## Prerequisites

- Kubernetes 1.19+
- Helm 3.8+
- Persistent Volume provisioner (for PVC support)

## Installation

### Install from OCI Registry

```bash
# Login to GHCR (if repository is private)
helm registry login ghcr.io -u <username>

# Install chart
helm install my-kiwix oci://ghcr.io/jacaudi/charts/kiwix \
  --version v0.1.0 \
  --namespace kiwix \
  --create-namespace \
  --values values.yaml
```

### Install from Source

```bash
# Clone repository
git clone https://github.com/jacaudi/kiwix-helm-chart.git
cd kiwix-helm-chart

# Update dependencies
helm dependency update

# Install
helm install my-kiwix . \
  --namespace kiwix \
  --create-namespace \
  --values values.yaml
```

## Configuration

### Basic Example

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-09.zim

persistence:
  data:
    size: 50Gi
```

### Periodic Updates (CronJob)

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim

downloader:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2am

persistence:
  data:
    size: 200Gi
    storageClass: ceph-block
```

### With Checksum Verification

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: abc123def456...
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `zimFiles` | List of ZIM file URLs to download | `[]` |
| `zimFiles[].url` | URL of ZIM file | Required |
| `zimFiles[].sha256` | SHA256 checksum (optional) | `null` |
| `downloader.enabled` | Enable downloader controller | `true` |
| `downloader.schedule` | CronJob schedule (empty = Job) | `""` |
| `downloader.image.repository` | Downloader image repository | `ghcr.io/jacaudi/kiwix-downloader` |
| `downloader.image.tag` | Downloader image tag | `latest` |
| `persistence.data.size` | PVC size | `100Gi` |
| `persistence.data.storageClass` | Storage class name | `""` (cluster default) |
| `service.main.ports.http.port` | HTTP service port | `8080` |
| `ingress.main.enabled` | Enable ingress | `false` |

See `values.yaml` for complete configuration options.

## Architecture

The chart uses a standalone downloader pattern with two controllers:

1. **Downloader Controller**: Job (one-time) or CronJob (periodic) that downloads ZIM files to shared storage
2. **Main Controller**: Deployment running kiwix-serve that serves the downloaded files

Both controllers share a PVC mounted at `/data`. The downloader reads URLs from a ConfigMap generated from `zimFiles`.

```
User provides zimFiles list
        ↓
    ConfigMap (zim-urls.json)
        ↓
    Downloader (Job/CronJob)
        ↓
    PVC (/data)
        ↓
    Kiwix-serve (Deployment)
```

## Storage Considerations

ZIM files can be large (100MB - 100GB). The chart uses a **keep-all** strategy, accumulating files over time.

**Recommended PVC sizes:**
- Small demo (1-2 files): 10-50 Gi
- Medium archive (5-10 files): 100-200 Gi
- Large archive (20+ files): 500+ Gi

Monitor PVC usage over time, especially when using periodic updates.

## Automated Dependency Updates

This project uses [Renovate](https://github.com/renovatebot/renovate) to automatically keep dependencies up-to-date:

- **GitHub Actions**: Auto-updated to latest versions
- **Docker base images**: Tracks Alpine Linux releases
- **Helm dependencies**: Monitors bjw-s common library updates
- **Container images**: Tracks kiwix-serve and downloader versions

**Schedule:** Daily at 2am UTC

**Auto-merge policy:** Patch updates (1.0.x) automatically merge after 3 days if CI passes.

**Dependency Dashboard:** Check the [Dependency Dashboard](../../issues) issue for pending updates.

### Manual Renovate Run

Trigger Renovate manually via GitHub Actions:
```bash
gh workflow run renovate.yaml
```

Or via GitHub UI: Actions → Renovate → Run workflow

## Troubleshooting

### Check Downloader Logs

```bash
# For Job
kubectl logs -n kiwix job/my-kiwix-downloader

# For CronJob (get latest job)
kubectl logs -n kiwix $(kubectl get jobs -n kiwix -l app.kubernetes.io/name=kiwix -o name | tail -1)
```

### Verify Downloaded Files

```bash
kubectl exec -n kiwix deployment/my-kiwix -- ls -lh /data
```

### Test Kiwix Service

```bash
# Port-forward
kubectl port-forward -n kiwix svc/my-kiwix 8080:8080

# Access in browser
open http://localhost:8080
```

### Common Issues

**Download timeout**: Increase Job timeout or check network connectivity
```yaml
downloader:
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
```

**PVC full**: Increase size or manually delete old files
```bash
kubectl exec -n kiwix deployment/my-kiwix -- rm /data/old-file.zim
```

## Development

### Building Downloader Image

```bash
cd docker
docker build -t ghcr.io/jacaudi/kiwix-downloader:test .
docker push ghcr.io/jacaudi/kiwix-downloader:test
```

### Testing Chart Locally

```bash
# Lint
helm lint .

# Template
helm template test . --values values.yaml

# Dry-run install
helm install test . --dry-run --debug
```

## License

See repository license.

## Contributing

Contributions welcome! Please open an issue or pull request.
```

### Step 2: Verify README formatting

Run: `grep -q "# Kiwix Helm Chart" README.md && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add README.md
git commit -m "docs: add comprehensive README

Installation instructions, configuration examples, architecture
overview, troubleshooting guide, and development setup.
Includes Renovate documentation section.
"
```

---

## Task 3: Final Chart Validation

**Files:**
- Verify all files created correctly

### Step 1: Update Helm dependencies

Run: `helm dependency update`
Expected: Downloads bjw-s common library chart to `charts/`

### Step 2: Lint chart

Run: `helm lint .`
Expected: No errors, possibly some warnings about default values

### Step 3: Template chart

Run: `helm template test . > /tmp/kiwix-rendered.yaml`
Expected: Successfully renders all templates

### Step 4: Verify rendered resources

Run: `cat /tmp/kiwix-rendered.yaml | grep -E "kind: (ConfigMap|Deployment|Job|Service|PersistentVolumeClaim)" | wc -l`
Expected: At least 5 resources (ConfigMap, Deployment, Job, Service, PVC)

### Step 5: Test with custom values

Create `/tmp/test-values.yaml`:
```yaml
zimFiles:
  - url: https://example.com/test.zim
    sha256: abc123

downloader:
  schedule: "0 3 * * *"

persistence:
  data:
    size: 50Gi
    storageClass: local-path
```

Run: `helm template test . -f /tmp/test-values.yaml > /tmp/kiwix-custom.yaml`
Expected: Successfully renders with custom values

### Step 6: Verify CronJob creation

Run: `grep -q "kind: CronJob" /tmp/kiwix-custom.yaml && echo "CronJob created"`
Expected: CronJob created (because schedule is set)

### Step 7: Commit validation success

```bash
git add -A
git commit -m "chore: validate chart implementation

All validation checks pass:
- Helm dependencies resolved
- Linting successful
- Template rendering works
- Both Job and CronJob modes tested
" --allow-empty
```

---

## Task 4: Create Renovate Configuration

**Files:**
- Create: `renovate.json`

### Step 1: Create renovate.json with comprehensive configuration

Create `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "schedule": ["at 2am"],
  "timezone": "UTC",
  "dependencyDashboard": true,
  "labels": ["dependencies", "renovate"],
  "assignees": ["jacaudi"],
  "packageRules": [
    {
      "description": "Group all GitHub Actions updates",
      "matchManagers": ["github-actions"],
      "groupName": "GitHub Actions",
      "automerge": false
    },
    {
      "description": "Auto-merge patch updates after stability period",
      "matchUpdateTypes": ["patch"],
      "automerge": true,
      "automergeType": "pr",
      "minimumReleaseAge": "3 days"
    },
    {
      "description": "Group Docker base images",
      "matchDatasources": ["docker"],
      "matchPackageNames": ["alpine"],
      "groupName": "Docker base images",
      "automerge": false
    },
    {
      "description": "Group Helm dependencies",
      "matchManagers": ["helmv3"],
      "matchPackageNames": ["common"],
      "groupName": "Helm dependencies",
      "automerge": false
    },
    {
      "description": "Track container images in values.yaml",
      "matchManagers": ["helm-values"],
      "matchPackageNames": ["ghcr.io/kiwix/kiwix-serve", "ghcr.io/jacaudi/kiwix-downloader"],
      "groupName": "Container images",
      "automerge": false
    }
  ]
}
```

### Step 2: Validate JSON syntax

Run: `cat renovate.json | jq .`
Expected: Pretty-printed JSON with no errors

### Step 3: Commit

```bash
git add renovate.json
git commit -m "feat: add Renovate configuration

- Daily schedule at 2am UTC
- Auto-merge patch updates after 3 days
- Group updates by type (Actions, Docker, Helm)
- Dependency dashboard enabled
"
```

---

## Task 5: Create Renovate GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/renovate.yaml`

### Step 1: Create Renovate workflow

Create `.github/workflows/renovate.yaml`:

```yaml
name: Renovate

on:
  schedule:
    # Run daily at 2am UTC
    - cron: '0 2 * * *'
  workflow_dispatch:
    # Allow manual trigger

permissions:
  contents: write
  pull-requests: write
  issues: write

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
        env:
          LOG_LEVEL: debug
```

### Step 2: Verify workflow syntax

Run: `cat .github/workflows/renovate.yaml | grep -q "name: Renovate" && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/renovate.yaml
git commit -m "feat: add Renovate GitHub Actions workflow

- Runs daily at 2am UTC
- Manual trigger via workflow_dispatch
- Uses RENOVATE_TOKEN secret
- Debug logging enabled
"
```

---

## Task 6: Update Docker Workflow to Latest Actions

**Files:**
- Modify: `.github/workflows/docker.yaml`

### Step 1: Update actions/checkout to v5

Find and replace in `.github/workflows/docker.yaml`:

**Find:**
```yaml
      - name: Checkout
        uses: actions/checkout@v4
```

**Replace with:**
```yaml
      - name: Checkout
        uses: actions/checkout@v5
```

### Step 2: Update docker/build-push-action to v6

Find and replace in `.github/workflows/docker.yaml`:

**Find:**
```yaml
      - name: Build and push
        uses: docker/build-push-action@v5
```

**Replace with:**
```yaml
      - name: Build and push
        uses: docker/build-push-action@v6
```

### Step 3: Verify changes

Run: `grep "checkout@v5" .github/workflows/docker.yaml && grep "build-push-action@v6" .github/workflows/docker.yaml && echo "OK"`
Expected: OK (both patterns found)

### Step 4: Commit

```bash
git add .github/workflows/docker.yaml
git commit -m "chore: update Docker workflow to latest actions

- actions/checkout@v4 → @v5
- docker/build-push-action@v5 → @v6
"
```

---

## Task 7: Create Renovate Documentation

**Files:**
- Create: `docs/RENOVATE.md`

### Step 1: Create RENOVATE_TOKEN secret documentation

Create `docs/RENOVATE.md`:

```markdown
# Renovate Setup

## Required Secret: RENOVATE_TOKEN

Renovate requires a GitHub Personal Access Token to create pull requests and trigger workflows.

### Creating the Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Name: `Renovate Token`
4. Expiration: Set to your preference (90 days, 1 year, or no expiration)
5. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
6. Click "Generate token"
7. Copy the token (you won't see it again!)

### Adding to Repository

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `RENOVATE_TOKEN`
4. Value: Paste the token from above
5. Click "Add secret"

### Verification

After adding the secret, trigger Renovate manually:

```bash
gh workflow run renovate.yaml
```

Check the Actions tab for the workflow run. If successful, Renovate will:
- Create a "Dependency Dashboard" issue
- Scan for updates
- Create PRs for any outdated dependencies

## Troubleshooting

**Workflow fails with "Bad credentials"**
- Check that RENOVATE_TOKEN secret is set correctly
- Verify token has `repo` and `workflow` scopes
- Token may have expired - generate a new one

**No PRs created**
- Dependencies may already be up-to-date
- Check Dependency Dashboard issue for status
- Review Renovate logs in workflow run

**Auto-merge not working**
- Check CI passes on Renovate PRs
- Verify 3-day minimum release age has passed
- Confirm package rule allows auto-merge

## Configuration

See `renovate.json` for configuration details:
- **Schedule**: Daily at 2am UTC
- **Auto-merge**: Patch updates only, after 3 days
- **Grouping**: By dependency type (Actions, Docker, Helm)
- **Dashboard**: Enabled (creates issue with update status)

## Manual Operations

**Trigger Renovate immediately:**
```bash
gh workflow run renovate.yaml
```

**Disable auto-merge for specific update:**
Add to `renovate.json`:
```json
{
  "packageRules": [
    {
      "matchPackageNames": ["package-name"],
      "automerge": false
    }
  ]
}
```

**Change schedule:**
Edit `schedule` in `renovate.json`:
```json
{
  "schedule": ["before 5am on Monday"]
}
```
```

### Step 2: Commit

```bash
git add docs/RENOVATE.md
git commit -m "docs: add Renovate setup documentation

- Token creation instructions
- Repository secret setup
- Troubleshooting guide
- Configuration examples
"
```

---

## Task 8: Verification and Testing

**Files:**
- No file changes, verification only

### Step 1: Validate renovate.json schema

Run: `cat renovate.json | jq . > /dev/null && echo "JSON valid"`
Expected: JSON valid

### Step 2: Check workflow syntax

Run: `yamllint .github/workflows/renovate.yaml .github/workflows/docker.yaml .github/workflows/chart.yaml || echo "Note: yamllint not installed, skipping"`
Expected: No errors (or note about yamllint)

### Step 3: Verify all action versions updated

Run: `grep -h "uses:" .github/workflows/*.yaml | sort | uniq`
Expected output should show latest versions:
```
      - uses: actions/checkout@v5
      - uses: appany/helm-oci-chart-releaser@v0.5.0
      - uses: azure/setup-helm@v4
      - uses: docker/build-push-action@v6
      - uses: docker/login-action@v3
      - uses: docker/metadata-action@v5
      - uses: docker/setup-buildx-action@v3
      - uses: renovatebot/github-action@v40
```

### Step 4: Test renovate.json parsing

Run: `jq '.extends, .schedule, .packageRules | length' renovate.json`
Expected: Numeric output showing config is parseable

### Step 5: Create summary commit

```bash
git add -A
git commit -m "chore: complete Renovate integration

All components implemented:
- renovate.json configuration
- renovate.yaml workflow
- Updated docker.yaml to latest actions
- chart.yaml with OCI action and latest versions
- Documentation for setup and usage

Next step: Add RENOVATE_TOKEN secret in GitHub UI
" --allow-empty
```

---

## Post-Implementation Checklist

After all tasks complete, manual steps required:

- [ ] **Add RENOVATE_TOKEN secret** in GitHub repository settings
  - Follow instructions in `docs/RENOVATE.md`
  - Generate Personal Access Token with `repo` and `workflow` scopes
  - Add as repository secret named `RENOVATE_TOKEN`

- [ ] **Test Renovate workflow**
  - Trigger manually: `gh workflow run renovate.yaml`
  - Check workflow succeeds in Actions tab
  - Verify Dependency Dashboard issue is created

- [ ] **Review first Renovate PRs**
  - Check grouping works correctly
  - Verify CI runs on PRs
  - Confirm labels are applied

- [ ] **Monitor auto-merge**
  - Wait for patch updates
  - After 3 days, verify auto-merge triggers
  - Check PR was merged automatically if CI passed

- [ ] **Adjust configuration if needed**
  - Fine-tune schedules
  - Adjust grouping rules
  - Modify auto-merge policies

## Success Criteria

Implementation is complete when:

1. ✅ chart.yaml workflow exists with latest actions and OCI releaser
2. ✅ README.md exists with comprehensive documentation
3. ✅ All chart validation checks pass
4. ✅ renovate.json exists with comprehensive package rules
5. ✅ renovate.yaml workflow exists and is syntactically valid
6. ✅ docker.yaml uses checkout@v5 and build-push-action@v6
7. ✅ docs/RENOVATE.md explains setup and usage
8. ✅ All changes committed to feature branch
9. ⏳ RENOVATE_TOKEN secret added (manual step)
10. ⏳ Renovate runs successfully (post-merge)

## Notes

- This plan completes Tasks 6-8 from the original kiwix-implementation.md plan (now Tasks 1-3)
- Adds Renovate integration for automated dependency management (Tasks 4-8)
- All workflows updated to latest action versions
- After completion, merge feature branch to main
- RENOVATE_TOKEN must be added before Renovate can run
- First Renovate run will create Dependency Dashboard issue
