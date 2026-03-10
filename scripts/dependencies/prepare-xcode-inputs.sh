#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dependencies/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"

main() {
  local manifest_path arch repo_root channel version stage_root frameworks_dir

  manifest_path="$(dependency_manifest_path)"
  arch="$(dependency_default_arch)"
  repo_root="$(dependency_repo_root)"
  channel="$(manifest_read_required '.default_channel' "${manifest_path}")"

  bash "${SCRIPT_DIR}/bootstrap.sh" --dependency all --manifest "${manifest_path}" --arch "${arch}"

  version="$(manifest_dependency_version cef "${channel}" "${manifest_path}")"
  stage_root="${repo_root}/$(manifest_dependency_staging_dir cef "${manifest_path}")/${version}/${arch}/Release"
  frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

  if [[ -d "${stage_root}" ]]; then
    mkdir -p "${frameworks_dir}"
    find "${stage_root}" -mindepth 1 -maxdepth 1 -exec cp -R {} "${frameworks_dir}/" \;
  fi
}

main "$@"
