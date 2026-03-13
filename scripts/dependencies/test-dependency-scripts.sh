#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}'"
  fi
}

assert_exists() {
  local path="$1"
  [[ -e "${path}" ]] || fail "expected path to exist: ${path}"
}

run_dependency_default_arch() {
  local script_path="$1"
  shift
  env "$@" bash -lc '
    source "$1"
    dependency_default_arch
  ' bash "${script_path}"
}

make_codex_archive() {
  local root="$1"
  local fixture_dir="${root}/codex-source"
  mkdir -p "${fixture_dir}/codex"
  cat >"${fixture_dir}/codex/codex" <<'EOF'
#!/bin/bash
echo "codex fixture"
EOF
  chmod +x "${fixture_dir}/codex/codex"
  tar -czf "${root}/codex.tar.gz" -C "${fixture_dir}" codex
}

make_cef_archive() {
  local root="$1"
  local fixture_dir="${root}/cef-source/cef_binary_fixture_macosarm64_minimal"
  mkdir -p "${fixture_dir}/Release/Chromium Embedded Framework.framework"
  mkdir -p "${fixture_dir}/Release/Chromium Embedded Framework.framework/Resources"
  mkdir -p "${fixture_dir}/Release/Chromium Embedded Framework.framework/Libraries"
  mkdir -p "${fixture_dir}/Release/AgentHub Helper.app/Contents/MacOS"
  mkdir -p "${fixture_dir}/Release/AgentHub Helper (Alerts).xpc/Contents/MacOS"
  mkdir -p "${fixture_dir}/Resources"
  touch "${fixture_dir}/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
  touch "${fixture_dir}/Release/Chromium Embedded Framework.framework/Libraries/libEGL.dylib"
  touch "${fixture_dir}/Release/AgentHub Helper.app/Contents/MacOS/AgentHub Helper"
  touch "${fixture_dir}/Release/AgentHub Helper (Alerts).xpc/Contents/MacOS/AgentHub Helper (Alerts)"
  cat >"${fixture_dir}/Release/Chromium Embedded Framework.framework/Resources/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Chromium Embedded Framework</string>
  <key>CFBundleIdentifier</key>
  <string>org.cef.framework.fixture</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
</dict>
</plist>
EOF
  touch "${fixture_dir}/Resources/icudtl.dat"
  tar -cjf "${root}/cef.tar.bz2" -C "${root}/cef-source" cef_binary_fixture_macosarm64_minimal
}

write_manifest() {
  local root="$1"
  local codex_sha cef_sha

  codex_sha="$(/usr/bin/shasum -a 256 "${root}/codex.tar.gz" | awk '{ print $1 }')"
  cef_sha="$(/usr/bin/shasum -a 256 "${root}/cef.tar.bz2" | awk '{ print $1 }')"

  cat >"${root}/manifest.json" <<EOF
{
  "schema_version": 1,
  "default_arch": "arm64",
  "codex": {
    "version": "1.2.3",
    "artifacts": {
      "arm64": {
        "url": "file://${root}/codex.tar.gz",
        "sha256": "${codex_sha}",
        "archive_type": "tar.gz"
      }
    }
  },
  "cef": {
    "version": "145.0.1+gfixture+chromium-145.0.7632.5",
    "artifacts": {
      "arm64": {
        "url": "file://${root}/cef.tar.bz2",
        "sha256": "${cef_sha}",
        "archive_type": "tar.bz2"
      }
    }
  }
}
EOF
}

test_bootstrap_stages_codex_and_cef() {
  local tmp_dir target_root
  tmp_dir="$(mktemp -d)"
  target_root="${tmp_dir}/repo"
  mkdir -p "${target_root}"
  mkdir -p "${target_root}/AgentHub/Resources"
  mkdir -p "${target_root}/build"
  git -C "${target_root}" init >/dev/null 2>&1

  pushd "${target_root}" >/dev/null
  make_codex_archive "${tmp_dir}"
  make_cef_archive "${tmp_dir}"
  write_manifest "${tmp_dir}"

  AGENTHUB_DEPENDENCY_REPO_ROOT="${target_root}" \
  AGENTHUB_DEPENDENCY_MANIFEST="${tmp_dir}/manifest.json" \
  AGENTHUB_DEPENDENCY_CACHE_DIR="${tmp_dir}/cache" \
  bash "${SCRIPT_DIR}/bootstrap.sh"

  assert_exists "${target_root}/AgentHub/Resources/codex/codex"
  assert_exists "${target_root}/build/dependencies/cef/145.0.1+gfixture+chromium-145.0.7632.5/arm64/Release/Chromium Embedded Framework.framework"
  assert_exists "${target_root}/build/dependencies/cef/145.0.1+gfixture+chromium-145.0.7632.5/arm64/Resources/icudtl.dat"
  assert_exists "${target_root}/build/dependencies/cef/current/arm64/Release/Chromium Embedded Framework.framework"
  popd >/dev/null
  rm -rf "${tmp_dir}"
}

test_prepare_xcode_inputs_copies_cef_release_payload() {
  local tmp_dir target_root output_root fake_codesign log_path
  tmp_dir="$(mktemp -d)"
  target_root="${tmp_dir}/repo"
  output_root="${tmp_dir}/BuildProducts/AgentHub.app/Contents"
  log_path="${tmp_dir}/codesign.log"
  mkdir -p "${target_root}"
  mkdir -p "${target_root}/AgentHub/Resources"
  mkdir -p "${target_root}/build"
  git -C "${target_root}" init >/dev/null 2>&1

  fake_codesign="${tmp_dir}/fake-codesign.sh"
  cat >"${fake_codesign}" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"${AGENTHUB_CODESIGN_LOG}"
EOF
  chmod +x "${fake_codesign}"

  pushd "${target_root}" >/dev/null
  make_codex_archive "${tmp_dir}"
  make_cef_archive "${tmp_dir}"
  write_manifest "${tmp_dir}"

  TARGET_BUILD_DIR="${tmp_dir}/BuildProducts" \
  FRAMEWORKS_FOLDER_PATH="AgentHub.app/Contents/Frameworks" \
  CODE_SIGNING_ALLOWED=YES \
  EXPANDED_CODE_SIGN_IDENTITY="fixture-identity" \
  AGENTHUB_DEPENDENCY_REPO_ROOT="${target_root}" \
  AGENTHUB_DEPENDENCY_MANIFEST="${tmp_dir}/manifest.json" \
  AGENTHUB_DEPENDENCY_CACHE_DIR="${tmp_dir}/cache" \
  AGENTHUB_CODESIGN_BIN="${fake_codesign}" \
  AGENTHUB_CODESIGN_LOG="${log_path}" \
  bash "${SCRIPT_DIR}/prepare-xcode-inputs.sh"

  assert_exists "${output_root}/Frameworks/Chromium Embedded Framework.framework"
  assert_exists "${output_root}/Frameworks/Chromium Embedded Framework.framework/Versions/Current/Resources/Info.plist"
  assert_exists "${output_root}/Frameworks/Chromium Embedded Framework.framework/Versions/Current/Libraries/libEGL.dylib"
  assert_exists "${output_root}/Frameworks/AgentHub Helper.app"
  assert_exists "${output_root}/Frameworks/AgentHub Helper (Alerts).xpc"
  assert_exists "${output_root}/Frameworks/icudtl.dat"
  assert_exists "${log_path}"
  grep -q "libEGL.dylib" "${log_path}" || fail "expected nested CEF dylib to be codesigned"
  grep -q "AgentHub Helper.app" "${log_path}" || fail "expected helper app to be copied and codesigned"
  grep -q "AgentHub Helper (Alerts).xpc" "${log_path}" || fail "expected helper xpc to be copied and codesigned"
  grep -q "Chromium Embedded Framework.framework" "${log_path}" || fail "expected framework to be codesigned"
  popd >/dev/null
  rm -rf "${tmp_dir}"
}

test_dependency_default_arch_prefers_manifest_default() {
  local tmp_dir repo_root manifest_path output
  tmp_dir="$(mktemp -d)"
  repo_root="${tmp_dir}/repo"
  manifest_path="${tmp_dir}/manifest.json"
  mkdir -p "${repo_root}/scripts/dependencies"
  cat >"${manifest_path}" <<'EOF'
{
  "schema_version": 1,
  "default_arch": "arm64"
}
EOF

  mkdir -p "${tmp_dir}/fake-bin"
  cat >"${tmp_dir}/fake-bin/uname" <<'EOF'
#!/bin/bash
echo "x86_64"
EOF
  chmod +x "${tmp_dir}/fake-bin/uname"

  output="$(run_dependency_default_arch "${SCRIPT_DIR}/lib/common.sh" \
    PATH="${tmp_dir}/fake-bin:${PATH}" \
    AGENTHUB_DEPENDENCY_REPO_ROOT="${repo_root}" \
    AGENTHUB_DEPENDENCY_MANIFEST="${manifest_path}")"

  assert_equals "arm64" "${output}"
  rm -rf "${tmp_dir}"
}

test_dependency_default_arch_prefers_explicit_target_arch() {
  local tmp_dir repo_root manifest_path output
  tmp_dir="$(mktemp -d)"
  repo_root="${tmp_dir}/repo"
  manifest_path="${tmp_dir}/manifest.json"
  mkdir -p "${repo_root}/scripts/dependencies"
  cat >"${manifest_path}" <<'EOF'
{
  "schema_version": 1,
  "default_arch": "arm64"
}
EOF

  output="$(run_dependency_default_arch "${SCRIPT_DIR}/lib/common.sh" \
    AGENTHUB_DEPENDENCY_REPO_ROOT="${repo_root}" \
    AGENTHUB_DEPENDENCY_MANIFEST="${manifest_path}" \
    AGENTHUB_TARGET_ARCH="x86_64" \
    NATIVE_ARCH_ACTUAL="arm64" \
    CURRENT_ARCH="arm64" \
    ARCHS="arm64")"

  assert_equals "x86_64" "${output}"
  rm -rf "${tmp_dir}"
}

test_dependency_default_arch_prefers_xcode_native_arch() {
  local tmp_dir repo_root manifest_path output
  tmp_dir="$(mktemp -d)"
  repo_root="${tmp_dir}/repo"
  manifest_path="${tmp_dir}/manifest.json"
  mkdir -p "${repo_root}/scripts/dependencies"
  cat >"${manifest_path}" <<'EOF'
{
  "schema_version": 1,
  "default_arch": "arm64"
}
EOF

  output="$(run_dependency_default_arch "${SCRIPT_DIR}/lib/common.sh" \
    AGENTHUB_DEPENDENCY_REPO_ROOT="${repo_root}" \
    AGENTHUB_DEPENDENCY_MANIFEST="${manifest_path}" \
    NATIVE_ARCH_ACTUAL="x86_64" \
    CURRENT_ARCH="arm64" \
    ARCHS="arm64")"

  assert_equals "x86_64" "${output}"
  rm -rf "${tmp_dir}"
}

test_dependency_default_arch_uses_single_archs_value() {
  local tmp_dir repo_root manifest_path output
  tmp_dir="$(mktemp -d)"
  repo_root="${tmp_dir}/repo"
  manifest_path="${tmp_dir}/manifest.json"
  mkdir -p "${repo_root}/scripts/dependencies"
  cat >"${manifest_path}" <<'EOF'
{
  "schema_version": 1,
  "default_arch": "arm64"
}
EOF

  output="$(run_dependency_default_arch "${SCRIPT_DIR}/lib/common.sh" \
    AGENTHUB_DEPENDENCY_REPO_ROOT="${repo_root}" \
    AGENTHUB_DEPENDENCY_MANIFEST="${manifest_path}" \
    ARCHS="x86_64")"

  assert_equals "x86_64" "${output}"
  rm -rf "${tmp_dir}"
}

test_dependency_default_arch_rejects_multi_archs_without_explicit_target() {
  local tmp_dir repo_root manifest_path output status
  tmp_dir="$(mktemp -d)"
  repo_root="${tmp_dir}/repo"
  manifest_path="${tmp_dir}/manifest.json"
  mkdir -p "${repo_root}/scripts/dependencies"
  cat >"${manifest_path}" <<'EOF'
{
  "schema_version": 1
}
EOF

  set +e
  output="$(run_dependency_default_arch "${SCRIPT_DIR}/lib/common.sh" \
    AGENTHUB_DEPENDENCY_REPO_ROOT="${repo_root}" \
    AGENTHUB_DEPENDENCY_MANIFEST="${manifest_path}" \
    ARCHS="arm64 x86_64" 2>&1)"
  status=$?
  set -e

  if [[ "${status}" -eq 0 ]]; then
    fail "expected multi-arch resolution to fail without AGENTHUB_TARGET_ARCH"
  fi
  assert_contains "${output}" "Set AGENTHUB_TARGET_ARCH explicitly"
  rm -rf "${tmp_dir}"
}

main() {
  test_bootstrap_stages_codex_and_cef
  test_prepare_xcode_inputs_copies_cef_release_payload
  test_dependency_default_arch_prefers_manifest_default
  test_dependency_default_arch_prefers_explicit_target_arch
  test_dependency_default_arch_prefers_xcode_native_arch
  test_dependency_default_arch_uses_single_archs_value
  test_dependency_default_arch_rejects_multi_archs_without_explicit_target
  echo "All dependency script tests passed"
}

main "$@"
