#!/usr/bin/env bash
# Add/remove items in the arrays; script handles the rest and prints progress.

set -euo pipefail
say(){ printf "\033[1;36m[APPS]\033[0m %s\n" "$*"; }

PACMAN_PKGS=(
  nitrogen         # wallpaper manager (restore on start)
  arandr           # display layout
  pcmanfm          # file manager
  gvfs             # virtual FS (needed for automount in pcmanfm)
  gvfs-mtp gvfs-gphoto2 gvfs-afc
  udisks2          # disks backend
  udiskie          # optional automount helper (tray if you want)
  cmus             # terminal music player
  cava             # audio visualizer
  flameshot        # screenshots
  picom            # compositor for st alpha
)

YAY_PKGS=(
  ttf-jetbrains-mono-nerd  # nice mono font
)

say "Installing pacman apps..."
sudo pacman --noconfirm --needed -S "${PACMAN_PKGS[@]}"

if ! command -v yay >/dev/null 2>&1; then
  say "yay not found; installing yay-bin..."
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi

say "Installing AUR apps via yay..."
yay --noconfirm --needed -S "${YAY_PKGS[@]}"

say "APPS step complete. To add more apps later, edit PACMAN_PKGS/YAY_PKGS arrays in this file."
