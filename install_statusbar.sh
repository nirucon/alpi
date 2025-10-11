#!/usr/bin/env bash
# STATUSBAR – by Nicklas Rudolfsson https://github.com/nirucon

# Strict error handling for reliability
set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Pretty logging ----------
say(){  printf "\033[1;36m[SBAR]\033[0m %s\n" "$*"; }
fail(){ printf "\033[1;31m[SBAR]\033[0m %s\n" "$*" >&2; }

# Fail with context if anything errors
trap 'fail "install_statusbar.sh failed. See previous step for details."' ERR

# ---------- Safety: refuse running as root ----------
# Running as root would place files under /root and cause confusion.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run this script with sudo/root. Run it as your normal user."
  # If you prefer to auto-target the invoking sudo user instead, you could replace the 'exit 1'
  # above with dynamic HOME detection:
  # if [ -n "${SUDO_USER:-}" ]; then
  #   USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  #   export HOME="$USER_HOME"
  #   say "Running under sudo; targeting HOME=$HOME for file installation."
  # else
  #   exit 1
  # fi
  exit 1
fi

LOCAL_BIN="$HOME/.local/bin"
XINIT="$HOME/.xinitrc"

# Ensure ~/.local/bin exists
mkdir -p "$LOCAL_BIN"

# Ensure ~/.local/bin is on PATH for future shells (idempotent append)
if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  say "Adding ~/.local/bin to PATH via ~/.bash_profile"
  grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bash_profile" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bash_profile"
fi

say "Writing dwm-status.sh (icons with ASCII fallback)…"
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

# Ensure .xinitrc launches the bar (append once, non-destructive)
if [ ! -f "$XINIT" ]; then
  say "Creating minimal ~/.xinitrc and enabling status bar…"
  cat > "$XINIT" <<'EOF'
#!/bin/sh
# Minimal X init with Swedish layout and dwm status bar
setxkbmap se
command -v nitrogen >/dev/null && nitrogen --restore &
command -v picom >/dev/null && picom --experimental-backends &
~/.local/bin/dwm-status.sh &
xsetroot -solid "#111111"
exec dwm
EOF
  chmod 644 "$XINIT"
elif ! grep -q 'dwm-status.sh' "$XINIT" 2>/dev/null; then
  say "Adding status bar launch to ~/.xinitrc …"
  {
    echo ''
    echo '# Status bar'
    echo '~/.local/bin/dwm-status.sh &'
  } >> "$XINIT"
else
  say "Status bar launch already present in ~/.xinitrc — leaving as-is."
fi

say "Status bar installed. (Tweak with DWM_STATUS_ICONS=0 and/or DWM_STATUS_INTERVAL=5)"
say "Verify: ls -la ~/.local/bin/dwm-status.sh"
