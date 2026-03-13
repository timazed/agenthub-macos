#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

main() {
  prepare_release_directories

  echo "Starting AgentHub release pipeline"
  echo "Channel: $(release_channel)"
  echo "Project: $(release_project)"
  echo "Scheme: $(release_scheme)"
  echo "Configuration: $(release_configuration)"
  echo "Dry run: ${AGENTHUB_RELEASE_DRY_RUN:-false}"

  eval "$("${SCRIPT_DIR}/read-version.sh" --shell)"
  echo "Current version: ${AGENTHUB_RELEASE_CURRENT_VERSION} (${AGENTHUB_RELEASE_CURRENT_BUILD})"

  "${SCRIPT_DIR}/check-version-collision.sh"
  "${SCRIPT_DIR}/build-release.sh"
  "${SCRIPT_DIR}/sign-release.sh"
  "${SCRIPT_DIR}/notarize-release.sh"
  "${SCRIPT_DIR}/publish-sparkle.sh"
  "${SCRIPT_DIR}/bump-version.sh"
  "${SCRIPT_DIR}/commit-release.sh"
}

main "$@"
