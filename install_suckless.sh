#!/usr/bin/env bash
# SUCKLESS – by Nicklas Rudolfsson https://github.com/nirucon

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Pretty logging ----------
MAG="\033[1;35m"; YLW="\033[1;33m"; NC="\033[0m"
say(){  printf "${MAG}[SUCK]${NC} %s\n" "$*"; }
warn(){ printf "${YLW}[SUCK]${NC} %s\n" "$*"; }
fail(){ printf "\033[1;31m[SUCK]\033[0m %s\n" "$*" >&2; }

trap 'fail "install_suckless.sh failed. See previous step for details."' ERR

SUCKLESS_DIR="$HOME/.config/suckless"
LOCAL_BIN="$HOME/.local/bin"
PICOM_CFG="$HOME/.config/picom/picom.conf"
XINIT="$HOME/.xinitrc"

# Fonts used outside suckless (safe for vanilla)
FONT_MAIN="JetBrainsMono Nerd Font"
FONT_ICON="Symbols Nerd Font Mono"

mkdir -p "$SUCKLESS_DIR" "$LOCAL_BIN" "$(dirname "$PICOM_CFG")"

append_once() {
  # Append a line once to a file (exact match)
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

clone_or_pull(){
  # Clone if absent; otherwise fast-forward pull
  local url="$1" dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only || warn "git pull failed for $dir; keeping existing tree."
  else
    git clone "$url" "$dir"
  fi
}

# ---------- Non-invasive helpers (safe for vanilla) ----------
say "Installing minimal helpers (picom, xsetroot, cli basics)…"
sudo pacman --noconfirm --needed -S picom xorg-xsetroot curl awk sed grep coreutils

say "Installing fonts (Nerd Symbols via pacman; JetBrains via yay)…"
sudo pacman --noconfirm --needed -S ttf-nerd-fonts-symbols-mono
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi
yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true

# ---------- Source selection ----------
say "Choose suckless source:"
echo "  1) Vanilla (upstream) — build with ZERO modifications  [default]"
echo "  2) NIRUCON (github.com/nirucon/suckless) — build as-is"
read -rp "Enter 1 or 2 [1]: " SRC_CHOICE
SRC_CHOICE="${SRC_CHOICE:-1}"

if [[ "$SRC_CHOICE" == "2" ]]; then
  # NIRUCON mode
  say "Cloning NIRUCON repo into ${SUCKLESS_DIR}…"
  if [ -d "$SUCKLESS_DIR/.git" ]; then
    git -C "$SUCKLESS_DIR" pull --ff-only || warn "git pull failed; using existing tree."
  else
    rm -rf "$SUCKLESS_DIR"
    git clone https://github.com/nirucon/suckless "$SUCKLESS_DIR"
  fi

  for comp in dmenu st slock dwm; do
    if [ -d "$SUCKLESS_DIR/$comp" ]; then
      say "Building $comp (as-is)…"
      make -C "$SUCKLESS_DIR/$comp" clean
      sudo make -C "$SUCKLESS_DIR/$comp" install
    else
      warn "$comp not found in repo — skipping."
    fi
  done
else
  # Vanilla mode
  say "Cloning/updating upstream repos into ${SUCKLESS_DIR}…"
  cd "$SUCKLESS_DIR"
  clone_or_pull "https://git.suckless.org/dwm"   "dwm"
  clone_or_pull "https://git.suckless.org/dmenu" "dmenu"
  clone_or_pull "https://git.suckless.org/slock" "slock"
  clone_or_pull "https://git.suckless.org/st"    "st"

  for comp in dmenu st slock dwm; do
    say "Building vanilla $comp (no changes)…"
    make -C "$comp" clean
    sudo make -C "$comp" install
  done
fi

# ---------- Picom: tiny, safe defaults ----------
if ! grep -q "class_g = 'St'" "$PICOM_CFG" 2>/dev/null; then
  say "Writing minimal picom.conf (st opacity via compositor)…"
  mkdir -p "$(dirname "$PICOM_CFG")"
  cat > "$PICOM_CFG" <<'EOF'
opacity-rule = [
  "0.86:class_g = 'St'"
];
backend = "glx";
vsync = true;
EOF
fi

# ---------- .xinitrc (status bar installed separately) ----------
say "Ensuring .xinitrc exists (SE keyboard, nitrogen restore, picom, dwm)…"
if [ ! -f "$XINIT" ]; then
  cat > "$XINIT" <<'EOF'
#!/bin/sh
# ────────────────────────────────────────────────
# Nicklas Rudolfsson xinit config
# ────────────────────────────────────────────────

# Go to home directory to ensure relative paths work
cd "$HOME"

# ────────────────────────────────────────────────
# Keyboard layout
# ────────────────────────────────────────────────
setxkbmap se    # Set Swedish keyboard layout

# ────────────────────────────────────────────────
# Solid color fallback (used briefly before wallpaper loads)
# ────────────────────────────────────────────────
xsetroot -solid "#111111"

# ────────────────────────────────────────────────
# Restore last wallpaper using Nitrogen (if installed)
# ────────────────────────────────────────────────
if command -v nitrogen >/dev/null; then
    nitrogen --restore &
fi

# ────────────────────────────────────────────────
# Start rotating wallpapers every 15 minutes (if script exists)
# Script: ~/.local/bin/wallrotate.sh
# ────────────────────────────────────────────────
if [ -x "$HOME/.local/bin/wallrotate.sh" ]; then
    "$HOME/.local/bin/wallrotate.sh" &
fi

# ────────────────────────────────────────────────
# Start compositor (for transparency, shadows, etc.)
# ────────────────────────────────────────────────
if command -v picom >/dev/null; then
    picom --experimental-backends &
fi

# ────────────────────────────────────────────────
# Start your DWM status bar (if available)
# ────────────────────────────────────────────────
if [ -x "$HOME/.local/bin/dwm-status.sh" ]; then
    "$HOME/.local/bin/dwm-status.sh" &
fi

# ────────────────────────────────────────────────
# Automatic screen locker after inactivity
# Uses xautolock + slock
# ────────────────────────────────────────────────
if command -v xautolock >/dev/null && command -v slock >/dev/null; then
    xautolock -time 10 -locker slock &
fi

# ────────────────────────────────────────────────
# Start Nextcloud sync client (if installed)
# ────────────────────────────────────────────────
if command -v nextcloud >/dev/null; then
    nextcloud --background &
fi

# ────────────────────────────────────────────────
# For transparency
# ────────────────────────────────────────────────
picom &

# ────────────────────────────────────────────────
# Trap to clean up background processes on exit
# ────────────────────────────────────────────────
trap 'kill -- -$$' EXIT

# ────────────────────────────────────────────────
# Start DWM with auto-restart on crash or manual restart
# Log output to /tmp/dwm.log for debugging
# ────────────────────────────────────────────────
while true; do
    /usr/local/bin/dwm 2> /tmp/dwm.log
done
EOF
  chmod 644 "$XINIT"
else
  append_once '# Status bar (installed by install_statusbar.sh)' "$XINIT"
  append_once '[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &' "$XINIT"
fi

say "Suckless install finished. Run install_statusbar.sh for the status bar."
