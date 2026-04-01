FROM mcr.microsoft.com/devcontainers/javascript-node:20-bookworm

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    python3 \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/ci/install_x07_toolchain.sh /tmp/install_x07_toolchain.sh
RUN chmod +x /tmp/install_x07_toolchain.sh

ARG X07_TOOLCHAIN_TAG
ARG X07_TOOLCHAIN_TARBALL_LINUX_X64

ENV X07_TOOLCHAIN_TAG="${X07_TOOLCHAIN_TAG}"
ENV X07_TOOLCHAIN_TARBALL_LINUX_X64="${X07_TOOLCHAIN_TARBALL_LINUX_X64}"

USER vscode
RUN /tmp/install_x07_toolchain.sh

ENV PATH="/home/vscode/.x07/bin:${PATH}"

