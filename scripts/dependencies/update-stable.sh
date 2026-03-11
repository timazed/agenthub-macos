#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dependencies/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GITHUB_API_ROOT="${AGENTHUB_GITHUB_API_ROOT:-https://api.github.com}"
CODEX_RELEASES_API="${GITHUB_API_ROOT}/repos/openai/codex/releases?per_page=20"
CEF_INDEX_URL="${AGENTHUB_CEF_INDEX_URL:-https://cef-builds.spotifycdn.com/index.json}"
CEF_DOWNLOAD_ROOT="${AGENTHUB_CEF_DOWNLOAD_ROOT:-https://cef-builds.spotifycdn.com/}"

require_jq() {
  require_command jq
}

manifest_update_field() {
  local jq_filter="$1"
  local manifest_path="$2"
  local temp_path

  temp_path="$(mktemp)"
  "$(jq_bin)" "${jq_filter}" "${manifest_path}" >"${temp_path}"
  mv "${temp_path}" "${manifest_path}"
}

update_codex_manifest() {
  local manifest_path="$1"
  local releases_json release_json version url archive_path sha256 archive_type

  releases_json="$(mktemp)"
  /usr/bin/curl -fsSL "${CODEX_RELEASES_API}" -o "${releases_json}"
  release_json="$(
    "$(jq_bin)" -c '[.[] | select(.prerelease == false and .draft == false)][0]' "${releases_json}"
  )"

  version="$(printf '%s' "${release_json}" | "$(jq_bin)" -r '.tag_name | sub("^rust-v"; "") | sub("^v"; "")')"
  url="$(
    printf '%s' "${release_json}" |
      "$(jq_bin)" -r '.assets[] | select(.name | test("aarch64-apple-darwin") and test("\\.tar\\.gz$")) | .browser_download_url' |
      head -n 1
  )"

  if [[ -z "${url}" || "${url}" == "null" ]]; then
    echo "Unable to locate a stable macOS arm64 Codex asset" >&2
    exit 1
  fi

  archive_type="tar.gz"
  archive_path="$(mktemp)"
  download_file "${url}" "${archive_path}"
  sha256="$(sha256_file "${archive_path}")"

  manifest_update_field \
    ".dependencies.codex.channels.stable.version = \"${version}\" |
     .dependencies.codex.channels.stable.artifacts.arm64.url = \"${url}\" |
     .dependencies.codex.channels.stable.artifacts.arm64.sha256 = \"${sha256}\" |
     .dependencies.codex.channels.stable.artifacts.arm64.archive_type = \"${archive_type}\"" \
    "${manifest_path}"

  rm -f "${archive_path}" "${releases_json}"
}

update_cef_manifest() {
  local manifest_path="$1"
  local index_json version filename url archive_type archive_path sha256

  index_json="$(mktemp)"
  /usr/bin/curl -fsSL "${CEF_INDEX_URL}" -o "${index_json}"

  version="$(
    "$(jq_bin)" -r '
      .macosarm64.versions
      | map(select(.channel == "stable"))
      | .[0].cef_version
    ' "${index_json}"
  )"
  filename="$(
    "$(jq_bin)" -r '
      .macosarm64.versions
      | map(select(.channel == "stable"))
      | .[0].files
      | map(select(.type == "minimal"))
      | if length > 0 then .[0].name else empty end
    ' "${index_json}"
  )"

  if [[ -z "${version}" || "${version}" == "null" || -z "${filename}" || "${filename}" == "null" ]]; then
    echo "Unable to locate a stable macOS arm64 CEF artifact from ${CEF_INDEX_URL}" >&2
    exit 1
  fi

  url="${CEF_DOWNLOAD_ROOT}${filename}"
  archive_type="tar.bz2"
  archive_path="$(mktemp)"
  download_file "${url}" "${archive_path}"
  sha256="$(sha256_file "${archive_path}")"

  manifest_update_field \
    ".dependencies.cef.channels.stable.version = \"${version}\" |
     .dependencies.cef.channels.stable.artifacts.arm64.url = \"${url}\" |
     .dependencies.cef.channels.stable.artifacts.arm64.sha256 = \"${sha256}\" |
     .dependencies.cef.channels.stable.artifacts.arm64.archive_type = \"${archive_type}\"" \
    "${manifest_path}"

  rm -f "${archive_path}" "${index_json}"
}

main() {
  local manifest_path

  manifest_path="$(dependency_manifest_path)"
  require_jq
  update_codex_manifest "${manifest_path}"
  update_cef_manifest "${manifest_path}"
}

main "$@"
