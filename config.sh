#!/usr/bin/env bash
# © Broadcom. All Rights Reserved.
# The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Copies the example variables files to a configuration directory.
#
# Usage:
#
#   ./config.sh [config_path]
#
# - The default configuration directory is config/ next to this script.
# - builds/<name>.pkrvars.hcl.example is copied to <name>.pkrvars.hcl.
# - builds/<os>/<dist>/<version>/*.pkrvars.hcl.example is copied to <os>-<dist>-<version>.pkrvars.hcl.
# - Existing .hcl files are moved to a backup.<timestamp> directory.
# - Nothing changes until every example file is copied.

set -euo pipefail

# Prints an error and exits.
error() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

# Prints the directory of this script, following symbolic links relative to their directory.
script_dir() {
    local file=$1 dir
    while [[ -L "$file" ]]; do
        dir=$(cd -P -- "$(dirname -- "$file")" && pwd)
        file=$(readlink -- "$file")
        [[ "$file" == /* ]] || file="$dir/$file"
    done
    cd -P -- "$(dirname -- "$file")" && pwd
}

show_help() {
    printf 'Usage: %s [options] [config_path]\n\n' "$(basename -- "$0")"
    printf 'Options:\n'
    printf '  --help, -h, -H       Display the help message.\n\n'
    printf 'config_path:\n'
    printf '  Specify the configuration directory.\n'
    printf '  Defaults to config/ next to this script.\n'
}

script_path=$(script_dir "$0")
builds_path="$script_path/builds"

while (($#)); do
    case "$1" in
    --help | -h | -H)
        show_help
        exit 0
        ;;
    --)
        shift
        break
        ;;
    -?*)
        printf 'Error: Invalid option: %s\n\n' "$1" >&2
        show_help >&2
        exit 1
        ;;
    *)
        break
        ;;
    esac
done

if (($# > 1)); then
    error "Expected one config_path, got $#."
fi
config_path=${1:-$script_path/config}

shopt -s nullglob

mkdir -p -- "$config_path" || error "Failed to create directory: $config_path"

# Copy into a staging directory first, so a failed copy leaves the configuration as it was.
staging=$(mktemp -d "$config_path/.config.XXXXXX") || error "Failed to create a staging directory in: $config_path"
trap 'rm -rf -- "$staging"' EXIT

# Copies an example file to the staging directory.
stage() {
    local src=$1 name=$2
    if [[ -e "$staging/$name" ]]; then
        error "More than one example file maps to $name: $src"
    fi
    cp -- "$src" "$staging/$name" || error "Failed to copy $src to $config_path/$name"
}

for src in "$builds_path"/*.pkrvars.hcl.example; do
    stage "$src" "$(basename -- "$src" .example)"
done

while IFS= read -r -d '' src; do
    dir=$(dirname -- "${src#"$builds_path"/}")
    stage "$src" "${dir//\//-}.pkrvars.hcl"
done < <(find "$builds_path" -mindepth 2 -type f -name '*.pkrvars.hcl.example' -print0)

staged=("$staging"/*)
if ((${#staged[@]} == 0)); then
    error "No example files found in: $builds_path"
fi

existing=("$config_path"/*.hcl)
if ((${#existing[@]} > 0)); then
    echo "> Backing up existing configurations..."
    backup_dir="$config_path/backup.$(date +%Y%m%d-%H%M%S)"
    # Keep an earlier backup taken in the same second.
    backup_base=$backup_dir
    n=1
    while [[ -e "$backup_dir" ]]; do
        backup_dir="$backup_base.$n"
        n=$((n + 1))
    done
    mkdir -- "$backup_dir" || error "Failed to create backup directory: $backup_dir"
    mv -- "${existing[@]}" "$backup_dir/" || error "Failed to move the existing configuration files to: $backup_dir"
    echo "> Backup created: $backup_dir"
fi

mv -- "${staged[@]}" "$config_path/" || error "Failed to move the configuration files to: $config_path"

echo "> Configuration setup complete: $config_path"
