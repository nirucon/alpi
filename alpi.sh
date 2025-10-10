#!/usr/bin/env bash
# Arch Linux Post Install (ALPI)

set -euo pipefail

GREEN="\033[1;32m"; BLUE="\033[1;34m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()   { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
step()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
oops()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1; }

if ! sudo -v; then oops "This script needs sudo privileges."; exit 1; fi

step "ALPI started"
say  "1/4 CORE  -> Keyboard (SE), Xorg, NetworkManager, startx, fonts"
./install_core.sh

say  "2/4 OPTIM -> Microcode, mirrors, zram, laptop power & thermal"
./install_optimize.sh

say  "3/4 SUCK  -> Build latest dwm/dmenu/st/slock + noir theme & keybinds"
./install_suckless.sh

say  "4/4 APPS  -> Desktop apps via pacman & yay lists"
./install_apps.sh

step "ALPI finished"
say  "Log out to TTY or reboot. Login on tty1 will auto-start dwm via startx."
