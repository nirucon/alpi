#!/usr/bin/env bash
# CORE: Swedish keyboard, Xorg, NetworkManager, startx, fonts, essentials.

set -euo pipefail

info(){ printf "\033[1;32m[CORE]\033[0m %s\n" "$*"; }
info "Syncing and upgrading system (pacman -Syu)..."
sudo pacman --noconfirm -Syu

info "Setting Swedish keyboard for TTY..."
sudo install -Dm644 /dev/stdin /etc/vconsole.conf <<EOF
KEYMAP=sv-latin1
EOF

HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN"

info "Installing base packages for Xorg and tools..."
sudo pacman --noconfirm --needed -S \
  base-devel git \
  xorg-server xorg-xinit xorg-xrandr xorg-xsetroot \
  libx11 libxft libxinerama freetype2 fontconfig \
  ttf-dejavu \
  networkmanager wireless_tools iw \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  alsa-utils brightnessctl

info "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager.service

info "Install desktop fonts (JetBrainsMono Nerd Font via yay later, fallback now)..."
sudo pacman --noconfirm --needed -S noto-fonts ttf-nerd-fonts-symbols-mono

# Prepare startx auto on tty1
BASH_PROFILE="$HOME/.bash_profile"
grep -qxF '[ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && exec startx' "$BASH_PROFILE" 2>/dev/null \
  || echo '[ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && exec startx' >> "$BASH_PROFILE"

info "CORE step complete."
