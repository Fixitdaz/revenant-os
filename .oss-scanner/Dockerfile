# Copyright 2026 Revenant OS (Fixitdaz)
# Environment setup for Anthropic OSS Scanner security auditing
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
     coreutils \
    curl \
    findutils \
    git \
     gnupg \
    grep \
    iproute2 \
    jq \
    nodejs \
    npm \
    openssl \
    procps \
    python3 \
    python3-pip \
    python3-prompt-toolkit \
    python3-pytest \
    python3-requests \
    python3-urllib3 \
    python3-yaml \
    sed \
    shellcheck \
    sudo \
    tar \
    util-linux \
    xclip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

# Install Revenant OS userland tools and chroot overlays into system paths for auditing
RUN if [ -d /src/config/includes.chroot/usr/local/bin ]; then \
        cp -r /src/config/includes.chroot/usr/local/bin/* /usr/local/bin/ && \
        chmod +x /usr/local/bin/*; \
    fi && \
    if [ -d /src/config/includes.chroot/etc ]; then \
        cp -rn /src/config/includes.chroot/etc/* /etc/ || true; \
    fi && \
    if [ -f /src/tools/revenant-update ]; then \
        cp /src/tools/revenant-update /usr/local/bin/revenant-update && \
        chmod +x /usr/local/bin/revenant-update; \
    fi && \
    mkdir -p /opt/revenant-os/skills /etc/revenant

# Verify syntax of Python and Bash security-critical entrypoints during build
RUN python3 -m py_compile /usr/local/bin/revenant-agent && \
    bash -n /usr/local/bin/revenant-update && \
    bash -n /usr/local/bin/omniroute-setup-free && \
    bash -n /src/build_iso.sh

WORKDIR /src
CMD ["bash"]
