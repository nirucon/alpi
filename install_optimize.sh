#!/usr/bin/env bash
set -euo pipefail

# Purpose:
# - Make safe, minimal system optimizations early: pacman.conf tuning, mirrors (optional), zram.
# Non-interactive:
# - ALPI_NONINTERACTIVE=1 skips mirror questions (default: skip reflector).

echo "[OPTI] Optimizing system configuration..."

# 1) pacman.conf tuning: enable ParallelDownloads safely if not already enabled.
PACMAN_CONF="/etc/pacman.conf"
if ! grep -Eq '^\s*ParallelDownloads\s*=\s*[0-9]+' "$PACMAN_CONF"; then
  echo "[OPTI] Enabling ParallelDownloads in pacman.conf (value: 5)."
  sudo sed -i 's/^\s*#\?\s*ParallelDownloads\s*=.*/ParallelDownloads = 5/; t; $a ParallelDownloads = 5' "$PACMAN_CONF"
else
  echo "[OPTI] ParallelDownloads already configured."
fi

# 2) Optionally refresh mirrors with reflector (skipped by default in non-interactive mode).
USE_REFLECTOR="n"
if [ "${ALPI_NONINTERACTIVE:-0}" != "1" ]; then
  echo -n "[OPTI] Use reflector to refresh mirrorlist now? (y/N): "
  read -r USE_REFLECTOR
fi

if [[ "${USE_REFLECTOR,,}" == "y" ]]; then
  echo "[OPTI] Installing reflector and refreshing mirrorlist..."
  sudo pacman --noconfirm --needed -S reflector
  # Keep it simple and conservative; Sweden + nearby.
  sudo reflector --country Sweden,Denmark,Norway,Finland --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
else
  echo "[OPTI] Skipping reflector (using current mirrorlist)."
fi

# 3) Update package database and system once, after mirror/pacman tuning.
echo "[OPTI] Updating system packages (pacman -Syu)..."
sudo pacman --noconfirm -Syyu

# 4) zram: write minimal config atomically and enable.
echo "[OPTI] Configuring zram via systemd zram-generator..."
sudo pacman --noconfirm --needed -S zram-generator
ZRAM_CFG="/etc/systemd/zram-generator.conf"
TMP="$(mktemp)"
cat >"$TMP" <<'EOF'
# zram-generator configuration (atomic write)
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF
sudo install -m 0644 -b "$TMP" "$ZRAM_CFG"
rm -f "$TMP"

echo "[OPTI] Reloading systemd and (re)starting zram unit..."
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || true

echo "[OPTI] Optimization complete."
