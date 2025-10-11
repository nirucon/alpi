#!/usr/bin/env bash
# SUCKLESS installer (vanilla or NIRUCON) + status bar + .xinitrc

set -euo pipefail
say(){ printf "\033[1;35m[SUCK]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[SUCK]\033[0m %s\n" "$*"; }

SUCKLESS_DIR="$HOME/.config/suckless"
LOCAL_BIN="$HOME/.local/bin"
ROFI_DIR="$HOME/.config/rofi"
PICOM_CFG="$HOME/.config/picom/picom.conf"
XINIT="$HOME/.xinitrc"

# Fonts:
FONT_ICON="Symbols Nerd Font Mono"   # for status icons
FONT_MAIN="JetBrainsMono Nerd Font"  # nice monospace (used by rofi theme etc.)

mkdir -p "$SUCKLESS_DIR" "$LOCAL_BIN" "$ROFI_DIR" "$(dirname "$PICOM_CFG")"

# --------------------------------------------------------------------
# Dependencies (picom + fonts + build helpers)
# --------------------------------------------------------------------
say "Installing compositor (picom) and base tools..."
sudo pacman --noconfirm --needed -S picom curl awk sed grep coreutils

say "Installing fonts (icons + mono)..."
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

clone_or_pull(){ [ -d "$2/.git" ] && git -C "$2" pull --ff-only || git clone "$1" "$2"; }

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
# Picom: small config (safe even for vanilla — it's not a suckless mod)
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
# Status bar (icon-aware, ASCII fallback if icons won't render)
# --------------------------------------------------------------------
say "Installing updated dwm status bar (icons + ASCII fallback)..."
install -Dm755 /dev/stdin "$LOCAL_BIN/dwm-status.sh" <<'EOF'
#!/usr/bin/env bash
# DWM status: [ 🔋/ | /disconnected | YYYY-MM-DD (w:WW) | HH:MM ]
# Icons require a font with those glyphs in dwm. If missing, we fallback to ASCII.
set -euo pipefail

supports_icons() {
  # crude heuristic: if Symbols Nerd Font is installed AND user wants icons
  fc-list | grep -qi "Symbols Nerd Font" || return 1
  # If dwm isn't configured to use it, glyphs may still tofu; allow override via ENV
  [ "${DWM_STATUS_ICONS:-1}" = "1" ]
}

battery() {
  shopt -s nullglob
  local bat_dirs=(/sys/class/power_supply/BAT*)
  shopt -u nullglob
  [ ${#bat_dirs[@]} -gt 0 ] || return 0

  local b="${bat_dirs[0]}"
  local cap="$(cat "$b/capacity" 2>/dev/null || echo "")"
  [ -n "$cap" ] || return 0
  local stat="$(cat "$b/status" 2>/dev/null || echo "")"

  if supports_icons; then
    local icon=""
    if   [ "$cap" -ge 90 ]; then icon=""
    elif [ "$cap" -ge 70 ]; then icon=""
    elif [ "$cap" -ge 50 ]; then icon=""
    elif [ "$cap" -ge 30 ]; then icon=""
    fi
    if [ "$stat" = "Charging" ]; then
      printf " %s %s%%" "$icon" "$cap"
    else
      printf "%s %s%%" "$icon" "$cap"
    fi
  else
    if [ "$stat" = "Charging" ]; then
      printf "BAT %s%% CHG" "$cap"
    else
      printf "BAT %s%%" "$cap"
    fi
  fi
}

wifi() {
  shopt -s nullglob
  local wl_ifaces=(/sys/class/net/wl*)
  shopt -u nullglob
  [ ${#wl_ifaces[@]} -gt 0 ] || return 0

  local ssid=""
  if command -v iwgetid >/dev/null 2>&1; then
    ssid="$(iwgetid -r 2>/dev/null || true)"
  fi
  if [ -z "$ssid" ] && command -v nmcli >/dev/null 2>&1; then
    ssid="$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null \
      | awk -F: '$2=="wifi" && $3=="connected"{print $4; exit}')"
  fi

  if [ -n "$ssid" ]; then
    if supports_icons; then printf " %s" "$ssid"; else printf "WIFI %s" "$ssid"; fi
  else
    if supports_icons; then printf "睊 disconnected"; else printf "WIFI disconnected"; fi
  fi
}

build_line() {
  local parts=()

  local b_str; b_str="$(battery 2>/dev/null || true)"; [ -n "${b_str:-}" ] && parts+=("$b_str")
  local w_str; w_str="$(wifi 2>/dev/null || true)";    [ -n "${w_str:-}" ] && parts+=("$w_str")

  local d t
  d="$(date +'%Y-%m-%d (w:%V)')"
  t="$(date +'%H:%M')"
  if supports_icons; then
    parts+=(" $d" " $t")
  else
    parts+=("DATE $d" "TIME $t")
  fi

  local line="${parts[0]:-}"
  if [ ${#parts[@]} -gt 1 ]; then
    for p in "${parts[@]:1}"; do line+=" | $p"; done
  fi
  printf "[ %s ]" "$line"
}

while :; do
  xsetroot -name "$(build_line)"
  sleep 10
done
EOF

# --------------------------------------------------------------------
# .xinitrc (Swedish keyboard, nitrogen restore, picom, status, dwm)
# --------------------------------------------------------------------
say "Creating .xinitrc (SE keyboard, nitrogen restore, picom, status, dwm)..."
cat > "$XINIT" <<'EOF'
#!/bin/sh
# Swedish keyboard in X
setxkbmap se

# Restore wallpaper (nitrogen) if available
command -v nitrogen >/dev/null && nitrogen --restore &

# Compositor (needed for st opacity rule above)
command -v picom >/dev/null && picom --experimental-backends &

# Status bar updater (icons if available, ASCII otherwise)
~/.local/bin/dwm-status.sh &

# Solid background fallback
xsetroot -solid "#111111"

# Start dwm
exec dwm
EOF
chmod 644 "$XINIT"

say "Suckless - Done."
