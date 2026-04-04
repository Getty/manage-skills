#!/usr/bin/env bash
set -euo pipefail

REPO="Getty/manage-skills"
SCRIPT_NAME="manage-skills"

# Colors
if [[ -t 1 ]]; then
  BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m' RESET=$'\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' RESET=''
fi

info() { echo "${GREEN}$*${RESET}"; }
warn() { echo "${YELLOW}$*${RESET}"; }
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

# Find install location
find_install_dir() {
  # 1. /usr/local/bin if writable
  if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
    echo "/usr/local/bin"
    return
  fi

  # 2. ~/.local/bin if it exists and is in PATH
  local local_bin="$HOME/.local/bin"
  if [[ -d "$local_bin" ]] && echo "$PATH" | tr ':' '\n' | grep -qF "$local_bin"; then
    echo "$local_bin"
    return
  fi

  # 3. ~/bin if it exists and is in PATH
  local home_bin="$HOME/bin"
  if [[ -d "$home_bin" ]] && echo "$PATH" | tr ':' '\n' | grep -qF "$home_bin"; then
    echo "$home_bin"
    return
  fi

  # 4. Create ~/.local/bin
  mkdir -p "$local_bin"
  echo "$local_bin"
}

main() {
  echo "${BOLD}Installing manage-skills${RESET}"
  echo ""

  local install_dir
  install_dir=$(find_install_dir)

  # Detect: running from a git clone?
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local source_script="$script_dir/manage-skills"
  local is_git_repo=false
  if [[ -f "$source_script" ]] && git -C "$script_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    is_git_repo=true
  fi

  if $is_git_repo; then
    # Dev mode: symlink so edits take effect immediately
    ln -sf "$source_script" "$install_dir/$SCRIPT_NAME"
    info "Symlinked to $source_script (dev mode)"
  elif [[ -f "$source_script" ]]; then
    # Local but not a git repo: copy
    cp "$source_script" "$install_dir/$SCRIPT_NAME"
  else
    # Download from GitHub
    local url="https://raw.githubusercontent.com/$REPO/main/manage-skills"
    if command -v curl &>/dev/null; then
      curl -fsSL "$url" -o "$install_dir/$SCRIPT_NAME"
    elif command -v wget &>/dev/null; then
      wget -qO "$install_dir/$SCRIPT_NAME" "$url"
    else
      die "Neither curl nor wget found"
    fi
  fi

  chmod +x "$install_dir/$SCRIPT_NAME"
  info "Installed to $install_dir/$SCRIPT_NAME"

  # Check if in PATH
  if ! command -v "$SCRIPT_NAME" &>/dev/null; then
    echo ""
    warn "$install_dir is not in your PATH."
    echo ""
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo "  export PATH=\"$install_dir:\$PATH\""
    echo ""
  fi

  # Init config if needed
  if [[ ! -d "$HOME/.manage-skills" ]]; then
    echo ""
    "$install_dir/$SCRIPT_NAME" init
  fi

  echo ""
  info "Done! Run 'manage-skills --help' to get started."
}

main "$@"
