
#!/usr/bin/env bash
# CORE – by Nicklas Rudolfsson https://github.com/nirucon

set -Eeuo pipefail
IFS=$'\n\t'

info(){ printf "\033[1;32m[CORE]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[CORE]\033[0m %s\n" "$*"; }
fail(){ printf "\033[1;31m[CORE]\033[0m %s\n" "$*" >&2; }

trap 'fail "install_core.sh failed. Check the previous step for details."' ERR

# System refresh early so subsequent installs are smooth
info "Syncing and upgrading system (pacman -Syu)…"
sudo pacman --noconfirm -Syu

# TTY keymap (Swedish)
info "Setting Swedish TTY keymap (/etc/vconsole.conf)…"
sudo install -Dm644 /dev/stdin /etc/vconsole.conf <<'EOF'
KEYMAP=sv-latin1
EOF

# Ensure user bin exists for utilities we might add later
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN"

# Base Xorg, audio, networking, and essentials
info "Installing base packages for Xorg, audio, and networking…"
sudo pacman --noconfirm --needed -S \
  base-devel git \
  xorg-server xorg-xinit xorg-xrandr xorg-xsetroot \
  libx11 libxft libxinerama freetype2 fontconfig \
  ttf-dejavu noto-fonts ttf-nerd-fonts-symbols-mono \
  networkmanager wireless_tools iw \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  alsa-utils brightnessctl

# Enable NM so Wi-Fi/ethernet works out of the box
info "Enabling NetworkManager…"
sudo systemctl enable --now NetworkManager.service

# Auto-start X on tty1 for a smooth first login
BASH_PROFILE="$HOME/.bash_profile"
AUTO_START='[ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && exec startx'
if ! grep -qxF "$AUTO_START" "$BASH_PROFILE" 2>/dev/null; then
  info "Enabling startx auto-launch on tty1…"
  printf '%s\n' "$AUTO_START" >> "$BASH_PROFILE"
else
  warn "startx auto-launch already present in ~/.bash_profile (kept as-is)."
fi

info "CORE step complete."
