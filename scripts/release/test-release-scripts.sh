#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

current_release_build() {
  bash "${SCRIPT_DIR}/read-version.sh" --value build
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "expected output to not contain: ${needle}"
  fi
}

setup_release_fixture() {
  local base_dir="$1"
  local app_path="${base_dir}/build/output/export/AgentHub.app"
  mkdir -p "${app_path}/Contents/MacOS"
  mkdir -p "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  mkdir -p "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  mkdir -p "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS"
  touch "${app_path}/Contents/MacOS/AgentHub"
  touch "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  touch "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
  ln -sfn B "${app_path}/Contents/Frameworks/Sparkle.framework/Versions/Current"
}

test_publish_requires_sparkle_key_for_real_releases() {
  local tmp_dir output status
  tmp_dir="$(mktemp -d)"
  setup_release_fixture "${tmp_dir}"

  set +e
  output="$(
    AGENTHUB_RELEASE_BUILD_DIR="${tmp_dir}/build" \
    AGENTHUB_RELEASE_OUTPUT_DIR="${tmp_dir}/build/output" \
    AGENTHUB_RELEASE_PUBLISH_DIR="${tmp_dir}/build/publish" \
    AGENTHUB_RELEASE_BASE_URL="https://updates.example.com/agenthub" \
    bash "${SCRIPT_DIR}/publish-sparkle.sh" 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    fail "publish-sparkle.sh succeeded without a Sparkle key"
  fi
  assert_contains "${output}" "missing Sparkle signing key"
  rm -rf "${tmp_dir}"
}

test_publish_dry_run_writes_placeholder_without_sparkle_key() {
  local tmp_dir output appcast_path current_build
  tmp_dir="$(mktemp -d)"
  setup_release_fixture "${tmp_dir}"
  current_build="$(current_release_build)"

  output="$(
    AGENTHUB_RELEASE_DRY_RUN=true \
    AGENTHUB_RELEASE_BUILD_DIR="${tmp_dir}/build" \
    AGENTHUB_RELEASE_OUTPUT_DIR="${tmp_dir}/build/output" \
    AGENTHUB_RELEASE_PUBLISH_DIR="${tmp_dir}/build/publish" \
    AGENTHUB_RELEASE_BASE_URL="https://updates.example.com/agenthub" \
    bash "${SCRIPT_DIR}/publish-sparkle.sh" 2>&1
  )"

  assert_contains "${output}" "Published Sparkle artifacts"
  appcast_path="${tmp_dir}/build/output/sparkle/appcast.xml"
  [[ -f "${appcast_path}" ]] || fail "expected placeholder appcast to be created"
  assert_contains "$(cat "${appcast_path}")" "sparkle:version=\"${current_build}\""
  rm -rf "${tmp_dir}"
}

test_collision_check_uses_build_number() {
  local tmp_dir pass_output fail_output status current_build
  tmp_dir="$(mktemp -d)"
  current_build="$(current_release_build)"

  cat >"${tmp_dir}/appcast-pass.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>1.0</title>
      <enclosure sparkle:version="999" sparkle:shortVersionString="1.0" />
    </item>
  </channel>
</rss>
EOF

  pass_output="$(
    AGENTHUB_RELEASE_APPCAST_SOURCE="${tmp_dir}/appcast-pass.xml" \
    bash "${SCRIPT_DIR}/check-version-collision.sh" 2>&1
  )"
  assert_contains "${pass_output}" "No version collision detected for build ${current_build}"

  cat >"${tmp_dir}/appcast-fail.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>9.9.9</title>
      <enclosure sparkle:version="CURRENT_BUILD_PLACEHOLDER" sparkle:shortVersionString="9.9.9" />
    </item>
  </channel>
</rss>
EOF

  CURRENT_BUILD="${current_build}" perl -0pi -e 's/CURRENT_BUILD_PLACEHOLDER/$ENV{CURRENT_BUILD}/g' "${tmp_dir}/appcast-fail.xml"

  set +e
  fail_output="$(
    AGENTHUB_RELEASE_APPCAST_SOURCE="${tmp_dir}/appcast-fail.xml" \
    bash "${SCRIPT_DIR}/check-version-collision.sh" 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    fail "check-version-collision.sh allowed a duplicate build number"
  fi
  assert_contains "${fail_output}" "Version collision detected for build ${current_build}"
  rm -rf "${tmp_dir}"
}

test_sign_release_uses_explicit_order_without_deep_signing() {
  local tmp_dir fake_codesign log_path output
  tmp_dir="$(mktemp -d)"
  setup_release_fixture "${tmp_dir}"
  log_path="${tmp_dir}/codesign.log"
  fake_codesign="${tmp_dir}/fake-codesign.sh"

  cat >"${fake_codesign}" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"${AGENTHUB_CODESIGN_LOG}"
exit 0
EOF
  chmod +x "${fake_codesign}"

  output="$(
    AGENTHUB_RELEASE_ENABLE_SIGNING=true \
    AGENTHUB_RELEASE_SIGNING_IDENTITY="Developer ID Application: Example" \
    AGENTHUB_RELEASE_BUILD_DIR="${tmp_dir}/build" \
    AGENTHUB_RELEASE_OUTPUT_DIR="${tmp_dir}/build/output" \
    AGENTHUB_CODESIGN_BIN="${fake_codesign}" \
    AGENTHUB_CODESIGN_LOG="${log_path}" \
    bash "${SCRIPT_DIR}/sign-release.sh" 2>&1
  )"

  assert_contains "${output}" "Re-signing"
  [[ -f "${log_path}" ]] || fail "expected fake codesign log to be written"

  local sign_lines
  sign_lines="$(head -n 5 "${log_path}")"
  assert_contains "${sign_lines}" "Downloader.xpc"
  assert_contains "${sign_lines}" "Installer.xpc"
  assert_contains "${sign_lines}" "Updater.app"
  assert_contains "${sign_lines}" "Autoupdate"
  assert_contains "${sign_lines}" "Sparkle.framework"
  assert_not_contains "$(head -n 6 "${log_path}")" "--deep --options runtime"
  assert_contains "$(tail -n 1 "${log_path}")" "--verify --deep --strict --verbose=2"
  rm -rf "${tmp_dir}"
}

main() {
  cd "${REPO_ROOT}"
  test_publish_requires_sparkle_key_for_real_releases
  test_publish_dry_run_writes_placeholder_without_sparkle_key
  test_collision_check_uses_build_number
  test_sign_release_uses_explicit_order_without_deep_signing
  echo "All release script tests passed"
}

main "$@"
