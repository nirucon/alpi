#!/usr/bin/env bash
set -euo pipefail

# Purpose:
# - Install core/runtime packages used by multiple steps.

echo "[CORE] Installing core packages..."

sudo pacman --noconfirm --needed -S \
  base-devel \
  git \
  wget \
  unzip \
  zip \
  neovim \
  ttf-nerd-fonts-symbols-mono

# Create standard dirs for user if needed.
echo "[CORE] Ensuring common user directories exist..."
mkdir -p "$HOME/.config" "$HOME/.local/bin"

# Add ~/.local/bin to PATH via ~/.bash_profile (idempotent).
BASH_PROFILE="$HOME/.bash_profile"
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$BASH_PROFILE" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASH_PROFILE"
  echo "[CORE] Added ~/.local/bin to PATH in ~/.bash_profile"
else
  echo "[CORE] ~/.local/bin already in PATH."
fi

echo "[CORE] Core installation complete."
