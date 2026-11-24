#!/usr/bin/env bash
# © Broadcom. All Rights Reserved.
# The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Sets the Packer environment variables so credentials stay out of configuration files.
#
# Usage (Bash or Zsh):
#
#   . ./set-envvars.sh
#
# - Press Enter to accept the value shown in brackets.
# - Leave other prompts blank to use the value from the configuration files.
# - Nothing changes until every prompt is answered.

if [ -n "${BASH_VERSION:-}" ]; then
    if [ "${BASH_SOURCE[0]}" = "$0" ]; then
        printf 'Error: This script must be sourced to set variables in the current shell:\n\n  . %s\n' "$0" >&2
        exit 1
    fi
elif [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in
    *:file*) ;;
    *)
        printf 'Error: This script must be sourced to set variables in the current shell:\n\n  . %s\n' "$0" >&2
        exit 1
        ;;
    esac
else
    printf 'Error: This script supports Bash and Zsh only.\n' >&2
    # shellcheck disable=SC2317 # exit runs when the file is executed.
    return 1 2>/dev/null || exit 1
fi

# The prompts in order, as kind|name|default|label.
#
# - header:          Starts a section.
# - gate:            Skips and clears the rest of the section when answered no.
# - text, secret:    Free text; secrets are hidden and masked.
# - bool:            y/n, exported as true/false.
# - int:MIN:MAX:     A whole number in the range.
# - enum:A,B:        One of the listed values.
# - duration:        A Packer duration, such as 20m.
# - ipv4, ipv4list:  An IPv4 address, or a comma-separated list exported as an HCL list.
# - directory:       An existing directory.
__pev_fields() {
    cat <<'FIELDS'
header|||Set the vSphere credentials.
text|vsphere_endpoint||Enter the FQDN of your vCenter instance.
text|vsphere_username||Enter the username for the user account.
secret|vsphere_password||Enter the password for the user account.
bool|vsphere_insecure_connection|false|Skip vCenter instance SSL verification?
header|||Set the vSphere settings.
text|vsphere_datacenter||Enter the vSphere datacenter name.
text|vsphere_cluster||Enter the vSphere cluster name.
text|vsphere_host||Enter the ESX host FQDN or IP.
text|vsphere_datastore||Enter the datastore name for virtual machines.
text|vsphere_network||Enter the network name.
text|vsphere_folder||Enter the folder name.
text|vsphere_resource_pool||Enter the resource pool name.
bool|vsphere_set_host_for_datastore_uploads|false|Set the host for datastore uploads?
header|||Set the common virtual machine settings.
int:1:99|common_vm_version|21|Enter the virtual hardware version.
bool|common_tools_upgrade_policy|true|Enable VMware Tools upgrade?
bool|common_remove_cdrom|true|Remove CD-ROMs?
header|||Set the common template and content library settings.
bool|common_template_conversion|false|Convert to a template?
bool|common_content_library_enabled|true|Import to a content library?
text|common_content_library||Enter the content library name.
bool|common_content_library_ovf|true|Import as an OVF template?
bool|common_content_library_destroy|true|Destroy the virtual machine after import?
bool|common_content_library_skip_export|false|Skip the import to the content library?
header|||Set the common OVF export settings.
bool|common_ovf_export_enabled|false|Export as an OVF artifact?
bool|common_ovf_export_overwrite|true|Overwrite an existing OVF artifact?
bool|common_ovf_export_image_files|true|Export OVF image files?
header|||Set the common removable media settings.
text|common_iso_datastore||Enter the datastore name for .iso files.
bool|common_iso_content_library_enabled|false|Use a content library for .iso files?
text|common_iso_content_library||Enter the content library name for .iso files.
header|||Set the common boot and provisioning settings.
enum:http,disk|common_data_source|http|Enter the provisioning data source (http or disk).
ipv4|common_http_ip||Enter the IP address of the interface on this host.
int:1:65535|common_http_port_min|8000|Enter the starting HTTP port.
int:1:65535|common_http_port_max|8099|Enter the ending HTTP port.
duration|common_ip_wait_timeout|20m|Enter the IP wait timeout.
duration|common_ip_settle_timeout|5s|Enter the IP settle timeout.
duration|common_shutdown_timeout|15m|Enter the virtual machine shutdown timeout in minutes.
header|||Set the virtual machine network settings for Linux builds.
gate|vm_static_ip|false|Use a static IP address instead of DHCP?
ipv4|vm_ip_address||Enter the IP address.
int:1:32|vm_ip_netmask||Enter the netmask prefix length (e.g., 24).
ipv4|vm_ip_gateway||Enter the gateway.
ipv4list|vm_dns_list||Enter the DNS servers, separated by commas.
header|||Set the proxy credentials.
gate|communicator_proxy|false|Use a SOCKS proxy?
text|communicator_proxy_host||Enter the FQDN or IP of the proxy.
int:1:65535|communicator_proxy_port||Enter the port for the proxy.
text|communicator_proxy_username||Enter the username for the proxy.
secret|communicator_proxy_password||Enter the password for the proxy.
header|||Set the default user account credentials.
text|build_username||Enter the username for the account.
secret|build_password||Enter the password for the account.
secret|build_password_encrypted||Enter the SHA-512 encrypted password for the account.
text|build_key||Enter the public key for the account.
header|||Set the Ansible credentials.
text|ansible_username|ansible|Enter the username for the account.
text|ansible_key||Enter the public key for the account
header|||Set the Red Hat Subscription Manager credentials.
gate|rhsm|false|Build Red Hat Enterprise Linux?
secret|rhsm_activation_key||Enter the activation key.
text|rhsm_organization||Enter the organization ID.
header|||Set the SUSE Customer Center credentials.
gate|scc|false|Build SUSE Linux Enterprise Server?
text|scc_email||Enter the email for the account.
secret|scc_code||Enter the code for the account.
header|||Set the HCP Packer registry.
bool|common_hcp_packer_registry_enabled|false|Enable the HCP Packer registry?
FIELDS
}

# Reads one answer, failing at the end of input.
__pev_read() {
    local label=$1 mode=$2 answer=''
    printf '%s' "$label" >&2
    if [ "$mode" = secret ]; then
        IFS= read -r -s answer || [ -n "$answer" ] || {
            printf '\n' >&2
            return 1
        }
        printf '\n' >&2
    else
        IFS= read -r answer || [ -n "$answer" ] || return 1
        answer=$(printf '%s' "$answer" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    fi
    printf '%s' "$answer"
}

# Prints the normalized value, failing if it is invalid.
__pev_normalize() {
    local kind=$1 value=$2 range min max ip list
    [ -n "$value" ] || return 0
    case "$kind" in
    bool | gate)
        case "$value" in
        [yY] | [yY][eE][sS] | [tT][rR][uU][eE]) printf 'true' ;;
        [nN] | [nN][oO] | [fF][aA][lL][sS][eE]) printf 'false' ;;
        *) return 1 ;;
        esac
        ;;
    int:*)
        range=${kind#int:}
        min=${range%%:*}
        max=${range#*:}
        printf '%s' "$value" | grep -Eq '^(0|[1-9][0-9]{0,8})$' || return 1
        [ "$value" -ge "$min" ] && [ "$value" -le "$max" ] || return 1
        printf '%s' "$value"
        ;;
    enum:*)
        case ",${kind#enum:}," in
        *",$value,"*) printf '%s' "$value" ;;
        *) return 1 ;;
        esac
        ;;
    duration)
        printf '%s' "$value" | grep -Eq '^([0-9]+(ns|us|ms|s|m|h))+$' || return 1
        printf '%s' "$value"
        ;;
    ipv4)
        __pev_is_ipv4 "$value" || return 1
        printf '%s' "$value"
        ;;
    ipv4list)
        list=''
        for ip in $(printf '%s' "$value" | tr ',' ' '); do
            __pev_is_ipv4 "$ip" || return 1
            list="$list${list:+,}\"$ip\""
        done
        printf '[%s]' "$list"
        ;;
    directory)
        [ -d "$value" ] || return 1
        printf '%s' "${value%/}"
        ;;
    *)
        printf '%s' "$value"
        ;;
    esac
}

__pev_is_ipv4() {
    printf '%s' "$1" | grep -Eq '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
}

__pev_hint() {
    local kind=$1 range
    case "$kind" in
    bool | gate) printf 'Enter y or n.' ;;
    int:*)
        range=${kind#int:}
        printf 'Enter a whole number from %s to %s.' "${range%%:*}" "${range#*:}"
        ;;
    enum:*) printf 'Enter one of: %s.' "$(printf '%s' "${kind#enum:}" | sed 's/,/, /g')" ;;
    duration) printf 'Enter a duration such as 30s, 20m, or 1h30m.' ;;
    ipv4) printf 'Enter an IPv4 address such as 172.16.100.192.' ;;
    ipv4list) printf 'Enter IPv4 addresses separated by commas.' ;;
    directory) printf 'Enter an existing directory.' ;;
    esac
}

# Prompts until the answer is valid, using the default for blank input.
__pev_ask() {
    local kind=$1 default=$2 label=$3 mode=text suffix answer value
    case "$kind" in
    secret) mode=secret ;;
    bool | gate) [ "$default" = true ] && suffix=' (y/n) [y]' || suffix=' (y/n) [n]' ;;
    *) [ -n "$default" ] && suffix=" [$default]" ;;
    esac
    while :; do
        answer=$(__pev_read "$label${suffix:-}: " "$mode") || return 1
        [ -n "$answer" ] || answer=$default
        if value=$(__pev_normalize "$kind" "$answer"); then
            printf '%s' "$value"
            return 0
        fi
        printf '  Invalid value. %s\n' "$(__pev_hint "$kind")" >&2
    done
}

# Applies the queued "set|NAME|value" and "unset|NAME|" lines.
__pev_apply() {
    local changes=$1 nl='
' line op var value set_count=0 unset_count=0
    while [ -n "$changes" ]; do
        line=${changes%%"$nl"*}
        changes=${changes#*"$nl"}
        op=${line%%|*}
        line=${line#*|}
        var=${line%%|*}
        value=${line#*|}
        if [ "$op" = set ]; then
            export "$var=$value"
            set_count=$((set_count + 1))
        else
            unset "$var"
            unset_count=$((unset_count + 1))
        fi
    done
    printf '\n> Set %s and cleared %s environment variables.\n' "$set_count" "$unset_count" >&2
}

__pev_display() {
    local kind name default label value
    printf '\nPacker Logging\n'
    for name in PACKER_LOG PACKER_LOG_PATH; do
        printf -- '- %s: %s\n' "$name" "$(printenv "$name" || printf '(not set)')"
    done
    while IFS='|' read -r kind name default label <&8; do
        case "$kind" in
        header) printf '\n%s\n' "$label" | sed 's/^Set the //; s/\.$//' ;;
        gate) ;;
        *)
            if ! value=$(printenv "PKR_VAR_$name"); then
                value='(not set)'
            elif [ "$kind" = secret ]; then
                value='********'
            fi
            printf -- '- PKR_VAR_%s: %s\n' "$name" "$value"
            ;;
        esac
    done 8< <(__pev_fields)
}

__pev_main() {
    local changes='' nl='
' kind name default label value skip=false
    printf 'Press Enter to accept the value in brackets.\n' >&2
    printf 'Leave other prompts blank to use the value from the configuration files.\n\n' >&2

    printf '> Set the Packer logging.\n' >&2
    value=$(__pev_ask bool false 'Enable logging for Packer?') || return 1
    if [ "$value" = true ]; then
        changes="${changes}set|PACKER_LOG|1$nl"
        value=$(__pev_ask directory '' 'Enter an existing directory for the log file (blank logs to the terminal)') || return 1
        if [ -n "$value" ]; then
            changes="${changes}set|PACKER_LOG_PATH|$value/packer.log$nl"
        else
            changes="${changes}unset|PACKER_LOG_PATH|$nl"
        fi
    else
        changes="${changes}unset|PACKER_LOG|${nl}unset|PACKER_LOG_PATH|$nl"
    fi

    while IFS='|' read -r kind name default label <&8; do
        case "$kind" in
        header)
            skip=false
            printf '\n> %s\n' "$label" >&2
            continue
            ;;
        gate)
            value=$(__pev_ask gate "$default" "$label") || return 1
            [ "$value" = true ] && skip=false || skip=true
            continue
            ;;
        esac
        if [ "$skip" = true ]; then
            value=''
        else
            value=$(__pev_ask "$kind" "$default" "$label") || return 1
        fi
        if [ -n "$value" ]; then
            changes="${changes}set|PKR_VAR_$name|$value$nl"
        else
            changes="${changes}unset|PKR_VAR_$name|$nl"
        fi
    done 8< <(__pev_fields)

    __pev_apply "$changes"

    printf '\n' >&2
    value=$(__pev_ask bool false 'Display the environment variables?') || value=false
    if [ "$value" = true ]; then
        __pev_display
    fi
}

if __pev_main; then
    __pev_rc=0
else
    __pev_rc=1
    printf '\n> Input ended before all prompts were answered. No variables were changed.\n' >&2
fi
unset -f __pev_fields __pev_read __pev_normalize __pev_is_ipv4 __pev_hint __pev_ask __pev_apply __pev_display __pev_main
eval "unset __pev_rc; return $__pev_rc"
