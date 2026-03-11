#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dependencies/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"

codesign_bin() {
  if [[ -n "${AGENTHUB_CODESIGN_BIN:-}" ]]; then
    echo "${AGENTHUB_CODESIGN_BIN}"
    return
  fi

  echo "/usr/bin/codesign"
}

sign_if_present() {
  local path="$1"
  local identity="$2"

  if [[ ! -e "${path}" ]]; then
    return
  fi

  "$(codesign_bin)" --force --sign "${identity}" --timestamp=none "${path}"
}

sign_cef_nested_binaries() {
  local framework_path="$1"
  local identity="$2"
  local path

  if [[ ! -d "${framework_path}" ]]; then
    return
  fi

  while IFS= read -r path; do
    sign_if_present "${path}" "${identity}"
  done < <(find "${framework_path}/Versions" -type f \( -path '*/Libraries/*' -o -name 'Chromium Embedded Framework' \) | sort)
}

normalize_cef_framework_layout() {
  local framework_path="$1"
  local version_dir

  if [[ -d "${framework_path}/Versions" ]]; then
    return
  fi

  version_dir="${framework_path}/Versions/A"
  mkdir -p "${version_dir}"

  if [[ -e "${framework_path}/Chromium Embedded Framework" && ! -L "${framework_path}/Chromium Embedded Framework" ]]; then
    mv "${framework_path}/Chromium Embedded Framework" "${version_dir}/Chromium Embedded Framework"
  fi

  if [[ -d "${framework_path}/Libraries" && ! -L "${framework_path}/Libraries" ]]; then
    mv "${framework_path}/Libraries" "${version_dir}/Libraries"
  fi

  if [[ -d "${framework_path}/Resources" && ! -L "${framework_path}/Resources" ]]; then
    mv "${framework_path}/Resources" "${version_dir}/Resources"
  fi

  ln -sfn A "${framework_path}/Versions/Current"
  ln -sfn "Versions/Current/Chromium Embedded Framework" "${framework_path}/Chromium Embedded Framework"
  ln -sfn "Versions/Current/Libraries" "${framework_path}/Libraries"
  ln -sfn "Versions/Current/Resources" "${framework_path}/Resources"
}

sign_staged_dependencies() {
  local frameworks_dir="$1"
  local identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  local path

  if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" || -z "${identity}" || "${identity}" == "-" ]]; then
    return
  fi

  while IFS= read -r path; do
    sign_if_present "${path}" "${identity}"
  done < <(find "${frameworks_dir}" -maxdepth 1 -type d -name '*.xpc' -print | sort)

  while IFS= read -r path; do
    sign_if_present "${path}" "${identity}"
  done < <(find "${frameworks_dir}" -maxdepth 1 -type d -name '*Helper*.app' -print | sort)

  sign_cef_nested_binaries "${frameworks_dir}/Chromium Embedded Framework.framework" "${identity}"
  sign_if_present "${frameworks_dir}/Chromium Embedded Framework.framework" "${identity}"
}

main() {
  local manifest_path arch repo_root stage_root frameworks_dir codex_binary path copied_framework

  manifest_path="$(dependency_manifest_path)"
  arch="$(dependency_default_arch)"
  repo_root="$(dependency_repo_root)"
  bash "${SCRIPT_DIR}/bootstrap.sh" --dependency all --manifest "${manifest_path}" --arch "${arch}" >/dev/null
  codex_binary="${repo_root}/$(manifest_dependency_resource_dir codex "${manifest_path}")/$(manifest_dependency_resource_binary_name codex "${manifest_path}")"
  stage_root="${repo_root}/$(manifest_dependency_staging_dir cef "${manifest_path}")/current/${arch}/Release"
  frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

  if [[ ! -f "${codex_binary}" ]]; then
    echo "Missing staged Codex binary at ${codex_binary}. Run scripts/dependencies/bootstrap.sh before building." >&2
    exit 1
  fi

  if [[ ! -d "${stage_root}" ]]; then
    echo "Missing staged CEF release payload at ${stage_root}. Run scripts/dependencies/bootstrap.sh before building." >&2
    exit 1
  fi

  mkdir -p "${frameworks_dir}"
  rm -rf \
    "${frameworks_dir}/Chromium Embedded Framework.framework" \
    "${frameworks_dir}"/*Helper*.app \
    "${frameworks_dir}"/*.xpc
  while IFS= read -r path; do
    cp -R "${path}" "${frameworks_dir}/"
  done < <(find "${stage_root}" -mindepth 1 -maxdepth 1 -print | sort)
  copied_framework="${frameworks_dir}/Chromium Embedded Framework.framework"
  normalize_cef_framework_layout "${copied_framework}"
  sign_staged_dependencies "${frameworks_dir}"
}

main "$@"
