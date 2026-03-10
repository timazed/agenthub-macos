#!/bin/bash

set -euo pipefail

repo_root() {
  git rev-parse --show-toplevel
}

release_channel() {
  echo "${AGENTHUB_RELEASE_CHANNEL:-release}"
}

release_derived_data() {
  echo "${AGENTHUB_RELEASE_DERIVED_DATA:-/tmp/agenthub-release-derived}"
}

release_build_dir() {
  echo "${AGENTHUB_RELEASE_BUILD_DIR:-$(repo_root)/build/release}"
}

release_output_dir() {
  echo "${AGENTHUB_RELEASE_OUTPUT_DIR:-$(release_build_dir)/output}"
}

release_publish_dir() {
  echo "${AGENTHUB_RELEASE_PUBLISH_DIR:-$(release_build_dir)/publish}"
}

release_scheme() {
  echo "${AGENTHUB_RELEASE_SCHEME:-AgentHub}"
}

release_configuration() {
  echo "${AGENTHUB_RELEASE_CONFIGURATION:-Release}"
}

release_project() {
  echo "${AGENTHUB_RELEASE_PROJECT:-AgentHub.xcodeproj}"
}

release_project_file() {
  echo "$(repo_root)/$(release_project)/project.pbxproj"
}

release_bundle_name() {
  echo "${AGENTHUB_RELEASE_PRODUCT_NAME:-AgentHub.app}"
}

release_bundle_identifier() {
  echo "${AGENTHUB_RELEASE_PRODUCT_BUNDLE_IDENTIFIER:-au.com.roseadvisory.AgentHub}"
}

release_archive_path() {
  echo "$(release_output_dir)/AgentHub.xcarchive"
}

release_export_path() {
  echo "$(release_output_dir)/export"
}

release_app_path() {
  echo "$(release_export_path)/$(release_bundle_name)"
}

release_artifacts_dir() {
  echo "$(release_output_dir)/sparkle"
}

release_appcast_path() {
  echo "$(release_artifacts_dir)/appcast.xml"
}

release_archive_name() {
  echo "${AGENTHUB_RELEASE_ARCHIVE_NAME:-AgentHub-$("${BASH_SOURCE[0]%/*}/read-version.sh" --value version 2>/dev/null || echo unknown)-$("${BASH_SOURCE[0]%/*}/read-version.sh" --value build 2>/dev/null || echo unknown).zip}"
}

release_notarization_archive_path() {
  echo "$(release_artifacts_dir)/AgentHub-notarization.zip"
}

release_dry_run() {
  [[ "${AGENTHUB_RELEASE_DRY_RUN:-false}" == "true" ]]
}

release_base_url() {
  echo "${AGENTHUB_RELEASE_BASE_URL:-https://updates.example.com/agenthub}"
}

release_feed_url() {
  echo "${AGENTHUB_RELEASE_FEED_URL:-$(release_base_url)/appcast.xml}"
}

release_appcast_source() {
  echo "${AGENTHUB_RELEASE_APPCAST_SOURCE:-$(release_feed_url)}"
}

release_git_remote() {
  echo "${AGENTHUB_GIT_REMOTE:-origin}"
}

signing_enabled() {
  [[ "${AGENTHUB_RELEASE_ENABLE_SIGNING:-false}" == "true" ]]
}

release_signing_identity() {
  echo "${AGENTHUB_RELEASE_SIGNING_IDENTITY:-}"
}

release_notary_key_id() {
  echo "${AGENTHUB_NOTARY_KEY_ID:-}"
}

release_notary_issuer_id() {
  echo "${AGENTHUB_NOTARY_ISSUER_ID:-}"
}

release_notary_key_path() {
  echo "${AGENTHUB_NOTARY_KEY_PATH:-}"
}

fail_release_step() {
  local step="$1"
  local reason="$2"
  echo "${step}: ${reason}" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    exit 1
  fi
}

prepare_release_directories() {
  mkdir -p "$(release_build_dir)"
  mkdir -p "$(release_output_dir)"
  mkdir -p "$(release_publish_dir)"
  mkdir -p "$(release_artifacts_dir)"
}

sparkle_tools_dir() {
  if [[ -n "${AGENTHUB_SPARKLE_TOOLS_DIR:-}" ]]; then
    echo "${AGENTHUB_SPARKLE_TOOLS_DIR}"
    return
  fi

  local artifact_dir
  artifact_dir="$(release_derived_data)/SourcePackages/artifacts/sparkle/Sparkle/bin"
  if [[ -d "${artifact_dir}" ]]; then
    echo "${artifact_dir}"
    return
  fi

  local repo_cached_dir
  repo_cached_dir="$(repo_root)/build/xcode-debug/SourcePackages/artifacts/sparkle/Sparkle/bin"
  if [[ -d "${repo_cached_dir}" ]]; then
    echo "${repo_cached_dir}"
    return
  fi

  echo ""
}
