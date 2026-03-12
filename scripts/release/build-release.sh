#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

resolve_packages() {
  xcodebuild \
    -project "$(release_project)" \
    -scheme "$(release_scheme)" \
    -derivedDataPath "$(release_derived_data)" \
    -resolvePackageDependencies
}

build_app() {
  xcodebuild \
    -project "$(release_project)" \
    -scheme "$(release_scheme)" \
    -configuration "$(release_configuration)" \
    -derivedDataPath "$(release_derived_data)" \
    -destination "platform=macOS" \
    AGENTHUB_SPARKLE_FEED_URL="$(release_feed_url)" \
    build
}

main() {
  prepare_release_directories

  resolve_packages
  build_app

  local built_app target_app
  built_app="$(release_derived_data)/Build/Products/$(release_configuration)/$(release_bundle_name)"
  target_app="$(release_app_path)"

  mkdir -p "$(dirname "${target_app}")"
  rm -rf "${target_app}"
  cp -R "${built_app}" "${target_app}"

  echo "Built app at ${target_app}"
}

main "$@"
