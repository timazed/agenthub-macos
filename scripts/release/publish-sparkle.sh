#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

archive_name() {
  release_archive_name
}

archive_url() {
  echo "$(release_base_url)/$(archive_name)"
}

archive_path() {
  echo "$(release_artifacts_dir)/$(archive_name)"
}

write_placeholder_appcast() {
  eval "$("${SCRIPT_DIR}/read-version.sh" --shell)"

  local archive_file length pub_date
  archive_file="$(archive_name)"
  length="$(stat -f%z "$(archive_path)")"
  pub_date="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S GMT")"

  cat >"$(release_appcast_path)" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>AgentHub Updates</title>
    <link>$(release_base_url)</link>
    <description>AgentHub release feed</description>
    <language>en</language>
    <item>
      <title>${AGENTHUB_RELEASE_CURRENT_VERSION}</title>
      <pubDate>${pub_date}</pubDate>
      <enclosure
        url="$(archive_url)"
        sparkle:version="${AGENTHUB_RELEASE_CURRENT_BUILD}"
        sparkle:shortVersionString="${AGENTHUB_RELEASE_CURRENT_VERSION}"
        length="${length}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
}

generate_appcast() {
  local tools_dir

  if [[ -n "${AGENTHUB_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    tools_dir="$(sparkle_tools_dir)"
    if [[ -z "${tools_dir}" ]]; then
      echo "Unable to locate Sparkle tools directory" >&2
      exit 1
    fi
    "${tools_dir}/generate_appcast" \
      --ed-key-file "${AGENTHUB_SPARKLE_PRIVATE_KEY_FILE}" \
      --download-url-prefix "$(release_base_url)/" \
      -o "$(release_appcast_path)" \
      "$(release_artifacts_dir)"
    return
  fi

  if [[ -n "${AGENTHUB_SPARKLE_PRIVATE_KEY_SECRET:-}" ]]; then
    tools_dir="$(sparkle_tools_dir)"
    if [[ -z "${tools_dir}" ]]; then
      echo "Unable to locate Sparkle tools directory" >&2
      exit 1
    fi
    local key_file
    key_file="$(mktemp)"
    trap 'rm -f "${key_file}"' EXIT
    printf '%s' "${AGENTHUB_SPARKLE_PRIVATE_KEY_SECRET}" >"${key_file}"
    "${tools_dir}/generate_appcast" \
      --ed-key-file "${key_file}" \
      --download-url-prefix "$(release_base_url)/" \
      -o "$(release_appcast_path)" \
      "$(release_artifacts_dir)"
    return
  fi

  if ! release_dry_run; then
    fail_release_step \
      "publish-sparkle" \
      "missing Sparkle signing key. Set AGENTHUB_SPARKLE_PRIVATE_KEY_FILE or AGENTHUB_SPARKLE_PRIVATE_KEY_SECRET for non-dry-run releases."
  fi

  write_placeholder_appcast
}

publish_artifacts() {
  cp "$(archive_path)" "$(release_publish_dir)/"
  cp "$(release_appcast_path)" "$(release_publish_dir)/"
}

main() {
  prepare_release_directories
  mkdir -p "$(release_artifacts_dir)"

  local app_path
  app_path="$(release_app_path)"
  if [[ ! -d "${app_path}" ]]; then
    echo "Release app bundle not found at ${app_path}" >&2
    exit 1
  fi

  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "$(archive_path)"
  generate_appcast
  publish_artifacts

  echo "Published Sparkle artifacts to $(release_publish_dir)"
}

main "$@"
