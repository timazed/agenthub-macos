#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

xcodebuild_arch_args() {
  if [[ -z "${AGENTHUB_TARGET_ARCH:-}" ]]; then
    return
  fi

  printf '%s\n' "ARCHS=${AGENTHUB_TARGET_ARCH}" "ONLY_ACTIVE_ARCH=YES"
}

resolve_packages() {
  local arch_args=()
  local cmd=()
  while IFS= read -r arg; do
    arch_args+=("${arg}")
  done < <(xcodebuild_arch_args)

  cmd=(
    "$(xcodebuild_bin)"
    -project "$(release_project)"
    -scheme "$(release_scheme)"
    -derivedDataPath "$(release_derived_data)"
  )
  if [[ "${#arch_args[@]}" -gt 0 ]]; then
    cmd+=("${arch_args[@]}")
  fi
  cmd+=(-resolvePackageDependencies)
  "${cmd[@]}"
}

build_app() {
  local arch_args=()
  local cmd=()
  while IFS= read -r arg; do
    arch_args+=("${arg}")
  done < <(xcodebuild_arch_args)

  cmd=(
    "$(xcodebuild_bin)"
    -project "$(release_project)"
    -scheme "$(release_scheme)"
    -configuration "$(release_configuration)"
    -derivedDataPath "$(release_derived_data)"
    -destination "platform=macOS"
    "AGENTHUB_SPARKLE_FEED_URL=$(release_feed_url)"
    "AGENTHUB_DEPENDENCY_MANIFEST=$(dependency_manifest)"
    "AGENTHUB_DEPENDENCY_CACHE_DIR=$(dependency_cache_dir)"
  )
  if [[ "${#arch_args[@]}" -gt 0 ]]; then
    cmd+=("${arch_args[@]}")
  fi
  cmd+=(build)
  "${cmd[@]}"
}

main() {
  prepare_release_directories
  bootstrap_dependencies

  resolve_packages
  build_app

  local built_app target_app
  built_app="$(release_derived_data)/Build/Products/$(release_configuration)/$(release_bundle_name)"
  target_app="$(release_app_path)"

  mkdir -p "$(dirname "${target_app}")"
  rm -rf "${target_app}"
  cp -R "${built_app}" "${target_app}"

  echo "Built release app at ${target_app}"
}

main "$@"
