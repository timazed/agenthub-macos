#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/dependencies/lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${BASH_SOURCE[0]%/*}/manifest.sh"

verify_dependency_archive() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local archive_path="$4"
  local manifest_path="${5:-$(dependency_manifest_path)}"
  local expected actual

  expected="$(manifest_dependency_value "${dependency_name}" "${channel}" "${arch}" "sha256" "${manifest_path}")"
  actual="$(sha256_file "${archive_path}")"

  if [[ "${expected}" != "${actual}" ]]; then
    echo "Checksum mismatch for ${dependency_name} ${channel} (${arch})" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual}" >&2
    exit 1
  fi
}
