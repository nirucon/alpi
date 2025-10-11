#!/usr/bin/env bash
set -euo pipefail

# ALPI - Arch Linux Post Installer
# By Nicklas Rudolfsson for my own simple setup

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

echo "[ALPI] Starting Arch Linux post-install."
echo "[ALPI] Script directory: $SCRIPT_DIR"

# 1) Optimizations first (mirrors, pacman tuning, zram) so later installs benefit.
echo "[ALPI] (1/5) Running OPTIMIZE..."
bash "$SCRIPT_DIR/install_optimize.sh"

# 2) Core packages and base system tasks (no 'pacman -Syu' here to avoid duplicate updates).
echo "[ALPI] (2/5) Running CORE..."
bash "$SCRIPT_DIR/install_core.sh"

# 3) Apps: installs yay (if missing) and main desktop apps (incl. picom, rofi, etc.).
echo "[ALPI] (3/5) Running APPS..."
bash "$SCRIPT_DIR/install_apps.sh"

# 4) Suckless desktop (DWM etc.), writes a single authoritative .xinitrc (starts picom & wallrotate.sh).
echo "[ALPI] (4/5) Running SUCKLESS..."
bash "$SCRIPT_DIR/install_suckless.sh"

# 5) Statusbar, Nextcloud-aware script, appends startup line if needed.
echo "[ALPI] (5/5) Running STATUSBAR..."
bash "$SCRIPT_DIR/install_statusbar.sh"

# Themedots: copy configs (incl. picom.conf) and helper scripts into ~/.local/bin (+x).
echo "[ALPI] (Extra) Applying Themedots..."
bash "$SCRIPT_DIR/install_themedots.sh"

echo "[ALPI] Done. You can now start X with 'startx' (or configure your display manager)."
