#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dependencies/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/dependencies/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"
# shellcheck source=scripts/dependencies/lib/fetch.sh
source "${SCRIPT_DIR}/lib/fetch.sh"
# shellcheck source=scripts/dependencies/lib/verify.sh
source "${SCRIPT_DIR}/lib/verify.sh"
# shellcheck source=scripts/dependencies/lib/stage.sh
source "${SCRIPT_DIR}/lib/stage.sh"

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

bootstrap_dependency() {
  local dependency_name="$1"
  local channel="$2"
  local arch="$3"
  local manifest_path="$4"
  local archive_path archive_type extraction_dir

  archive_path="$(fetch_dependency_archive "${dependency_name}" "${channel}" "${arch}" "${manifest_path}")"
  verify_dependency_archive "${dependency_name}" "${channel}" "${arch}" "${archive_path}" "${manifest_path}"
  archive_type="$(manifest_dependency_value "${dependency_name}" "${channel}" "${arch}" "archive_type" "${manifest_path}")"
  extraction_dir="$(mktemp -d)"
  trap 'rm -rf "${extraction_dir}"' RETURN
  extract_archive "${archive_path}" "${extraction_dir}" "${archive_type}"

  case "${dependency_name}" in
    codex)
      stage_codex_dependency "${extraction_dir}" "${manifest_path}" >/dev/null
      ;;
    cef)
      stage_cef_dependency "${extraction_dir}" "${channel}" "${arch}" "${manifest_path}" >/dev/null
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
  local manifest_path
  local arch
  local channel

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
  channel="$(manifest_read_required '.default_channel' "${manifest_path}")"

  case "${dependency_name}" in
    all)
      bootstrap_dependency codex "${channel}" "${arch}" "${manifest_path}"
      bootstrap_dependency cef "${channel}" "${arch}" "${manifest_path}"
      ;;
    codex|cef)
      bootstrap_dependency "${dependency_name}" "${channel}" "${arch}" "${manifest_path}"
      ;;
    *)
      echo "Unsupported dependency selection: ${dependency_name}" >&2
      exit 1
      ;;
  esac
}

main "$@"
