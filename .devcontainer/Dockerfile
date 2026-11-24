# © Broadcom. All Rights Reserved.
# The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Use the base Ubuntu devcontainer image.
FROM mcr.microsoft.com/devcontainers/base:3.0.14-ubuntu26.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install additional packages.
RUN apt-get update && \
    apt-get install -y apt-transport-https curl git jq software-properties-common unzip wget whois xorriso ca-certificates && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

# Install Packer using the latest release.
RUN PACKER_VERSION="$(curl -fsSL --insecure https://api.github.com/repos/hashicorp/packer/releases/latest | jq -r .tag_name | sed 's/^v//')" && \
    echo "Latest Packer Version: ${PACKER_VERSION}." && \
    PACKER_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" && \
    echo "Downloading Packer from ${PACKER_URL}..." && \
    curl -fsSL --insecure -o "packer_${PACKER_VERSION}_linux_amd64.zip" "${PACKER_URL}" && \
    echo "Installing Packer ${PACKER_VERSION}..." && \
    unzip -o "packer_${PACKER_VERSION}_linux_amd64.zip" && \
    mv packer /usr/local/bin/ && \
    rm "packer_${PACKER_VERSION}_linux_amd64.zip"

# Install Terraform using the latest release.
RUN TERRAFORM_VERSION="$(curl -fsSL --insecure https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r .tag_name | sed 's/^v//')" && \
    echo "Latest Terraform Version: ${TERRAFORM_VERSION}." && \
    TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    echo "Downloading Terraform from ${TERRAFORM_URL}..." && \
    curl -fsSL --insecure -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" "${TERRAFORM_URL}" && \
    echo "Installing Terraform ${TERRAFORM_VERSION}..." && \
    unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    mv terraform /usr/local/bin/ && \
    rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# Install Gomplate using the latest release.
RUN GOMPLATE_VERSION="$(curl -fsSL --insecure https://api.github.com/repos/hairyhenderson/gomplate/releases/latest | jq -r .tag_name | sed 's/^v//')" && \
    echo "Latest Gomplate Version: ${GOMPLATE_VERSION}." && \
    GOMPLATE_URL="https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}/gomplate_linux-amd64" && \
    echo "Downloading Gomplate ${GOMPLATE_VERSION}..." && \
    curl -fsSL --insecure -o gomplate_linux-amd64 "${GOMPLATE_URL}" && \
    echo "Installing Gomplate ${GOMPLATE_VERSION}..." && \
    chmod +x gomplate_linux-amd64 && \
    mv gomplate_linux-amd64 /usr/local/bin/gomplate

# Install PowerShell using the latest release.
RUN PWSH_VERSION="$(curl -fsSL --insecure https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r .tag_name | sed 's/^v//')" && \
    echo "Latest PowerShell Version: ${PWSH_VERSION}." && \
    PWSH_DEB_URL="$(curl -fsSL --insecure https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.deb")).browser_download_url' | head -n 1)" && \
    PWSH_DEB_NAME="$(basename "${PWSH_DEB_URL}")" && \
    echo "Downloading PowerShell ${PWSH_VERSION}..." && \
    curl -fsSL --insecure -o "${PWSH_DEB_NAME}" "${PWSH_DEB_URL}" && \
    echo "Installing PowerShell ${PWSH_VERSION}..." && \
    dpkg -i "${PWSH_DEB_NAME}" && \
    rm "${PWSH_DEB_NAME}"

# Install Python3 and Ansible.
RUN add-apt-repository --yes --update ppa:ansible/ansible && \
    apt-get update && \
    apt-get install -y python3 python3-pip ansible && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set PATH
ENV PATH="$HOME/.local/bin:$PATH"
