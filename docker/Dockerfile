FROM ghcr.io/void-linux/void-glibc:latest

# Update and install dependencies
# We install all tools required by the CI workflows to avoid repeated installations
RUN xbps-install -Syu xbps && \
    xbps-install -Sy \
    git \
    curl \
    bash \
    python3 \
    github-cli \
    util-linux \
    shadow \
    findutils \
    tar \
    gzip \
    libstdc++ \
    ca-certificates \
    && rm -rf /var/cache/xbps/*
