#!/bin/bash

set -euo pipefail

dependency_repo_root() {
  if [[ -n "${AGENTHUB_DEPENDENCY_REPO_ROOT:-}" ]]; then
    echo "${AGENTHUB_DEPENDENCY_REPO_ROOT}"
    return
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(cd "${script_dir}/../../.." && pwd)"
}

dependency_manifest_path() {
  if [[ -n "${AGENTHUB_DEPENDENCY_MANIFEST:-}" ]]; then
    echo "${AGENTHUB_DEPENDENCY_MANIFEST}"
    return
  fi

  echo "$(dependency_repo_root)/scripts/dependencies/manifest.json"
}

dependency_default_arch() {
  if [[ -n "${AGENTHUB_TARGET_ARCH:-}" ]]; then
    echo "${AGENTHUB_TARGET_ARCH}"
    return
  fi

  local machine
  machine="$(uname -m)"
  case "${machine}" in
    arm64|aarch64)
      echo "arm64"
      ;;
    x86_64)
      echo "x86_64"
      ;;
    *)
      echo "${machine}"
      ;;
  esac
}

dependency_cache_dir() {
  if [[ -n "${AGENTHUB_DEPENDENCY_CACHE_DIR:-}" ]]; then
    echo "${AGENTHUB_DEPENDENCY_CACHE_DIR}"
    return
  fi

  echo "$(dependency_repo_root)/build/dependency-cache"
}

ensure_parent_dir() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

jq_bin() {
  require_command jq
  command -v jq
}

sha256_file() {
  local file_path="$1"
  /usr/bin/shasum -a 256 "${file_path}" | awk '{ print $1 }'
}

download_file() {
  local url="$1"
  local output_path="$2"
  ensure_parent_dir "${output_path}"
  /usr/bin/curl -fsSL "${url}" -o "${output_path}"
}

extract_archive() {
  local archive_path="$1"
  local destination_dir="$2"
  local archive_type="$3"

  rm -rf "${destination_dir}"
  mkdir -p "${destination_dir}"

  case "${archive_type}" in
    tar.gz|tgz)
      /usr/bin/tar -xzf "${archive_path}" -C "${destination_dir}"
      ;;
    tar.bz2)
      /usr/bin/tar -xjf "${archive_path}" -C "${destination_dir}"
      ;;
    zip)
      /usr/bin/ditto -x -k "${archive_path}" "${destination_dir}"
      ;;
    *)
      echo "Unsupported archive type: ${archive_type}" >&2
      exit 1
      ;;
  esac
}

find_first_named() {
  local root_dir="$1"
  local name="$2"
  find "${root_dir}" -type f -name "${name}" -print | head -n 1
}
