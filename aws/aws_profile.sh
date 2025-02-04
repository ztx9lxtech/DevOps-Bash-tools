#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2024-09-17 03:24:18 +0200 (Tue, 17 Sep 2024)
#
#  https///github.com/HariSekhon/DevOps-Bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
. "$srcdir/lib/utils.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Switches to an AWS Profile selected from a convenient interactive menu list of AWS profiles to choose from

Parses \$AWS_CONFIG_FILE or \$HOME/.aws/config for the menu list

Skips the menu if there is only 1 AWS profile found in the config

Then sets the AWS_PROFILE and exec's to \$SHELL to inherit it

Convenient when you have lots of work AWS profiles


Requires dialogue menu CLI tool to be installed - attempts to install it via OS package manager if not already found
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="[<aws_config_path>]"

help_usage "$@"

max_args 1 "$@"

if ! type -P dialog &>/dev/null; then
    timestamp "Diaglog not found in \$PATH, attempting to install via OS package manager"
    echo
    "$srcdir/../packages/install_packages.sh" dialog
    echo
fi

[ -n "${HOME:-}" ] || HOME=~

config="${1:-${AWS_CONFIG_FILE:-$HOME/.aws/config}}"

aws_profile(){
    local profile="${1// }"
    if [ -n "$profile" ]; then
        if ! [[ "$profile" =~ ^[[:alnum:]_-]+$ ]]; then
            echo "invalid profile name given, must be alphanumeric, dashes and underscores allowed"
            return 1
        fi
        local profile_data
        profile_data="$(aws_get_profile_data "$profile")"
        [ -n "$profile_data" ] ||
        profile_data="$(aws_get_profile_data "$profile" "$config")"
        if [ -z "$profile_data" ]; then
            echo "profile [$profile] not found in $config!"
            return 1
        fi
        #aws_clean_env
        timestamp "Setting AWS_PROFILE='$profile'"
        export AWS_PROFILE="$profile"
    elif [ -n "$AWS_PROFILE" ]; then
        timestamp "AWS_PROFILE='$AWS_PROFILE' was already set"
    else
        die "ERROR: not setting AWS Profile (not found)"
    fi
}

aws_get_profile_data(){
    local profile="$1"
    local filename="${2:-$config}"
    sed -n "/^[[:space:]]*\\[\\(profile[[:space:]]*\\)*$profile\\]/,/^[[:space:]]*\\[/p" "$filename"
}

profiles="$(sed -n 's/^[[:space:]]*\[\(profile[[:space:]][[:space:]]*\)*\(.*\)\]/\2/p' "$config" | sort -fu)"

profile_menu_items=()

while read -r line; do

    # used for counting and string conversion if only a single item

    profile_menu_items+=("$line")

    # passed to dialog because it requires args: tag1 visibletext tag2 visibletext
    # - by making the second one blank it uses the item as both the tag to be returned
    # to script as well as the visible text

    profile_menu_tag_items+=("$line" " ")

done <<< "$profiles"

if [ "${#profile_menu_items[@]}" -eq 0 ];then
    die 'No AWS Profiles found!'
elif [ "${#profile_menu_items[@]}" -eq 1 ];then
    profile="${profile_menu_items[*]}"
else
    profile="$(dialog --menu "Choose which AWS profile to switch to:" "$LINES" "$COLUMNS" "$LINES" "${profile_menu_tag_items[@]}" 3>&1 1>&2 2>&3)"
fi

aws_profile "$profile"

exec "$SHELL"
