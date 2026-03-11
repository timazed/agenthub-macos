#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

codesign_path() {
  local path="$1"
  local identity="$2"

  echo "Signing ${path}"
  "$(codesign_bin)" --force --options runtime --timestamp --sign "${identity}" "${path}"
}

sign_if_present() {
  local path="$1"
  local identity="$2"
  if [[ -e "${path}" ]]; then
    codesign_path "${path}" "${identity}"
  fi
}

sign_cef_framework_contents_if_present() {
  local framework_path="$1"
  local identity="$2"
  local path

  if [[ ! -d "${framework_path}" ]]; then
    return 0
  fi

  while IFS= read -r path; do
    sign_if_present "${path}" "${identity}"
  done < <(find "${framework_path}/Versions" -type f \( -path '*/Libraries/*' -o -name 'Chromium Embedded Framework' \) | sort)
}

sign_cef_if_present() {
  local app_path="$1"
  local identity="$2"
  local frameworks_dir helper framework_path

  frameworks_dir="${app_path}/Contents/Frameworks"
  if [[ ! -d "${frameworks_dir}" ]]; then
    return 0
  fi

  while IFS= read -r helper; do
    sign_if_present "${helper}" "${identity}"
  done < <(find "${frameworks_dir}" -maxdepth 1 -type d -name '*Helper*.app' | sort)

  while IFS= read -r helper; do
    sign_if_present "${helper}" "${identity}"
  done < <(find "${frameworks_dir}" -maxdepth 1 -type d -name '*.xpc' | sort)

  framework_path="${frameworks_dir}/Chromium Embedded Framework.framework"
  sign_cef_framework_contents_if_present "${framework_path}" "${identity}"
  sign_if_present "${framework_path}" "${identity}"
}

main() {
  if release_dry_run; then
    echo "Dry run enabled; skipping release signing"
    return 0
  fi

  if ! signing_enabled; then
    fail_release_step \
      "sign-release" \
      "release signing is disabled. Set AGENTHUB_RELEASE_ENABLE_SIGNING=true after provisioning the Jenkins macOS signing environment."
  fi

  local app_path
  app_path="$(release_app_path)"
  if [[ ! -d "${app_path}" ]]; then
    fail_release_step "sign-release" "app bundle not found at ${app_path}"
  fi

  local identity
  identity="$(release_signing_identity)"
  if [[ -z "${identity}" ]]; then
    fail_release_step "sign-release" "missing AGENTHUB_RELEASE_SIGNING_IDENTITY"
  fi

  local sparkle_framework sparkle_current
  sparkle_framework="${app_path}/Contents/Frameworks/Sparkle.framework"
  sparkle_current="${sparkle_framework}/Versions/Current"

  echo "Re-signing ${app_path} with Developer ID identity: ${identity}"
  sign_if_present "${sparkle_current}/XPCServices/Downloader.xpc" "${identity}"
  sign_if_present "${sparkle_current}/XPCServices/Installer.xpc" "${identity}"
  sign_if_present "${sparkle_current}/Updater.app" "${identity}"
  sign_if_present "${sparkle_current}/Autoupdate" "${identity}"
  sign_if_present "${sparkle_framework}" "${identity}"
  sign_cef_if_present "${app_path}" "${identity}"
  codesign_path "${app_path}" "${identity}"
  "$(codesign_bin)" --verify --deep --strict --verbose=2 "${app_path}"
}

main "$@"
