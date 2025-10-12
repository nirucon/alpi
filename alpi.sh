#!/usr/bin/env bash
# alpi.sh — Arch post-install orchestrator
# Purpose: Run all install scripts in the correct order with clear output and safe defaults.
# Author:  Nicklas Rudolfsson (NIRUCON)
# Notes:
#   • Run this script as a NORMAL USER (not root).
#   • Steps that need root either handle sudo internally (core/apps) or are invoked via sudo here (optimize).
#   • Idempotent: safe to re-run.

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
GRN="\033[1;32m"; CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; NC="\033[0m"
say()  { printf "${GRN}[ALPI]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; exit 1; }
trap 'fail "alpi.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || fail "Do NOT run alpi.sh as root. Start it as your normal user."
command -v pacman >/dev/null 2>&1 || fail "This orchestrator targets Arch (pacman not found)."
command -v sudo   >/dev/null 2>&1 || fail "sudo is required."

# ───────── Defaults ─────────
DRY_RUN=0
STEPS=(core lookandfeel suckless statusbar apps optimize)

SCK_SOURCE="vanilla"   # default non-interactive choice
ASK_SUCKLESS=0
SCK_NO_FONTS=0
CORE_NO_SNAPSHOTS=0
CORE_NO_UPGRADE=0
APPS_NO_YAY=0
APPS_NO_FILES=0
OPTI_DISABLE=0
JOBS="$(nproc 2>/dev/null || echo 2)"

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
PATH="$HOME/.local/bin:$PATH"

usage(){ cat <<'EOF'
alpi.sh — options
  --only list          Comma-separated subset (core,lookandfeel,suckless,statusbar,apps,optimize)
  --skip list          Comma-separated steps to skip
  --nirucon            Build suckless from github.com/nirucon/suckless (non-interactive)
  --ask-suckless       Ask interactively (TTY) Vanilla vs Custom when running suckless step
  --no-fonts           Do not install fonts in install_suckless.sh
  --no-snapshots       Do not set up timeshift/autosnap in install_core.sh
  --no-upgrade         Skip pacman -Syu in install_core.sh
  --no-yay             Do not install yay or any AUR apps in install_apps.sh
  --no-files           Ignore apps-pacman.txt and apps-yay.txt in install_apps.sh
  --jobs N             Parallel make jobs for suckless builds (default: nproc)
  --dry-run            Print actions without changing the system
  -h|--help            Show this help

Design:
• Run as NORMAL USER. Core/Apps handle sudo internally. Optimize is invoked via sudo.
• Order: core → lookandfeel → suckless → statusbar → apps → optimize
EOF
}

parse_csv(){ local IFS=","; read -r -a _arr <<<"$1"; printf '%s\n' "${_arr[@]}"; }
contains(){ local n=$1; shift; for e; do [[ $e == "$n" ]] && return 0; done; return 1; }

# ───────── Execution helpers ─────────
run_user(){
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "${CYN}[ALPI]${NC} [dry-run user] %q %s\n" "$1" "${*:2}"
  else
    "$@"
  fi
}

run_root(){
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "${CYN}[ALPI]${NC} [dry-run root] %q %s\n" "$1" "${*:2}"
  else
    sudo -n -- "$@"
  fi
}

# Ask for sudo once and keep it alive (used by optimize here, and by core/apps internally)
step "Validating sudo and starting keepalive"
sudo -v || fail "Need sudo privileges."
( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) & SUDO_KEEPALIVE=$!
cleanup_keepalive(){ kill "$SUDO_KEEPALIVE" 2>/dev/null || true; }
trap 'cleanup_keepalive; fail "alpi.sh failed. See previous messages for details."' ERR
trap 'cleanup_keepalive' EXIT

# ───────── Resolve scripts ─────────
LOOK="$SCRIPT_DIR/install_lookandfeel.sh"
SUCK="$SCRIPT_DIR/install_suckless.sh"
SBAR="$SCRIPT_DIR/install_statusbar.sh"
CORE="$SCRIPT_DIR/install_core.sh"
APPS="$SCRIPT_DIR/install_apps.sh"
OPTI="$SCRIPT_DIR/install_optimize.sh"
for f in "$LOOK" "$SUCK" "$SBAR" "$CORE" "$APPS" "$OPTI"; do
  [[ -f "$f" ]] || fail "Missing script: $f"
  chmod +x "$f" || true
endone

say "Starting ALPI orchestration"

for stepname in "${STEPS[@]}"; do
  if [[ -n "${SKIP_STEPS:-}" ]] && contains "$stepname" "${SKIP_STEPS[@]}"; then
    warn "Skipping step: $stepname"; continue
  fi

  case "$stepname" in
    core)
      step "[1/6] Core setup (runs as user; uses sudo internally)"
      args=()
      (( CORE_NO_SNAPSHOTS==1 )) && args+=(--no-snapshots)
      (( CORE_NO_UPGRADE==1 ))   && args+=(--no-upgrade)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run_user "$CORE" "${args[@]}"
      ;;

    lookandfeel)
      step "[2/6] Look & Feel (user space: dotfiles, config)"
      args=()
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run_user "$LOOK" "${args[@]}"
      ;;

    suckless)
      step "[3/6] Suckless stack (dwm, st, dmenu, slock...) — build as user"
      args=(--jobs "$JOBS")
      (( SCK_NO_FONTS==1 )) && args+=(--no-fonts)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      if (( ASK_SUCKLESS==0 )); then
        args+=(--source "$SCK_SOURCE")
      fi
      run_user "$SUCK" "${args[@]}"
      ;;

    statusbar)
      step "[4/6] Status bar (user space)"
      args=()
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run_user "$SBAR" "${args[@]}"
      ;;

    apps)
      step "[5/6] Applications (runs as user; uses sudo/pacman internally; yay builds as user)"
      args=()
      (( APPS_NO_YAY==1 ))   && args+=(--no-yay)
      (( APPS_NO_FILES==1 )) && args+=(--no-files)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run_user "$APPS" "${args[@]}"
      ;;

    optimize)
      if (( OPTI_DISABLE==1 )); then warn "Skipping optimize by policy"; continue; fi
      step "[6/6] Optimize (root-only tweaks) — invoked via sudo"
      args=()
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run_root "$OPTI" "${args[@]}"
      ;;

    *)
      warn "Unknown step: $stepname (skipping)"
      ;;
  esac

  say "Completed step: $stepname"
done

cat <<'EOT'
========================================================
ALPI complete

Order executed: core → lookandfeel → suckless → statusbar → apps → optimize
• Run alpi.sh as a NORMAL USER.
• Core/Apps run as user and call sudo inside; Optimize runs via sudo here.
• Safe to re-run; scripts use backups and idempotent operations.
• Choose Vanilla vs Custom Suckless:
    ./alpi.sh --ask-suckless
  or force custom non-interactively:
    ./alpi.sh --nirucon
========================================================
EOT
