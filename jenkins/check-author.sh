#!/bin/bash

set -euo pipefail

BUILD_AUTHOR_NAME="${AGENTHUB_BUILD_AUTHOR_NAME:-Jenkins Build Server}"

latest_committer() {
  git log -1 --pretty=format:%an
}

main() {
  local committer
  committer="$(latest_committer)"

  if [[ "${committer}" != "${BUILD_AUTHOR_NAME}" ]]; then
    echo "Fresh commit!"
    exit 0
  fi

  echo "Last commit by build server!"
  exit 1
}

main "$@"
