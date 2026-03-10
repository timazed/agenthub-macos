#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

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

  echo "Re-signing ${app_path} with Developer ID identity: ${identity}"
  /usr/bin/codesign --force --deep --options runtime --timestamp --sign "${identity}" "${app_path}"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${app_path}"
}

main "$@"
