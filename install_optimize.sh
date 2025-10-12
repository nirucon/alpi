#!/usr/bin/env bash
# install_optimize.sh — performance & QoL tweaks for Arch
# Purpose: Apply safe system optimizations (zram, journald size, pacman conf, tmpfs /tmp, swappiness),
#          with clear, revert-friendly behavior.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
GRN="\033[1;32m"; BLU="\033[1;34m"; YLW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GRN}[OPTI]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_optimize.sh failed. See previous messages for details."' ERR

[[ ${EUID:-$(id -u)} -ne 0 ]] || { fail "Do not run as root."; exit 1; }
command -v sudo >/dev/null 2>&1 || { fail "sudo not found"; exit 1; }

# ───────── Flags ─────────
DRY_RUN=0
usage(){ cat <<'EOF'
install_optimize.sh — options
  --dry-run    Print actions without changing the system
  -h|--help    Show this help

Changes applied (safe & revertable):
• zram-generator with lz4, size = RAM/2  → /etc/systemd/zram-generator.conf
• journald size limit (100M), persistent logs
• tmpfs for /tmp (optional, if not already in use)
• vm.swappiness=10 via sysctl.d
• pacman.conf enhancements: Color, ParallelDownloads=5, ILoveCandy (if missing)
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown arg: $1"; usage; exit 1;;
  esac
done

# ───────── Runner (array-safe) ─────────
# One arg → run via shell (allows pipes/&&). Many args → exec exact argv.
run(){
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
  else
    if [[ $# -eq 1 ]]; then bash -lc "$1"; else "$@"; fi
  fi
}

timestamp(){ date +%Y%m%d-%H%M%S; }
backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  local b="${f}.bak.$(timestamp)"
  run sudo cp -a -- "$f" "$b"
  warn "Backup: $f -> $b"
}

# ───────── zram (systemd zram-generator) ─────────
step "Configuring zram (lz4, RAM/2)"
run sudo pacman -S --needed --noconfirm systemd zram-generator zram-generator-defaults || true
ZRAM_CFG="/etc/systemd/zram-generator.conf"
ZRAM_DESIRED=$'[zram0]\nzram-size = ram / 2\ncompression-algorithm = lz4\n'

if [[ -f "$ZRAM_CFG" ]]; then
  if grep -q '\[zram0\]' "$ZRAM_CFG" 2>/dev/null; then
    # Write temp as user (no sudo), then sudo mv into place — avoids odd /tmp perms
    tmp="$(mktemp)"
    awk '
      BEGIN{inblk=0}
      /^\[zram0\]/{print "[zram0]"; print "zram-size = ram / 2"; print "compression-algorithm = lz4"; inblk=1; next}
      inblk && /^\[/{inblk=0}
      !inblk{print}
    ' "$ZRAM_CFG" > "$tmp"
    backup "$ZRAM_CFG"
    run sudo mv "$tmp" "$ZRAM_CFG"
    run sudo chmod 644 "$ZRAM_CFG"
  else
    backup "$ZRAM_CFG"
    printf '%s' "$ZRAM_DESIRED" | run sudo tee -a "$ZRAM_CFG" >/dev/null
  fi
else
  printf '%s' "$ZRAM_DESIRED" | run sudo tee "$ZRAM_CFG" >/dev/null
  run sudo chmod 644 "$ZRAM_CFG"
fi
run sudo systemctl daemon-reload
run sudo systemctl restart systemd-zram-setup@zram0.service || true

# ───────── journald limits ─────────
step "Tuning systemd-journald"
run sudo mkdir -p /etc/systemd/journald.conf.d
JOUR_CFG="/etc/systemd/journald.conf.d/99-custom.conf"
backup "$JOUR_CFG"
run "printf '%s\n' '[Journal]' 'SystemMaxUse=100M' 'RuntimeMaxUse=100M' 'Storage=persistent' | sudo tee '$JOUR_CFG' >/dev/null"
run sudo systemctl restart systemd-journald

# ───────── /tmp on tmpfs (optional) ─────────
step "Ensuring /tmp is tmpfs (if supported)"
FSTAB="/etc/fstab"
if ! grep -qE '^tmpfs\s+/tmp\s+tmpfs' "$FSTAB" 2>/dev/null; then
  backup "$FSTAB"
  echo 'tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0' | run sudo tee -a "$FSTAB" >/dev/null
  warn "Added tmpfs /tmp. Reboot recommended."
else
  say "/tmp already on tmpfs — skipping"
fi

# ───────── Swappiness ─────────
step "Setting vm.swappiness=10"
run sudo mkdir -p /etc/sysctl.d
SYSCTL="/etc/sysctl.d/99-swappiness.conf"
backup "$SYSCTL"
echo 'vm.swappiness=10' | run sudo tee "$SYSCTL" >/dev/null
run sudo sysctl -p "$SYSCTL" || true

# ───────── pacman.conf cosmetics & speed (non-destructive) ─────────
step "Tweaking pacman.conf (Color, ParallelDownloads, ILoveCandy)"
PACMAN_CONF="/etc/pacman.conf"
backup "$PACMAN_CONF"
# Enable Color
grep -qE '^Color' "$PACMAN_CONF"      || echo 'Color'               | run sudo tee -a "$PACMAN_CONF" >/dev/null
# ParallelDownloads
grep -qE '^ParallelDownloads' "$PACMAN_CONF" || echo 'ParallelDownloads = 5' | run sudo tee -a "$PACMAN_CONF" >/dev/null
# ILoveCandy (fun, optional)
grep -qE '^ILoveCandy' "$PACMAN_CONF" || echo 'ILoveCandy'          | run sudo tee -a "$PACMAN_CONF" >/dev/null

cat <<'EOT'
========================================================
Optimization complete

• zram configured with lz4 (RAM/2)
• journald capped at 100M (persistent)
• /tmp mounted as tmpfs (fstab) if not already
• vm.swappiness=10 via sysctl.d
• pacman.conf tweaked (Color, ParallelDownloads, ILoveCandy)

Reboot recommended for /tmp tmpfs and zram to fully apply.
========================================================
EOT
