#!/usr/bin/env bash
# ALPI – by Nicklas Rudolfsson https://github.com/nirucon

# Strict mode for reliability
set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Pretty logging ----------
GREEN="\033[1;32m"; BLUE="\033[1;34m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
step() { printf "${BLUE}==>${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

# ---------- Error trap with line context ----------
on_error() {
  local exit_code=$?
  fail "ALPI aborted (exit $exit_code). See the last step above for context."
  exit "$exit_code"
}
trap on_error ERR

# ---------- Resolve script directory so we can run from anywhere ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Sudo pre-flight ----------
if ! sudo -v; then
  fail "Sudo privileges are required to continue."
  exit 1
fi

step "ALPI started"
say  "1/4 CORE  -> Keyboard (SE), Xorg, NetworkManager, startx, fonts"
bash "$SCRIPT_DIR/install_core.sh"

say  "2/4 OPTIM -> Microcode, mirrors (optional), zram, laptop power/thermals, timesync"
bash "$SCRIPT_DIR/install_optimize.sh"

say  "3/4 SUCK  -> Build dwm/dmenu/st/slock (vanilla or NIRUCON), minimal X init + picom"
bash "$SCRIPT_DIR/install_suckless.sh"

say  "4/4 APPS  -> Desktop apps via pacman & yay, LazyVim bootstrap"
bash "$SCRIPT_DIR/install_apps.sh"

# ---------- Optional: theming & dotfiles ----------
if [ -x "$SCRIPT_DIR/install_themedots.sh" ]; then
  echo
  warn "Optional step: theming & dotfiles (.bashrc, dunst, alacritty, rofi) from nirucon/suckless_themedots"
  read -rp "Run install_themedots.sh now? [y/N]: " _ans
  _ans="${_ans:-N}"
  if [[ "$_ans" =~ ^[Yy]$ ]]; then
    say  "5/5 DOTS  -> Applying theming & dotfiles"
    bash "$SCRIPT_DIR/install_themedots.sh"
  else
    say  "Skipping theming/dots (you can run: $SCRIPT_DIR/install_themedots.sh later)."
  fi
else
  warn "install_themedots.sh not found in $SCRIPT_DIR — skipping optional theming step."
fi

step "ALPI finished"
say  "Log out to TTY or reboot. Login on tty1 will auto-start dwm via startx."
