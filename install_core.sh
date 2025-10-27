#!/usr/bin/env bash
# install_core.sh — baseline system setup for Arch
# Purpose: Set up core system pieces (snapshots, base CLI, Xorg/graphics/audio/network essentials),
#          with clear, English-only output and idempotent behavior.
# Author:  Nicklas Rudolfsson (NIRUCON)
#
# Changes in this version:
# - Replaced Timeshift with Snapper (better for Btrfs)
# - Automatic Btrfs detection (no manual config needed)
# - Installs snap-pac for automatic pre/post snapshots
# - Installs grub-btrfs for snapshot boot menu
# - All other functionality unchanged

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
GRN="\033[1;32m"
BLU="\033[1;34m"
YLW="\033[1;33m"
RED="\033[1;31m"
CYN="\033[1;36m"
NC="\033[0m"
say() { printf "${GRN}[CORE]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
info() { printf "${CYN}[INFO]${NC} %s\n" "$*"; }
trap 'fail "install_core.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || {
  fail "Do not run as root."
  exit 1
}
command -v sudo >/dev/null 2>&1 || {
  fail "sudo not found"
  exit 1
}

# ───────── Flags ─────────
DRY_RUN=0
FULL_UPGRADE=1     # can be disabled with --no-upgrade
ENABLE_SNAPSHOTS=1 # can be disabled with --no-snapshots

usage() {
  cat <<'EOF'
install_core.sh — options
  --no-upgrade      Skip pacman -Syu
  --no-snapshots    Skip Snapper + snap-pac setup
  --dry-run         Print actions without changing the system
  -h|--help         Show this help

Design:
- Installs base developer CLI, network, Xorg, audio, micro-utilities.
- Sets up Snapper for Btrfs snapshots (instant, <1s per snapshot)
- Installs snap-pac for automatic pre/post snapshots on pacman operations
- Installs grub-btrfs for snapshot boot menu (if GRUB detected)
- Works on both @ subvolume and flat Btrfs layouts

Snapshot system:
- Btrfs required (automatically detected)
- Snapshots created before/after every pacman operation
- Boot from snapshots via GRUB menu
- Minimal disk overhead (Btrfs Copy-on-Write)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-upgrade)
    FULL_UPGRADE=0
    shift
    ;;
  --no-snapshots)
    ENABLE_SNAPSHOTS=0
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

# ───────── Runner (safe for arrays) ─────────
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

# ───────── Btrfs detection helper ─────────
is_btrfs_root() {
  findmnt -n -o FSTYPE / 2>/dev/null | grep -q '^btrfs$'
}

# ───────── Snapper snapshot system setup ─────────
if ((ENABLE_SNAPSHOTS == 1)); then
  step "Setting up Snapper snapshot system"
  
  # Check if root is Btrfs
  if is_btrfs_root; then
    info "✓ Btrfs detected on root filesystem"
    
    # Install Snapper and snap-pac
    info "Installing Snapper packages..."
    run sudo pacman -S --needed --noconfirm snapper snap-pac
    
    # Install grub-btrfs if GRUB is present
    if command -v grub-mkconfig >/dev/null 2>&1; then
      info "GRUB detected - installing grub-btrfs for snapshot boot menu"
      run sudo pacman -S --needed --noconfirm grub-btrfs
    else
      info "GRUB not detected (may use systemd-boot)"
    fi
    
    # Create Snapper root config if it doesn't exist
    if [[ ! -d /.snapshots ]]; then
      info "Creating Snapper root configuration..."
      run sudo snapper -c root create-config /
      
      # Configure retention policy (same as Timeshift defaults)
      if [[ -f /etc/snapper/configs/root ]]; then
        info "Configuring snapshot retention policy..."
        run sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root
        run sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="3"/' /etc/snapper/configs/root
        run sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="1"/' /etc/snapper/configs/root
        run sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
        run sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
      fi
    else
      info "Snapper root config already exists"
    fi
    
    # Enable grub-btrfsd service if grub-btrfs is installed
    if command -v grub-mkconfig >/dev/null 2>&1 && pacman -Q grub-btrfs >/dev/null 2>&1; then
      info "Enabling grub-btrfsd for automatic GRUB menu updates..."
      run sudo systemctl enable --now grub-btrfsd.service 2>/dev/null || true
      
      # Generate initial GRUB config
      info "Generating GRUB configuration..."
      run sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || warn "GRUB config generation failed (non-fatal)"
    fi
    
    info "✓ Snapper configured successfully"
    info "  → Snapshots: automatic before/after pacman operations (via snap-pac)"
    info "  → Retention: 3 daily, 1 weekly"
    info "  → Boot menu: available in GRUB (if installed)"
    
  else
    warn "Root filesystem is NOT Btrfs!"
    warn "Snapper requires Btrfs. Detected filesystem: $(findmnt -n -o FSTYPE / 2>/dev/null || echo 'unknown')"
    warn "Skipping snapshot setup."
    warn "To use snapshots, reinstall Arch with Btrfs filesystem."
  fi
else
  warn "--no-snapshots set: skipping Snapper setup"
fi

# ───────── System upgrade (optional) ─────────
if ((FULL_UPGRADE == 1)); then
  step "Syncing & upgrading system"
  run "sudo pacman -Syu --noconfirm"
else
  warn "--no-upgrade set: skipping pacman -Syu"
fi

# ───────── Ensure ~/.local/bin exists ─────────
ensure_home_bin() { mkdir -p "$HOME/.local/bin"; }
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
  
  # Btrfs tools (for Btrfs systems)
  btrfs-progs
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

# ───────── Summary ─────────
cat <<'EOT'
========================================================
Core setup complete

- System upgraded (unless --no-upgrade)
- Snapper installed with automatic snapshots (if Btrfs)
- snap-pac: Pre/post snapshots on pacman operations
- grub-btrfs: Snapshot boot menu (if GRUB present)
- Base CLI, Xorg, audio, network installed
- NetworkManager and ufw enabled

Snapshot system status:
EOT

if ((ENABLE_SNAPSHOTS == 1)) && is_btrfs_root; then
  if command -v snapper >/dev/null 2>&1; then
    echo "  ✓ Snapper: ACTIVE"
    echo "  ✓ Filesystem: Btrfs"
    echo "  → Test: sudo snapper list"
    echo "  → Create manual snapshot: sudo snapper create --description 'Manual backup'"
    if command -v grub-mkconfig >/dev/null 2>&1; then
      echo "  → Boot from snapshot: Reboot → GRUB → 'Arch Linux snapshots'"
    fi
  else
    echo "  ✗ Snapper: NOT INSTALLED (check errors above)"
  fi
else
  echo "  - Snapshots: DISABLED (--no-snapshots or no Btrfs)"
fi

cat <<'EOT'

Next steps:
  1. Run other ALPI scripts: ./alpi.sh --nirucon
  2. Start X session: startx
  3. Test snapshots: sudo snapper list
========================================================
EOT
