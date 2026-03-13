#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

main() {
  if release_dry_run; then
    echo "Dry run enabled; skipping notarization"
    return 0
  fi

  if ! signing_enabled; then
    fail_release_step \
      "notarize-release" \
      "release signing is disabled. Provision Developer ID signing and notarization credentials before running a non-dry-run release."
  fi

  local key_id issuer_id key_path app_path notarization_archive
  key_id="$(release_notary_key_id)"
  issuer_id="$(release_notary_issuer_id)"
  key_path="$(release_notary_key_path)"
  app_path="$(release_app_path)"
  notarization_archive="$(release_notarization_archive_path)"

  if [[ -z "${key_id}" ]]; then
    fail_release_step "notarize-release" "missing AGENTHUB_NOTARY_KEY_ID"
  fi

  if [[ -z "${issuer_id}" ]]; then
    fail_release_step "notarize-release" "missing AGENTHUB_NOTARY_ISSUER_ID"
  fi

  if [[ -z "${key_path}" ]]; then
    fail_release_step "notarize-release" "missing AGENTHUB_NOTARY_KEY_PATH"
  fi

  require_file "${key_path}"

  if [[ ! -d "${app_path}" ]]; then
    fail_release_step "notarize-release" "app bundle not found at ${app_path}"
  fi

  rm -f "${notarization_archive}"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${notarization_archive}"

  echo "Submitting ${notarization_archive} for notarization"
  /usr/bin/xcrun notarytool submit "${notarization_archive}" \
    --key "${key_path}" \
    --key-id "${key_id}" \
    --issuer "${issuer_id}" \
    --wait

  echo "Stapling notarization ticket to ${app_path}"
  /usr/bin/xcrun stapler staple "${app_path}"
}

main "$@"
