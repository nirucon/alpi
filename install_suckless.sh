#!/usr/bin/env bash
# install_suckless.sh — build & install the suckless stack (dwm, st, dmenu, slock, slstatus)
# Purpose: Compile and install suckless programs with zero/own patches, wire a safe ~/.xinitrc,
#          and (optionally) install minimal runtime deps & fonts if missing.
# Author:  Nicklas Rudolfsson (NIRUCON)
# Output:  Clear, English-only status messages. Safe & idempotent where possible.
# Notes:   Picom *configuration* is handled by install_lookandfeel.sh to avoid conflicts.
#          This script will NOT write picom.conf. It may install picom package if missing.

set -Eeuo pipefail
IFS=$'
	'

# ───────── Pretty logging ─────────
MAG="[1;35m"; YLW="[1;33m"; RED="[1;31m"; BLU="[1;34m"; GRN="[1;32m"; NC="[0m"
say()  { printf "${MAG}[SUCK]${NC} %s
" "$*"; }
step() { printf "${BLU}==>${NC} %s
" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s
" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s
" "$*" >&2; }
trap 'fail "install_suckless.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run as root. This script writes to HOME and uses sudo only when needed."; exit 1
fi
command -v sudo >/dev/null 2>&1 || warn "sudo not found — system installs may be skipped."

# ───────── Paths / Defaults ─────────
SUCKLESS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/suckless"
LOCAL_BIN="${HOME}/.local/bin"
XINIT="${HOME}/.xinitrc"
BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/suckless-build"
PREFIX="/usr/local"
JOBS="$(nproc 2>/dev/null || echo 2)"

# Repos (vanilla by default)
DWM_REPO_VANILLA="https://git.suckless.org/dwm"
ST_REPO_VANILLA="https://git.suckless.org/st"
DMENU_REPO_VANILLA="https://git.suckless.org/dmenu"
SLOCK_REPO_VANILLA="https://git.suckless.org/slock"
SLSTATUS_REPO_VANILLA="https://git.suckless.org/slstatus"

# NIRUCON mono-repo (components as subdirs)
NIRUCON_REPO="https://github.com/nirucon/suckless"

SOURCE_MODE="vanilla"   # vanilla | nirucon
MANAGE_XINIT=1
INSTALL_FONTS=1          # can be disabled; only installs if fonts are missing
DRY_RUN=0
COMPONENTS=(dwm st dmenu slock slstatus)

FONT_MAIN="JetBrainsMono Nerd Font"
FONT_ICON="Symbols Nerd Font Mono"

usage(){ cat <<'EOF'
install_suckless.sh — options
  --source MODE      vanilla | nirucon  (default: vanilla)
  --prefix DIR       Install prefix for make install (default: /usr/local)
  --only LIST        Comma-separated subset: dwm,st,dmenu,slock,slstatus
  --no-xinit         Do NOT modify ~/.xinitrc
  --no-fonts         Do NOT attempt to install fonts
  --jobs N           Parallel make -j (default: nproc)
  --dry-run          Print actions without changing the system
  -h|--help          Show this help

Design:
• Picom.conf is NOT managed here (handled by install_lookandfeel.sh).
• Status bar content is provided by install_statusbar.sh; we only ensure hooks.
• Non-interactive by default (safe for running in a series by alpi.sh).
EOF
}

parse_components(){ IFS=',' read -r -a COMPONENTS <<<"$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_MODE="$2"; shift 2;;
    --prefix) PREFIX="$2"; shift 2;;
    --only)   parse_components "$2"; shift 2;;
    --no-xinit) MANAGE_XINIT=0; shift;;
    --no-fonts) INSTALL_FONTS=0; shift;;
    --jobs)   JOBS="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ───────── Helpers ─────────
ts(){ date +"%Y%m%d-%H%M%S"; }
ensure_dir(){ mkdir -p "$1"; }
append_once(){ local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
run(){ if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] $*"; else eval "$@"; fi }
backup_if_exists(){ local f="$1"; [[ -e "$f" ]] || return 0; local b="${f}.bak.$(ts)"; cp -a -- "$f" "$b"; warn "Backup: $f -> $b"; }

pkg_install(){
  # Best-effort deps for building & runtime
  local pkgs=(base-devel git make gcc pkgconf libx11 libxft libxinerama libxrandr libxext libxrender libxfixes freetype2 fontconfig xorg-xsetroot picom xautolock)
  if command -v pacman >/dev/null 2>&1; then
    step "Installing build/runtime dependencies via pacman (if missing)"
    if [[ $DRY_RUN -eq 1 ]]; then
      say "[dry-run] sudo pacman -S --needed --noconfirm ${pkgs[*]}"
    else
      sudo pacman -S --needed --noconfirm "${pkgs[@]}" || warn "pacman dependency install failed (continuing)"
    fi
  else
    warn "pacman not found; ensure build dependencies are present manually."
  fi
}

fonts_install_if_missing(){
  [[ $INSTALL_FONTS -eq 1 ]] || { warn "--no-fonts set: skipping font checks/install"; return 0; }
  step "Checking for required fonts"
  local need_main=1 need_icon=1
  if fc-list | grep -qi "${FONT_MAIN}"; then need_main=0; fi
  if fc-list | grep -qi "${FONT_ICON}"; then need_icon=0; fi
  if (( need_main==0 && need_icon==0 )); then say "Required fonts already installed"; return 0; fi

  if command -v pacman >/dev/null 2>&1; then
    if (( need_icon==1 )); then
      say "Installing ${FONT_ICON} via pacman"
      run "sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols-mono"
    fi
  fi
  if (( need_main==1 )); then
    if ! command -v yay >/dev/null 2>&1; then
      step "Installing yay-bin (AUR helper) to fetch ${FONT_MAIN}"
      local tmp; tmp="$(mktemp -d)"; (cd "$tmp" && run "git clone https://aur.archlinux.org/yay-bin.git" && cd yay-bin && run "makepkg -si --noconfirm"); rm -rf "$tmp"
    fi
    say "Installing ${FONT_MAIN} via yay"
    run "yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true"
  fi
}

clone_or_pull(){
  # Clone if absent; otherwise fast-forward pull
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    step "Updating $(basename "$dir")"
    (cd "$dir" && run "git fetch --all --prune" && run "git pull --ff-only") || warn "git update failed for $dir; keeping existing tree."
  else
    ensure_dir "$(dirname "$dir")"
    step "Cloning $(basename "$dir")"
    run "git clone '$url' '$dir'"
  fi
}

make_install(){
  local dir="$1" name="$2"
  step "Building $name"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] (cd '$dir' && make clean && make -j$JOBS && sudo make PREFIX='$PREFIX' install)"
  else
    (cd "$dir" && make clean && make -j"$JOBS" && sudo make PREFIX="$PREFIX" install)
  fi
}

# ───────── Prepare dirs & deps ─────────
ensure_dir "$SUCKLESS_DIR" "$LOCAL_BIN" "$BUILD_DIR"
pkg_install
fonts_install_if_missing

# ───────── Fetch sources ─────────
case "$SOURCE_MODE" in
  vanilla)
    say "Source mode: VANILLA (upstream)"
    clone_or_pull "$DWM_REPO_VANILLA"   "$SUCKLESS_DIR/dwm"
    clone_or_pull "$ST_REPO_VANILLA"    "$SUCKLESS_DIR/st"
    clone_or_pull "$DMENU_REPO_VANILLA" "$SUCKLESS_DIR/dmenu"
    clone_or_pull "$SLOCK_REPO_VANILLA" "$SUCKLESS_DIR/slock"
    clone_or_pull "$SLSTATUS_REPO_VANILLA" "$SUCKLESS_DIR/slstatus"
    ;;
  nirucon)
    say "Source mode: NIRUCON (github.com/nirucon/suckless)"
    clone_or_pull "$NIRUCON_REPO" "$SUCKLESS_DIR"
    ;;
  *) fail "Unknown --source value: $SOURCE_MODE";;
endcase

# ───────── Build & install ─────────
for comp in "${COMPONENTS[@]}"; do
  case "$SOURCE_MODE" in
    vanilla)
      if [[ -d "$SUCKLESS_DIR/$comp" ]]; then
        make_install "$SUCKLESS_DIR/$comp" "$comp"
      else
        warn "$comp not found under $SUCKLESS_DIR — skipping"
      fi
      ;;
    nirucon)
      if [[ -d "$SUCKLESS_DIR/$comp" ]]; then
        make_install "$SUCKLESS_DIR/$comp" "$comp"
      else
        warn "$comp not found in NIRUCON repo — skipping"
      fi
      ;;
  esac
done

# ───────── .xinitrc wiring (no duplicates) ─────────
if [[ $MANAGE_XINIT -eq 1 ]]; then
  step "Wiring ~/.xinitrc (safe, minimal)"
  if [[ ! -f "$XINIT" ]]; then
    cat > "$XINIT" <<'EOF'
#!/bin/sh
# ────────────────────────────────────────────────
# Nicklas Rudolfsson — minimal xinit for dwm
# ────────────────────────────────────────────────
cd "$HOME"
setxkbmap se
xsetroot -solid "#111111"

# Restore wallpaper (if Nitrogen present)
if command -v nitrogen >/dev/null; then
  nitrogen --restore &
fi

# Optional rotating wallpapers every 15 minutes (if script exists)
# Script: ~/.local/bin/wallrotate.sh
if [ -x "$HOME/.local/bin/wallrotate.sh" ]; then
  "$HOME/.local/bin/wallrotate.sh" &
fi

# Optional Nextcloud sync client (if installed)
if command -v nextcloud >/dev/null; then
  nextcloud --background &
fi

# Start compositor if available (config handled by install_lookandfeel.sh)
if command -v picom >/dev/null; then
  picom &
fi

# Start status bar if installed (installed by install_statusbar.sh)
[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &

# Optional auto-lock after 10 min if tools are present
if command -v xautolock >/dev/null && command -v slock >/dev/null; then
  xautolock -time 10 -locker slock &
fi

# Cleanup children on exit
trap 'kill -- -$$' EXIT

# Auto-restart dwm and log
while true; do
  /usr/local/bin/dwm 2> /tmp/dwm.log
done
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
    append_once 'while true; do /usr/local/bin/dwm 2> /tmp/dwm.log; done' "$XINIT"
  fi
else
  warn "--no-xinit set: leaving ~/.xinitrc untouched"
fi

# ───────── Final notes ─────────
cat <<'EOT'
========================================================
Suckless install finished

• Components built: dwm/st/dmenu/slock/slstatus (customize with --only)
• Picom.conf was not modified (managed by install_lookandfeel.sh)
• Status bar hook present; run install_statusbar.sh to install bar scripts
• Start X with:  startx

Tips:
• Choose source with --source vanilla|nirucon (non-interactive, ALPI-friendly)
• Use --no-fonts to skip font checks (if handled by install_lookandfeel.sh)
• Override PREFIX with --prefix if you prefer /usr
========================================================
EOT
