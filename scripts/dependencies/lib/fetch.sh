#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/dependencies/lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${BASH_SOURCE[0]%/*}/manifest.sh"

artifact_extension_for_type() {
  local archive_type="$1"
  case "${archive_type}" in
    tar.gz|tgz)
      echo "tar.gz"
      ;;
    tar.bz2)
      echo "tar.bz2"
      ;;
    zip)
      echo "zip"
      ;;
    *)
      echo "Unsupported archive type: ${archive_type}" >&2
      exit 1
      ;;
  esac
}

artifact_cache_path() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local manifest_path="${4:-$(dependency_manifest_path)}"
  local version archive_type extension

  version="$(manifest_dependency_version "${dependency_name}" "${channel}" "${manifest_path}")"
  archive_type="$(manifest_dependency_value "${dependency_name}" "${channel}" "${arch}" "archive_type" "${manifest_path}")"
  extension="$(artifact_extension_for_type "${archive_type}")"
  echo "$(dependency_cache_dir)/${dependency_name}/${version}/${arch}.${extension}"
}

fetch_dependency_archive() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local manifest_path="${4:-$(dependency_manifest_path)}"
  local url cache_path

  url="$(manifest_dependency_value "${dependency_name}" "${channel}" "${arch}" "url" "${manifest_path}")"
  cache_path="$(artifact_cache_path "${dependency_name}" "${channel}" "${arch}" "${manifest_path}")"

  if [[ ! -f "${cache_path}" ]]; then
    echo "Downloading ${dependency_name} ${channel} (${arch})" >&2
    download_file "${url}" "${cache_path}"
  fi

  echo "${cache_path}"
}
