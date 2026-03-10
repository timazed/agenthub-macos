#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

fetch_appcast() {
  local source
  source="$(release_appcast_source)"

  if [[ -f "${source}" ]]; then
    cat "${source}"
    return 0
  fi

  curl -fsSL "${source}"
}

main() {
  eval "$("${SCRIPT_DIR}/read-version.sh" --shell)"

  if release_dry_run; then
    echo "Dry run: skipping version collision check"
    exit 0
  fi

  local appcast
  if ! appcast="$(fetch_appcast 2>/dev/null)"; then
    echo "No existing appcast found at $(release_appcast_source); treating this as the first published release"
    exit 0
  fi

  if grep -q "<title>${AGENTHUB_RELEASE_CURRENT_VERSION}</title>" <<<"${appcast}"; then
    echo "Version collision detected for ${AGENTHUB_RELEASE_CURRENT_VERSION}" >&2
    exit 1
  fi

  echo "No version collision detected for ${AGENTHUB_RELEASE_CURRENT_VERSION}"
}

main "$@"
