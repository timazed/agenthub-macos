#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_exists() {
  local path="$1"
  [[ -e "${path}" ]] || fail "expected path to exist: ${path}"
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
  mkdir -p "${fixture_dir}/Release/AgentHub Helper.app/Contents/MacOS"
  mkdir -p "${fixture_dir}/Resources"
  touch "${fixture_dir}/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
  touch "${fixture_dir}/Release/AgentHub Helper.app/Contents/MacOS/AgentHub Helper"
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
  "default_channel": "stable",
  "default_arch": "arm64",
  "dependencies": {
    "codex": {
      "install_mode": "resource_binary",
      "resource_dir": "AgentHub/Resources/codex",
      "resource_binary_name": "codex",
      "channels": {
        "stable": {
          "version": "1.2.3",
          "artifacts": {
            "arm64": {
              "url": "file://${root}/codex.tar.gz",
              "sha256": "${codex_sha}",
              "archive_type": "tar.gz",
              "binary_name": "codex"
            }
          }
        }
      }
    },
    "cef": {
      "install_mode": "cef_release_bundle",
      "staging_dir": "build/dependencies/cef",
      "channels": {
        "stable": {
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
  popd >/dev/null
  rm -rf "${tmp_dir}"
}

test_prepare_xcode_inputs_copies_cef_release_payload() {
  local tmp_dir target_root output_root
  tmp_dir="$(mktemp -d)"
  target_root="${tmp_dir}/repo"
  output_root="${tmp_dir}/BuildProducts/AgentHub.app/Contents"
  mkdir -p "${target_root}"
  mkdir -p "${target_root}/AgentHub/Resources"
  mkdir -p "${target_root}/build"
  git -C "${target_root}" init >/dev/null 2>&1

  pushd "${target_root}" >/dev/null
  make_codex_archive "${tmp_dir}"
  make_cef_archive "${tmp_dir}"
  write_manifest "${tmp_dir}"

  TARGET_BUILD_DIR="${tmp_dir}/BuildProducts" \
  FRAMEWORKS_FOLDER_PATH="AgentHub.app/Contents/Frameworks" \
  AGENTHUB_DEPENDENCY_REPO_ROOT="${target_root}" \
  AGENTHUB_DEPENDENCY_MANIFEST="${tmp_dir}/manifest.json" \
  AGENTHUB_DEPENDENCY_CACHE_DIR="${tmp_dir}/cache" \
  bash "${SCRIPT_DIR}/prepare-xcode-inputs.sh"

  assert_exists "${output_root}/Frameworks/Chromium Embedded Framework.framework"
  assert_exists "${output_root}/Frameworks/AgentHub Helper.app"
  popd >/dev/null
  rm -rf "${tmp_dir}"
}

main() {
  test_bootstrap_stages_codex_and_cef
  test_prepare_xcode_inputs_copies_cef_release_payload
  echo "All dependency script tests passed"
}

main "$@"
