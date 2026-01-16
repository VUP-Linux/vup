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
    make \
    && rm -rf /var/cache/xbps/*

# Install Odin from VUP repository (install public key first for signature verification)
COPY keys/78:b8:1b:87:74:ff:ce:49:f8:f9:06:9a:04:7f:7e:1e.plist /var/db/xbps/keys/
RUN xbps-install -y -R https://github.com/VUP-Linux/vup/releases/download/languages-x86_64-current -S odin

# Build and install vuru (VUP package manager)
# This enables installing VUP dependencies during builds
COPY vuru /tmp/vuru-build
RUN cd /tmp/vuru-build && \
    make && \
    install -Dm755 build/vuru /usr/local/bin/vuru && \
    rm -rf /tmp/vuru-build
