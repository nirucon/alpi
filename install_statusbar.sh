#!/usr/bin/env bash
# STATUSBAR – by Nicklas Rudolfsson https://github.com/nirucon

set -Eeuo pipefail
IFS=$'\n\t'

say(){ printf "\033[1;36m[SBAR]\033[0m %s\n" "$*"; }
fail(){ printf "\033[1;31m[SBAR]\033[0m %s\n" "$*" >&2; }
trap 'fail "install_statusbar.sh failed. See previous step for details."' ERR

LOCAL_BIN="$HOME/.local/bin"
XINIT="$HOME/.xinitrc"
mkdir -p "$LOCAL_BIN"

say "Writing dwm-status.sh (icons with ASCII fallback)…"
install -Dm755 /dev/stdin "$LOCAL_BIN/dwm-status.sh" <<'EOF'
#!/usr/bin/env bash
# DWM status: [ 🔋/ | /disconnected | YYYY-MM-DD (w:WW) | HH:MM ]
# Env:
#   DWM_STATUS_ICONS=0|1 (default 1)
#   DWM_STATUS_INTERVAL=seconds (default 10)

set -Eeuo pipefail
IFS=$'\n\t'

supports_icons() {
  fc-list | grep -qi "Symbols Nerd Font" || return 1
  [ "${DWM_STATUS_ICONS:-1}" = "1" ]
}

battery() {
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

build_line() {
  local parts=()

  local b_str; b_str="$(battery 2>/dev/null || true)"; [ -n "${b_str:-}" ] && parts+=("$b_str")
  local w_str; w_str="$(wifi 2>/dev/null || true)";    [ -n "${w_str:-}" ] && parts+=("$w_str")

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
  say "Creating minimal .xinitrc and enabling status bar…"
  cat > "$XINIT" <<'EOF'
#!/bin/sh
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

say "Status bar installed. (Use DWM_STATUS_ICONS=0 and/or DWM_STATUS_INTERVAL=5 to tweak.)"
