FROM ghcr.io/void-linux/void-glibc:latest

# Update and install dependencies
# We install all tools required by the CI workflows to avoid repeated installations
RUN xbps-install -Syu -y xbps && \
    xbps-install -Sy -y \
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
    odin \
    && rm -rf /var/cache/xbps/*

# Build and install vuru (VUP package manager)
# This enables installing VUP dependencies during builds
COPY vuruV3 /tmp/vuru-build
RUN cd /tmp/vuru-build && \
    make && \
    install -Dm755 build/vuru /usr/local/bin/vuru && \
    rm -rf /tmp/vuru-build
