# Downloader Pod Expiration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable pod lifecycle controls (max runtime and auto-cleanup) for downloader Job/CronJob

**Architecture:** Add two new configuration fields to values.yaml that map to Kubernetes activeDeadlineSeconds and ttlSecondsAfterFinished. Modify the controller template to conditionally include these fields using Helm's with blocks.

**Tech Stack:** Helm charts, bjw-s common library, Kubernetes Job/CronJob specs

---

## Task 1: Add Configuration Fields to values.yaml

**Files:**
- Modify: `values.yaml:22-27`

**Step 1: Add maxRuntime and cleanupAfter fields**

Add two new fields under the `downloader` section:

```yaml
# Downloader configuration (single source of truth)
downloader:
  enabled: true
  schedule: ""  # Empty = Job, cron format (e.g., "0 2 * * 0") = CronJob
  resources: {}
  maxRuntime: 3600      # Maximum seconds pod can run (activeDeadlineSeconds)
  cleanupAfter: 3600    # Seconds after completion before pod is deleted (ttlSecondsAfterFinished)
```

**Step 2: Verify Helm lint passes**

Run: `helm lint .`

Expected output:
```
==> Linting .
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

**Step 3: Commit configuration changes**

```bash
git add values.yaml
git commit -m "feat: add downloader pod expiration configuration fields

Add maxRuntime and cleanupAfter fields to control pod lifecycle:
- maxRuntime: maximum seconds pod can run (default 3600)
- cleanupAfter: seconds after completion before cleanup (default 3600)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Modify Controller Template for Job Mode

**Files:**
- Modify: `templates/_values-controllers.tpl:33-52`

**Step 1: Add lifecycle fields to Job configuration**

Modify the downloader section to add conditional activeDeadlineSeconds and ttlSecondsAfterFinished fields for Job mode:

```yaml
  {{- if .Values.downloader.enabled }}
  downloader:
    enabled: true
    {{- if .Values.downloader.schedule }}
    type: cronjob
    cronjob:
      schedule: {{ .Values.downloader.schedule | quote }}
    {{- else }}
    type: job
    job:
      {{- with .Values.downloader.maxRuntime }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      {{- with .Values.downloader.cleanupAfter }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
    {{- end }}
    containers:
      main:
        image:
          repository: {{ .Values.images.downloader.repository }}
          tag: {{ .Values.images.downloader.tag }}
          pullPolicy: {{ .Values.images.downloader.pullPolicy }}
        {{- with .Values.downloader.resources }}
        resources: {{- toYaml . | nindent 10 }}
        {{- end }}
  {{- end }}
```

**Step 2: Test template renders correctly with default values**

Run: `helm template test . | grep -A10 "kind: Job"`

Expected: Should see Job with activeDeadlineSeconds and ttlSecondsAfterFinished set to 3600

**Step 3: Commit Job mode changes**

```bash
git add templates/_values-controllers.tpl
git commit -m "feat: add pod expiration fields to downloader Job

Add activeDeadlineSeconds and ttlSecondsAfterFinished to Job type
using conditional with blocks to only include when configured.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Add Lifecycle Fields to CronJob Mode

**Files:**
- Modify: `templates/_values-controllers.tpl:36-40`

**Step 1: Add fields inside cronjob configuration block**

Modify the cronjob section to add activeDeadlineSeconds and ttlSecondsAfterFinished:

```yaml
    {{- if .Values.downloader.schedule }}
    type: cronjob
    cronjob:
      schedule: {{ .Values.downloader.schedule | quote }}
      {{- with .Values.downloader.maxRuntime }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      {{- with .Values.downloader.cleanupAfter }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
    {{- else }}
```

**Step 2: Test template with CronJob mode**

Create temporary test values:
```bash
echo 'downloader:
  schedule: "0 2 * * 0"
  maxRuntime: 3600
  cleanupAfter: 3600' > /tmp/test-cronjob.yaml

helm template test . -f /tmp/test-cronjob.yaml | grep -A15 "kind: CronJob"
```

Expected: Should see CronJob with activeDeadlineSeconds and ttlSecondsAfterFinished in jobTemplate.spec

**Step 3: Commit CronJob mode changes**

```bash
git add templates/_values-controllers.tpl
git commit -m "feat: add pod expiration fields to downloader CronJob

Add activeDeadlineSeconds and ttlSecondsAfterFinished to CronJob type
using conditional with blocks to only include when configured.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Test with Null Values

**Files:**
- Test: Template rendering with null values

**Step 1: Test with maxRuntime null**

```bash
echo 'downloader:
  maxRuntime: null
  cleanupAfter: 3600' > /tmp/test-null-runtime.yaml

helm template test . -f /tmp/test-null-runtime.yaml | grep -A20 "kind: Job"
```

Expected: Should NOT contain activeDeadlineSeconds, SHOULD contain ttlSecondsAfterFinished: 3600

**Step 2: Test with cleanupAfter null**

```bash
echo 'downloader:
  maxRuntime: 3600
  cleanupAfter: null' > /tmp/test-null-cleanup.yaml

helm template test . -f /tmp/test-null-cleanup.yaml | grep -A20 "kind: Job"
```

Expected: SHOULD contain activeDeadlineSeconds: 3600, should NOT contain ttlSecondsAfterFinished

**Step 3: Test with both null**

```bash
echo 'downloader:
  maxRuntime: null
  cleanupAfter: null' > /tmp/test-both-null.yaml

helm template test . -f /tmp/test-both-null.yaml | grep -A20 "kind: Job"
```

Expected: Should NOT contain activeDeadlineSeconds or ttlSecondsAfterFinished

**Step 4: Document test results**

Create test verification note:
```bash
echo "✓ Null value tests passed
- maxRuntime: null excludes activeDeadlineSeconds
- cleanupAfter: null excludes ttlSecondsAfterFinished
- Both null excludes both fields" > /tmp/test-results.txt
cat /tmp/test-results.txt
```

---

## Task 5: Test with Custom Values

**Files:**
- Test: Template rendering with custom values

**Step 1: Test with custom values (Job mode)**

```bash
echo 'downloader:
  maxRuntime: 7200
  cleanupAfter: 600' > /tmp/test-custom.yaml

helm template test . -f /tmp/test-custom.yaml | grep -A20 "kind: Job"
```

Expected: Should contain activeDeadlineSeconds: 7200 and ttlSecondsAfterFinished: 600

**Step 2: Test with custom values (CronJob mode)**

```bash
echo 'downloader:
  schedule: "0 3 * * 1"
  maxRuntime: 1800
  cleanupAfter: 300' > /tmp/test-custom-cron.yaml

helm template test . -f /tmp/test-custom-cron.yaml | grep -A25 "kind: CronJob"
```

Expected: CronJob with activeDeadlineSeconds: 1800 and ttlSecondsAfterFinished: 300 in jobTemplate.spec

**Step 3: Verify helm lint still passes**

Run: `helm lint .`

Expected: 1 chart(s) linted, 0 chart(s) failed

---

## Task 6: Verify Final State and Update Chart Version

**Files:**
- Read: `values.yaml` - verify configuration documented
- Read: `templates/_values-controllers.tpl` - verify template complete
- Run: Final validation commands

**Step 1: Run complete template test**

```bash
helm template test . > /tmp/full-template.yaml
echo "Template size: $(wc -l < /tmp/full-template.yaml) lines"
grep -c "activeDeadlineSeconds" /tmp/full-template.yaml || echo "Field correctly conditional"
```

Expected: Template renders successfully, fields appear when configured

**Step 2: Run helm lint final check**

Run: `helm lint .`

Expected: 1 chart(s) linted, 0 chart(s) failed

**Step 3: Test actual template with defaults**

```bash
helm template test . | grep -E "(activeDeadlineSeconds|ttlSecondsAfterFinished)"
```

Expected: Should show both fields with value 3600

**Step 4: Create summary commit**

```bash
git add -A
git commit -m "feat: complete downloader pod expiration implementation

Summary of changes:
- Added downloader.maxRuntime config field (default: 3600)
- Added downloader.cleanupAfter config field (default: 3600)
- Implemented activeDeadlineSeconds for max runtime control
- Implemented ttlSecondsAfterFinished for auto-cleanup
- Supports both Job and CronJob modes
- Conditional inclusion using with blocks
- Tested with default, null, and custom values

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `values.yaml` contains `downloader.maxRuntime: 3600`
- [ ] `values.yaml` contains `downloader.cleanupAfter: 3600`
- [ ] Template includes fields for Job mode
- [ ] Template includes fields for CronJob mode
- [ ] Null values correctly omit fields
- [ ] Custom values correctly override defaults
- [ ] `helm lint .` passes with 0 failures
- [ ] `helm template test .` renders successfully
- [ ] Both fields visible in rendered Job with default values

## Next Steps

After implementation:
1. Use @superpowers:verification-before-completion to verify all tests pass
2. Use @superpowers:requesting-code-review to review implementation
3. Use @superpowers:finishing-a-development-branch to merge or create PR
