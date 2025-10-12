#!/usr/bin/env bash
# install_optimize.sh — performance & QoL tweaks for Arch
# Purpose: Apply safe system optimizations (zram, journald size, pacman conf, tmpfs /tmp, swappiness),
#          AND handle firmware smartly so only needed linux-firmware subpackages are installed.
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

# `run` runs commands and prints them. If given one argument, it runs via bash -lc to support pipes/redirects.
run() {
  if [[ $# -eq 0 ]]; then return 0; fi
  printf "+ %s\n" "$*"
  if [[ $# -eq 1 ]]; then bash -lc "$1"; else "$@"; fi
}

timestamp(){ date +%Y%m%d-%H%M%S; }
backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  local b="${f}.bak.$(timestamp)"
  run sudo cp -a -- "$f" "$b"
  warn "Backup: $f -> $b"
}

sudo pacman -S --needed pciutils usbutils

# ──────────────────────────────────────────────────────────────────────────────
#                           Firmware optimization (NEW)
#   Installs only firmware that matches this machine + correct CPU microcode.
#   Optionally trims already installed, unnecessary firmware subpackages.
#   Does not alter unrelated optimizations in this script.
# ──────────────────────────────────────────────────────────────────────────────
# Firmware flags (scoped)
FW_TRIM=0                # --fw-trim: remove non-matching linux-firmware-* with pacman -Rdd
FW_DRY=0                 # --fw-dry-run: print planned actions
FW_ALL=0                 # --fw-all: force install all linux-firmware-* subpackages
FW_REBUILD_INIT=0        # --fw-rebuild-init: run mkinitcpio -P after changes
FW_PACMAN_CONFIRM="--noconfirm"  # override with --fw-no-confirm

# Parse firmware-only flags without interfering with the rest
for _arg in "$@"; do
  case "$_arg" in
    --fw-trim)         FW_TRIM=1 ;;
    --fw-dry-run)      FW_DRY=1 ;;
    --fw-all)          FW_ALL=1 ;;
    --fw-rebuild-init) FW_REBUILD_INIT=1 ;;
    --fw-no-confirm)   FW_PACMAN_CONFIRM="" ;;
  esac
done
unset _arg

fw_pkg_available() { pacman -Si "$1" >/dev/null 2>&1; }

fw_install_pkgs() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  if (( FW_DRY )); then
    echo "pacman -Sy --needed ${FW_PACMAN_CONFIRM} ${pkgs[*]}"
  else
    run pacman -Sy --needed ${FW_PACMAN_CONFIRM} "${pkgs[@]}"
  fi
}

fw_optimize() {
  step "Firmware: detecting hardware (PCI/USB/CPU)"
  local pci usb cpu
  pci="$(lspci -nn 2>/dev/null || true)"
  usb="$(lsusb 2>/dev/null || true)"
  cpu="$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/Vendor ID|Vendor/ {gsub(/^[ \t]+/,"",$2); print tolower($2)}' | head -n1)"

  shopt -s nocasematch
  local has_intel=0 has_amd=0 has_nvidia=0 has_realtek=0 has_mediatek=0 has_broadcom=0 has_atheros=0 has_cirrus=0
  printf '%s\n%s\n' "$pci" "$usb" | grep -q 'intel'    && has_intel=1
  printf '%s\n'      "$pci"        | grep -qE 'amd|ati' && has_amd=1
  printf '%s\n'      "$pci"        | grep -q 'nvidia'   && has_nvidia=1
  printf '%s\n%s\n' "$pci" "$usb" | grep -q 'realtek'  && has_realtek=1
  printf '%s\n%s\n' "$pci" "$usb" | grep -q 'mediatek' && has_mediatek=1
  printf '%s\n%s\n' "$pci" "$usb" | grep -q 'broadcom' && has_broadcom=1
  printf '%s\n%s\n' "$pci" "$usb" | grep -qE 'atheros|qualcomm' && has_atheros=1
  printf '%s\n'      "$pci"        | grep -q 'cirrus'   && has_cirrus=1
  shopt -u nocasematch

  say   "Firmware: CPU vendor: ${cpu:-unknown}"
  say "Firmware: Intel:${has_intel} AMD/ATI:${has_amd} NVIDIA:${has_nvidia} Realtek:${has_realtek} Mediatek:${has_mediatek} Broadcom:${has_broadcom} Atheros/Qualcomm:${has_atheros} Cirrus:${has_cirrus}"

  # Decide desired firmware packages
  local desired=()
  if (( FW_ALL )); then
    warn "Firmware: --fw-all set — installing all firmware subpackages (debug)."
    desired+=(linux-firmware-intel linux-firmware-amdgpu linux-firmware-radeon linux-firmware-nvidia \
              linux-firmware-realtek linux-firmware-mediatek linux-firmware-broadcom \
              linux-firmware-atheros linux-firmware-cirrus linux-firmware-other)
  else
    (( has_intel   )) && desired+=(linux-firmware-intel)
    (( has_amd     )) && desired+=(linux-firmware-amdgpu linux-firmware-radeon)
    (( has_nvidia  )) && desired+=(linux-firmware-nvidia)
    (( has_realtek )) && desired+=(linux-firmware-realtek)
    (( has_mediatek)) && desired+=(linux-firmware-mediatek)
    (( has_broadcom)) && desired+=(linux-firmware-broadcom)
    (( has_atheros )) && desired+=(linux-firmware-atheros)
    (( has_cirrus  )) && desired+=(linux-firmware-cirrus)
    # If you often need misc firmware, you can add:
    # desired+=(linux-firmware-other)
  fi
  if ((${#desired[@]}==0)); then
    warn "Firmware: no known vendor matched — falling back to meta package 'linux-firmware'."
    desired=(linux-firmware)
  fi

  # CPU microcode
  local ucode=()
  case "${cpu:-}" in
    *intel*) ucode+=(intel-ucode) ;;
    *amd*)   ucode+=(amd-ucode) ;;
    *)       warn "Firmware: unknown CPU vendor — skipping microcode (install intel-ucode/amd-ucode manually if needed)";;
  esac

  step "Firmware: plan"
  info "To install: ${desired[*]}"
  info "CPU microcode: ${ucode[*]:-none}"
  (( FW_TRIM )) && info "Will trim unnecessary firmware after install."
  (( FW_DRY  )) && warn "DRY-RUN: printing actions only."

  # Install microcode (idempotent)
  step "Firmware: installing CPU microcode (if applicable)"
  fw_install_pkgs "${ucode[@]:-}"

  # Install firmware: prefer split subpackages; if none available, fall back
  step "Firmware: installing linux-firmware packages"
  local available=()
  for p in "${desired[@]}"; do
    fw_pkg_available "$p" && available+=("$p")
  done
  if ((${#available[@]}==0)); then
    warn "Firmware: split subpackages not found on this mirror — using 'linux-firmware'."
    available=(linux-firmware)
  fi
  fw_install_pkgs "${available[@]}"

  # Optional trim
  if (( FW_TRIM )); then
    step "Firmware: trimming non-matching linux-firmware-* packages"
    if [[ " ${available[*]} " == *" linux-firmware "* ]]; then
      info "Firmware: meta package in use — skipping trim."
    else
      mapfile -t _installed < <(pacman -Qq | grep '^linux-firmware' || true)
      declare -A _keep=()
      local r=()
      for p in "${available[@]}"; do _keep["$p"]=1; done
      # remove meta if present with split packages
      pacman -Qq linux-firmware >/dev/null 2>&1 && r+=("linux-firmware")
      for p in "${_installed[@]}"; do
        [[ -n "${_keep[$p]:-}" ]] && continue
        [[ "$p" == "linux-firmware" ]] && continue
        r+=("$p")
      done
      if ((${#r[@]})); then
        info "Firmware: removing: ${r[*]}"
        if (( FW_DRY )); then
          echo "pacman -Rdd ${FW_PACMAN_CONFIRM} ${r[*]}"
        else
          run pacman -Rdd ${FW_PACMAN_CONFIRM} "${r[@]}"
        fi
      else
        info "Firmware: nothing to remove."
      fi
    fi
  fi

  # Optional: rebuild initramfs
  if (( FW_REBUILD_INIT )); then
    if [[ -x /usr/bin/mkinitcpio ]]; then
      step "Firmware: rebuilding initramfs (requested via --fw-rebuild-init)"
      if (( FW_DRY )); then
        echo "mkinitcpio -P"
      else
        run mkinitcpio -P
      fi
    else
      warn "Firmware: mkinitcpio not found — skipping initramfs rebuild."
    fi
  fi
}

# Execute firmware optimization before system tweaks
fw_optimize

# ───────── zram (systemd zram-generator) ─────────
# Configure half RAM as zram swap using lz4. Safe and reversible via backup.
step "Configuring zram (systemd zram-generator)"
run 'sudo pacman -Sy --needed --noconfirm zram-generator || true'
ZRAM_CFG="/etc/systemd/zram-generator.conf"
if [[ ! -f "$ZRAM_CFG" ]]; then
  backup "$ZRAM_CFG"
  run "sudo tee '$ZRAM_CFG' >/dev/null <<'CFG'
# Generated by install_optimize.sh
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
swap-priority = 100
CFG"
else
  warn "zram-generator.conf already exists — leaving as-is."
fi
run "sudo systemctl daemon-reload"
# Try to activate now (optional, will also apply next boot)
run "sudo systemctl start systemd-zram-setup@zram0.service || true"

# ───────── journald persistent size cap ─────────
# Set persistent storage with a 100M cap to prevent runaway logs.
step "Configuring systemd-journald cap (100M)"
run "sudo install -d -m 0755 /etc/systemd/journald.conf.d"
JOURNALD_D="/etc/systemd/journald.conf.d/99-override.conf"
if [[ ! -f "$JOURNALD_D" ]]; then
  run "sudo tee '$JOURNALD_D' >/dev/null <<'CFG'
# Generated by install_optimize.sh
[Journal]
Storage=persistent
SystemMaxUse=100M
RuntimeMaxUse=50M
CFG"
else
  warn "journald override already exists — leaving as-is."
fi
run "sudo systemctl restart systemd-journald || true"

# ───────── tmpfs for /tmp via fstab ─────────
# Mount /tmp as tmpfs if not already configured in fstab.
step "Ensuring /tmp is tmpfs via /etc/fstab"
FSTAB="/etc/fstab"
if ! grep -Eq '^[^#]*[[:space:]]/tmp[[:space:]]+tmpfs' "$FSTAB"; then
  backup "$FSTAB"
  run "echo 'tmpfs   /tmp    tmpfs   defaults,nosuid,nodev,mode=1777   0  0' | sudo tee -a '$FSTAB' >/dev/null"
else
  warn "/tmp tmpfs entry already present — leaving as-is."
fi

# ───────── vm.swappiness ─────────
# Reduce swappiness to prefer RAM; value 10 is a common conservative choice.
step "Setting vm.swappiness=10"
SYSCTL_D="/etc/sysctl.d/99-swappiness.conf"
if [[ ! -f "$SYSCTL_D" ]]; then
  run "echo 'vm.swappiness=10' | sudo tee '$SYSCTL_D' >/dev/null"
else
  warn "swappiness override already exists — leaving as-is."
fi
run "sudo sysctl --system >/dev/null || true"

# ───────── pacman.conf QoL tweaks ─────────
# Enable Color, set ParallelDownloads, and optional ILoveCandy (commented).
step "Tweaking /etc/pacman.conf (Color, ParallelDownloads)"
PACMAN_CONF="/etc/pacman.conf"
backup "$PACMAN_CONF"
# Enable Color
run "sudo sed -i 's/^#Color/Color/' '$PACMAN_CONF'"
# Set or bump ParallelDownloads to 10
if grep -Eq '^#?ParallelDownloads' "$PACMAN_CONF"; then
  run "sudo sed -i 's/^#\\?ParallelDownloads.*/ParallelDownloads = 10/' '$PACMAN_CONF'"
else
  run "sudo sed -i '/\\[options\\]/a ParallelDownloads = 10' '$PACMAN_CONF'"
fi
# Fun but harmless (kept commented to avoid surprising users)
if ! grep -q 'ILoveCandy' "$PACMAN_CONF"; then
  run "sudo sed -i '/\\[options\\]/a #ILoveCandy' '$PACMAN_CONF'"
fi

cat <<'EOT'
========================================================
Optimization complete

• Firmware: only vendor-matching linux-firmware subpackages installed (with safe fallback).
• CPU microcode installed if vendor detected.
• zram configured with lz4 (RAM/2)
• journald capped at 100M (persistent)
• /tmp mounted as tmpfs (fstab) if not already
• vm.swappiness=10 via sysctl.d
• pacman.conf tweaked (Color, ParallelDownloads, #ILoveCandy)

Reboot recommended for /tmp tmpfs and zram to fully apply.
========================================================
EOT
