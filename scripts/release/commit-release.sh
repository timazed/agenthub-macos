#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

git_author_name() {
  echo "${AGENTHUB_BUILD_AUTHOR_NAME:-Jenkins Build Server}"
}

git_author_email() {
  echo "${AGENTHUB_BUILD_AUTHOR_EMAIL:-jenkins@example.com}"
}

git_branch() {
  echo "${AGENTHUB_RELEASE_GIT_BRANCH:-$(git branch --show-current)}"
}

main() {
  if release_dry_run; then
    echo "Dry run: skipping git commit and push"
    exit 0
  fi

  eval "$("${SCRIPT_DIR}/read-version.sh" --shell)"

  local project_file
  project_file="$(release_project)/project.pbxproj"

  git add "${project_file}"

  if git diff --cached --quiet; then
    echo "No release metadata changes to commit"
    exit 0
  fi

  local message
  message="$(printf '%s' "$(release_channel)" | tr '[:lower:]' '[:upper:]') release bump to ${AGENTHUB_RELEASE_CURRENT_VERSION} (${AGENTHUB_RELEASE_CURRENT_BUILD})"

  git -c user.name="$(git_author_name)" -c user.email="$(git_author_email)" commit -m "${message}"

  if [[ "${AGENTHUB_RELEASE_SKIP_GIT_PUSH:-false}" == "true" ]]; then
    echo "Skipping git push because AGENTHUB_RELEASE_SKIP_GIT_PUSH=true"
    exit 0
  fi

  git push "$(release_git_remote)" "$(git_branch)"
}

main "$@"
