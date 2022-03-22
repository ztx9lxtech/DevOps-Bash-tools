#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2022-03-22 10:47:11 +0000 (Tue, 22 Mar 2022)
#
#  https://github.com/HariSekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(dirname "${BASH_SOURCE[0]}")"

# shellcheck disable=SC1090
. "$srcdir/lib/github.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Mirrors all or given repos from GitHub to GitLab via APIs and SSH mirror clones

Useful to create/sync GitHub backup repos on GitLab for DR purposes

Especially in dynamic environments where people are adding new repos, avoids having to maintain configurations as finds and iterates all non-fork repos by default
Can't use Terraform to dynamically create these backups because a simple commented/deleted code mistake would bypass prevent_destroy and delete your backup repos as well as your originals!

    https://github.com/hashicorp/terraform/issues/17599

Cron this script as per your preferred backup schedule

If no repos are given, iterates all non-fork repos for the current user or GitHub organization

Each repo will have the same name in GitLab as it does on GitHub, but characters other than alphanumeric/dash/underscores will be replaced by underscore,
and any leading special characters will be removed to meet GitLab's repo naming requirements eg. a repo called '.test' on GitHub will mirrored to just 'test' on GitLab

Requires \$GITHUB_TOKEN AND \$GITLAB_TOKEN to be set as well as a locally available SSH key for cloning/pull/push.
Set GIT_SSH_COMMAND='ssh -i ~/.ssh/some-other-private-key' if you need to customize the SSH behaviour such as specifying a particular SSH private key

In a GitHub Organization, only repos the user can read will be mirrored, others won't be returned in the list of GitHub repos to even try (as an outside collaborator user)

Source GitHub and Destination GitLab accounts, in order or priority:

    \$GITHUB_ORGANIZATION, \$GITHUB_USER or owner of the \$GITHUB_TOKEN
    \$GITLAB_OWNER, \$GITLAB_USER or the owner of the \$GITLAB_TOKEN
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="[<repo1> <repo2> <repo3> ...]"

check_env_defined "GITHUB_TOKEN"
check_env_defined "GITLAB_TOKEN"

help_usage "$@"

#min_args 1 "$@"

timestamp "Starting GitHub to GitLab mirroring"
echo >&2

owner="${GITHUB_ORGANIZATION:-${GITHUB_USER:-$(get_github_user)}}"
gitlab_owner="${GITLAB_OWNER:-${GITLAB_USER:-$("$srcdir/gitlab_api.sh" /user | jq -r .username)}}"

if is_blank "$owner"; then
    die "Failed to determine GitHub owner"
fi
if is_blank "$gitlab_owner"; then
    die "Failed to determine GitLab owner"
fi

#timestamp "Getting GitLab id in case we need to create any repos in GitLab"
#gitlab_id="$("$srcdir/gitlab_api.sh" "/users?username=$gitlab_owner" | jq -r '.[0].id')"
#echo >&2
#if is_blank "$gitlab_id"; then
#    die "Failed to determine GitLab id"
#fi

if [ $# -gt 0 ]; then
    repos="$*"
else
    timestamp "Getting list of all non-fork GitHub repos owned by '$owner'"
    repos="$(get_github_repos "$owner" "${GITHUB_ORGANIZATION:-}")"
    echo >&2
fi

# not using mktemp because we want to reuse this staging area between runs for efficiency
tmpdir="/tmp/github_to_gitlab_mirroring_$owner"

timestamp "Switching to '$tmpdir' directory for mirror staging"
mkdir -p -v "$tmpdir"
cd "$tmpdir"
echo >&2

succeeded=0
failed=0

mirror_repo(){
    local repo="$1"
    # GitLab doesn't allow repo name like .github, only alnum, dashes and underscores, and not starting with unusual characters either
    gitlab_repo="$(sed 's/[^[:alnum:]_-]/_/g; s/^[^[:alnum:]]*//' <<< "$repo")"
    gitlab_owner_repo="$("$srcdir/urlencode.sh" <<< "$gitlab_owner/$gitlab_repo")"
    timestamp "Checking GitLab repo '$gitlab_owner/$gitlab_repo' exists"
    if ! "$srcdir/gitlab_api.sh" "/projects/$gitlab_owner_repo" >/dev/null; then
        timestamp "Creating GitLab repo '$gitlab_owner/$gitlab_repo'"
        # only available for admins
        #"$srcdir/gitlab_api.sh" "/projects/user/$gitlab_id" -X POST -d "{ \"name\": \"$gitlab_repo\", \"visibility\": \"private\" }" >/dev/null
        "$srcdir/gitlab_api.sh" "/projects" -X POST -d "{ \"name\": \"$gitlab_repo\", \"visibility\": \"private\" }" >/dev/null
        echo >&2
    fi
    if [ -d "$repo.git" ]; then
        timestamp "Using existing clone in directory '$repo.git'"
        pushd "$repo.git" >/dev/null || return 1
        git remote update origin || return 1
    else
        timestamp "Cloning GitHub repo to directory '$repo.git'"
        git clone --mirror "git@github.com:$owner/$repo.git" || return 1
        pushd "$repo.git" >/dev/null || return 1
    fi
    if ! git remotes -v | awk '{print $1}' | grep -Fxq gitlab; then
        timestamp "Adding GitLab remote origin"
        git remotes add gitlab git@gitlab.com:"$gitlab_owner/$gitlab_repo"
        echo >&2
    fi
    timestamp "Pushing all branches to GitLab"
    git push --all gitlab || return 1  # XXX: without return 1 the function ignores errors, even with set -e inside the function
    timestamp "Pushing all tags to GitLab"
    git push --tags gitlab || return 1
    # more dangerous, force overwrites remote repo refs
    #git push --mirror gitlab || return 1
    popd >/dev/null || return 1
    echo >&2
    ((succeeded+=1))
}

for repo in $repos; do
    if ! mirror_repo "$repo"; then
        echo >&2
        timestamp "ERROR: Failed to mirror repo '$repo' to GitLab" >&2
        echo >&2
        ((failed+=1))
    fi
done

if [ $failed -gt 0 ]; then
    timestamp "ERROR: $failed GitHub repos failed to mirror to GitLab ($succeeded succeeded)"
    exit 1
fi

timestamp "GitHub to GitLab mirroring completed successfully for $succeeded repos"
