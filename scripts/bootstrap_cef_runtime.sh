#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_PATH="${REPO_ROOT}/Packages/CEFKit/cef_runtime_manifest.json"

if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "error: Missing runtime manifest at ${MANIFEST_PATH}" >&2
  exit 1
fi

eval "$(
/usr/bin/python3 - "${MANIFEST_PATH}" "$(uname -m)" <<'PY'
import json
import shlex
import sys

manifest_path = sys.argv[1]
machine = sys.argv[2]

platform_map = {
    "arm64": "macosarm64",
    "x86_64": "macosx64",
}

platform_key = platform_map.get(machine)
if not platform_key:
    raise SystemExit(f"Unsupported macOS architecture: {machine}")

with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

platform_data = manifest["platforms"].get(platform_key)
if not platform_data:
    raise SystemExit(f"No manifest platform entry for {platform_key}")

pairs = {
    "CEF_VERSION": manifest["cefVersion"],
    "CHROMIUM_VERSION": manifest["chromiumVersion"],
    "RUNTIME_DIRECTORY": manifest["runtimeDirectory"],
    "PLATFORM_KEY": platform_key,
    "ARCHIVE_NAME": platform_data["archiveName"],
    "ARCHIVE_ROOT": platform_data["archiveRoot"],
    "DOWNLOAD_URL": platform_data["url"],
    "EXPECTED_SHA256": platform_data["sha256"],
}

for key, value in pairs.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

RUNTIME_ROOT="${REPO_ROOT}/${RUNTIME_DIRECTORY}"
CACHE_ROOT="${REPO_ROOT}/Vendor/CEFRuntime/.downloads"
ARCHIVE_PATH="${CACHE_ROOT}/${ARCHIVE_NAME}"
HASH_MARKER="${RUNTIME_ROOT}/.bootstrap-${PLATFORM_KEY}.sha256"

mkdir -p "${CACHE_ROOT}"

runtime_is_ready() {
  [[ -f "${RUNTIME_ROOT}/Debug/Chromium Embedded Framework.framework/Chromium Embedded Framework" ]] \
    && [[ -f "${RUNTIME_ROOT}/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework" ]] \
    && [[ -f "${RUNTIME_ROOT}/include/cef_app.h" ]] \
    && [[ -f "${RUNTIME_ROOT}/libcef_dll/wrapper/libcef_dll_wrapper.cc" ]] \
    && [[ -f "${HASH_MARKER}" ]] \
    && [[ "$(cat "${HASH_MARKER}")" == "${EXPECTED_SHA256}" ]]
}

if runtime_is_ready; then
  echo "CEF runtime already provisioned at ${RUNTIME_ROOT}"
  exit 0
fi

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "Downloading ${DOWNLOAD_URL}"
  curl -fL --retry 5 --retry-all-errors -o "${ARCHIVE_PATH}" "${DOWNLOAD_URL}"
fi

ACTUAL_SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "warning: Cached archive checksum mismatch. Re-downloading ${ARCHIVE_NAME}" >&2
  rm -f "${ARCHIVE_PATH}"
  curl -fL --retry 5 --retry-all-errors -o "${ARCHIVE_PATH}" "${DOWNLOAD_URL}"
  ACTUAL_SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
fi

if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "error: SHA256 mismatch for ${ARCHIVE_NAME}" >&2
  echo "expected: ${EXPECTED_SHA256}" >&2
  echo "actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cef-runtime-bootstrap.XXXXXX")"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Extracting ${ARCHIVE_NAME}"
tar -xjf "${ARCHIVE_PATH}" -C "${TMP_DIR}"

EXTRACTED_ROOT="${TMP_DIR}/${ARCHIVE_ROOT}"
if [[ ! -d "${EXTRACTED_ROOT}" ]]; then
  echo "error: Expected extracted directory ${EXTRACTED_ROOT} not found" >&2
  exit 1
fi

if [[ ! -d "${EXTRACTED_ROOT}/Debug" || ! -d "${EXTRACTED_ROOT}/Release" || ! -d "${EXTRACTED_ROOT}/include" || ! -d "${EXTRACTED_ROOT}/libcef_dll" ]]; then
  echo "error: Extracted runtime is missing required directories (Debug/Release/include/libcef_dll)" >&2
  exit 1
fi

echo "Provisioning runtime at ${RUNTIME_ROOT}"
rm -rf "${RUNTIME_ROOT}"
mkdir -p "${RUNTIME_ROOT}"
ditto "${EXTRACTED_ROOT}/Debug" "${RUNTIME_ROOT}/Debug"
ditto "${EXTRACTED_ROOT}/Release" "${RUNTIME_ROOT}/Release"
ditto "${EXTRACTED_ROOT}/include" "${RUNTIME_ROOT}/include"
ditto "${EXTRACTED_ROOT}/libcef_dll" "${RUNTIME_ROOT}/libcef_dll"
if [[ -d "${EXTRACTED_ROOT}/WrapperBuild" ]]; then
  ditto "${EXTRACTED_ROOT}/WrapperBuild" "${RUNTIME_ROOT}/WrapperBuild"
fi

cat > "${HASH_MARKER}" <<EOF
${EXPECTED_SHA256}
EOF

cat > "${RUNTIME_ROOT}/bootstrap-metadata.json" <<EOF
{
  "cefVersion": "${CEF_VERSION}",
  "chromiumVersion": "${CHROMIUM_VERSION}",
  "platform": "${PLATFORM_KEY}",
  "archiveName": "${ARCHIVE_NAME}",
  "sha256": "${EXPECTED_SHA256}"
}
EOF

echo "CEF runtime ready: ${RUNTIME_ROOT}"
