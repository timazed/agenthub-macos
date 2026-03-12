#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTHUB_RELEASE_CHANNEL="${AGENTHUB_RELEASE_CHANNEL:-release}"

exec "${SCRIPT_DIR}/build-release.sh" "$@"
