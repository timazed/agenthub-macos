#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTHUB_RELEASE_CHANNEL="${AGENTHUB_RELEASE_CHANNEL:-beta}"

exec "${SCRIPT_DIR}/build-release.sh" "$@"
