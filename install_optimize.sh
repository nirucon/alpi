#!/usr/bin/env bash
# OPTIMIZE – by Nicklas Rudolfsson https://github.com/nirucon

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Pretty logging ----------
GRN="\033[1;32m"; BLU="\033[1;34m"; YLW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GRN}[OPTI]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

trap 'fail "install_optimize.sh failed. Check the previous step for details."' ERR

# ---------- Sudo pre-flight ----------
if ! sudo -v; then fail "Sudo privileges are required."; exit 1; fi

# ---------- pacman & makepkg tuning ----------
step "Enabling pacman niceties: Color + ParallelDownloads=10"
sudo sed -i 's/^\s*#\s*Color/Color/' /etc/pacman.conf || true
if grep -Eq '^\s*ParallelDownloads\s*=' /etc/pacman.conf; then
  sudo sed -i 's/^\s*ParallelDownloads\s*=.*/ParallelDownloads = 10/' /etc/pacman.conf
else
  echo 'ParallelDownloads = 10' | sudo tee -a /etc/pacman.conf >/dev/null
fi
say "pacman configured."

step "Setting makepkg parallel build flags"
CORES="$(nproc)"
sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j${CORES}\"|g" /etc/makepkg.conf
say "MAKEFLAGS set to -j${CORES}."

# ---------- Optional mirrors via reflector ----------
step "Refresh mirrorlist with reflector? (SE/NO/DK, latest 20, HTTPS) "
read -rp "(y/N): " USE_REFLECTOR
if [[ "${USE_REFLECTOR,,}" == "y" ]]; then
  say "Installing reflector (if needed)…"
  sudo pacman --noconfirm --needed -S reflector
  say "Updating mirrors (sorted by rate)…"
  sudo systemctl stop reflector.service 2>/dev/null || true
  sudo reflector --verbose \
    --country Sweden,Norway,Denmark \
    --latest 20 --protocol https --sort rate \
    --save /etc/pacman.d/mirrorlist \
    || warn "Reflector failed; keeping existing mirrorlist."
  say "Mirrorlist updated."
else
  say "Skipping reflector (keeping current mirrors)."
fi

# ---------- CPU microcode ----------
step "Installing CPU microcode (Intel/AMD)…"
if grep -q GenuineIntel /proc/cpuinfo; then
  sudo pacman --noconfirm --needed -S intel-ucode
  say "Installed intel-ucode."
elif grep -q AuthenticAMD /proc/cpuinfo; then
  sudo pacman --noconfirm --needed -S amd-ucode
  say "Installed amd-ucode."
else
  warn "Unknown CPU vendor; skipped microcode."
fi

# ---------- zram (swap-in-RAM) ----------
step "Enabling zram (lz4, size = RAM/2)…"
sudo pacman --noconfirm --needed -S zram-generator

ZRAM_CFG="/etc/systemd/zram-generator.conf"
read -r -d '' ZRAM_DESIRED <<'EOF' || true
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF

if [[ -f "$ZRAM_CFG" ]]; then
  if ! grep -q 'zram-size' "$ZRAM_CFG" 2>/dev/null; then
    echo "$ZRAM_DESIRED" | sudo tee -a "$ZRAM_CFG" >/dev/null
  else
    # Replace any existing [zram0] block conservatively
    sudo awk '
      BEGIN{printed=0}
      /^\[zram0\]/{print "[zram0]"; print "zram-size = ram / 2"; print "compression-algorithm = lz4"; skip=1; next}
      skip && /^\[/{skip=0}
      !skip{print}
      END{if(!printed){}}
    ' "$ZRAM_CFG" | sudo tee "$ZRAM_CFG" >/dev/null
  fi
else
  echo "$ZRAM_DESIRED" | sudo tee "$ZRAM_CFG" >/dev/null
fi

sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || true
say "zram configured."

# ---------- Laptop power & thermals ----------
step "Detecting laptop to enable power optimizations…"
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  say "Battery found: enabling TLP"
  sudo pacman --noconfirm --needed -S tlp
  sudo systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
  sudo systemctl enable --now tlp.service

  if grep -q GenuineIntel /proc/cpuinfo; then
    say "Intel laptop: enabling thermald"
    sudo pacman --noconfirm --needed -S thermald
    sudo systemctl enable --now thermald.service
  fi
else
  say "No laptop battery detected; skipping TLP/thermald."
fi

# ---------- Time sync ----------
step "Ensuring systemd-timesyncd is active…"
sudo systemctl enable --now systemd-timesyncd.service 2>/dev/null || true
say "Time sync active."

cat <<'EOT'

========================================================
OPTIMIZE DONE

• pacman: Color + ParallelDownloads=10
• makepkg: MAKEFLAGS = -jN (N = CPU cores)
• mirrors: reflector (optional; only if you confirmed)
• microcode: intel-ucode / amd-ucode (based on CPU)
• zram: lz4, size = RAM/2
• laptop: TLP enabled (and thermald on Intel)
• time sync: systemd-timesyncd enabled

Safe to re-run anytime.
========================================================
EOT
