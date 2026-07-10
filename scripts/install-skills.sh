#!/usr/bin/env bash
# Install (symlink) the codex-harness skill catalog into a target repo's
# Codex skill-discovery scope.
#
# Usage: scripts/install-skills.sh [target-dir]
#
# target-dir defaults to "." (this repo's own root scope, for self-hosting
# and testing). Symlinks are created at "<target-dir>/.agents/skills/<name>"
# pointing at this repo's "<repo-root>/.agents/skills/<name>" so the target
# always tracks the source, never a stale copy.
#
# Idempotent: re-running skips a symlink that already points at the correct
# source, refreshes one that points elsewhere or has gone stale, and never
# errors on a clean rerun. A pre-existing real file/directory at the target
# path (not a symlink) is left untouched and reported, never clobbered.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_SKILLS_DIR="${REPO_ROOT}/.agents/skills"

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
TARGET_SKILLS_DIR="${TARGET_DIR}/.agents/skills"

if [[ ! -d "${SOURCE_SKILLS_DIR}" ]]; then
  echo "install-skills: source skills dir not found at ${SOURCE_SKILLS_DIR}" >&2
  exit 1
fi

mkdir -p "${TARGET_SKILLS_DIR}"

installed=0
refreshed=0
skipped=0
conflicts=0

for skill_path in "${SOURCE_SKILLS_DIR}"/harness-*/; do
  [[ -d "${skill_path}" ]] || continue
  skill_name="$(basename "${skill_path}")"
  source_path="${SOURCE_SKILLS_DIR}/${skill_name}"
  link_path="${TARGET_SKILLS_DIR}/${skill_name}"

  if [[ -L "${link_path}" ]]; then
    current_target="$(readlink "${link_path}")"
    if [[ "${current_target}" == "${source_path}" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    rm "${link_path}"
    ln -s "${source_path}" "${link_path}"
    refreshed=$((refreshed + 1))
  elif [[ -e "${link_path}" ]]; then
    echo "install-skills: WARNING skipping ${link_path} — exists and is not a symlink" >&2
    conflicts=$((conflicts + 1))
  else
    ln -s "${source_path}" "${link_path}"
    installed=$((installed + 1))
  fi
done

echo "install-skills: installed=${installed} refreshed=${refreshed} unchanged=${skipped} conflicts=${conflicts} -> ${TARGET_SKILLS_DIR}"

if [[ "${conflicts}" -gt 0 ]]; then
  exit 1
fi
