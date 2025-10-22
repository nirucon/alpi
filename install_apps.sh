#!/usr/bin/env bash
# install_apps.sh — application layer for Arch
# Purpose: Install desktop apps & developer tools via pacman and (optionally) yay.
#          Reads package lists from config/apps-pacman.txt and config/apps-aur.txt
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"
YLW="\033[1;33m"
RED="\033[1;31m"
BLU="\033[1;34m"
GRN="\033[1;32m"
NC="\033[0m"
say() { printf "${CYN}[APPS]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_apps.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || {
  fail "Do not run as root."
  exit 1
}

# ───────── Paths ─────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PACMAN_FILE="$SCRIPT_DIR/config/apps-pacman.txt"
AUR_FILE="$SCRIPT_DIR/config/apps-aur.txt"

# ───────── Flags ─────────
DRY_RUN=0
USE_YAY=1

usage() {
  cat <<'EOF'
install_apps.sh — options
  --no-yay      Do not install yay or any AUR packages
  --dry-run     Print actions without changing the system
  -h|--help     Show this help

Package lists:
  Edit config/apps-pacman.txt for official repo packages
  Edit config/apps-aur.txt for AUR packages
  
  Format: one package per line, lines starting with # are ignored
  
  Example:
    neovim           # text editor
    firefox          # web browser
    # discord        # disabled for now
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-yay)
    USE_YAY=0
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    warn "Unknown argument: $1"
    usage
    exit 1
    ;;
  esac
done

# ───────── Helpers ─────────
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
  else
    if [[ $# -eq 1 ]]; then
      bash -lc "$1"
    else
      "$@"
    fi
  fi
}

# Read package list from file (ignore comments and empty lines)
read_package_list() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # Read file, strip comments and whitespace, take first word (package name)
  grep -vE '^\s*(#|$)' "$file" | awk '{print $1}' | sort -u
}

append_once() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >>"$file"
}

# ───────── Read package lists ─────────
step "Reading package lists from config/"

mapfile -t PACMAN_PKGS < <(read_package_list "$PACMAN_FILE")
mapfile -t AUR_PKGS < <(read_package_list "$AUR_FILE")

if ((${#PACMAN_PKGS[@]} == 0)); then
  warn "No packages found in $PACMAN_FILE"
  warn "Create the file and add packages (one per line)"
fi

if ((${#AUR_PKGS[@]} == 0)); then
  warn "No AUR packages found in $AUR_FILE"
fi

say "Found ${#PACMAN_PKGS[@]} pacman packages and ${#AUR_PKGS[@]} AUR packages"

# ───────── Install pacman apps ─────────
if ((${#PACMAN_PKGS[@]} > 0)); then
  step "Installing pacman packages (${#PACMAN_PKGS[@]} total)"
  run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
else
  say "No pacman packages to install"
fi

# ───────── Install yay + AUR apps (optional) ─────────
if ((USE_YAY == 1)); then
  if ! command -v yay >/dev/null 2>&1; then
    step "Installing yay-bin (AUR helper)"
    tmp="$(mktemp -d)"
    run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
    rm -rf "$tmp"
  else
    say "yay already installed"
  fi

  if ((${#AUR_PKGS[@]} > 0)); then
    step "Installing AUR packages via yay (${#AUR_PKGS[@]} total)"
    run yay -S --needed --noconfirm "${AUR_PKGS[@]}"
  else
    say "No AUR packages to install"
  fi
else
  warn "--no-yay set: skipping AUR packages"
fi

# ───────── Neovim (LazyVim bootstrap) ─────────
NVIM_DIR="$HOME/.config/nvim"
LAZY_STARTER_REPO="https://github.com/LazyVim/starter"

if command -v nvim >/dev/null 2>&1; then
  if [[ ! -d "$NVIM_DIR" ]]; then
    step "Bootstrapping LazyVim"
    run git clone --depth=1 "$LAZY_STARTER_REPO" "$NVIM_DIR"
    (cd "$NVIM_DIR" && run rm -rf .git)
    # First-time plugin sync (non-fatal if it fails headless)
    run nvim --headless "+Lazy! sync" +qa || true
    say "LazyVim starter installed to $NVIM_DIR"
  else
    say "Neovim config exists ($NVIM_DIR) — leaving as-is"
  fi
else
  warn "Neovim not found; skipping LazyVim bootstrap"
fi

# ───────── Ensure EDITOR vars and PATH (idempotent) ─────────
BASH_PROFILE="$HOME/.bash_profile"

# Create .bash_profile if it doesn't exist
if [[ ! -f "$BASH_PROFILE" ]]; then
  cat >"$BASH_PROFILE" <<'EOF'
# .bash_profile

# Source .bashrc if it exists
[[ -f ~/.bashrc ]] && . ~/.bashrc

# User-specific environment and startup programs
EOF
fi

append_once 'export EDITOR=nvim' "$BASH_PROFILE"
append_once 'export VISUAL=nvim' "$BASH_PROFILE"

if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  append_once 'export PATH="$HOME/.local/bin:$PATH"' "$BASH_PROFILE"
fi

cat <<'EOT'
========================================================
Apps installation complete

- Packages installed from config/apps-pacman.txt
- AUR packages installed from config/apps-aur.txt
- LazyVim bootstrapped if Neovim is installed
- ~/.bash_profile configured with EDITOR and PATH

To add more apps:
  1. Edit config/apps-pacman.txt or config/apps-aur.txt
  2. Run: ./alpi.sh --only apps
========================================================
EOT
