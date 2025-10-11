#!/usr/bin/env bash
# SUCKLESS installer (vanilla or NIRUCON) + minimal non-suckless setup (.xinitrc, picom, fonts)
# - Vanilla: clone upstream suckless.org and build with ZERO modifications
# - NIRUCON: clone https://github.com/nirucon/suckless and build as-is
# This script does NOT install the status bar — use install_statusbar.sh for that.
# Safe & idempotent. Comments in English.

set -euo pipefail
say(){ printf "\033[1;35m[SUCK]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[SUCK]\033[0m %s\n" "$*"; }

SUCKLESS_DIR="$HOME/.config/suckless"
LOCAL_BIN="$HOME/.local/bin"
PICOM_CFG="$HOME/.config/picom/picom.conf"
XINIT="$HOME/.xinitrc"

# Fonts used OUTSIDE suckless (we never touch vanilla configs)
FONT_MAIN="JetBrainsMono Nerd Font"   # rofi etc (optional, not required by suckless)
FONT_ICON="Symbols Nerd Font Mono"    # for icons if you later enable them in dwm yourself

mkdir -p "$SUCKLESS_DIR" "$LOCAL_BIN" "$(dirname "$PICOM_CFG")"

append_once() { local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
clone_or_pull(){ [ -d "$2/.git" ] && git -C "$2" pull --ff-only || git clone "$1" "$2"; }

# --------------------------------------------------------------------
# Minimal dependencies that do NOT modify suckless sources
# --------------------------------------------------------------------
say "Installing minimal helpers (safe for vanilla too)..."
sudo pacman --noconfirm --needed -S picom xorg-xsetroot curl awk sed grep coreutils

# Fonts: optional, they don't alter suckless; useful for rofi/term/your future config
say "Installing fonts (optional, safe)..."
sudo pacman --noconfirm --needed -S ttf-nerd-fonts-symbols-mono
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi
yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true

# --------------------------------------------------------------------
# Choose source (Vanilla = NO customization; NIRUCON = your repo as-is)
# --------------------------------------------------------------------
say "Choose suckless source:"
echo "  1) Vanilla (upstream suckless.org) — build with ZERO modifications  [default]"
echo "  2) NIRUCON (clone github.com/nirucon/suckless) — build as-is"
read -rp "Enter 1 or 2 [1]: " SRC_CHOICE
SRC_CHOICE="${SRC_CHOICE:-1}"

if [[ "$SRC_CHOICE" == "2" ]]; then
  # ---------------------- NIRUCON mode ----------------------
  say "Cloning NIRUCON repo into ${SUCKLESS_DIR} ..."
  if [ -d "$SUCKLESS_DIR/.git" ]; then
    git -C "$SUCKLESS_DIR" pull --ff-only || warn "git pull failed; using existing tree."
  else
    rm -rf "$SUCKLESS_DIR"
    git clone https://github.com/nirucon/suckless "$SUCKLESS_DIR"
  fi

  for comp in dmenu st slock dwm; do
    if [ -d "$SUCKLESS_DIR/$comp" ]; then
      say "Building $comp (as-is)..."
      make -C "$SUCKLESS_DIR/$comp" clean
      sudo make -C "$SUCKLESS_DIR/$comp" install
    else
      warn "$comp not found in repo — skipping."
    fi
  done

else
  # ---------------------- VANILLA mode ----------------------
  say "Cloning/updating upstream repos into ${SUCKLESS_DIR} ..."
  cd "$SUCKLESS_DIR"
  clone_or_pull "https://git.suckless.org/dwm"   "dwm"
  clone_or_pull "https://git.suckless.org/dmenu" "dmenu"
  clone_or_pull "https://git.suckless.org/slock" "slock"
  clone_or_pull "https://git.suckless.org/st"    "st"

  for comp in dmenu st slock dwm; do
    say "Building vanilla $comp (no changes)..."
    make -C "$comp" clean
    sudo make -C "$comp" install
  done
fi

# --------------------------------------------------------------------
# Picom: tiny config (not a suckless mod; safe to write once)
# --------------------------------------------------------------------
if ! grep -q "class_g = 'St'" "$PICOM_CFG" 2>/dev/null; then
  say "Writing minimal picom.conf (st opacity via compositor)..."
  mkdir -p "$(dirname "$PICOM_CFG")"
  cat > "$PICOM_CFG" <<'EOF'
opacity-rule = [
  "0.86:class_g = 'St'"
];
backend = "glx";
vsync = true;
EOF
fi

# --------------------------------------------------------------------
# .xinitrc (SE keyboard, nitrogen restore, picom, dwm) — status bar handled separately
# --------------------------------------------------------------------
say "Ensuring .xinitrc exists (SE keyboard, nitrogen restore, picom, dwm)..."
if [ ! -f "$XINIT" ]; then
  cat > "$XINIT" <<'EOF'
#!/bin/sh
# Swedish keyboard in X
setxkbmap se

# Restore wallpaper (nitrogen) if available
command -v nitrogen >/dev/null && nitrogen --restore &

# Compositor (useful for st translucency)
command -v picom >/dev/null && picom --experimental-backends &

# Status bar (installed by install_statusbar.sh)
[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &

# Solid background fallback
xsetroot -solid "#111111"

# Start dwm
exec dwm
EOF
  chmod 644 "$XINIT"
else
  # Append status bar launch if missing (install_statusbar.sh also ensures this, but harmless)
  grep -q 'dwm-status.sh' "$XINIT" 2>/dev/null || {
    echo '' >> "$XINIT"
    echo '# Status bar (installed by install_statusbar.sh)' >> "$XINIT"
    echo '[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &' >> "$XINIT"
  }
fi

say "Suckless install finished (vanilla untouched / NIRUCON as-is). Run install_statusbar.sh next for the bar."
