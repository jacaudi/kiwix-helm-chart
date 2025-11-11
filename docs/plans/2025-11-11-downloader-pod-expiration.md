# Downloader Pod Expiration Configuration

**Date:** 2025-11-11
**Status:** Approved
**Feature:** Configurable pod lifecycle management for downloader Job/CronJob

## Overview

Add user-configurable pod expiration controls for the downloader Job/CronJob to:
1. Prevent stuck downloads from running indefinitely (max runtime limit)
2. Automatically clean up completed pods after a specified time (auto-cleanup)

Both behaviors default to 1 hour and are independently configurable.

## Requirements

- Separate configuration for max runtime and cleanup time
- Default: 3600 seconds (1 hour) for both settings
- Support both Job mode (schedule: "") and CronJob mode (schedule: "cron expression")
- Allow disabling either behavior by setting to null/empty
- Maintain backward compatibility with existing deployments

## Configuration Interface

Add two new fields to `values.yaml` under the existing `downloader` section:

```yaml
downloader:
  enabled: true
  schedule: ""
  resources: {}
  maxRuntime: 3600      # Maximum seconds pod can run (activeDeadlineSeconds)
  cleanupAfter: 3600    # Seconds after completion before pod is deleted (ttlSecondsAfterFinished)
```

### Field Descriptions

**maxRuntime** (default: 3600)
- Maps to Kubernetes `activeDeadlineSeconds`
- Terminates pod if still running after this duration
- Prevents stuck downloads from consuming cluster resources indefinitely
- Set to `null` to disable (no runtime limit)

**cleanupAfter** (default: 3600)
- Maps to Kubernetes `ttlSecondsAfterFinished`
- Deletes pod this many seconds after completion (success or failure)
- Keeps cluster clean while allowing time to check logs
- Set to `null` to disable (pods remain until manually deleted)

## Implementation

### Template Changes

Modify `templates/_values-controllers.tpl` in the downloader controller section:

```yaml
downloader:
  enabled: true
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
  type: job
  {{- with .Values.downloader.maxRuntime }}
  activeDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with .Values.downloader.cleanupAfter }}
  ttlSecondsAfterFinished: {{ . }}
  {{- end }}
  {{- end }}
```

The `{{- with }}` blocks ensure fields are only added when values are set (not null/empty). This works for both Job and CronJob types. The bjw-s common chart passes these fields through to the Kubernetes Job/CronJob spec.

## Edge Cases and Behavior

### Null/Empty Values
- If either field is `null` or omitted: that specific feature is disabled
- Example: `maxRuntime: null` with `cleanupAfter: 3600` = no runtime limit, but cleanup after 1 hour

### Value Validation
- Kubernetes requires positive integers for both fields
- Zero or negative values cause Job/CronJob creation to fail
- No chart-side validation - relies on Kubernetes API validation
- Users see immediate error: "Invalid value: 0: must be greater than 0"

### Interaction Between Settings
- If `maxRuntime: 1800` and `cleanupAfter: 3600`:
  - Pod terminates after 30 min if still running
  - Then cleans up 1 hour after it finishes (either from completion or termination)
- If download completes in 5 minutes:
  - Pod stays until `cleanupAfter` expires (1 hour after completion)
- If download hits `maxRuntime`:
  - Pod is killed
  - Cleanup timer starts immediately

### Backward Compatibility
- Existing deployments without these fields continue unchanged
- No defaults applied = Kubernetes defaults apply (no limits)
- No breaking changes to existing configurations

## Use Cases

**Long downloads with ample log time:**
```yaml
downloader:
  maxRuntime: 7200      # 2 hours for large ZIM files
  cleanupAfter: 3600    # Keep logs for 1 hour
```

**Quick cleanup for automated monitoring:**
```yaml
downloader:
  maxRuntime: 1800      # 30 minute timeout
  cleanupAfter: 600     # Clean up after 10 minutes
```

**No runtime limit, but clean up logs:**
```yaml
downloader:
  maxRuntime: null      # No limit
  cleanupAfter: 1800    # Clean up after 30 minutes
```

**Prevent runaway jobs, manual cleanup:**
```yaml
downloader:
  maxRuntime: 3600      # 1 hour timeout
  cleanupAfter: null    # Keep pods for manual inspection
```

## Testing

1. Test Job mode with defaults
2. Test CronJob mode with defaults
3. Test with null values (both fields)
4. Test with custom values (e.g., 600 seconds)
5. Test with invalid values (0, negative) - should fail at apply time
6. Verify helm template output contains correct fields
7. Deploy and verify pod behavior in cluster
