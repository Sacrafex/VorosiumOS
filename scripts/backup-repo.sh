#!/usr/bin/env bash
set -euo pipefail

# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

# Modes:
#   default        Create a backup honoring .gitignore (tracked + untracked, excluding ignored files)
#   -all           Create a backup including ALL files in the workspace (except .git and .backups)
#   -submodules    Initialize and update submodules before backup (best effort)

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
BACKUP_DIR="$REPO_ROOT/.backups"
TS="$(date +%Y%m%d-%H%M%S)"
TARCMD=(tar --no-same-owner --no-same-permissions --ignore-failed-read)

usage() {
  echo "Usage:"
  echo "  $0 [-all] [-submodules]   Create a backup snapshot into .backups/"
  echo "  $0 -list                   List available backups"
  echo "  $0 -recover <id>           Recover working tree from a backup id"
  echo
  echo "Options:"
  echo "  -all         Include ignored files (tar full workspace, excluding .git and .backups)"
  echo "  -submodules  Initialize/update submodules before backup (best effort)"
}

msg() { echo "[+] $*"; }
err() { echo "[-] $*" >&2; }

do_backup() {
  mkdir -p "$BACKUP_DIR"
  local dest="$BACKUP_DIR/$TS"
  msg "Creating backup at $dest"
  mkdir -p "$dest"

  (
    cd "$REPO_ROOT"
    # Save metadata
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git rev-parse HEAD > "$dest/HEAD" 2>/dev/null || echo "NO_GIT_HEAD" > "$dest/HEAD"
      git status -sb > "$dest/git-status.txt" || true
      git remote -v > "$dest/git-remotes.txt" || true
    fi

    # Update submodules
    if [[ ${WITH_SUBMODULES:-0} -eq 1 ]] && command -v git >/dev/null 2>&1; then
      git submodule update --init --recursive || true
    fi

    if [[ ${INCLUDE_ALL:-0} -eq 1 ]]; then
      # Include all files except .git and .backups
      "${TARCMD[@]}" --exclude=".git" --exclude=".backups" -czf "$dest/worktree.tar.gz" .
    else
      # Honor .gitignore: use git ls-files for tracked and untracked (non-ignored) files
      if git ls-files -z --others --cached --exclude-standard >/dev/null 2>&1; then
        git ls-files -z --others --cached --exclude-standard \
          | grep -zv "^\.backups/" \
          | "${TARCMD[@]}" --null -T - -czf "$dest/worktree.tar.gz"
      else
        # Fallback: tar the directory excluding .git and .backups
        "${TARCMD[@]}" --exclude=".git" --exclude=".backups" -czf "$dest/worktree.tar.gz" .
      fi
    fi
  )

  msg "Backup complete: $dest"
}

list_backups() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "No backups found."
    return 0
  fi
  ls -1 "$BACKUP_DIR" | sort
}

recover_backup() {
  local id="${1:-}"
  local src="$BACKUP_DIR/$id"
  [[ -d "$src" ]] || { err "Backup not found: $id"; exit 1; }

  msg "Recovering from backup $id"
  (
    cd "$REPO_ROOT"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
        err "Working tree not clean. Please stash or commit changes before recovering."
        exit 1
      fi
    fi
    tar -xzf "$src/worktree.tar.gz" -C "$REPO_ROOT"
  )
  msg "Recovery complete. Review changes and commit/push as needed."
}

INCLUDE_ALL=0
WITH_SUBMODULES=0

ARGS=("$@")
if [[ ${#ARGS[@]} -eq 0 ]]; then
  do_backup; exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -list) list_backups; exit 0 ;;
    -recover) recover_backup "${2:-}"; exit 0 ;;
    -all) INCLUDE_ALL=1 ;;
    -submodules) WITH_SUBMODULES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

do_backup
