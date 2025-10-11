#!/usr/bin/env bash
set -euo pipefail

# Purpose:
# - Install primary desktop applications.

echo "[APPS] Installing desktop applications..."

# pacman packages (prefer repo when available)
PACMAN_PKGS=(
  nitrogen
  alacritty
  rofi
  dunst
  libnotify
  feh
  xorg-xset
  xorg-xrandr
  xorg-xinit
  xclip
  picom
  maim
  jq
)

sudo pacman --noconfirm --needed -S "${PACMAN_PKGS[@]}"

# Install yay (only here; idempotent)
if ! command -v yay >/dev/null 2>&1; then
  echo "[APPS] Installing yay (AUR helper)..."
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmpdir"
else
  echo "[APPS] yay already installed."
fi

# AUR packages
YAY_PKGS=(
  ttf-jetbrains-mono-nerd
  brave-bin
  spotify
  xautolock
)

echo "[APPS] Installing AUR packages with yay..."
yay --noconfirm --needed -S "${YAY_PKGS[@]}" || true

echo "[APPS] Applications installation complete."
