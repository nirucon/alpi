#!/usr/bin/env bash
# install_suckless.sh — build & install the suckless stack (dwm, st, dmenu, slock, slstatus)
# Purpose: Compile and install suckless programs (vanilla or nirucon tree), wire a safe ~/.xinitrc,
#          and (optionally) install minimal deps & fonts if missing.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
MAG="\033[1;35m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${MAG}[SUCK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_suckless.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || { fail "Do not run as root."; exit 1; }
command -v sudo >/dev/null 2>&1 || warn "sudo not found — system install steps may be skipped."

# ───────── Paths / Defaults ─────────
SUCKLESS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/suckless"
LOCAL_BIN="$HOME/.local/bin"
XINIT="$HOME/.xinitrc"
BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/suckless-build"
PREFIX="/usr/local"
JOBS="$(nproc 2>/dev/null || echo 2)"

# Upstream repos
DWM_REPO_VANILLA="https://git.suckless.org/dwm"
ST_REPO_VANILLA="https://git.suckless.org/st"
DMENU_REPO_VANILLA="https://git.suckless.org/dmenu"
SLOCK_REPO_VANILLA="https://git.suckless.org/slock"
SLSTATUS_REPO_VANILLA="https://git.suckless.org/slstatus"

# NIRUCON mono-repo
NIRUCON_REPO="https://github.com/nirucon/suckless"

SOURCE_MODE=""          # vanilla|nirucon (empty → decide later)
MANAGE_XINIT=1
INSTALL_FONTS=1
DRY_RUN=0
COMPONENTS=(dwm st dmenu slock slstatus)

FONT_MAIN="JetBrainsMono Nerd Font"
FONT_ICON="Symbols Nerd Font Mono"

usage(){ cat <<'EOF'
install_suckless.sh — options
  --source MODE      vanilla | nirucon   (if omitted, you will be asked in a TTY; otherwise default vanilla)
  --prefix DIR       Install prefix (default: /usr/local)
  --only LIST        Comma-separated subset: dwm,st,dmenu,slock,slstatus
  --no-xinit         Do NOT modify ~/.xinitrc
  --no-fonts         Do NOT attempt to install fonts
  --jobs N           Parallel make -j (default: nproc)
  --dry-run          Print actions without changing the system
  -h|--help          Show this help
EOF
}

need_val(){ local opt="$1" val="${2-}"; [[ -n "$val" ]] || fail "Option $opt requires a value. See --help."; }
parse_components(){ IFS=',' read -r -a COMPONENTS <<<"$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  need_val "$1" "${2-}"; SOURCE_MODE="$2"; shift 2;;
    --prefix)  need_val "$1" "${2-}"; PREFIX="$2"; shift 2;;
    --only)    need_val "$1" "${2-}"; parse_components "$2"; shift 2;;
    --jobs)    need_val "$1" "${2-}"; JOBS="$2"; shift 2;;
    --no-xinit) MANAGE_XINIT=0; shift;;
    --no-fonts) INSTALL_FONTS=0; shift;;
    --dry-run)  DRY_RUN=1; shift;;
    -h|--help)  usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# Decide source if not specified
if [[ -z "$SOURCE_MODE" ]]; then
  if [[ -t 0 ]]; then
    say "Choose suckless source:"
    echo "  1) Vanilla (upstream) — zero modifications [default]"
    echo "  2) Custom (NIRUCON repo) — your patched tree"
    read -rp "Enter 1 or 2 [1]: " choice
    choice="${choice:-1}"
    if [[ "$choice" == "2" ]]; then SOURCE_MODE="nirucon"; else SOURCE_MODE="vanilla"; fi
  else
    SOURCE_MODE="vanilla"
  fi
fi

# ───────── Helpers (array-safe) ─────────
ts(){ date +"%Y%m%d-%H%M%S"; }
ensure_dir(){ mkdir -p "$1"; }
append_once(){ local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
run(){ if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] $*"; else "$@"; fi; }
backup_if_exists(){ local f="$1"; [[ -e "$f" ]] || return 0; local b="${f}.bak.$(ts)"; cp -a -- "$f" "$b"; warn "Backup: $f -> $b"; }

pkg_install(){
  local pkgs=(base-devel git make gcc pkgconf
              libx11 libxft libxinerama libxrandr libxext libxrender libxfixes
              freetype2 fontconfig
              xorg-xsetroot xorg-xinit)
  if command -v pacman >/dev/null 2>&1; then
    step "Installing build/runtime dependencies via pacman (if missing)"
    run sudo pacman -S --needed --noconfirm "${pkgs[@]}" || warn "pacman dependency install failed (continuing)"
  else
    warn "pacman not found; ensure build deps are present manually."
  fi
}

fonts_install_if_missing(){
  [[ $INSTALL_FONTS -eq 1 ]] || { warn "--no-fonts set: skipping font checks/install"; return 0; }
  step "Checking for required fonts"
  local need_main=1 need_icon=1
  fc-list | grep -qi "${FONT_MAIN}"  && need_main=0 || true
  fc-list | grep -qi "${FONT_ICON}"  && need_icon=0 || true
  (( need_main==0 && need_icon==0 )) && { say "Required fonts already installed"; return 0; }
  if (( need_icon==1 )) && command -v pacman >/dev/null 2>&1; then
    say "Installing ${FONT_ICON} via pacman"
    run sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols-mono || true
  fi
  if (( need_main==1 )); then
    if ! command -v yay >/dev/null 2>&1; then
      step "Installing yay-bin (AUR helper) to fetch ${FONT_MAIN}"
      local tmp; tmp="$(mktemp -d)"
      run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
      ( cd "$tmp/yay-bin" && run makepkg -si --noconfirm )
      rm -rf "$tmp"
    fi
    say "Installing ${FONT_MAIN} via yay"
    run yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true
  fi
}

clone_or_pull(){
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    step "Updating $(basename "$dir")"
    run git -C "$dir" fetch --all --prune || warn "git fetch failed for $dir"
    run git -C "$dir" pull --ff-only || warn "git pull failed for $dir; keeping existing tree."
  else
    ensure_dir "$(dirname "$dir")"
    step "Cloning $(basename "$dir")"
    run git clone "$url" "$dir"
  fi
}

make_install(){
  local dir="$1" name="$2"
  step "Building $name"
  ( cd "$dir" && { [[ $DRY_RUN -eq 1 ]] && say "[dry-run] make -j$JOBS && sudo make PREFIX=$PREFIX install" \
                || { make clean && make -j"$JOBS" && sudo make PREFIX="$PREFIX" install; }; } )
}

# ───────── Prepare & deps ─────────
ensure_dir "$SUCKLESS_DIR" "$LOCAL_BIN" "$BUILD_DIR"
pkg_install
fonts_install_if_missing

# ───────── Fetch sources ─────────
case "$SOURCE_MODE" in
  vanilla)
    say "Source mode: VANILLA (upstream)"
    clone_or_pull "$DWM_REPO_VANILLA"      "$SUCKLESS_DIR/dwm"
    clone_or_pull "$ST_REPO_VANILLA"       "$SUCKLESS_DIR/st"
    clone_or_pull "$DMENU_REPO_VANILLA"    "$SUCKLESS_DIR/dmenu"
    clone_or_pull "$SLOCK_REPO_VANILLA"    "$SUCKLESS_DIR/slock"
    clone_or_pull "$SLSTATUS_REPO_VANILLA" "$SUCKLESS_DIR/slstatus"
    ;;
  nirucon)
    say "Source mode: CUSTOM (NIRUCON repo)"
    clone_or_pull "$NIRUCON_REPO" "$SUCKLESS_DIR"
    ;;
  *) fail "Unknown source mode: $SOURCE_MODE";;
esac

# ───────── Build & install ─────────
for comp in "${COMPONENTS[@]}"; do
  if [[ -d "$SUCKLESS_DIR/$comp" ]]; then
    make_install "$SUCKLESS_DIR/$comp" "$comp"
  else
    warn "$comp not found under $SUCKLESS_DIR — skipping"
  fi
done

# ───────── .xinitrc wiring ─────────
if [[ $MANAGE_XINIT -eq 1 ]]; then
  step "Wiring ~/.xinitrc (safe, minimal)"
  if [[ ! -f "$XINIT" ]]; then
    cat > "$XINIT" <<'EOF'
#!/bin/sh
# =============================================================================
#  .xinitrc — Arch Linux + Suckless Nirucon setup
# =============================================================================

#----------------------------#
# 1) Basic session hygiene   #
#----------------------------#

# Always start in $HOME
cd "$HOME"

# If no user D-Bus is present, re-exec this script under dbus-run-session.
# This is the most reliable way to get a working session bus for X11 + startx.
if [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session "$0" "$@"
fi

# Export X env vars to systemd --user so user services (like dunst.service) can find DISPLAY/XAUTHORITY.
# Harmless if systemd user instance isn't running.
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
fi

# Merge X resources if present (fonts, colors, DPI, etc.)
[ -r "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Keyboard layout (set yours; example: Swedish). Comment this out if configured elsewhere.
command -v setxkbmap >/dev/null 2>&1 && setxkbmap se

# Set a simple root background color (prevents unstyled root-window flash).
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid "#111111"

# Optional: enable NumLock if available
command -v numlockx >/dev/null 2>&1 && numlockx on

# Optional: HiDPI scaling example via xrandr (uncomment and adjust as needed)
# command -v xrandr >/dev/null 2>&1 && xrandr --output eDP-1 --scale 0.75x0.75

#--------------------------------#
# 2) Autostart helper programs   #
#--------------------------------#

# Compositor (tear-free, transparency). Remove if you prefer no compositor.
command -v picom >/dev/null 2>&1 && picom &

# Wallpaper restore (Nitrogen). Safe no-op if missing.
command -v nitrogen >/dev/null 2>&1 && nitrogen --restore &

# Cloud client (Nextcloud) in background mode if installed.
command -v nextcloud >/dev/null 2>&1 && nextcloud --background &

# Notifications (dunst). Start explicitly so notify-send works immediately.
# If you prefer the systemd user unit, this is still safe; dunst will refuse a duplicate.
command -v dunst >/dev/null 2>&1 && dunst &

# DWM status bar
[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &

# Optional: screen locker on idle (requires both xautolock + slock).
if command -v xautolock >/dev/null 2>&1 && command -v slock >/dev/null 2>&1; then
  # Lock after 10 minutes idle; adjust to taste.
  xautolock -time 10 -locker slock &
fi

# Wallpaper rotator
[ -x "$HOME/.local/bin/wallrotate.sh" ] && "$HOME/.local/bin/wallrotate.sh" &

# Polkit agent
if command -v /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 >/dev/null 2>&1; then
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
fi

#----------------------------------------------#
# 3) Clean teardown & robust DWM launch loop   #
#----------------------------------------------#

# Ensure all background children die when this script exits.
trap 'kill -- -$$' EXIT

# Path to log DWM
DWM_LOG="/tmp/dwm.log"

# Find DWM binary (installed or custom-compiled).
DWM_BIN="$(command -v dwm || echo /usr/local/bin/dwm)"

# Restart policy:
# - If DWM exits with code 0 (normal quit), stop the loop and end session.
# - If it crashes (non-zero), restart automatically.
while :; do
  "$DWM_BIN" 2>"$DWM_LOG"
  status=$?
  [ $status -eq 0 ] && break
  # Brief pause to avoid rapid restart loops in case of immediate crash
  sleep 0.5
done

# If we get here with status 0, session exits cleanly (dbus-run-session will also exit).
EOF
    chmod 644 "$XINIT"
  else
    append_once '# --- SUCKLESS HOOKS ---' "$XINIT"
    append_once 'setxkbmap se' "$XINIT"
    append_once 'xsetroot -solid "#111111"' "$XINIT"
    append_once '[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &' "$XINIT"
    append_once '[ -x "$HOME/.local/bin/wallrotate.sh" ] && "$HOME/.local/bin/wallrotate.sh" &' "$XINIT"
    append_once 'command -v nextcloud >/dev/null && nextcloud --background &' "$XINIT"
    append_once 'if command -v xautolock >/dev/null && command -v slock >/dev/null; then xautolock -time 10 -locker slock & fi' "$XINIT"
    append_once 'while true; do "$(command -v dwm || echo /usr/local/bin/dwm)" 2> /tmp/dwm.log; done' "$XINIT"
  fi
else
  warn "--no-xinit set: leaving ~/.xinitrc untouched"
fi

cat <<'EOT'
========================================================
Suckless install finished

• Components built: dwm/st/dmenu/slock/slstatus (customize with --only)
• picom.conf is managed by install_lookandfeel.sh
• Status bar script is installed by install_statusbar.sh
• Start X with:  startx
========================================================
EOT
