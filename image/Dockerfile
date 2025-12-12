FROM alpine:3.23

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    coreutils

# Create non-root user
RUN addgroup -g 1000 downloader && \
    adduser -D -u 1000 -G downloader downloader

# Copy download script
COPY downloader.sh /usr/local/bin/downloader.sh
RUN chmod +x /usr/local/bin/downloader.sh

# Set working directory and ownership
WORKDIR /data
RUN chown downloader:downloader /data

# Switch to non-root user
USER downloader

# Run download script
ENTRYPOINT ["/usr/local/bin/downloader.sh"]
