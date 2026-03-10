#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/dependencies/lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${BASH_SOURCE[0]%/*}/manifest.sh"

stage_codex_dependency() {
  local extraction_dir="$1"
  local manifest_path="${2:-$(dependency_manifest_path)}"
  local repo_root output_dir binary_name source_binary

  repo_root="$(dependency_repo_root)"
  output_dir="${repo_root}/$(manifest_dependency_resource_dir codex "${manifest_path}")"
  binary_name="$(manifest_dependency_resource_binary_name codex "${manifest_path}")"
  source_binary="$(find_first_named "${extraction_dir}" "${binary_name}")"

  if [[ -z "${source_binary}" || ! -f "${source_binary}" ]]; then
    echo "Unable to locate Codex binary after extraction" >&2
    exit 1
  fi

  mkdir -p "${output_dir}"
  cp "${source_binary}" "${output_dir}/${binary_name}"
  chmod 755 "${output_dir}/${binary_name}"
  echo "${output_dir}/${binary_name}"
}

stage_cef_dependency() {
  local extraction_dir="$1"
  local channel="$2"
  local arch="$3"
  local manifest_path="${4:-$(dependency_manifest_path)}"
  local repo_root version stage_root release_dir support_dir

  repo_root="$(dependency_repo_root)"
  version="$(manifest_dependency_version cef "${channel}" "${manifest_path}")"
  stage_root="${repo_root}/$(manifest_dependency_staging_dir cef "${manifest_path}")/${version}/${arch}"
  release_dir="$(find "${extraction_dir}" -type d -name Release -print | head -n 1)"

  if [[ -z "${release_dir}" || ! -d "${release_dir}" ]]; then
    echo "Unable to locate CEF Release directory after extraction" >&2
    exit 1
  fi

  support_dir="$(dirname "${release_dir}")"
  rm -rf "${stage_root}"
  mkdir -p "${stage_root}"
  cp -R "${release_dir}" "${stage_root}/Release"

  if [[ -d "${support_dir}/Resources" ]]; then
    cp -R "${support_dir}/Resources" "${stage_root}/Resources"
  fi

  if [[ -d "${support_dir}/Debug" ]]; then
    cp -R "${support_dir}/Debug" "${stage_root}/Debug"
  fi

  echo "${stage_root}"
}
