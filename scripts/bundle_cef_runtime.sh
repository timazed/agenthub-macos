#!/usr/bin/env bash
set -euo pipefail

CEF_VERSION="${CEF_RUNTIME_VERSION:-136.1.4+g89c0a8c+chromium-136.0.7103.93}"
CEF_CONFIGURATION="${CEF_FRAMEWORK_CONFIGURATION:-${CONFIGURATION:-Release}}"
CEF_RUNTIME_ROOT="${CEF_RUNTIME_ROOT:-${PROJECT_DIR}/Vendor/CEFRuntime/${CEF_VERSION}}"
FRAMEWORK_SOURCE="${CEF_RUNTIME_ROOT}/${CEF_CONFIGURATION}/Chromium Embedded Framework.framework"
FRAMEWORK_DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Chromium Embedded Framework.framework"
FRAMEWORK_VERSION_DIR="${FRAMEWORK_DEST}/Versions/A"
RESOURCE_SOURCE="${FRAMEWORK_SOURCE}/Resources"
RESOURCE_DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
SIGNING_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
APP_EXECUTABLE="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"
FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
HELPER_FRAMEWORK_LOAD_PATH='@executable_path/../../../Chromium Embedded Framework.framework/Chromium Embedded Framework'
MAIN_FRAMEWORK_LOAD_PATH='@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework'

if [[ ! -d "${FRAMEWORK_SOURCE}" ]]; then
  echo "error: Missing CEF runtime at ${FRAMEWORK_SOURCE}" >&2
  echo "Run these commands from repo root before building:" >&2
  echo "  git submodule update --init --recursive" >&2
  echo "  scripts/bootstrap_cef_runtime.sh" >&2
  exit 1
fi

mkdir -p "${FRAMEWORKS_DIR}"
rm -rf "${FRAMEWORK_DEST}" "${FRAMEWORKS_DIR}/${PRODUCT_NAME} Helper.app" "${FRAMEWORKS_DIR}/${PRODUCT_NAME} Helper (Alerts).app" "${FRAMEWORKS_DIR}/${PRODUCT_NAME} Helper (GPU).app" "${FRAMEWORKS_DIR}/${PRODUCT_NAME} Helper (Plugin).app" "${FRAMEWORKS_DIR}/${PRODUCT_NAME} Helper (Renderer).app"
mkdir -p "${FRAMEWORK_VERSION_DIR}"
ditto "${FRAMEWORK_SOURCE}/Chromium Embedded Framework" "${FRAMEWORK_VERSION_DIR}/Chromium Embedded Framework"
ditto "${FRAMEWORK_SOURCE}/Resources" "${FRAMEWORK_VERSION_DIR}/Resources"
if [[ -d "${FRAMEWORK_SOURCE}/Libraries" ]]; then
  ditto "${FRAMEWORK_SOURCE}/Libraries" "${FRAMEWORK_VERSION_DIR}/Libraries"
fi
(
  cd "${FRAMEWORK_DEST}"
  ln -sfn A Versions/Current
  ln -sfn "Versions/Current/Chromium Embedded Framework" "Chromium Embedded Framework"
  ln -sfn Versions/Current/Resources Resources
  if [[ -d "${FRAMEWORK_VERSION_DIR}/Libraries" ]]; then
    ln -sfn Versions/Current/Libraries Libraries
  fi
)

create_helper_app() {
  HELPER_NAME="$1"
  BUNDLE_SUFFIX="$2"
  HELPER_APP_DIR="${FRAMEWORKS_DIR}/${HELPER_NAME}.app"
  HELPER_EXECUTABLE_DIR="${HELPER_APP_DIR}/Contents/MacOS"
  HELPER_EXECUTABLE="${HELPER_EXECUTABLE_DIR}/${HELPER_NAME}"
  HELPER_INFO_PLIST="${HELPER_APP_DIR}/Contents/Info.plist"
  mkdir -p "${HELPER_EXECUTABLE_DIR}"
  cp "${APP_EXECUTABLE}" "${HELPER_EXECUTABLE}"
  install_name_tool -change "${MAIN_FRAMEWORK_LOAD_PATH}" "${HELPER_FRAMEWORK_LOAD_PATH}" "${HELPER_EXECUTABLE}"
  cat > "${HELPER_INFO_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${HELPER_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${HELPER_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${PRODUCT_BUNDLE_IDENTIFIER}.helper${BUNDLE_SUFFIX}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${HELPER_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleVersion</key>
  <string>${CURRENT_PROJECT_VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>LSFileQuarantineEnabled</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>${MACOSX_DEPLOYMENT_TARGET}</string>
  <key>LSUIElement</key>
  <string>1</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
EOF
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${HELPER_EXECUTABLE}"
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${HELPER_APP_DIR}"
}

if [[ -d "${FRAMEWORK_VERSION_DIR}/Libraries" ]]; then
  find "${FRAMEWORK_VERSION_DIR}/Libraries" -type f -exec codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none {} \;
fi

codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${FRAMEWORK_VERSION_DIR}/Chromium Embedded Framework"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${FRAMEWORK_DEST}"
create_helper_app "${PRODUCT_NAME} Helper" ""
create_helper_app "${PRODUCT_NAME} Helper (Alerts)" ".alerts"
create_helper_app "${PRODUCT_NAME} Helper (GPU)" ".gpu"
create_helper_app "${PRODUCT_NAME} Helper (Plugin)" ".plugin"
create_helper_app "${PRODUCT_NAME} Helper (Renderer)" ".renderer"
ditto "${RESOURCE_SOURCE}" "${RESOURCE_DEST}"
