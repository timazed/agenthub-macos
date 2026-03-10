#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

usage() {
  cat <<'EOF'
Usage:
  read-version.sh [--shell]
  read-version.sh --value <version|build|product-name|bundle-id>
EOF
}

load_release_block() {
  awk -v bundle_id="$(release_bundle_identifier)" -v config_name="$(release_configuration)" '
    $0 ~ "/\\* " config_name " \\*/ = \\{" {
      in_block = 1
      block = $0 ORS
      next
    }
    in_block {
      block = block $0 ORS
      if ($0 ~ /^		};$/) {
        if (block ~ "PRODUCT_BUNDLE_IDENTIFIER = " bundle_id ";") {
          printf "%s", block
          exit
        }
        in_block = 0
        block = ""
      }
    }
  ' "$(release_project_file)"
}

read_setting() {
  local key="$1"
  load_release_block | awk -F' = ' -v search_key="${key}" '$1 ~ search_key { gsub(/;/, "", $2); print $2; exit }'
}

main() {
  local mode="plain"
  local value_key=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --shell)
        mode="shell"
        shift
        ;;
      --value)
        mode="value"
        value_key="${2:-}"
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

  local version build product_name bundle_id
  version="$(read_setting "MARKETING_VERSION")"
  build="$(read_setting "CURRENT_PROJECT_VERSION")"
  product_name="$(read_setting "PRODUCT_NAME")"
  bundle_id="$(read_setting "PRODUCT_BUNDLE_IDENTIFIER")"

  case "${mode}" in
    shell)
      cat <<EOF
AGENTHUB_RELEASE_CURRENT_VERSION='${version}'
AGENTHUB_RELEASE_CURRENT_BUILD='${build}'
AGENTHUB_RELEASE_CURRENT_PRODUCT_NAME='${product_name}'
AGENTHUB_RELEASE_CURRENT_BUNDLE_ID='${bundle_id}'
EOF
      ;;
    value)
      case "${value_key}" in
        version) echo "${version}" ;;
        build) echo "${build}" ;;
        product-name) echo "${product_name}" ;;
        bundle-id) echo "${bundle_id}" ;;
        *)
          echo "Unsupported value key: ${value_key}" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      cat <<EOF
version=${version}
build=${build}
product_name=${product_name}
bundle_id=${bundle_id}
EOF
      ;;
  esac
}

main "$@"
