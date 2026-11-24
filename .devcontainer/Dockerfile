# © Broadcom. All Rights Reserved.
# The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Use the base Ubuntu devcontainer image.
FROM mcr.microsoft.com/devcontainers/base:3.0.14-ubuntu26.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool versions. Update these to upgrade a tool; each download is verified before it is installed.
ARG PACKER_VERSION=1.16.2
ARG TERRAFORM_VERSION=1.17.2
ARG GOMPLATE_VERSION=5.3.1
ARG PWSH_VERSION=7.7.0

# The fingerprint of the HashiCorp release signing key (https://www.hashicorp.com/security).
ARG HASHICORP_KEY_FINGERPRINT=C874011F0AB405110D02105534365D9472D7468F

# Set by BuildKit to the architecture of the image (amd64 or arm64).
ARG TARGETARCH

# Install additional packages.
RUN apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl git gnupg jq software-properties-common unzip wget whois xorriso && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

# Install Packer and Terraform. The SHA256SUMS file must be signed by the HashiCorp release key.
WORKDIR /tmp/install
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    export GNUPGHOME=/tmp/install/gnupg && \
    mkdir -m 700 "${GNUPGHOME}" && \
    curl -fsSL -o hashicorp.asc https://www.hashicorp.com/.well-known/pgp-key.txt && \
    gpg --batch --import hashicorp.asc && \
    gpg --batch --list-keys --with-colons | grep -qx "fpr:::::::::${HASHICORP_KEY_FINGERPRINT}:" && \
    for tool in "packer:${PACKER_VERSION}" "terraform:${TERRAFORM_VERSION}"; do \
        name="${tool%%:*}" && version="${tool#*:}" && \
        base="https://releases.hashicorp.com/${name}/${version}" && \
        zip="${name}_${version}_linux_${arch}.zip" && \
        echo "Installing ${name} ${version} (${arch})..." && \
        curl -fsSLO "${base}/${zip}" && \
        curl -fsSLO "${base}/${name}_${version}_SHA256SUMS" && \
        curl -fsSLO "${base}/${name}_${version}_SHA256SUMS.sig" && \
        gpg --batch --verify "${name}_${version}_SHA256SUMS.sig" "${name}_${version}_SHA256SUMS" && \
        grep " ${zip}\$" "${name}_${version}_SHA256SUMS" | sha256sum --check --strict && \
        unzip -o "${zip}" "${name}" -d /usr/local/bin || exit 1; \
    done && \
    rm -rf /tmp/install/* && \
    packer version && \
    terraform version

# Install Gomplate.
WORKDIR /tmp/install
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    base="https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}" && \
    file="gomplate_linux-${arch}" && \
    echo "Installing gomplate ${GOMPLATE_VERSION} (${arch})..." && \
    curl -fsSLO "${base}/${file}" && \
    curl -fsSLO "${base}/checksums-v${GOMPLATE_VERSION}_sha256.txt" && \
    awk -v file="${file}" '$2 == "bin/" file { print $1 "  " file }' "checksums-v${GOMPLATE_VERSION}_sha256.txt" | \
        sha256sum --check --strict && \
    install -m 0755 "${file}" /usr/local/bin/gomplate && \
    rm -rf /tmp/install/* && \
    gomplate --version

# Install PowerShell. The release publishes hashes.sha256 as UTF-16.
WORKDIR /tmp/install
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    base="https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}" && \
    file="powershell_${PWSH_VERSION}-1.deb_${arch}.deb" && \
    echo "Installing PowerShell ${PWSH_VERSION} (${arch})..." && \
    curl -fsSLO "${base}/${file}" && \
    curl -fsSLO "${base}/hashes.sha256" && \
    iconv -f UTF-16 -t UTF-8 hashes.sha256 | tr -d '\r' | awk -v file="${file}" '$2 == "*" file || $2 == file { print $1 "  " file }' | \
        sha256sum --check --strict && \
    apt-get update && \
    apt-get install -y "./${file}" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/install/* && \
    pwsh --version

WORKDIR /

# Install Python3 and Ansible.
RUN add-apt-repository --yes --update ppa:ansible/ansible && \
    apt-get update && \
    apt-get install -y python3 python3-pip ansible && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set PATH
ENV PATH="$HOME/.local/bin:$PATH"
