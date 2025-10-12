#!/usr/bin/env bash
# install_statusbar.sh — install dwm status bar launcher script only
# Purpose: Install a robust, dependency-light dwm status script to ~/.local/bin without
#          touching other configs. Pairs cleanly with install_suckless.sh & install_lookandfeel.sh.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${CYN}[SBAR]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_statusbar.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run as root. Run as your normal user."; exit 1
fi

# ───────── Defaults / args ─────────
LOCAL_BIN="$HOME/.local/bin"
XINIT="$HOME/.xinitrc"
HOOK_XINIT=0       # default: do NOT touch ~/.xinitrc
ENSURE_PATH=1      # ensure ~/.local/bin in PATH via ~/.bash_profile
INSTALL_DEPS=1     # best-effort install of minimal runtime deps
DRY_RUN=0

usage(){ cat <<'EOF'
install_statusbar.sh — options
  --hook-xinit      Append a one-line launcher to ~/.xinitrc (idempotent; file must already exist)
  --no-path         Do NOT modify ~/.bash_profile to add ~/.local/bin to PATH
  --no-deps         Do NOT attempt to install runtime dependencies
  --dry-run         Print actions without changing the system
  -h|--help         Show this help

Design:
• Installs only the bar script to ~/.local/bin/dwm-status.sh.
• By default, does not edit ~/.xinitrc (kept in install_suckless.sh).
• The generated bar script content is preserved EXACTLY as provided.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook-xinit) HOOK_XINIT=1; shift;;
    --no-path)    ENSURE_PATH=0; shift;;
    --no-deps)    INSTALL_DEPS=0; shift;;
    --dry-run)    DRY_RUN=1; shift;;
    -h|--help)    usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ───────── Helpers ─────────
run(){ if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] $*"; else eval "$@"; fi }
append_once(){ local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
ensure_dir(){ mkdir -p "$1"; }

# ───────── Prepare dirs ─────────
ensure_dir "$LOCAL_BIN"

# ───────── Minimal runtime deps (best-effort) ─────────
# Keep this light; do not fail if a package is missing in a custom repo setup.
if (( INSTALL_DEPS == 1 )); then
  if command -v pacman >/dev/null 2>&1; then
    step "Ensuring minimal runtime tools exist (best-effort)"
    # Needed binaries: xsetroot (xorg-xsetroot), fc-list (fontconfig), gdbus (from glib2),
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
if (( ENSURE_PATH == 1 )); then
  if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
    step "Adding ~/.local/bin to PATH via ~/.bash_profile"
    run "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' '$HOME/.bash_profile' 2>/dev/null || echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> '$HOME/.bash_profile'"
  else
    say "~/.local/bin already present in PATH"
  fi
fi

# ───────── Install bar script (CONTENT UNCHANGED) ─────────
step "Installing dwm-status.sh into $LOCAL_BIN"
if [[ $DRY_RUN -eq 1 ]]; then
  say "[dry-run] Would write $LOCAL_BIN/dwm-status.sh (755)"
else
  install -Dm755 /dev/stdin "$LOCAL_BIN/dwm-status.sh" <<'EOF'
#!/usr/bin/env bash
# DWM status:
# Icons first (if a Nerd Font is available), otherwise fall back to compact text.
# Icon example: [  87% |  my-ssid |  online | 2025-10-12 w:41 | 09:05 ]
# Text example:  [ B: 87% | N: my-ssid | S: online | 2025-10-12 w:41 | 09:05 ]
#
# by Nicklas Rudolfsson https://github.com/nirucon
#
# Env:
DWM_STATUS_ICONS=1                # default 1; set 0 to force text-only
DWM_STATUS_ASSUME_ICONS=1         # optional hard override to force icon mode (default 0)
# DWM_STATUS_INTERVAL=seconds       # default 10

set -Eeuo pipefail
IFS=$'\n\t'

# Ensure common tools are available in non-interactive autostarts
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

supports_icons() {
  # Respect explicit opt-out first
  [ "${DWM_STATUS_ICONS:-1}" = "1" ] || return 1

  # Manual override if your login environment is quirky
  [ "${DWM_STATUS_ASSUME_ICONS:-0}" = "1" ] && return 0

  # Try fc-list
  if command -v fc-list >/dev/null 2>&1; then
    if fc-list | grep -qi 'Nerd Font'; then
      return 0
    fi
  fi

  # Fallback: fc-match -s
  if command -v fc-match >/dev/null 2>&1; then
    if fc-match -s | grep -qi 'Nerd Font'; then
      return 0
    fi
  fi

  return 1
}

battery() {
  # Show battery if present (first BAT* only, quietly skip otherwise)
  shopt -s nullglob
  local bat_dirs=(/sys/class/power_supply/BAT*)
  shopt -u nullglob
  [ ${#bat_dirs[@]} -gt 0 ] || return 0

  local b="${bat_dirs[0]}"
  local cap stat
  cap="$(cat "$b/capacity" 2>/dev/null || true)"
  [ -n "${cap:-}" ] || return 0
  stat="$(cat "$b/status" 2>/dev/null || true)"

  if supports_icons; then
    local icon=""
    if [ "$cap" -ge 90 ]; then
      icon=""
    elif [ "$cap" -ge 70 ]; then
      icon=""
    elif [ "$cap" -ge 50 ]; then
      icon=""
    elif [ "$cap" -ge 30 ]; then icon=""; fi

    if [ "$stat" = "Charging" ] || [ "$stat" = "Unknown" ]; then
      printf " %s %s%%" "$icon" "$cap"
    else
      printf "%s %s%%" "$icon" "$cap"
    fi
  else
    printf "B: %s%%" "$cap"
  fi
}

wifi_ssid() {
  # Return SSID if connected via Wi-Fi, else empty
  local ssid=""
  if command -v iwgetid >/dev/null 2>&1; then
    ssid="$(iwgetid -r 2>/dev/null || true)"
  fi
  if [ -z "$ssid" ] && command -v nmcli >/dev/null 2>&1; then
    ssid="$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null |
      awk -F: '$2=="wifi" && $3=="connected"{print $4; exit}')"
  fi
  printf "%s" "$ssid"
}

wired_state() {
  # Prefer en*; fall back to eth*. Return operstate (up/down/unknown)
  shopt -s nullglob
  local ifs=(/sys/class/net/en* /sys/class/net/eth*)
  shopt -u nullglob
  local i
  for i in "${ifs[@]}"; do
    [ -d "$i" ] || continue
    local name="${i##*/}"
    [ "$name" = "lo" ] && continue
    if [ -f "$i/operstate" ]; then
      cat "$i/operstate"
      return 0
    fi
  done
  return 1
}

network() {
  # 1) Wi-Fi SSID if connected
  local ssid
  ssid="$(wifi_ssid)"
  if [ -n "$ssid" ]; then
    if supports_icons; then
      printf " %s" "$ssid"
    else
      printf "N: %s" "$ssid"
    fi
    return 0
  fi

  # 2) Wired operstate if present
  local wstate=""
  wstate="$(wired_state 2>/dev/null || true)"
  if [ -n "$wstate" ]; then
    if supports_icons; then
      printf " %s" "$wstate"
    else
      printf "N: %s" "$wstate"
    fi
    return 0
  fi

  # 3) Otherwise offline
  if supports_icons; then
    printf " off"
  else
    printf "N: offline"
  fi
}

# --- Nextcloud status (icon-first, text fallback) ---
nc_status() {
  # If client isn't installed, don't show anything
  command -v nextcloud >/dev/null 2>&1 || return 0

  # If process not running -> offline
  if ! pgrep -x nextcloud >/dev/null 2>&1; then
    if supports_icons; then printf " offline"; else printf "S: offline"; fi
    return 0
  fi

  local any_sync=0 any_online=0
  if command -v gdbus >/dev/null 2>&1; then
    local objs
    objs="$(gdbus call --session \
      --dest com.nextcloudgmbh.Nextcloud \
      --object-path /com/nextcloudgmbh/Nextcloud \
      --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null)" || objs=""
    if [ -n "$objs" ]; then
      while IFS= read -r path; do
        local v up
        for prop in Status State Connected; do
          v="$(gdbus call --session \
            --dest com.nextcloudgmbh.Nextcloud \
            --object-path "$path" \
            --method org.freedesktop.DBus.Properties.Get \
            org.freedesktop.CloudProvider1 "$prop" 2>/dev/null || true)"
          [ -n "$v" ] && break
        done
        [ -z "$v" ] && continue
        up="$(printf "%s" "$v" | tr '[:lower:]' '[:upper:]')"
        if printf "%s" "$up" | grep -Eq "SYNC|BUSY|RUN|WORK|PROGRESS"; then
          any_sync=1
        elif printf "%s" "$up" | grep -Eq "OK|IDLE|READY|TRUE|ONLINE|CONNECTED"; then
          any_online=1
        fi
      done < <(printf "%s\n" "$objs" | sed -n "s/^\s*['\"]\([^'\"]\+\)['\"].*/\1/p")
    fi
  fi

  if [ "$any_sync" -eq 1 ]; then
    if supports_icons; then printf " syncing"; else printf "S: syncing"; fi
  elif [ "$any_online" -eq 1 ]; then
    if supports_icons; then printf " online"; else printf "S: online"; fi
  else
    # Client running but status unknown -> treat as online (conservative)
    if supports_icons; then printf " idle"; else printf "S: online"; fi
  fi
}

date_part() { date +'%Y-%m-%d w:%V'; }
time_part() { date +'%H:%M'; }

build_line() {
  local parts=()

  local b
  b="$(battery 2>/dev/null || true)"
  [ -n "$b" ] && parts+=("$b")
  local n
  n="$(network 2>/dev/null || true)"
  [ -n "$n" ] && parts+=("$n")
  local s
  s="$(nc_status 2>/dev/null || true)"
  [ -n "$s" ] && parts+=("$s")

  if supports_icons; then
    parts+=(" $(date_part)" " $(time_part)")
  else
    parts+=("$(date_part)" "$(time_part)")
  fi

  local line="${parts[0]:-}"
  if [ ${#parts[@]} -gt 1 ]; then
    for p in "${parts[@]:1}"; do line+=" | $p"; done
  fi
  printf "[ %s ]" "$line"
}

INTERVAL="${DWM_STATUS_INTERVAL:-10}"
while :; do
  xsetroot -name "$(build_line)"
  sleep "$INTERVAL"
done
EOF
fi

# ───────── Optional: hook into ~/.xinitrc (idempotent) ─────────
if (( HOOK_XINIT == 1 )); then
  step "Appending dwm-status.sh launcher to ~/.xinitrc (idempotent)"
  if [[ ! -f "$XINIT" ]]; then
    warn "~/.xinitrc not found — not creating it (install_suckless.sh manages it)."
  else
    append_once '# Status bar (installed by install_statusbar.sh)' "$XINIT"
    append_once '[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &' "$XINIT"
    say "Launcher hook ensured in $XINIT"
  fi
else
  say "Not modifying ~/.xinitrc (default). Use --hook-xinit to append the launcher."
fi

say "Status bar installed. (Tweak at runtime with DWM_STATUS_ICONS=0 and/or DWM_STATUS_INTERVAL=5)"
say "Verify: ls -la ~/.local/bin/dwm-status.sh"
