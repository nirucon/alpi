#!/usr/bin/env bash
# alpi.sh — Arch post-install orchestrator
# Purpose: Run all install scripts in the correct order with clear output and safe defaults.
# Author:  Nicklas Rudolfsson (NIRUCON)
# Output:  Clear, English-only status messages. Fail-fast on errors.

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
GRN="\033[1;32m"; CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; NC="\033[0m"
say()  { printf "${GRN}[ALPI]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "alpi.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || { fail "Do not run as root."; exit 1; }
command -v pacman >/dev/null 2>&1 || { fail "This orchestrator targets Arch (pacman not found)."; exit 1; }

# ───────── Defaults ─────────
DRY_RUN=0
STEPS=(core lookandfeel suckless statusbar apps optimize)

SCK_SOURCE="vanilla"   # default non-interactive choice
ASK_SUCKLESS=0         # when 1: let install_suckless.sh prompt (TTY only)
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
• Order: core → lookandfeel → suckless → statusbar → apps → optimize
• --ask-suckless lets you pick Vanilla vs Custom; otherwise default is non-interactive.
EOF
}

parse_csv(){ local IFS=","; read -r -a _arr <<<"$1"; printf '%s\n' "${_arr[@]}"; }
contains(){ local n=$1; shift; for e; do [[ $e == "$n" ]] && return 0; done; return 1; }

# Array-safe runner
run(){
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "${CYN}[ALPI]${NC} [dry-run] %s\n" "$*"
  else
    if [[ $# -eq 1 ]]; then bash -lc "$1"; else "$@"; fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)    mapfile -t STEPS < <(parse_csv "$2"); shift 2;;
    --skip)    readarray -t SKIP_STEPS < <(parse_csv "$2"); shift 2;;
    --nirucon) SCK_SOURCE="nirucon"; ASK_SUCKLESS=0; shift;;
    --ask-suckless) ASK_SUCKLESS=1; shift;;
    --no-fonts) SCK_NO_FONTS=1; shift;;
    --no-snapshots) CORE_NO_SNAPSHOTS=1; shift;;
    --no-upgrade)   CORE_NO_UPGRADE=1; shift;;
    --no-yay)       APPS_NO_YAY=1; shift;;
    --no-files)     APPS_NO_FILES=1; shift;;
    --jobs)         JOBS="$2"; shift 2;;
    --dry-run)      DRY_RUN=1; shift;;
    -h|--help)      usage; exit 0;;
    *) warn "Unknown option: $1"; usage; exit 1;;
  esac
done

# Resolve scripts
LOOK="$SCRIPT_DIR/install_lookandfeel.sh"
SUCK="$SCRIPT_DIR/install_suckless.sh"
SBAR="$SCRIPT_DIR/install_statusbar.sh"
CORE="$SCRIPT_DIR/install_core.sh"
APPS="$SCRIPT_DIR/install_apps.sh"
OPTI="$SCRIPT_DIR/install_optimize.sh"
for f in "$LOOK" "$SUCK" "$SBAR" "$CORE" "$APPS" "$OPTI"; do
  [[ -f "$f" ]] || { fail "Missing script: $f"; }
  chmod +x "$f" || true
done

say "Starting ALPI orchestration"

for stepname in "${STEPS[@]}"; do
  if [[ -n "${SKIP_STEPS:-}" ]] && contains "$stepname" "${SKIP_STEPS[@]}"; then
    warn "Skipping step: $stepname"; continue
  fi
  case "$stepname" in
    core)
      step "[1/6] Core setup"
      args=()
      (( CORE_NO_SNAPSHOTS==1 )) && args+=(--no-snapshots)
      (( CORE_NO_UPGRADE==1 ))   && args+=(--no-upgrade)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run "$CORE" "${args[@]}"
      ;;
    lookandfeel)
      step "[2/6] Look & Feel (dotfiles, scripts, picom.conf)"
      args=()
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run "$LOOK" "${args[@]}"
      ;;
    suckless)
      step "[3/6] Suckless stack (dwm, st, dmenu, slock, slstatus)"
      args=(--jobs "$JOBS")
      (( SCK_NO_FONTS==1 )) && args+=(--no-fonts)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      if (( ASK_SUCKLESS==0 )); then
        # Non-interactive: pass explicit source
        args+=(--source "$SCK_SOURCE")
      fi
      run "$SUCK" "${args[@]}"
      ;;
    statusbar)
      step "[4/6] Status bar (dwm-status.sh)"
      args=()
      # Keep .xinitrc managed by suckless; no --hook-xinit here by default
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run "$SBAR" "${args[@]}"
      ;;
    apps)
      step "[5/6] Applications"
      args=()
      (( APPS_NO_YAY==1 )) && args+=(--no-yay)
      (( APPS_NO_FILES==1 )) && args+=(--no-files)
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run "$APPS" "${args[@]}"
      ;;
    optimize)
      if (( OPTI_DISABLE==1 )); then warn "Skipping optimize by policy"; continue; fi
      step "[6/6] Optimize (zram, journald, /tmp tmpfs, swappiness, pacman.conf)"
      args=()
      (( DRY_RUN==1 )) && args+=(--dry-run)
      run "$OPTI" "${args[@]}"
      ;;
    *) warn "Unknown step: $stepname (skipping)";;
  esac
  say "Completed step: $stepname"
done

cat <<'EOT'
========================================================
ALPI complete

Order executed: core → lookandfeel → suckless → statusbar → apps → optimize
• Re-run safely; idempotent installs and backups are used.
• Want to pick Vanilla vs Custom? Use:  ./alpi.sh --ask-suckless
• Force custom non-interactively:    ./alpi.sh --nirucon
========================================================
EOT
