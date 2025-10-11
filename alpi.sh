#!/usr/bin/env bash
# ALPI – by Nicklas Rudolfsson (nirucon)
# One-shot setup for Arch Linux suckless/dwm environment for my own needs - NO WARRANTY!
# Runs: core -> optimize -> suckless -> apps -> statusbar -> (optional) themedots

set -Eeuo pipefail
IFS=$'\n\t'

# -------------------- Colors --------------------
GREEN="\033[1;32m"; BLUE="\033[1;34m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
step() { printf "${BLUE}==>${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; }

# -------------------- Error trap --------------------
on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]}
  fail "Error on line ${line_no}. Aborting. (exit ${exit_code})"
  exit $exit_code
}
trap on_error ERR

# -------------------- Preconditions --------------------
if [[ ${EUID} -eq 0 ]]; then
  fail "Do not run alpi.sh as root. Run as a normal user; the script uses sudo when needed."
  exit 1
fi

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  fail "\$HOME is not set or does not point to a valid directory."
  exit 1
fi

# Resolve SCRIPT_DIR even if symlinked
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"

say  "Starting ALPI"
say  "SCRIPT_DIR: $SCRIPT_DIR"
say  "User:       $(whoami)"
say  "HOME:       $HOME"

# -------------------- Require helper scripts --------------------
require_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    fail "Missing file: $f"
    exit 1
  fi
  if [[ ! -x "$f" ]]; then
    warn "File not executable, setting +x: $f"
    chmod +x "$f"
  fi
}

require_file "$SCRIPT_DIR/install_core.sh"
require_file "$SCRIPT_DIR/install_optimize.sh"
require_file "$SCRIPT_DIR/install_suckless.sh"
require_file "$SCRIPT_DIR/install_apps.sh"
require_file "$SCRIPT_DIR/install_statusbar.sh"
# optional
if [[ -f "$SCRIPT_DIR/install_themedots.sh" ]]; then
  chmod +x "$SCRIPT_DIR/install_themedots.sh" || true
fi

# -------------------- Run steps --------------------
echo
step "1/5 CORE  -> Base installation and system tasks"
bash "$SCRIPT_DIR/install_core.sh"

echo
step "2/5 OPTI  -> Optimizations"
bash "$SCRIPT_DIR/install_optimize.sh"

echo
step "3/5 SUCK  -> Build/Install suckless (dwm/dmenu/st etc.)"
bash "$SCRIPT_DIR/install_suckless.sh"

echo
step "4/5 APPS  -> Install applications"
bash "$SCRIPT_DIR/install_apps.sh"

echo
step "5/5 SBAR  -> Install status bar (~/.local/bin/dwm-status.sh)"
bash "$SCRIPT_DIR/install_statusbar.sh"

# -------------------- Sanity checks --------------------
echo
step "Verifying status bar & .xinitrc"
if [[ -f "$HOME/.local/bin/dwm-status.sh" ]]; then
  say  "OK: Found $HOME/.local/bin/dwm-status.sh"
else
  warn "Missing $HOME/.local/bin/dwm-status.sh (install_statusbar.sh may have aborted?)."
fi

if [[ -f "$HOME/.xinitrc" ]]; then
  if grep -q "dwm-status.sh" "$HOME/.xinitrc"; then
    say  "OK: .xinitrc launches the status bar."
  else
    warn ".xinitrc does not seem to start the status bar. Add:  ~/.local/bin/dwm-status.sh &"
  fi
else
  warn "Missing $HOME/.xinitrc – verify that install_suckless.sh created it."
fi

# -------------------- Optional: theming & dotfiles --------------------
if [ -x "$SCRIPT_DIR/install_themedots.sh" ]; then
  echo
  warn "Optional step: theming & dotfiles (bashrc, dunst, alacritty, rofi)."
  read -rp "Run install_themedots.sh now? [y/N]: " _ans
  _ans="${_ans:-N}"
  if [[ "$_ans" =~ ^[Yy]$ ]]; then
    say  "DOTS -> Applying theme & dotfiles"
    bash "$SCRIPT_DIR/install_themedots.sh"
  else
    say  "Skipped theming/dots (run later if needed)."
  fi
else
  warn "install_themedots.sh not found in $SCRIPT_DIR — skipping."
fi

echo
step "ALPI finished."
say  "Log out to TTY or reboot. Logging in on tty1 starts dwm via startx (if configured)."
