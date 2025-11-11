#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/config/zim-urls.json}"
DATA_DIR="${DATA_DIR:-/data}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "ERROR: $*" >&2
}

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Parse config file
if ! FILE_COUNT=$(jq -r '.files | length' "$CONFIG_FILE"); then
    error "Failed to parse config file"
    exit 1
fi

log "Found $FILE_COUNT file(s) to process"

# Process each file
for i in $(seq 0 $((FILE_COUNT - 1))); do
    URL=$(jq -r ".files[$i].url" "$CONFIG_FILE")
    CHECKSUM=$(jq -r ".files[$i].sha256" "$CONFIG_FILE")
    FILENAME=$(basename "$URL")
    FILEPATH="$DATA_DIR/$FILENAME"

    log "Processing ($((i + 1))/$FILE_COUNT): $FILENAME"

    # Check if file already exists with valid checksum
    if [[ -f "$FILEPATH" ]] && [[ "$CHECKSUM" != "null" ]]; then
        log "File exists, verifying checksum..."
        if echo "$CHECKSUM  $FILEPATH" | sha256sum -c -s; then
            log "Checksum valid, skipping download"
            continue
        else
            log "Checksum mismatch, re-downloading"
            rm -f "$FILEPATH"
        fi
    elif [[ -f "$FILEPATH" ]]; then
        log "File exists and no checksum provided, skipping"
        continue
    fi

    # Download with retry logic
    ATTEMPT=1
    SUCCESS=false

    while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
        log "Download attempt $ATTEMPT/$MAX_RETRIES: $URL"

        if curl -L -f -o "$FILEPATH" "$URL" 2>&1; then
            SUCCESS=true
            break
        else
            error "Download failed (attempt $ATTEMPT/$MAX_RETRIES)"
            rm -f "$FILEPATH"

            if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
                DELAY=$((RETRY_DELAY * ATTEMPT))
                log "Retrying in ${DELAY}s..."
                sleep "$DELAY"
            fi
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    if [[ "$SUCCESS" == "false" ]]; then
        error "Failed to download $FILENAME after $MAX_RETRIES attempts"
        exit 1
    fi

    # Verify checksum if provided
    if [[ "$CHECKSUM" != "null" ]]; then
        log "Verifying checksum..."
        if echo "$CHECKSUM  $FILEPATH" | sha256sum -c -s; then
            log "Checksum verified successfully"
        else
            error "Checksum verification failed for $FILENAME"
            rm -f "$FILEPATH"
            exit 1
        fi
    fi

    log "Successfully downloaded: $FILENAME ($(du -h "$FILEPATH" | cut -f1))"
done

log "All downloads completed successfully"
exit 0
