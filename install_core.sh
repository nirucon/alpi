#!/usr/bin/env bash
# CORE – by Nicklas Rudolfsson https://github.com/nirucon
# English-only output

set -Eeuo pipefail
IFS=$'\n\t'

info(){ printf "\033[1;32m[CORE]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[CORE]\033[0m %s\n" "$*"; }
fail(){ printf "\033[1;31m[CORE]\033[0m %s\n" "$*" >&2; }

trap 'fail "install_core.sh failed. See logs above for details."' ERR

# -----------------------------------------------------------------------------
# Timeshift + autosnap hook (works with Limine; no grub-btrfs needed)
# Place this BEFORE any system upgrade so the pre-transaction snapshot runs now.
# -----------------------------------------------------------------------------
if ! command -v timeshift >/dev/null 2>&1; then
  info "Installing Timeshift…"
  sudo pacman -S --noconfirm --needed timeshift
else
  info "Timeshift already installed (skipping)."
fi

# If you have an AUR helper (yay), prefer the official autosnap package.
if command -v yay >/dev/null 2>&1; then
  if ! pacman -Qi timeshift-autosnap >/dev/null 2>&1; then
    info "Installing timeshift-autosnap (AUR) to enable pacman pre-transaction snapshots…"
    yay -S --noconfirm --needed timeshift-autosnap
  else
    info "timeshift-autosnap already installed (skipping)."
  fi
else
  # Minimal built-in pacman hook as a fallback when AUR is unavailable.
  if [[ ! -f /etc/pacman.d/hooks/50-timeshift-pre.hook ]]; then
    info "Creating minimal pacman hook for Timeshift pre-transaction snapshots…"
    sudo install -d -m 755 /etc/pacman.d/hooks
    sudo tee /etc/pacman.d/hooks/50-timeshift-pre.hook >/dev/null <<'EOF'
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Timeshift: create pre-transaction snapshot
When = PreTransaction
Exec = /usr/bin/timeshift --create --comments "pre-pacman" --tags P
NeedsTargets
EOF
  else
    info "Timeshift pacman hook already present (skipping)."
  fi
fi

# Optional: take an initial baseline snapshot
if sudo timeshift --list >/dev/null 2>&1; then
  info "Creating initial Timeshift snapshot (baseline)…"
  sudo timeshift --create --comments "Initial snapshot" --tags O || true
else
  warn "Timeshift not initialized yet; baseline snapshot skipped."
fi

# -----------------------------------------------------------------------------
# System refresh AFTER the autosnap hook is installed
# -----------------------------------------------------------------------------
info "Syncing and upgrading system (pacman -Syu)…"
sudo pacman --noconfirm -Syu

# -----------------------------------------------------------------------------
# Ensure ~/.local/bin exists
# -----------------------------------------------------------------------------
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN"

# -----------------------------------------------------------------------------
# Base Xorg, audio, networking, and essentials
# -----------------------------------------------------------------------------
info "Installing base packages for Xorg, audio, and networking…"
sudo pacman --noconfirm --needed -S \
  base-devel git \
  xorg-server xorg-xinit xorg-xrandr xorg-xsetroot \
  libx11 libxft libxinerama freetype2 fontconfig \
  ttf-dejavu noto-fonts ttf-nerd-fonts-symbols-mono \
  networkmanager wireless_tools iw \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  alsa-utils brightnessctl imlib2

# Enable NM so Wi-Fi/ethernet works out of the box
info "Enabling NetworkManager…"
sudo systemctl enable --now NetworkManager.service

# -----------------------------------------------------------------------------
# Auto-start X on tty1 for a smooth first login
# -----------------------------------------------------------------------------
BASH_PROFILE="$HOME/.bash_profile"
AUTO_START='[ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && exec startx'
if ! grep -qxF "$AUTO_START" "$BASH_PROFILE" 2>/dev/null; then
  info "Enabling startx auto-launch on tty1…"
  printf '%s\n' "$AUTO_START" >> "$BASH_PROFILE"
else
  warn "startx auto-launch already present in ~/.bash_profile (kept as-is)."
fi

info "CORE step complete."
