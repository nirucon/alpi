#!/usr/bin/env bash
# OPTIMIZE: Safe performance tuning: pacman, makepkg, mirrors, microcode, zram, laptop power.

set -euo pipefail
say(){ printf "\033[1;34m[OPTI]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[OPTI]\033[0m %s\n" "$*"; }

say "Enabling pacman Color and ParallelDownloads=10..."
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf || true
if grep -Eq '^\s*ParallelDownloads\s*=' /etc/pacman.conf; then
  sudo sed -i 's/^\s*ParallelDownloads\s*=.*/ParallelDownloads = 10/' /etc/pacman.conf
else
  echo 'ParallelDownloads = 10' | sudo tee -a /etc/pacman.conf >/dev/null
fi

say "Setting MAKEFLAGS to -j$(nproc)..."
sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j$(nproc)\"|g" /etc/makepkg.conf

say "Refreshing fast mirrors (SE/NO/DK) with reflector..."
sudo pacman --noconfirm --needed -S reflector
sudo systemctl stop reflector.service || true
sudo reflector --verbose --country Sweden,Norway,Denmark \
  --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist \
  || warn "Reflector failed; keeping existing mirrors."

say "Installing CPU microcode..."
if grep -q GenuineIntel /proc/cpuinfo; then
  sudo pacman --noconfirm --needed -S intel-ucode
elif grep -q AuthenticAMD /proc/cpuinfo; then
  sudo pacman --noconfirm --needed -S amd-ucode
else
  warn "Unknown CPU vendor; skipping microcode."
fi

say "Enabling zram (lz4, size = RAM/2)..."
sudo pacman --noconfirm --needed -S zram-generator
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || true

# Laptop detection via battery presence
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  say "Laptop detected: enabling TLP (disable power-profiles-daemon)."
  sudo pacman --noconfirm --needed -S tlp
  sudo systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
  sudo systemctl enable --now tlp.service
  if grep -q GenuineIntel /proc/cpuinfo; then
    say "Intel laptop: enabling thermald."
    sudo pacman --noconfirm --needed -S thermald
    sudo systemctl enable --now thermald.service
  fi
fi

say "Optimization step complete."
