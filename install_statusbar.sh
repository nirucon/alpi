#!/usr/bin/env bash
# install_statusbar.sh — install dwm status bar from lookandfeel repo
# Purpose: Install dwm-status.sh script (fetched from lookandfeel repo) to ~/.local/bin
#          and create xinitrc hook for autostart. Does NOT embed the script as heredoc.
# Author:  Nicklas Rudolfsson (NIRUCON)
#
# Changes in this version:
# - Fetches dwm-status.sh from lookandfeel repo (not embedded)
# - Creates xinitrc hook instead of modifying .xinitrc
# - Auto-runs install_lookandfeel.sh if repo not found

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"
YLW="\033[1;33m"
RED="\033[1;31m"
BLU="\033[1;34m"
GRN="\033[1;32m"
NC="\033[0m"
say() { printf "${CYN}[SBAR]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_statusbar.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run as root. Run as your normal user."
  exit 1
fi

# ───────── Paths ─────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOCAL_BIN="$HOME/.local/bin"
XINITRC_HOOKS="$HOME/.config/xinitrc.d"
LOOKANDFEEL_CACHE="$HOME/.cache/alpi/lookandfeel/main"
STATUS_SOURCE="$LOOKANDFEEL_CACHE/scripts/dwm-status.sh"

# ───────── Defaults / args ─────────
INSTALL_DEPS=1 # best-effort install of minimal runtime deps
DRY_RUN=0

usage() {
  cat <<'EOF'
install_statusbar.sh — options
  --no-deps         Do NOT attempt to install runtime dependencies
  --dry-run         Print actions without changing the system
  -h|--help         Show this help

Design:
- Fetches dwm-status.sh from lookandfeel repo (scripts/dwm-status.sh)
- Installs to ~/.local/bin/dwm-status.sh
- Creates xinitrc hook for autostart (does NOT modify .xinitrc)
- If lookandfeel repo not found, offers to run install_lookandfeel.sh first

Note: This script should run AFTER install_lookandfeel.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-deps)
    INSTALL_DEPS=0
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    warn "Unknown argument: $1"
    usage
    exit 1
    ;;
  esac
done

# ───────── Helpers ─────────
run() { if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] $*"; else eval "$@"; fi; }
ensure_dir() { mkdir -p "$1"; }

# ───────── Prepare dirs ─────────
ensure_dir "$LOCAL_BIN"
ensure_dir "$XINITRC_HOOKS"

# ───────── Minimal runtime deps (best-effort) ─────────
if ((INSTALL_DEPS == 1)); then
  if command -v pacman >/dev/null 2>&1; then
    step "Ensuring minimal runtime tools exist (best-effort)"
    # Needed binaries: xsetroot (xorg-xsetroot), fc-list (fontconfig),
    # text tools (grep/sed/gawk/coreutils), Wi-Fi utilities (wireless_tools for iwgetid),
    # and nmcli fallback (networkmanager).
    run "sudo pacman -S --needed --noconfirm xorg-xsetroot fontconfig glib2 grep sed gawk coreutils wireless_tools networkmanager || true"
  else
    warn "pacman not found; skipping dependency install"
  fi
else
  say "Skipping dependency checks (--no-deps)"
fi

# ───────── Ensure ~/.local/bin on PATH ─────────
if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  warn "~/.local/bin is not in your PATH."
  warn "Install_apps.sh should have added it to ~/.bash_profile"
  warn "Log out and back in, or run: source ~/.bash_profile"
fi

# ───────── Check if lookandfeel repo exists ─────────
if [[ ! -d "$LOOKANDFEEL_CACHE" ]]; then
  warn "Lookandfeel repo not found at: $LOOKANDFEEL_CACHE"
  warn "The status bar script (dwm-status.sh) is stored in the lookandfeel repo."
  warn ""
  warn "You need to run install_lookandfeel.sh first:"
  warn "  ./alpi.sh --only lookandfeel"
  warn ""
  warn "Or run the full installation:"
  warn "  ./alpi.sh --nirucon"
  fail "Cannot continue without lookandfeel repo"
fi

# ───────── Check if dwm-status.sh exists in lookandfeel repo ─────────
if [[ ! -f "$STATUS_SOURCE" ]]; then
  warn "dwm-status.sh not found in lookandfeel repo at: $STATUS_SOURCE"
  warn ""
  warn "Expected location: $LOOKANDFEEL_CACHE/scripts/dwm-status.sh"
  warn ""
  warn "Please ensure your lookandfeel repo contains scripts/dwm-status.sh"
  warn "You can verify by running:"
  warn "  ls -la $LOOKANDFEEL_CACHE/scripts/"
  fail "Cannot install status bar without source script"
fi

# ───────── Install bar script from lookandfeel repo ─────────
step "Installing dwm-status.sh from lookandfeel repo"
if [[ $DRY_RUN -eq 1 ]]; then
  say "[dry-run] Would install $STATUS_SOURCE -> $LOCAL_BIN/dwm-status.sh (755)"
else
  install -Dm755 "$STATUS_SOURCE" "$LOCAL_BIN/dwm-status.sh"
  say "Installed: $STATUS_SOURCE -> $LOCAL_BIN/dwm-status.sh"
fi

# ───────── Create xinitrc hook for autostart ─────────
step "Creating xinitrc hook for status bar autostart"

if [[ $DRY_RUN -eq 1 ]]; then
  say "[dry-run] Would create $XINITRC_HOOKS/30-statusbar.sh"
else
  cat >"$XINITRC_HOOKS/30-statusbar.sh" <<'EOF'
#!/bin/sh
# DWM status bar hook
# Created by install_statusbar.sh

# Start dwm-status.sh if installed
[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &
EOF
  chmod +x "$XINITRC_HOOKS/30-statusbar.sh"
  say "Created xinitrc hook: ~/.config/xinitrc.d/30-statusbar.sh"
fi

cat <<'EOT'
========================================================
Status bar installation complete

- dwm-status.sh installed to ~/.local/bin/
- Xinitrc hook created (will autostart with X session)
- Source: lookandfeel repo (scripts/dwm-status.sh)

Configuration:
  The status bar can be configured via environment variables:
  
  DWM_STATUS_ICONS=1        # Use Nerd Font icons (default: 1)
  DWM_STATUS_INTERVAL=10    # Refresh interval in seconds (default: 10)
  DWM_STATUS_WIFI_CMD=...   # Force SSID detection method (nmcli/iwgetid)
  
  Set these in ~/.bash_profile or ~/.xinitrc before the status bar starts.

Testing:
  Run manually: ~/.local/bin/dwm-status.sh
  Check logs: tail -f /tmp/dwm.log (if errors occur)

To update the status bar:
  1. Edit scripts/dwm-status.sh in your lookandfeel repo
  2. Run: ./alpi.sh --only lookandfeel,statusbar
========================================================
EOT
