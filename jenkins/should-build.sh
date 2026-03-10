#!/bin/bash

set -euo pipefail

BRANCH_REF="${AGENTHUB_JENKINS_BRANCH:-origin/main}"
LOOKBACK_HOURS="${AGENTHUB_JENKINS_LOOKBACK_HOURS:-24}"

latest_commit_epoch() {
  git log -1 --format=%ct "${BRANCH_REF}"
}

now_epoch() {
  date +%s
}

main() {
  local latest_epoch current_epoch diff_hours
  latest_epoch="$(latest_commit_epoch)"
  current_epoch="$(now_epoch)"
  diff_hours="$(((current_epoch - latest_epoch) / 3600))"

  if [[ "${diff_hours}" -lt "${LOOKBACK_HOURS}" ]]; then
    echo "Run it"
    exit 0
  fi

  echo "Nothing new in the last ${LOOKBACK_HOURS} hours"
  exit 1
}

main "$@"
