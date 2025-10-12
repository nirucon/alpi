#!/usr/bin/env bash
# install_core.sh — baseline system setup for Arch
# Purpose: Set up core system pieces (snapshots, base CLI, Xorg/graphics/audio/network essentials),
#          with clear, English-only output and idempotent behavior.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
GRN="\033[1;32m"; BLU="\033[1;34m"; YLW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GRN}[CORE]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_core.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || { fail "Do not run as root."; exit 1; }
command -v sudo >/dev/null 2>&1 || { fail "sudo not found"; exit 1; }

# ───────── Flags ─────────
DRY_RUN=0
FULL_UPGRADE=1         # can be disabled with --no-upgrade
ENABLE_SNAPSHOTS=1     # can be disabled with --no-snapshots

usage(){ cat <<'EOF'
install_core.sh — options
  --no-upgrade      Skip pacman -Syu
  --no-snapshots    Skip Timeshift + autosnap hook
  --dry-run         Print actions without changing the system
  -h|--help         Show this help

Design:
• Installs base developer CLI, network, Xorg, audio, micro-utilities.
• Optional pre-transaction snapshots via timeshift-autosnap.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-upgrade)   FULL_UPGRADE=0; shift;;
    --no-snapshots) ENABLE_SNAPSHOTS=0; shift;;
    --dry-run)      DRY_RUN=1; shift;;
    -h|--help)      usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ───────── Runner (safe for arrays) ─────────
# If called with a single string → run through a shell (allows pipes/&&).
# If called with multiple args → run as an argv list (ideal for "${arr[@]}").
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
  else
    if [[ $# -eq 1 ]]; then
      bash -lc "$1"
    else
      "$@"
    fi
  fi
}

# ───────── Timeshift + autosnap (optional) ─────────
if (( ENABLE_SNAPSHOTS==1 )); then
  step "Installing timeshift + autosnap (best-effort)"
  run sudo pacman -S --needed --noconfirm timeshift
  # autosnap from AUR (yay) if available
  if command -v yay >/dev/null 2>&1; then
    run "yay -S --needed --noconfirm timeshift-autosnap"
  else
    warn "yay not found — skipping timeshift-autosnap"
  fi
fi

# ───────── System upgrade (optional) ─────────
if (( FULL_UPGRADE==1 )); then
  step "Syncing & upgrading system"
  run "sudo pacman -Syu --noconfirm"
else
  warn "--no-upgrade set: skipping pacman -Syu"
fi

# ───────── Ensure ~/.local/bin exists ─────────
ensure_home_bin(){ mkdir -p "$HOME/.local/bin"; }
ensure_home_bin

# ───────── Core package set ─────────
# Keep these light; apps belong in install_apps.sh
BASE_PKGS=(
  # CLI & dev
  base base-devel git make gcc pkgconf curl wget unzip zip tar rsync
  grep sed findutils coreutils which diffutils gawk
  htop less nano tree imlib2

  # Shell helpers
  bash-completion

  # Network basics
  networkmanager openssh inetutils bind-tools iproute2

  # Audio (PipeWire stack)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber pavucontrol

  # Xorg minimal + utilities
  xorg-server xorg-xinit xorg-xsetroot xorg-xrandr xorg-xset xorg-xinput

  # Fonts minimal (icons handled elsewhere)
  ttf-dejavu noto-fonts

  # Misc
  ufw
)

step "Installing core packages"
# IMPORTANT: use array expansion so newlines/spaces don't split commands
run sudo pacman -S --needed --noconfirm "${BASE_PKGS[@]}"

# ───────── Enable services ─────────
step "Enabling services (NetworkManager, ufw)"
run "sudo systemctl enable --now NetworkManager"
run "sudo systemctl enable --now ufw || true"

# ───────── UFW sane defaults (idempotent) ─────────
if command -v ufw >/dev/null 2>&1; then
  step "Configuring ufw (allow out, deny in)"
  run "sudo ufw default deny incoming || true"
  run "sudo ufw default allow outgoing || true"
  run "sudo ufw enable || true"
fi

cat <<'EOT'
========================================================
Core setup complete

• System upgraded (unless --no-upgrade)
• Timeshift installed (autosnap if yay exists)
• Base CLI, Xorg, audio, network installed
• NetworkManager and ufw enabled
========================================================
EOT
