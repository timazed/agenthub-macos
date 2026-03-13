#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dependencies/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --dependency <all|codex|cef>  Dependency to stage (default: all)
  --manifest <path>             Override dependency manifest path
  --arch <arm64|x86_64>         Override target architecture
  -h, --help                    Show help
EOF
}

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
  local arch="$2"
  local manifest_path="$3"
  local version archive_type extension

  version="$(dependency_version "${dependency_name}" "${manifest_path}")"
  archive_type="$(dependency_artifact_value "${dependency_name}" "${arch}" "archive_type" "${manifest_path}")"
  extension="$(artifact_extension_for_type "${archive_type}")"
  echo "$(dependency_cache_dir)/${dependency_name}/${version}/${arch}.${extension}"
}

fetch_dependency_archive() {
  local dependency_name="$1"
  local arch="$2"
  local manifest_path="$3"
  local url cache_path

  url="$(dependency_artifact_value "${dependency_name}" "${arch}" "url" "${manifest_path}")"
  cache_path="$(artifact_cache_path "${dependency_name}" "${arch}" "${manifest_path}")"

  if [[ ! -f "${cache_path}" ]]; then
    echo "Downloading ${dependency_name} (${arch})" >&2
    download_file "${url}" "${cache_path}"
  fi

  echo "${cache_path}"
}

verify_dependency_archive() {
  local dependency_name="$1"
  local arch="$2"
  local archive_path="$3"
  local manifest_path="$4"
  local expected actual

  expected="$(dependency_artifact_value "${dependency_name}" "${arch}" "sha256" "${manifest_path}")"
  actual="$(sha256_file "${archive_path}")"

  if [[ "${expected}" != "${actual}" ]]; then
    echo "Checksum mismatch for ${dependency_name} (${arch})" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual}" >&2
    exit 1
  fi
}

stage_codex_dependency() {
  local extraction_dir="$1"
  local repo_root="$2"
  local output_path source_binary executable_count

  output_path="$(codex_binary_path "${repo_root}")"
  source_binary="$(find_first_named "${extraction_dir}" "${CODEX_BINARY_NAME}")"

  if [[ -z "${source_binary}" ]]; then
    source_binary="$(find "${extraction_dir}" -type f -perm -111 -name 'codex*' -print | head -n 1)"
  fi

  if [[ -z "${source_binary}" ]]; then
    executable_count="$(find "${extraction_dir}" -type f -perm -111 | wc -l | awk '{ print $1 }')"
    if [[ "${executable_count}" == "1" ]]; then
      source_binary="$(find "${extraction_dir}" -type f -perm -111 -print | head -n 1)"
    fi
  fi

  if [[ -z "${source_binary}" || ! -f "${source_binary}" ]]; then
    echo "Unable to locate Codex binary after extraction" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${output_path}")"
  cp "${source_binary}" "${output_path}"
  chmod 755 "${output_path}"
}

stage_cef_dependency() {
  local extraction_dir="$1"
  local repo_root="$2"
  local version="$3"
  local arch="$4"
  local release_dir support_dir stage_root current_root

  release_dir="$(find "${extraction_dir}" -type d -name Release -print | head -n 1)"
  if [[ -z "${release_dir}" || ! -d "${release_dir}" ]]; then
    echo "Unable to locate CEF Release directory after extraction" >&2
    exit 1
  fi

  support_dir="$(dirname "${release_dir}")"
  stage_root="$(cef_stage_dir "${repo_root}" "${version}" "${arch}")"
  current_root="$(cef_current_dir "${repo_root}" "${arch}")"

  rm -rf "${stage_root}" "${current_root}"
  mkdir -p "${stage_root}" "${current_root}"
  cp -R "${release_dir}" "${stage_root}/Release"
  cp -R "${release_dir}" "${current_root}/Release"

  if [[ -d "${support_dir}/Resources" ]]; then
    cp -R "${support_dir}/Resources" "${stage_root}/Resources"
    cp -R "${support_dir}/Resources" "${current_root}/Resources"
  fi
}

bootstrap_dependency() {
  local dependency_name="$1"
  local arch="$2"
  local manifest_path="$3"
  local repo_root="$4"
  local archive_path archive_type extraction_dir version

  archive_path="$(fetch_dependency_archive "${dependency_name}" "${arch}" "${manifest_path}")"
  verify_dependency_archive "${dependency_name}" "${arch}" "${archive_path}" "${manifest_path}"
  archive_type="$(dependency_artifact_value "${dependency_name}" "${arch}" "archive_type" "${manifest_path}")"
  version="$(dependency_version "${dependency_name}" "${manifest_path}")"
  extraction_dir="$(mktemp -d)"
  trap 'rm -rf "${extraction_dir}"' RETURN
  extract_archive "${archive_path}" "${extraction_dir}" "${archive_type}"

  case "${dependency_name}" in
    codex)
      stage_codex_dependency "${extraction_dir}" "${repo_root}"
      ;;
    cef)
      stage_cef_dependency "${extraction_dir}" "${repo_root}" "${version}" "${arch}"
      ;;
    *)
      echo "Unsupported dependency: ${dependency_name}" >&2
      exit 1
      ;;
  esac

  trap - RETURN
  rm -rf "${extraction_dir}"
}

main() {
  local dependency_name="all"
  local manifest_path arch repo_root

  manifest_path="$(dependency_manifest_path)"
  arch="$(dependency_default_arch)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dependency)
        dependency_name="$2"
        shift 2
        ;;
      --manifest)
        manifest_path="$2"
        shift 2
        ;;
      --arch)
        arch="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  require_command jq
  repo_root="$(dependency_repo_root)"

  case "${dependency_name}" in
    all)
      bootstrap_dependency codex "${arch}" "${manifest_path}" "${repo_root}"
      bootstrap_dependency cef "${arch}" "${manifest_path}" "${repo_root}"
      ;;
    codex|cef)
      bootstrap_dependency "${dependency_name}" "${arch}" "${manifest_path}" "${repo_root}"
      ;;
    *)
      echo "Unsupported dependency selection: ${dependency_name}" >&2
      exit 1
      ;;
  esac
}

main "$@"
