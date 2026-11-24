#!/usr/bin/env bash
# © Broadcom. All Rights Reserved.
# The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Builds a virtual machine image for VMware vSphere with HashiCorp Packer.
#
# Usage:
#
#   ./build.sh [options] [config_path]
#
# - Each of --os, --dist, --version, and --edition skips its menu. The others are shown as menus.
# - With --auto-continue, nothing is prompted and the script exits with the Packer exit status.
# - config_path defaults to config/ next to this script. Create it with ./config.sh.

set -euo pipefail

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

# Prints a path as an absolute path, relative to the working directory, without a trailing slash.
absolute_path() {
    local path=$1
    [[ "$path" == /* ]] || path="$PWD/$path"
    [[ "$path" == / ]] || path=${path%/}
    printf '%s' "$path"
}

# Prints the arguments in lower case.
lower() {
    printf '%s' "$*" | tr '[:upper:]' '[:lower:]'
}

script_path=$(script_dir "$0")
json_path="$script_path/project.json"
config_path="$script_path/config"

os=""
dist=""
version=""
edition=""
auto_continue=false
debug=false
show_command=false
run_check_dependencies=false
logging_enabled=false
log_file=""
build_status=0

# Writes a message to the log file when logging is enabled.
log_message() {
    [[ "$logging_enabled" == true ]] || return 0
    printf '%s [%s]: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" "$2" >>"$log_file"
}

# Prints an error message.
error() {
    printf '\033[0;31m✘ Error:\033[0m %s\n' "$1" >&2
    log_message error "$1"
}

# Prints an error message and exits, with status 1 unless another is given.
fail() {
    error "$1"
    exit "${2:-1}"
}

# Prints a warning message.
warn() {
    printf '\033[0;33m%s\033[0m %s\n' "$1" "$2"
    log_message warn "$1 $2"
}

show_help() {
    printf 'Usage: %s [options] [config_path]\n\n' "$(basename -- "$0")"
    printf 'Options:\n'
    printf '  --help, -h, -H       Display the help message.\n'
    printf '  --deps, -d, -D       Check the required dependencies.\n'
    printf '  --json, -j, -J       Specify the project file.\n'
    printf '                       Defaults to project.json next to this script.\n'
    printf '  --os                 Specify the guest operating system (e.g., Linux, Windows).\n'
    printf '  --dist               Specify the distribution (e.g., Ubuntu Server, Windows Server).\n'
    printf '  --version            Specify the version (e.g., 24.04, 2025).\n'
    printf '  --edition            Specify the edition for Windows (e.g., Standard, Datacenter).\n'
    printf '  --auto-continue      Build without prompts.\n'
    printf '                       Requires --os, --dist, --version, and --edition for Windows.\n'
    printf '  --show, -s, -S       Display the Packer command for the build.\n'
    printf '  --debug, -b, -B      Run Packer in debug mode.\n\n'
    printf 'config_path:\n'
    printf '  Specify the configuration directory.\n'
    printf '  Defaults to config/ next to this script.\n'
}

# Prints an error and the help, and exits with status 2.
usage_error() {
    error "$1"
    printf '\n' >&2
    show_help >&2
    exit 2
}

# Fails unless the option has a value.
require_value() {
    if [[ $# -lt 2 || -z "$2" ]]; then
        usage_error "$1 requires a value."
    fi
}

positional=()
while (($#)); do
    case "$1" in
    --help | -h | -H)
        show_help
        exit 0
        ;;
    --deps | -d | -D)
        run_check_dependencies=true
        shift
        ;;
    --debug | -b | -B)
        debug=true
        shift
        ;;
    --json | -j | -J)
        require_value "$@"
        json_path=$(absolute_path "$2")
        shift 2
        ;;
    --os)
        require_value "$@"
        os=$2
        shift 2
        ;;
    --dist)
        require_value "$@"
        dist=$2
        shift 2
        ;;
    --version)
        require_value "$@"
        version=$2
        shift 2
        ;;
    --edition)
        require_value "$@"
        edition=$2
        shift 2
        ;;
    --auto-continue)
        auto_continue=true
        shift
        ;;
    --show | -s | -S)
        show_command=true
        shift
        ;;
    --)
        shift
        positional+=("$@")
        break
        ;;
    -?*)
        usage_error "Invalid option: $1"
        ;;
    *)
        positional+=("$1")
        shift
        ;;
    esac
done

if ((${#positional[@]} > 1)); then
    usage_error "Expected one config_path, got ${#positional[@]}."
elif ((${#positional[@]} == 1)); then
    config_path=$(absolute_path "${positional[0]}")
fi

if ! command -v jq >/dev/null 2>&1; then
    fail "jq is not installed."
fi

if [[ ! -f "$json_path" ]]; then
    fail "Project file not found: $json_path"
fi

if ! jq -e . "$json_path" >/dev/null 2>&1; then
    fail "Project file is not valid JSON: $json_path"
fi

# Set up logging before anything else is reported. A relative logging path is relative to the
# working directory.
if [[ "$(jq -r '.settings.build_logging_enabled // false' "$json_path")" == true ]]; then
    logging_path=$(jq -r '.settings.build_logging_path // ""' "$json_path")
    logging_path=$(absolute_path "${logging_path:-.}")
    log_file="$logging_path/$(jq -r '.settings.build_logging_filename // "build.log"' "$json_path")"
    if mkdir -p -- "$logging_path" && touch -- "$log_file"; then
        logging_enabled=true
        log_message info "Log file: $log_file."
    else
        warn "Warning:" "Logging is disabled. The log file cannot be written: $log_file"
    fi
fi

# Prints the version requirement for a dependency in the project file, such as ">= 1.16.2".
version_requirement() {
    jq -r --arg name "$1" '.dependencies[] | select(.name == $name) | .version_requirement' "$json_path"
}

# Prints the first version number in the output of the command's --version option.
installed_version() {
    { "$1" --version 2>/dev/null || true; } | sed -nE '1s/[^0-9]*([0-9]+(\.[0-9]+)+).*/\1/p'
}

# Succeeds when the installed version meets the requirement, such as ">= 1.16.2" or "== 1.16.2".
meets_requirement() {
    local installed=$1 operator=$2 required=$3
    case "$operator" in
    ">=") [[ "$(printf '%s\n%s\n' "$required" "$installed" | sort -V | sed -n 1p)" == "$required" ]] ;;
    "==") [[ "$installed" == "$required" ]] ;;
    *) return 1 ;;
    esac
}

# Prints the result of a dependency check, and fails when the dependency is missing or too old.
check_command() {
    local cmd=$1 name operator required installed
    name="$(printf '%s' "${cmd:0:1}" | tr '[:lower:]' '[:upper:]')${cmd:1}"
    read -r operator required <<<"$(version_requirement "$cmd")" || true
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '\033[0;31m[✘]\033[0m %s is not installed. %s or later is required.\n' "$name" "$required"
        return 1
    fi
    installed=$(installed_version "$cmd")
    if [[ -n "$operator" ]] && ! meets_requirement "$installed" "$operator" "$required"; then
        printf '\033[0;31m[✘]\033[0m %s: %s is installed. %s or later is required.\n' "$name" "$installed" "$required"
        return 1
    fi
    printf '\033[0;32m[✔]\033[0m %s: %s is installed. %s or later is required.\n' "$name" "$installed" "$required"
}

if [[ "$run_check_dependencies" == true ]]; then
    for cmd in packer ansible terraform git gomplate; do
        check_command "$cmd" || true
    done
    printf '\n'
    if [[ "$auto_continue" != true ]]; then
        printf 'Press \033[32mEnter\033[0m to continue.\n'
        read -r || exit 1
    fi
fi

# Ansible and Packer are required for every build.
for cmd in ansible packer; do
    if ! output=$(check_command "$cmd"); then
        printf '%s\n' "$output" >&2
        exit 1
    fi
done

if [[ ! -d "$config_path" ]]; then
    fail "Configuration directory not found: $config_path. Run ./config.sh to create it."
fi

project_name=$(jq -r '.project.name // ""' "$json_path")
project_version=$(jq -r '.project.version // ""' "$json_path")

# The branch name, or the commit when the HEAD is detached.
branch_name=$(git -C "$script_path" symbolic-ref --short -q HEAD 2>/dev/null) ||
    branch_name=$(git -C "$script_path" rev-parse --short HEAD 2>/dev/null) ||
    branch_name=""

# Packer builds use path.cwd for manifests, artifacts, and Ansible, so they run from the project root.
cd "$script_path"

clear_screen() {
    if [[ -t 1 ]]; then
        clear
    fi
}

print_title() {
    local title="$project_name $project_version" subtitle="B U I L D" line_width=80 padding
    if [[ -n "$branch_name" ]]; then
        title="$title (Branch: $branch_name)"
    fi
    padding=$(((line_width - ${#title}) / 2))
    ((padding > 0)) || padding=0
    printf '\033[34m%*s%s\033[0m\n' "$padding" '' "$title"
    padding=$(((line_width - ${#subtitle}) / 2))
    printf '\033[32m%*s%s\033[0m\n' "$padding" '' "$subtitle"
}

# Displays the information about the project.
show_info() {
    clear_screen
    printf '\033[32m%s\033[0m: \033[34m%s\033[0m\n\n' "$project_name" "$project_version"
    printf 'Copyright 2023-%s Broadcom. All Rights Reserved.\n\n' "$(date +%Y)"
    printf 'License: %s\n\n' "$(jq -r '.project.license[0].name // ""' "$json_path")"
    printf '%s\n\n' "$(jq -r '.project.description // ""' "$json_path")"
    printf 'GitHub Repository: %s\n' "$(jq -r '.project.urls.github // ""' "$json_path")"
    printf 'Documentation: %s\n\n' "$(jq -r '.project.urls.documentation // ""' "$json_path")"
    show_help
    printf 'Press \033[32mEnter\033[0m to continue.\n'
    read -r || exit 1
}

# The jq filter for the selected distribution or Windows type.
# shellcheck disable=SC2016 # $os and $dist are jq variables.
dist_filter='.os[] | select(.name == $os) | (.distributions // .types // [])[] | select(.description == $dist)'

list_os() {
    jq -r '.os[].name' "$json_path"
}

list_dists() {
    jq -r --arg os "$os" '.os[] | select(.name == $os) | (.distributions // .types // [])[] | .description' "$json_path" | sort
}

list_versions() {
    jq -r --arg os "$os" --arg dist "$dist" \
        "$dist_filter"' | .versions | to_entries[] | select(any(.value[]; .enabled == "true")) | .key' "$json_path" | sort -V -r
}

list_editions() {
    jq -r --arg os "$os" --arg dist "$dist" --arg version "$version" \
        "$dist_filter"' | .versions[$version] // [] | .[] | .editions[]? | select(.enabled == "true") | .edition' "$json_path" | sort -r
}

# Prints the build directory name for the selection, then each variables file from build_files.
list_build_files() {
    jq -r --arg os "$os" --arg dist "$dist" --arg version "$version" --arg edition "$edition" \
        "[$dist_filter"' | .versions[$version] // [] | .[] | select(.enabled == "true") | . as $v
        | if $edition == "" then $v else ($v.editions[]? | select(.edition == $edition and .enabled == "true")) end
        | [$v.version] + [.build_files[0] // {} | .[]]] | first // [] | .[]' "$json_path"
}

# Loads the output lines of a command into the items array.
items=()
load_items() {
    local line
    items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            items+=("$line")
        fi
    done < <("$@")
}

# Prints the name of a selection option for messages.
option_noun() {
    case "$1" in
    --os) printf 'OS' ;;
    --dist) printf 'distribution' ;;
    *) printf '%s' "${1#--}" ;;
    esac
}

# Selects one of the items into $selection. The preset value is used when it is given, and the
# menu is shown otherwise. Returns 1 when the user goes back.
#
# Arguments: the option name, the preset value, the menu heading, the prompt, the prefix for each
# item, and whether the menu offers back (b) or info (i).
selection=""
select_item() {
    local option=$1 preset=$2 heading=$3 prompt=$4 prefix=$5 extra=$6 noun input i
    local show_menu=true
    noun=$(option_noun "$option")

    if ((${#items[@]} == 0)); then
        fail "No $noun options found in $json_path."
    fi

    if [[ -n "$preset" ]]; then
        for i in "${items[@]}"; do
            if [[ "$i" == "$preset" ]]; then
                selection=$preset
                printf '\033[0;32m✔ Selected %s:\033[0m %s\n' "$noun" "$selection"
                return 0
            fi
        done
        error "Unsupported $noun: $preset."
        printf '\033[0;34mℹ Supported options are:\033[0m\n' >&2
        for i in "${items[@]}"; do
            printf '\033[0;34m- %s\033[0m\n' "$i" >&2
        done
        exit 2
    fi

    if [[ "$auto_continue" == true ]]; then
        usage_error "--auto-continue requires $option."
    fi

    while true; do
        if [[ "$show_menu" == true ]]; then
            clear_screen
            print_title
            printf '\n%s:\n\n' "$heading"
            for i in "${!items[@]}"; do
                printf '%s: %s%s\n' "$((i + 1))" "$prefix" "${items[$i]}"
            done
            if [[ "$extra" == info ]]; then
                printf '\nEnter \033[31mq\033[0m to quit or \033[34mi\033[0m for info.\n\n'
            else
                printf '\nEnter \033[32mb\033[0m to go back, or \033[31mq\033[0m to quit.\n\n'
            fi
            show_menu=false
        fi

        if ! read -r -p "$prompt" input; then
            fail "No input. Exiting."
        fi
        case "$input" in
        [qQ])
            exit 0
            ;;
        [bB])
            if [[ "$extra" == back ]]; then
                return 1
            fi
            ;;
        [iI])
            if [[ "$extra" == info ]]; then
                show_info
                show_menu=true
                continue
            fi
            ;;
        *)
            if [[ "$input" =~ ^[0-9]+$ ]] && ((10#$input >= 1 && 10#$input <= ${#items[@]})); then
                selection=${items[10#$input - 1]}
                log_message info "Selected $noun: $selection"
                return 0
            fi
            ;;
        esac
        printf '\n'
        warn "Invalid Selection:" "Enter a number between 1 and ${#items[@]}."
        printf '\n'
    done
}

# Prints the build directory name for the distribution.
dist_directory() {
    case "$dist" in
    *"Red Hat"*) printf 'rhel' ;;
    *"SUSE"*) printf 'sles' ;;
    *"Photon"*) printf 'photon' ;;
    *"Windows Server"*) printf 'server' ;;
    *"Windows Desktop"*) printf 'desktop' ;;
    *) lower "${dist%% *}" ;;
    esac
}

# Prints the Packer --only filter for the Windows edition, or nothing for other builds.
only_filter() {
    case "$dist|$edition" in
    "Windows Server|Standard") printf 'vsphere-iso.windows-server-standard-dexp,vsphere-iso.windows-server-standard-core' ;;
    "Windows Server|Datacenter") printf 'vsphere-iso.windows-server-datacenter-dexp,vsphere-iso.windows-server-datacenter-core' ;;
    "Windows Desktop|Enterprise") printf 'vsphere-iso.windows-desktop-ent' ;;
    "Windows Desktop|Professional") printf 'vsphere-iso.windows-desktop-pro' ;;
    "$dist|") ;;
    *) return 1 ;;
    esac
}

# Prints the build_username from the configuration, or PKR_VAR_build_username when it is not set there.
build_username() {
    local value
    value=$(sed -nE 's/^[[:space:]]*build_username[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$config_path/build.pkrvars.hcl" | tail -n 1)
    printf '%s' "${value:-${PKR_VAR_build_username:-}}"
}

validate_linux_username() {
    local username=$1
    if [[ ! "$username" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}'\$')$ ]]; then
        error "Build username '$username' is invalid for Linux. Check the build.pkrvars.hcl file."
        printf '\nUsername validation rules:\n\n' >&2
        printf '1. It starts with a lowercase letter or an underscore.\n' >&2
        printf '2. It continues with up to 31 lowercase letters, numbers, underscores, or hyphens,\n' >&2
        printf '   or up to 30 of them followed by a dollar sign ($).\n' >&2
        exit 1
    fi
}

validate_windows_username() {
    local username=$1 forbidden='"/\[]:;|=,+*?<>@' i
    local valid=true
    if ((${#username} > 20)) || [[ "$username" =~ ^[.\ ]+$ ]]; then
        valid=false
    fi
    for ((i = 0; i < ${#forbidden}; i++)); do
        if [[ "$username" == *"${forbidden:i:1}"* ]]; then
            valid=false
        fi
    done
    if [[ "$valid" != true ]]; then
        error "Build username '$username' is invalid for Windows. Check the build.pkrvars.hcl file."
        printf '\nUsername validation rules:\n\n' >&2
        printf '1. It has at most 20 characters.\n' >&2
        printf '2. It does not consist only of periods or spaces.\n' >&2
        printf '3. It does not contain any of: %s\n' "$forbidden" >&2
        exit 1
    fi
}

# Set by prepare_build.
build_path=""
build_label=""
packer_args=()

# Resolves the selection to a build directory and Packer arguments. Returns 1 when the build
# directory does not exist.
prepare_build() {
    local folder relative only file
    local -a var_files=() missing=()

    load_items list_build_files
    if ((${#items[@]} < 2)); then
        fail "No build files found for $dist $version $edition in $json_path."
    fi
    folder=$(lower "${items[0]}")
    var_files=("${items[@]:1}")

    relative="$(lower "$os")/$(dist_directory)/$folder"
    build_path="$script_path/builds/$relative/"
    build_label="$dist $version${edition:+ $edition}"
    var_files+=("${relative//\//-}.pkrvars.hcl")

    if [[ ! -d "$build_path" ]]; then
        error "The build directory does not exist: $build_path"
        return 1
    fi

    if ! only=$(only_filter); then
        fail "Unsupported edition: $dist $edition"
    fi

    for file in "${var_files[@]}"; do
        if [[ ! -f "$config_path/$file" ]]; then
            missing+=("$file")
        fi
    done
    if ((${#missing[@]} > 0)); then
        fail "Missing configuration files in $config_path: ${missing[*]}. Run ./config.sh to create them."
    fi

    packer_args=(build -force)
    if [[ "$auto_continue" == true ]]; then
        packer_args+=(-on-error=abort)
    else
        packer_args+=(-on-error=ask)
    fi
    if [[ "$debug" == true ]]; then
        packer_args+=(-debug)
    fi
    if [[ -n "$only" ]]; then
        packer_args+=("--only=$only")
    fi
    for file in "${var_files[@]}"; do
        packer_args+=("-var-file=$config_path/$file")
    done
    packer_args+=("$build_path")
}

# Steps through the menus and the confirmation until a build is chosen. Going back clears the
# selection for that menu and the ones after it.
choose_build() {
    local state=os has_editions=false action kind
    while true; do
        case "$state" in
        os)
            load_items list_os
            select_item --os "$os" "Select a guest operating system" "Select a guest operating system: " "" info
            os=$selection
            state=dist
            ;;
        dist)
            load_items list_dists
            kind="$os distribution"
            if [[ "$os" == Windows ]]; then
                kind="$os type"
            fi
            if select_item --dist "$dist" "Select a $kind" "Enter a number of the $kind: " "" back; then
                dist=$selection
                state=version
            else
                os="" dist="" version="" edition=""
                state=os
            fi
            ;;
        version)
            load_items list_versions
            if select_item --version "$version" "Select a version" "Select a version: " "$dist " back; then
                version=$selection
                state=edition
            else
                dist="" version="" edition=""
                state=dist
            fi
            ;;
        edition)
            load_items list_editions
            has_editions=false
            if ((${#items[@]} > 0)); then
                has_editions=true
                if select_item --edition "$edition" "Select an edition" "Select an edition: " "$dist " back; then
                    edition=$selection
                    state=confirm
                else
                    version="" edition=""
                    state=version
                fi
            else
                edition=""
                state=confirm
            fi
            ;;
        confirm)
            if ! prepare_build; then
                if [[ "$auto_continue" == true ]]; then
                    exit 2
                fi
                while true; do
                    printf '\nWould you like to go (\033[0;33mb\033[0m)ack or (\033[0;31mq\033[0m)uit?\n'
                    read -r action || exit 1
                    case "$action" in
                    [bB]*) break ;;
                    [qQ]*) exit 0 ;;
                    esac
                done
                version="" edition=""
                state=version
                continue
            fi

            printf '\nBuild a %s virtual machine image for VMware vSphere?\n' "$build_label"
            if [[ "$branch_name" == */* ]]; then
                printf "\n\033[33mWarning:\033[0m The branch name contains a slash ('\033[33m/\033[0m') which may cause issues with the build.\n\n"
            fi

            if [[ "$auto_continue" == true ]]; then
                printf '\nAuto-continue is enabled. Skipping user prompt...\n'
                return 0
            fi

            while true; do
                read -r -p $'\nWould you like to (\e[32mc\e[0m)ontinue, go (\e[33mb\e[0m)ack, or (\e[31mq\e[0m)uit? ' action || exit 1
                log_message info "User selected: $action"
                case "$action" in
                [cC]*)
                    return 0
                    ;;
                [qQ]*)
                    exit 0
                    ;;
                [bB]*)
                    if [[ "$has_editions" == true ]]; then
                        edition=""
                        state=edition
                    else
                        version="" edition=""
                        state=version
                    fi
                    break
                    ;;
                esac
            done
            ;;
        esac
    done
}

# Runs packer init and packer build for the prepared build, and sets build_status.
run_build() {
    local validate_username username
    build_status=0

    validate_username=validate_linux_username
    if [[ "$os" == Windows ]]; then
        validate_username=validate_windows_username
    fi
    username=$(build_username)
    if [[ -z "$username" ]]; then
        fail "build_username is not set in $config_path/build.pkrvars.hcl or PKR_VAR_build_username."
    fi
    "$validate_username" "$username"

    printf '\nInitializing HashiCorp Packer and the required plugins...\n'
    log_message info "Running: packer init $build_path"
    packer init "$build_path" || build_status=$?
    if ((build_status != 0)); then
        error "packer init failed with exit status $build_status."
        return 0
    fi

    printf 'Starting the build of %s...\n\n' "$build_label"
    if [[ "$show_command" == true ]]; then
        printf '\n\033[32mThe following command is run for this build:\033[0m\n\n'
        printf '\033[34m'
        printf '%q ' packer "${packer_args[@]}"
        printf '\033[0m\n\n'
    fi
    log_message info "Running: packer ${packer_args[*]}"
    packer "${packer_args[@]}" || build_status=$?
    if ((build_status != 0)); then
        error "The build of $build_label failed with exit status $build_status."
    else
        log_message info "The build of $build_label finished."
    fi
}

while true; do
    choose_build
    run_build

    # With --auto-continue, run a single build and exit with the Packer exit status, so CI
    # pipelines fail when the build fails.
    if [[ "$auto_continue" == true ]]; then
        exit "$build_status"
    fi

    while true; do
        printf 'Would you like to (\033[0;32mc\033[0m)ontinue, or (\033[0;31mq\033[0m)uit? '
        read -r action || exit "$build_status"
        log_message info "User selected: $action"
        case "$action" in
        [cC]*)
            os="" dist="" version="" edition=""
            break
            ;;
        [qQ]*)
            exit "$build_status"
            ;;
        esac
    done
done
