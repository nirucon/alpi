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
  --hook-xinit      Append a one-line launcher to ~/.xinitrc (idempotent)
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
# We do NOT install heavy deps; just helpful tools if missing. Safe to skip with --no-deps.
if (( INSTALL_DEPS == 1 )); then
  if command -v pacman >/dev/null 2>&1; then
    step "Ensuring minimal runtime tools exist (best-effort)"
    run "sudo pacman -S --needed --noconfirm xorg-xsetroot inetutils grep sed coreutils fontconfig gawk"
    # Wi-Fi helpers if available in repos
    run "sudo pacman -S --needed --noconfirm iw networkmanager || true"
    # DBus helper for Nextcloud status parsing
    run "sudo pacman -S --needed --noconfirm glib2 || true" || true
  else
    warn "pacman not found; skipping dependency install"
  fi
else
  warn "--no-deps set: skipping dependency checks"
fi

# ───────── Ensure ~/.local/bin on PATH ─────────
if (( ENSURE_PATH == 1 )); then
  if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
    step "Adding ~/.local/bin to PATH via ~/.bash_profile"
    run "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' '$HOME/.bash_profile' 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> '$HOME/.bash_profile'"
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
# DWM status: [ 🔋/ | /disconnected | YYYY-MM-DD (w:WW) | HH:MM ]
# by Nicklas Rudolfsson https://github.com/nirucon
#
# Purpose:
#   Lightweight, dependency-minimal status line for dwm via xsetroot.
#   Uses Nerd Font icons when available; falls back to ASCII text otherwise.
#
# Environment:
#   DWM_STATUS_ICONS=0|1       # default 1; set 0 to force ASCII-only
#   DWM_STATUS_INTERVAL=seconds # default 10; update interval

set -Eeuo pipefail
IFS=$'\n\t'

supports_icons() {
  # Detect a Symbols Nerd Font and whether icons are allowed
  fc-list | grep -qi "Symbols Nerd Font" || return 1
  [ "${DWM_STATUS_ICONS:-1}" = "1" ]
}

battery() {
  # Show battery percent and charging status if a battery is present
  shopt -s nullglob
  local bat_dirs=(/sys/class/power_supply/BAT*)
  shopt -u nullglob
  [ ${#bat_dirs[@]} -gt 0 ] || return 0

  local b="${bat_dirs[0]}"
  local cap stat
  cap="$(cat "$b/capacity" 2>/dev/null || echo "")"
  [ -n "$cap" ] || return 0
  stat="$(cat "$b/status" 2>/dev/null || echo "")"

  if supports_icons; then
    local icon=""
    if   [ "$cap" -ge 90 ]; then icon=""
    elif [ "$cap" -ge 70 ]; then icon=""
    elif [ "$cap" -ge 50 ]; then icon=""
    elif [ "$cap" -ge 30 ]; then icon=""
    fi
    if [ "$stat" = "Charging" ]; then
      printf " %s %s%%" "$icon" "$cap"
    else
      printf "%s %s%%" "$icon" "$cap"
    fi
  else
    if [ "$stat" = "Charging" ]; then
      printf "BAT %s%% CHG" "$cap"
    else
      printf "BAT %s%%" "$cap"
    fi
  fi
}

wifi() {
  # Show SSID if connected via Wi-Fi; otherwise show disconnected
  shopt -s nullglob
  local wl_ifaces=(/sys/class/net/wl*)
  shopt -u nullglob
  [ ${#wl_ifaces[@]} -gt 0 ] || return 0

  local ssid=""
  if command -v iwgetid >/dev/null 2>&1; then
    ssid="$(iwgetid -r 2>/dev/null || true)"
  fi
  if [ -z "$ssid" ] && command -v nmcli >/dev/null 2>&1; then
    ssid="$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null \
      | awk -F: '$2=="wifi" && $3=="connected"{print $4; exit}')"
  fi

  if [ -n "$ssid" ]; then
    if supports_icons; then printf " %s" "$ssid"; else printf "WIFI %s" "$ssid"; fi
  else
    if supports_icons; then printf "󰤭 disconnected"; else printf "WIFI disconnected"; fi
  fi
}

# --- Nextcloud status (no tray needed) ---
nc_status() {
  # Don't show anything if client is not installed
  command -v nextcloud >/dev/null 2>&1 || return 0

  # If process not running -> OFF
  pgrep -x nextcloud >/dev/null 2>&1 || {
    if supports_icons; then printf " off"; else printf "NC off"; fi
    return 0
  }

  # Try CloudProviders via D-Bus (Nextcloud desktop client exposes com.nextcloudgmbh.Nextcloud)
  if command -v gdbus >/dev/null 2>&1; then
    local objs; objs="$(gdbus call --session \
      --dest com.nextcloudgmbh.Nextcloud \
      --object-path /com/nextcloudgmbh/Nextcloud \
      --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null)" || objs=""

    # If query failed, just say RUN
    if [ -z "$objs" ]; then
      if supports_icons; then printf " run"; else printf "NC run"; fi
      return 0
    fi

    # Parse object paths from the returned dict (bash-safe heuristic)
    local any_sync=0 any_ok=0
    while IFS= read -r path; do
      # Probe a few common props on org.freedesktop.CloudProvider1
      local val=""
      for prop in Status State Connected; do
        v="$(gdbus call --session \
             --dest com.nextcloudgmbh.Nextcloud \
             --object-path "$path" \
             --method org.freedesktop.DBus.Properties.Get \
             org.freedesktop.CloudProvider1 "$prop" 2>/dev/null || true)"
        [ -n "$v" ] && { val="$v"; break; }
      done
      [ -z "$val" ] && continue

      up="$(printf "%s" "$val" | tr '[:lower:]' '[:upper:]')"
      if printf "%s" "$up" | grep -Eq "SYNC|BUSY|RUN|WORK|PROGRESS"; then
        any_sync=1
      elif printf "%s" "$up" | grep -Eq "OK|IDLE|READY|TRUE|ONLINE|CONNECTED"; then
        any_ok=1
      fi
    done < <(printf "%s\n" "$objs" | sed -n "s/^\s*['\"]\([^'\"]\+\)['\"].*/\1/p")

    if [ "$any_sync" -eq 1 ]; then
      if supports_icons; then printf " sync"; else printf "NC sync"; fi
    elif [ "$any_ok" -eq 1 ]; then
      if supports_icons; then printf " ok"; else printf "NC ok"; fi
    else
      if supports_icons; then printf " run"; else printf "NC run"; fi
    fi
    return 0
  fi

  # Fallback if no gdbus: we know it's running
  if supports_icons; then printf " run"; else printf "NC run"; fi
}

build_line() {
  # Compose the full status string from parts, with graceful omissions
  local parts=()

  local b_str; b_str="$(battery 2>/dev/null || true)"; [ -n "${b_str:-}" ] && parts+=("$b_str")
  local w_str; w_str="$(wifi 2>/dev/null || true)";    [ -n "${w_str:-}" ] && parts+=("$w_str")
  local n_str; n_str="$(nc_status 2>/dev/null || true)"; [ -n "${n_str:-}" ] && parts+=("$n_str")

  local d t
  d="$(date +'%Y-%m-%d (w:%V)')"
  t="$(date +'%H:%M')"
  if supports_icons; then
    parts+=(" $d" " $t")
  else
    parts+=("DATE $d" "TIME $t")
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
