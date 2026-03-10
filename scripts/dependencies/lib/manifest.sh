#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/dependencies/lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"

manifest_read_required() {
  local expression="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  local value

  value="$(/opt/homebrew/bin/jq -r "${expression}" "${manifest_path}")"
  if [[ -z "${value}" || "${value}" == "null" ]]; then
    echo "Manifest value is missing for expression: ${expression}" >&2
    exit 1
  fi

  echo "${value}"
}

manifest_read_optional() {
  local expression="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  /opt/homebrew/bin/jq -r "${expression} // empty" "${manifest_path}"
}

manifest_dependency_version() {
  local dependency_name="$1"
  local channel="$2"
  local manifest_path="${3:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.channels.${channel}.version" "${manifest_path}"
}

manifest_dependency_value() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local key="$4"
  local manifest_path="${5:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.channels.${channel}.artifacts.${arch}.${key}" "${manifest_path}"
}

manifest_dependency_optional_value() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local key="$4"
  local manifest_path="${5:-$(dependency_manifest_path)}"
  manifest_read_optional ".dependencies.${dependency_name}.channels.${channel}.artifacts.${arch}.${key}" "${manifest_path}"
}

manifest_dependency_install_mode() {
  local dependency_name="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.install_mode" "${manifest_path}"
}

manifest_dependency_resource_dir() {
  local dependency_name="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.resource_dir" "${manifest_path}"
}

manifest_dependency_resource_binary_name() {
  local dependency_name="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.resource_binary_name" "${manifest_path}"
}

manifest_dependency_staging_dir() {
  local dependency_name="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  manifest_read_required ".dependencies.${dependency_name}.staging_dir" "${manifest_path}"
}
