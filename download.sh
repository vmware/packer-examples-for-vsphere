#!/usr/bin/env bash
# © Broadcom. All Rights Reserved.
# The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

follow_link() {
    file="$1"
    while [ -L "$file" ]; do
        file=$(readlink "$file")
    done
    echo "$file"
}

# Get the script path.
script_path=$(realpath "$(dirname "$(follow_link "$0")")")

# Default to the project file next to this script.
json_path="$script_path/project.json"
restart_args=()

run_check_dependencies=false
run_check_jq=false
run_show_help=false

# This function prompts the user to press Enter to continue.
press_enter_continue() {
    printf "Press \033[32mEnter\033[0m to continue.\n"
    read -r
    exec "$0" "${restart_args[@]}"
}

# This function prompts the user to press Enter to exit.
press_enter_exit() {
    printf "Press \033[31mEnter\033[0m to exit.\n"
    read -r
    exit 0
}

if [ $# -eq 0 ]; then
    run_check_jq=true
fi

while (("$#")); do
    case "$1" in
    --json | -j | -J)
        json_path="$2"
        [[ "$json_path" == /* ]] || json_path="$PWD/$json_path"
        restart_args=(--json "$json_path")
        run_check_jq=true
        shift 2
        ;;
    --deps | -d | -D)
        run_check_dependencies=true
        shift
        ;;
    --help | -h | -H)
        run_show_help=true
        shift
        ;;
    *)
        printf "\033[33mInvalid Option:\033[0m %s\n\n" "$1"
        press_enter_exit
        ;;
    esac
done

# This function checks if the required dependencies are installed.
check_dependencies() {
    local cmd
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local NC='\033[0m' # No Color
    local CHECKMARK="${GREEN}[✔]${NC}"
    local CROSSMARK="${RED}[✘]${NC}"
    local missing_deps=false
    local http_client_installed=false

    for cmd in jq wget curl; do
        if command -v $cmd &>/dev/null; then
            if [ "$cmd" = "wget" ] || [ "$cmd" = "curl" ]; then
                http_client_installed=true
            fi
            echo -e "$CHECKMARK $cmd is installed."
        else
            if [ "$cmd" = "jq" ]; then
                missing_deps=true
                echo -e "$CROSSMARK $cmd is not installed."
            fi
        fi
    done

    if ! $http_client_installed; then
        printf "\033[0;31m[✘]\033[0m Neither \033[0;31mwget\033[0m nor \033[0;31mcurl\033[0m is installed.\n"
        missing_deps=true
    fi

    if $missing_deps; then
        printf "\n"
        press_enter_exit
    else
        printf "\n"
        press_enter_continue
    fi
}

# After the loop, check if check_dependencies needs to be run
if $run_check_dependencies; then
    check_dependencies
fi

# Check for jq
check_jq() {
    if ! command -v jq &>/dev/null; then
        echo -e "\033[0;31m[✘]\033[0m jq is not installed."
        exit 1
    fi
}

# Checks that a URL is reachable with curl or wget.
url_exists() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o /dev/null --head "$1"
    else
        wget -q --spider "$1"
    fi
}

# Downloads a URL to a file with curl or wget, removing a partial file on failure.
download_file() {
    local destination=$1 url=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o "$destination" "$url" && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$destination" "$url" && return 0
    else
        print_message error "Neither curl or wget is installed.\n"
        exit 1
    fi
    rm -f "$destination"
    return 1
}

# After the loop, check if check_jq needs to be run
if $run_check_jq; then
    check_jq
fi

# This function displays the help message.
show_help() {
    printf "\nOptions:\n"
    printf "  --deps, -d, -D       Check the dependencies.\n"
    printf "  --json, -j, -J       Specify the JSON file path.\n"
    printf "  --help, -h, -H       Display this help message.\n\n"
    printf "Note: You can set an environment variable for the Red Hat Subscription Manager offline\n"
    printf "      token to simplify downloading Red Hat Enterprise Linux.\n\n"
    printf '      \033[32mexport rhsm_offline_token="your_rhsm_offline_token_value"\033[0m\n\n'
    press_enter_continue
}

# After the loop, check if show_help needs to be run
if $run_show_help; then
    show_help
fi

# Set the default values for the variables.
os_names=$(jq -r '.os[] | .name' "$json_path")
os_array=()
if [[ -n "$os_names" ]]; then
    IFS=$'\n' read -rd '' -a os_array <<<"$os_names"
fi

# The jq filter for the selected distribution or Windows type.
# shellcheck disable=SC2016 # $os and $dist are jq variables, not shell variables.
dist_filter='.os[] | select(.name == $os) | (.distributions // .types)[] | select(.description == $dist)'

# Prints the selected architecture entry from the project file as JSON.
arch_entry() {
    jq -c --arg os "$os" --arg dist "$dist" --arg version "$version" --arg arch "$arch" \
        "$dist_filter | .versions[][] | select(.version == \$version) | .architectures[] | select(.architecture == \$arch)" \
        "$json_path"
}

# Prints a field of the selected architecture entry, or nothing if it is missing.
entry_field() {
    printf '%s' "$entry" | jq -r --arg field "$1" '.[$field] // empty'
}

# Get the project information from the JSON file.
get_project_info() {
    local field=$1
    jq -r ".project.${field}" "$json_path"
}

# Get the settings from the JSON file.
get_settings() {
    local field=$1
    jq -r ".settings.${field}" "$json_path"
}

# Get the settings from the JSON file.
iso_base_path=$(get_settings "iso_base_path")
rename_iso=$(get_settings "rename_iso")
cleanup_failed_iso_verification=$(get_settings "cleanup_failed_iso_verification")
logging_enabled=$(get_settings download_logging_enabled)
logging_path=$(get_settings download_logging_path)
logfile_filename=$(get_settings download_logging_filename)

# Resolve a relative ISO path against the project directory.
[[ "$iso_base_path" == /* ]] || iso_base_path="$script_path/$iso_base_path"

# This function displays the information about the script and project.
info() {
    project_name=$(get_project_info "name")
    project_description=$(get_project_info "description")
    project_version=$(get_project_info "version")
    project_license=$(get_project_info "license[0].name")
    project_github_url=$(get_project_info "urls.github")
    project_docs_url=$(get_project_info "urls.documentation")
    clear
    printf "\033[32m%s\033[0m: \033[34m%s\033[0m\n\n" "$project_name" "$project_version"
    printf "Copyright 2023-%s Broadcom. All Rights Reserved.\n\n" "$(date +%Y)"
    printf "License: %s\n\n" "$project_license"
    printf "%s\n\n" "$project_description"
    printf "GitHub Repository: %s\n" "$project_github_url"
    printf "Documentation: %s\n\n" "$project_docs_url"
    show_help "continue"
    press_enter_continue
}

# This function prompts the user to go back or quit.
prompt_user() {
    printf "Enter \033[32mb\033[0m to go back, or \033[31mq\033[0m to quit.\n\n"
}

# This function prints a message to the console based on the message type.
print_message() {
    local type=$1
    local message=$2
    local no_color_message

    case $type in
    error)
        printf "\033[31m%s\033[0m$message"
        ;;
    info)
        printf "\033[37m%s\033[0m$message"
        ;;
    warn)
        printf "\033[33m%s\033[0m$message"
        ;;
    debug)
        printf "\033[34m%s\033[0m$message"
        ;;
    *)
        printf "%s" "$message"
        ;;
    esac

    if [[ "$logging_enabled" == "true" ]]; then
        # Remove color formatting from the log message
        no_color_message=$(echo -e "$message" | sed -r "s/\x1b\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
        log_message "$type" "$no_color_message"
    fi
}

log_message() {
    local type=$1
    local message=$2
    if [ "$logging_enabled" = true ]; then
        printf "%s [%s]: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(echo "$type" | tr '[:lower:]' '[:upper:]')" "$message" >>"$log_file"
    fi
}

print_title() {
    project_name=$(jq -r '.project.name' "$json_path")
    project_version=$(jq -r '.project.version' "$json_path")
    line_width=80
    title="${project_name} ${project_version}"
    subtitle="D O W N L O A D"
    padding_title=$(((line_width - ${#title}) / 2))
    padding_subtitle=$(((line_width - ${#subtitle}) / 2))

    printf "\033[34m%*s%s\033[0m\n" $padding_title '' "$title"
    printf "\033[32m%*s%s\033[0m\n" $padding_subtitle '' "$subtitle"
}

# This function selects the guest operating system family.
# Only `Linux`` and `Windows`` are supported presently in the JSON file.
select_os() {
    clear
    print_title
    printf "\nSelect a guest operating system:\n\n"
    for i in "${!os_array[@]}"; do
        printf '%d: %s\n' "$((i + 1))" "${os_array[$i]}"
    done
    printf "\nEnter \033[31mq\033[0m to quit or \033[34mi\033[0m for info.\n\n"

    while true; do
        read -r -p "Select a guest operating system: " os_input
        if [[ $os_input == [qQ] ]]; then
            exit 0
        elif [[ $os_input == [iI] ]]; then
            info
        elif ((os_input >= 1 && os_input <= ${#os_array[@]})); then
            os=${os_array[$((os_input - 1))]}
            select_distribution
            break
        else
            printf "\n"
            print_message warn "\033[33mInvalid Selection:\033[0m Enter a number between 1 and ${#os_array[@]}."
            printf "\n\n"
        fi
    done
}

select_distribution() {
    dist_descriptions=$(jq -r --arg os "$os" '.os[] | select(.name == $os) | (.distributions // .types)[] | .description' "$json_path")

    # Check if the distribution descriptions are empty.
    if [ -z "$dist_descriptions" ]; then
        printf "\nNo distributions found for %s.\n" "$os"
        select_os
        return
    fi

    # Convert the distribution descriptions to a sorted array.
    IFS=$'\n' read -rd '' -a dist_array < <(sort <<<"$dist_descriptions")

    # Print the submenu.
    clear
    print_title
    printf "\nSelect a %s:\n\n" "$([[ "$os" == "Windows" ]] && echo "$os type" || echo "$os distribution")"
    for i in "${!dist_array[@]}"; do
        printf '%d: %s\n' "$((i + 1))" "${dist_array[$i]}"
    done
    printf "\n"
    prompt_user

    while true; do
        read -r -p "Enter a number of the $([[ "$os" == "Windows" ]] && echo "$os type" || echo "$os distribution"): " dist_input
        if [[ $dist_input == [qQ] ]]; then
            exit 0
        elif [[ $dist_input == [bB] ]]; then
            select_os
            break
        elif ((dist_input >= 1 && dist_input <= ${#dist_array[@]})); then
            dist=${dist_array[$((dist_input - 1))]}
            select_version
            break
        else
            printf "\n"
            print_message warn "\033[33mInvalid Selection:\033[0m Enter a number between 1 and ${#dist_array[@]}."
            printf "\n\n"
        fi
    done
}

# This function selects the version based on the guest operating system's distribution or type.
select_version() {
    # Check if the selected distribution is SUSE Linux Enterprise Server.
    # SUSE Linux Enterprise Server is not available for download using this script.
    if [ "$dist" == "SUSE Linux Enterprise Server" ]; then
        printf "\nSUSE Linux Enterprise Server \033[31mis not\033[0m available for download using this script.\n\n"
        press_enter_continue
    fi

    version_descriptions=$(jq -r --arg os "$os" --arg dist "$dist" "$dist_filter | .versions[][] | .version" "$json_path")

    # Convert the version descriptions to an array and sort it in descending order.
    IFS=$'\n' read -rd '' -a version_array <<<"$(echo "$version_descriptions" | sort -V -r)"

    # Print the submenu.
    clear
    print_title
    printf "\nSelect a version:\n\n"
    for i in "${!version_array[@]}"; do
        printf '%d: %s %s\n' "$((i + 1))" "$dist" "${version_array[$i]}"
    done
    printf "\n"
    prompt_user

    # Select a version.
    while true; do
        read -r -p "Select a version: " version_input
        if [[ "$version_input" == [qQ] ]]; then
            exit 0
        elif [[ $version_input == [bB] ]]; then
            select_distribution
            break
        elif [[ $version_input =~ ^[0-9]+$ ]] && ((version_input >= 1 && version_input <= ${#version_array[@]})); then
            version=${version_array[$((version_input - 1))]}
            select_architecture
            break
        else
            printf "\n"
            print_message warn "\033[33mInvalid Selection:\033[0m Enter a number between 1 and ${#version_array[@]}.\n"
            printf "\n"
        fi
    done
}

# This function selects the architecture based on the guest operating system's distribution or type.
# Only `amd64` and `arm64` architectures are supported presently in the JSON file.
select_architecture() {
    arch_names=$(jq -r --arg os "$os" --arg dist "$dist" --arg version "$version" \
        "$dist_filter | .versions[][] | select(.version == \$version) | .architectures[].architecture" "$json_path")

    # Convert the architecture names to an array..
    arch_array=()
    if [[ -n "$arch_names" ]]; then
        IFS=$'\n' read -rd '' -a arch_array <<<"$arch_names"
    fi

    # Print the submenu.
    if [[ ${#arch_array[@]} -eq 1 ]]; then
        arch=${arch_array[0]}
        select_download
    else
        clear
        print_title
        printf "\nSelect an architecture:\n\n"
        for i in "${!arch_array[@]}"; do
            printf '%d: %s\n' "$((i + 1))" "${arch_array[$i]}"
        done
        printf "\n"
        prompt_user

        while true; do
            printf "\n"
            read -r -p "Select an architecture: " arch_number
            if [[ "$arch_number" == [qQ] ]]; then
                exit 0
            elif [[ "$arch_number" == [bB] ]]; then
                select_version
                break
            elif ((arch_number >= 1 && arch_number <= ${#arch_array[@]})); then
                arch=${arch_array[$((arch_number - 1))]}
                select_download
                break
            else
                printf "\n"
                print_message warn "\033[33mInvalid Selection:\033[0m Enter a number between 1 and ${#arch_array[@]}.\n"
                printf "\n"
            fi
        done
    fi
}

# This function downloads and verifies the selected ISO image.
select_download() {
    local entry checksum_value checksum_algorithm expected_checksum checksum_file action
    downloaded=false
    entry=$(arch_entry)
    checksum_value=$(entry_field checksum)
    checksum_algorithm=$(entry_field checksum_algorithm | tr '[:upper:]' '[:lower:]')
    download_dir="$iso_base_path/$(printf '%s' "$os/$dist/$version/$arch" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

    # Find the download link and filename.
    if [[ "$dist" == *"Red Hat"* ]]; then
        resolve_rhel_image "$checksum_value" || return
    else
        download_link=$(entry_field download_link)
        file_name=$(entry_field filename)
        [ -n "$file_name" ] || file_name=$(basename "${download_link%%\?*}")
        if ! url_exists "$download_link"; then
            printf "\n"
            print_message warn "\033[33mInvalid Data:\033[0m Inaccessible URL in JSON configuration: \033[34m$download_link\033[0m"
            printf "\n"
            return
        fi
    fi
    full_path="$download_dir/$file_name"
    mkdir -p "$download_dir"

    # Find the expected checksum before downloading.
    checksum_file=''
    if [[ "$checksum_value" =~ ^https?:// ]]; then
        checksum_file="$download_dir/checksum"
        if ! download_file "$checksum_file" "$checksum_value"; then
            print_message error "Failed to download the checksum file: \033[34m$checksum_value\033[0m.\n"
            return
        fi
        expected_checksum=$(checksum_from_list "$checksum_file" "$file_name")
        if [ -z "$expected_checksum" ]; then
            print_message error "No checksum for \033[34m$file_name\033[0m in \033[34m$checksum_value\033[0m.\n"
            return
        fi
    else
        expected_checksum=$checksum_value
    fi

    # Reuse a matching file, or ask before replacing an existing one.
    if [ -f "$full_path" ]; then
        printf "\n"
        print_message warn "\033[33mExisting ISO file found: \033[34m$full_path\033[0m"
        printf "\n"
        if [ -n "$expected_checksum" ] && [ "$(file_checksum "$checksum_algorithm" "$full_path")" = "$expected_checksum" ]; then
            print_message info "The existing file matches the checksum. Skipping the download.\n"
            downloaded=true
            if $rename_iso; then
                rename_file
            fi
            return
        fi
        if [ -n "$expected_checksum" ]; then
            print_message warn "\033[33mChecksum does not match. The file may be corrupted.\033[0m"
        fi
        while true; do
            read -r -p $'\nWould you like to (\e[32mc\e[0m)ontinue, go (\e[33mb\e[0m)ack, or (\e[31mq\e[0m)uit? ' action
            log_message "info" "User selected: $action"
            case $action in
            [cC]*) break ;;
            [qQ]*) exit 0 ;;
            [bB]*)
                select_distribution
                return
                ;;
            esac
        done
    fi

    printf "\n"
    print_message info "\033[32mDownloading:\033[0m \033[34m$file_name\033[0m => \033[34m$download_dir\033[0m."
    printf "\n\n"
    if ! download_file "$full_path" "$download_link"; then
        print_message error "Download \033[31mfailed\033[0m for \033[34m$download_link\033[0m.\n"
        return
    fi

    if [ -z "$expected_checksum" ]; then
        # The Microsoft Windows Evaluation Center does not publish checksums.
        printf "\n"
        print_message warn "No checksum is published for \033[34m$file_name\033[0m. Skipping verification.\n"
        downloaded=true
    else
        verify_download "$checksum_algorithm" "$expected_checksum" "$checksum_file"
    fi

    # Rename the downloaded file.
    if $downloaded && $rename_iso; then
        rename_file
    fi
}

# Sets the Red Hat download link and filename from the API, prompting for the offline token.
# Red Hat Enterprise Linux must be downloaded from Red Hat Subscription Manager using the API.
resolve_rhel_image() {
    local checksum=$1 invalid_attempts=0 access_token image

    # If the 'rhsm_offline_token' is not provided as an environment variable, prompt the user to enter it.
    while true; do
        if [[ -z "${rhsm_offline_token}" ]]; then
            printf "\n"
            read -r -sp "Enter your Red Hat Subscription Manager offline token: " rhsm_offline_token
            printf "\n"
            read -r -sp "Enter your Red Hat Subscription Manager offline token again: " rhsm_offline_token_verify
            printf "\n"
        else
            rhsm_offline_token_verify=$rhsm_offline_token
        fi

        if [ -z "$rhsm_offline_token" ] || [ -z "$rhsm_offline_token_verify" ]; then
            printf "\n\n"
            print_message error "The tokens are blank. Returning to version selection.\n"
            sleep 2
            select_version
            return 1
        elif [ "$rhsm_offline_token" != "$rhsm_offline_token_verify" ]; then
            printf "\n\n"
            print_message error "Tokens do not match. Please try again.\n"
            invalid_attempts=$((invalid_attempts + 1))
        elif [[ ! $rhsm_offline_token =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
            printf "\n\n"
            print_message error "Incorrect token format. Please try again.\n"
            invalid_attempts=$((invalid_attempts + 1))
            rhsm_offline_token=""
        else
            break
        fi

        if [[ $invalid_attempts -ge 3 ]]; then
            printf "\n"
            print_message error "Too many invalid attempts. Returning to version selection.\n"
            sleep 2
            select_version
            return 1
        fi
    done

    # Get the access token, passing the offline token on stdin to keep it out of the process list.
    access_token=$(printf '%s' "$rhsm_offline_token" |
        curl -fsS https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
            -d grant_type=refresh_token -d client_id=rhsm-api --data-urlencode refresh_token@- 2>/dev/null |
        jq -r '.access_token // empty')

    # Clear the token variables to force the user to enter them again.
    rhsm_offline_token=""
    rhsm_offline_token_verify=""

    if [ -z "$access_token" ]; then
        printf "\n"
        print_message error "Failed to get an access token from Red Hat Subscription Manager. Check the offline token.\n"
        return 1
    fi

    # Get the filename and download link, passing the header on stdin.
    image=$(printf 'Authorization: Bearer %s\n' "$access_token" |
        curl -fsSL -H @- "https://api.access.redhat.com/management/v1/images/$checksum/download")
    file_name=$(printf '%s' "$image" | jq -r '.body.filename // empty' 2>/dev/null)
    download_link=$(printf '%s' "$image" | jq -r '.body.href // empty' 2>/dev/null)
    if [ -z "$file_name" ] || [ -z "$download_link" ]; then
        printf "\n"
        print_message error "Failed to get the image download from Red Hat for checksum \033[34m$checksum\033[0m.\n"
        return 1
    fi
}

# Prints the checksum for a file from a list in "hash  file" or "ALGO (file) = hash" format.
checksum_from_list() {
    awk -v name="$2" '
        $NF == name || $NF == "*" name { print $1; exit }
        $2 == "(" name ")" && $3 == "=" { print $4; exit }
    ' "$1"
}

# Prints the checksum of a file with the given algorithm.
file_checksum() {
    local command
    case "$1" in
    sha256 | sha512 | sha1 | md5) command="${1}sum" ;;
    *)
        print_message error "Unsupported checksum algorithm: \033[34m$1\033[0m"
        exit 1
        ;;
    esac
    "$command" "$2" | awk '{print $1}'
}

# Compares the downloaded file with the expected checksum, removing it on failure if configured.
verify_download() {
    local algorithm=$1 expected=$2 actual path
    local -a paths=("$full_path")
    [ -z "$3" ] || paths+=("$3")
    actual=$(file_checksum "$algorithm" "$full_path")

    printf "\n"
    print_message info "\033[32mVerifying:\033[0m \033[34m$algorithm\033[0m checksum for \033[34m$file_name\033[0m.\n"
    if [ "$actual" = "$expected" ]; then
        print_message info "Verification of checksum \033[32msuccessful\033[0m for \033[34m$file_name\033[0m.\n"
        print_message info "        - \033[32mExpected:\033[0m \033[34m$expected\033[0m\n"
        print_message info "        - \033[32mActual:\033[0m   \033[34m$actual\033[0m\n\n"
        downloaded=true
        return
    fi

    print_message error "Verification of checksum \033[31mfailed\033[0m for \033[34m$file_name\033[0m.\n"
    print_message info "        - \033[32mExpected:\033[0m \033[34m$expected\033[0m\n"
    print_message info "        - \033[31mActual:\033[0m   \033[34m$actual\033[0m\n\n"
    print_message error "Download \033[1m\033[31mfailed\033[0m for \033[34m$dist $version $arch\033[0m.\n"

    if $cleanup_failed_iso_verification; then
        for path in "${paths[@]}"; do
            if rm -f "$path" && [ ! -e "$path" ]; then
                print_message info "        - \033[32mRemoved:\033[0m \033[34m$path\033[0m.\n"
            else
                print_message info "        - \033[31mFailed to remove:\033[0m \033[34m$path\033[0m.\n"
            fi
        done
    fi
    printf "\n\n"
    press_enter_continue
}

# This function renames a downloaded file based on the distribution/type, version, and architecture.
rename_file() {
    # Check if the operating system is Linux or Windows.
    if [[ "$os" == *"Linux"* ]] || [[ "$os" == *"Windows"* ]]; then
        # Switch to the download directory.
        cd "$download_dir" || {
            print_message error "Failed to change to directory: \033[34m$download_dir\033[0m"
            return 1
        }

        # Check if the file exists.
        if [[ ! -f "$file_name" ]]; then
            print_message error "File does not exist: \033[34m$file_name\033[0m"
        fi

        # Rename the file based on the distribution or type, version, and architecture.
        case "$arch" in
        "amd64") iso_name="$(echo "$dist-$version-x86-64.iso" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')" ;;
        "arm64") iso_name="$(echo "$dist-$version-aarch64.iso" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')" ;;
        *) print_message error "Unsupported architecture: \033[34m$arch\033[0m" ;;
        esac

        # Rename the file.
        mv "$file_name" "$iso_name"
        print_message info "Renaming: \033[34m$file_name\033[0m => \033[34m$iso_name\033[0m.\n"
    else
        print_message error "Unsupported guest operating system: \033[34m$os\033[0m"
    fi
}

# Check if logging is enabled.
if [[ "$logging_enabled" == "true" ]]; then
    # If logging_path is empty, use the current directory
    if [[ -z "$logging_path" ]]; then
        logging_path=$(pwd)
    fi

    log_file="$logging_path/$logfile_filename"

    # Check if the log file exists. If not, create it.
    if [[ ! -f "$log_file" ]]; then
        touch "$log_file"
        log_message "info" "Log file created: $log_file."
    fi
fi

# Start the script with the selecting the guest operating system.
select_os

# Prompt the user to continue or quit.
while true; do
    if [[ "$downloaded" == true ]]; then
        print_message info "Download completed successfully for $dist $version $arch.\n"
    fi

    read -r -p $'\nWould you like to (\e[32mc\e[0m)ontinue or (\e[31mq\e[0m)uit? ' action
    log_message "info" "User selected: $action"
    case $action in
    [cC]*)
        cd "$script_path" || {
            printf "\n"
            print_message error "Failed to change to directory: \033[34m$script_path\033[0m"
            exit 1
        }
        exec "$0" "${restart_args[@]}"
        ;;
    [qQ]*) exit ;;
    esac
done

# TODO:
# - Add support for SUSE Enterprise Linux Server download.
