#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/env.sh
source "${SCRIPT_DIR}/env.sh"

bump_mode() {
  echo "${AGENTHUB_RELEASE_BUMP:-patch}"
}

increment_patch_version() {
  local version="$1"
  IFS='.' read -r major minor patch <<<"${version}"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  echo "${major}.${minor}.$((patch + 1))"
}

main() {
  eval "$("${SCRIPT_DIR}/read-version.sh" --shell)"

  local current_version current_build next_version next_build
  current_version="${AGENTHUB_RELEASE_CURRENT_VERSION}"
  current_build="${AGENTHUB_RELEASE_CURRENT_BUILD}"
  next_build="$((current_build + 1))"

  case "$(bump_mode)" in
    patch)
      next_version="$(increment_patch_version "${current_version}")"
      ;;
    build)
      next_version="${current_version}"
      ;;
    *)
      echo "Unsupported AGENTHUB_RELEASE_BUMP value: $(bump_mode)" >&2
      exit 1
      ;;
  esac

  if release_dry_run; then
    echo "Dry run: would bump version ${current_version} (${current_build}) -> ${next_version} (${next_build})"
    exit 0
  fi

  local project_file
  project_file="$(repo_root)/$(release_project)/project.pbxproj"

  NEXT_BUILD="${next_build}" ruby -pi -e 'gsub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = #{ENV.fetch("NEXT_BUILD")};")' "${project_file}"
  NEXT_VERSION="${next_version}" ruby -pi -e 'gsub(/MARKETING_VERSION = [^;]+;/, "MARKETING_VERSION = #{ENV.fetch("NEXT_VERSION")};")' "${project_file}"

  echo "Bumped version ${current_version} (${current_build}) -> ${next_version} (${next_build})"
}

main "$@"
