# Vorosium

## Installation

### To Install, Please visit check out our official site [here](https://killianzabinsky.com/). (Incomplete)

## Quickstart (developer)

Prerequisites
- Linux host with required packages (build-essential, git, qemu, debootstrap, sudo for privileged operations).
- A working Git remote named `origin` (this repository).

Basic steps for building.

1. Build kernel (Autoruns Debian Rootfs by Default.):

   ```bash
   # From repo root
   ./scripts/build-kernel.sh
   ```

   This script defaults to an `OUTDIR` under the project root. See `scripts/build-kernel.sh` for flags.

2. Boot the image under QEMU:

   ```bash
   ./kernel/boot.sh
   ```

   `boot.sh` is a thin wrapper around qemu with recommended device and networking flags for local testing. Script can be ran with `-nogui` to run in terminal.

## For Developers

This section describes the recommended local developer workflow and repository hygiene rules.

Repository layout highlights
- `kernel/` — kernel sources and kernel-specific helpers (`makefile`, `ramdisk` `helpers`).
- `scripts/` — repository helper scripts (build kernel, add rootfs, boot image, etc...).
- `build/` — generated build outputs and rootfs images (these are large and intentionally ignored by .gitignore).

Developer principles
- Keep large, generated build artifacts out of Git history. Use `OUTDIR` and `build/` for local outputs.
- Run non-privileged builds under the repository user by setting the default `OUTDIR` (scripts already use an `out/`/`build/` pattern).
- Do not take code without giving credit. Author must be cited at the top of the file. If changes are made, add additional authors.

Handling permission errors
- If you see permission warnings from Git like `unable to unlink '.git/objects/...' Permission denied`, some files are likely root-owned from a previous sudo run.
- Fix ownership for the repository (recommended):

  ```bash
  cd /path/to/Vorosium
  sudo chown -R "$(id -un):$(id -gn)" "$(pwd)"
  sudo rm -f .git/gc.log
  git gc --prune=all
  ```

  After this you should be able to commit and run the helper scripts without permission errors.

History rewrites and backups
- The repository contains tooling to purge large files from history. These are destructive operations from a shared-collaboration perspective and should be used carefully.
- When performing history rewrite or purge operations, the scripts create local and remote backups (timestamped `backup-main-*` branches and `pre-purge-backup-*` tags) before applying destructive changes. Keep those backups until you have validated the rewrite and coordinated with collaborators.

Collaborator coordination after force-push
- If history is rewritten and `origin/main` is force-updated, instruct collaborators to reset their local `main` to the new remote state:

  ```bash
  git fetch origin
  git checkout main
  git reset --hard origin/main
  ```

  Rebase any feature branches onto the new `main` as necessary.

Troubleshooting
- If the guarded push script fails with `error: insufficient permission for adding an object to repository database .git/objects` then run the ownership fix above and retry the push.
- If `scripts/push.sh` untracked a file you still need, restore it from your working tree (it remains present) and follow the commit workflow described in `scripts/commit-kernel-artifacts.sh` if you intend to keep large artifacts in git (not recommended for typical development).

License
- We are not responsible for complications when developing.
- See the repository `LICENSE` and directory files for licensing details of respective components.
