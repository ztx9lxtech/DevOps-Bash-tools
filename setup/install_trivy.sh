#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2022-01-10 19:07:22 +0000 (Mon, 10 Jan 2022)
#
#  https://github.com/HariSekhon/DevOps-Bash-tools
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

# shellcheck disable=SC1090
. "$srcdir/../lib/utils.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Installs Trivy by AquaSec
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args=""

help_usage "$@"

#min_args 1 "$@"

#version="${1:-0.22.0}"
version="${1:-latest}"

owner_repo="aquasecurity/trivy"

if [ "$version" = latest ]; then
    timestamp "determining latest version of '$owner_repo' via GitHub API"
    version="$("$srcdir/../github_repo_latest_release.sh" "$owner_repo")"
    timestamp "latest version is '$version'"
else
    is_semver "$version" || die "non-semver version argument given: '$version' - should be in format: N.N.N"
    [[ "$version" =~ ^v ]] || version="v$version"
fi

os="$(uname -s)"
arch="$(uname -m)"

if [ "$os" = Darwin ]; then
    os="macOS"
fi

if [ "$arch" = x86_64 ]; then
    arch="64bit"
elif [ "$arch" = i386 ]; then
    arch="32bit"
elif [[ "$arch" =~ arm ]]; then
    arch="$(tr '[:lower:]' '[:upper:]' <<< "$arch")"
else
    die "unsupported architecture detected: $arch"
fi

export RUN_VERSION_OPT=1

"$srcdir/../install_binary.sh" "https://github.com/$owner_repo/releases/download/$version/trivy_${version#v}_${os}-${arch}.tar.gz" trivy
