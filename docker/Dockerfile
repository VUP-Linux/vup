FROM ghcr.io/void-linux/void-glibc:latest

# Update and install dependencies
# We install all tools required by the CI workflows to avoid repeated installations
# Odin needs llvm and clang for building itself as well as building .odin files on *Nix systems
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
    clang \
    llvm \
    && rm -rf /var/cache/xbps/*

# Build Odin from source
WORKDIR /Odin-install
RUN git clone https://github.com/odin-lang/Odin.git /Odin-install \
    && git checkout dev-2024-12 \
    && make

RUN mkdir /opt/Odin \
    && cp -R ./base ./core ./shared ./vendor ./odin /opt/Odin/
WORKDIR /
RUN rm -rf /Odin-install

ENV PATH="/opt/Odin:${PATH}"

# Build and install vuru (VUP package manager)
# This enables installing VUP dependencies during builds
COPY vuru /tmp/vuru-build
RUN cd /tmp/vuru-build && \
    make && \
    install -Dm755 build/vuru /usr/local/bin/vuru && \
    rm -rf /tmp/vuru-build
