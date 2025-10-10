#!/usr/bin/env bash
# SUCKLESS: Build latest dwm/dmenu/st/slock; apply noir theme, keybinds, status bar, rofi theme.
# Safe & idempotent. Comments in English.

set -euo pipefail
say(){ printf "\033[1;35m[SUCK]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[SUCK]\033[0m %s\n" "$*"; }

SUCKLESS_DIR="$HOME/.config/suckless"
LOCAL_BIN="$HOME/.local/bin"
ROFI_DIR="$HOME/.config/rofi"
PICOM_CFG="$HOME/.config/picom/picom.conf"
XINIT="$HOME/.xinitrc"
FONT_NAME="JetBrainsMono Nerd Font"

mkdir -p "$SUCKLESS_DIR" "$LOCAL_BIN" "$ROFI_DIR" "$(dirname "$PICOM_CFG")"

# --------------------------------------------------------------------
# Dependencies used by this module (compositor for st transparency)
# --------------------------------------------------------------------
say "Installing compositor (picom) for st transparency..."
sudo pacman --noconfirm --needed -S picom

say "Ensure Nerd Font is available (via yay)..."
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi
yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true

# --------------------------------------------------------------------
# Get latest upstream sources
# --------------------------------------------------------------------
say "Cloning/updating suckless repositories..."
cd "$SUCKLESS_DIR"
clone_or_pull(){ [ -d "$2/.git" ] && git -C "$2" pull --ff-only || git clone "$1" "$2"; }
clone_or_pull "https://git.suckless.org/dwm"   "dwm"
clone_or_pull "https://git.suckless.org/dmenu" "dmenu"
clone_or_pull "https://git.suckless.org/slock" "slock"
clone_or_pull "https://git.suckless.org/st"    "st"

# --------------------------------------------------------------------
# st: base on config.def.h, only tweak font; transparency via picom
# --------------------------------------------------------------------
say "Configuring st (base on config.def.h)..."
cp -f st/config.def.h st/config.h
# Font: clean, readable mono with Nerd glyphs
sed -i "s|^static char \\*font = .*|static char *font = \"${FONT_NAME}:size=11:antialias=true:autohint=true\";|" st/config.h

say "Building & installing st..."
make -C st clean
sudo make -C st install

# Picom opacity rule for st (no patching needed)
if ! grep -q "class_g = 'St'" "$PICOM_CFG" 2>/dev/null; then
  say "Writing minimal picom.conf (st opacity, glx backend, vsync)..."
  cat > "$PICOM_CFG" <<'EOF'
opacity-rule = [
  "0.86:class_g = 'St'"
];
backend = "glx";
vsync = true;
EOF
fi

# --------------------------------------------------------------------
# dmenu: write a known-good config.h (noir) — portable across versions
# --------------------------------------------------------------------
say "Writing noir config for dmenu (safe, strictly valid C)..."
cat > dmenu/config.h <<EOF
static int topbar = 1;
static const char *fonts[] = { "${FONT_NAME}:size=11" };
static const char *prompt = NULL;
static const char *colors[SchemeLast][2] = {
    /*               fg         bg       */
    [SchemeNorm] = { "#cfcfcf", "#111111" },
    [SchemeSel]  = { "#ffffff", "#333333" },
    [SchemeOut]  = { "#eeeeee", "#333333" }
};
static unsigned int lines = 0;
static unsigned int lineheight = 26;
static const char worddelimiters[] = " ";
EOF

say "Building & installing dmenu..."
make -C dmenu clean
sudo make -C dmenu install

# --------------------------------------------------------------------
# slock: stock (stable). Blur patches are version-fragile → skip by default
# --------------------------------------------------------------------
say "Building & installing slock (stock, stable)..."
make -C slock clean
sudo make -C slock install

# --------------------------------------------------------------------
# dwm: base on config.def.h, apply noir palette, font, Super as MOD,
#      add/adjust keybinds (slock, restart, rofi, pcmanfm, flameshot,
#      volume/brightness). All inserted safely/idempotently.
# --------------------------------------------------------------------
say "Configuring dwm (base on config.def.h + noir + requested keybinds)..."
cp -f dwm/config.def.h dwm/config.h

# Font(s) + dmenu font used by dmenucmd
sed -i "s|^static const char \\*fonts\\[\\] = .*|static const char *fonts[] = { \"${FONT_NAME}:size=11\" };|" dwm/config.h
sed -i "s|^static const char dmenufont\\[\\] = .*|static const char dmenufont[] = \"${FONT_NAME}:size=11\";|" dwm/config.h

# Noir palette via existing color variables (present in config.def.h for dwm 6.x)
# Map: bg=#111111, border=#333333, norm-fg=#eeeeee, sel bg/border=#333333, sel fg=#ffffff
sed -i 's|^static const char col_gray1\\[\\] = .*|static const char col_gray1[] = "#111111";|' dwm/config.h
sed -i 's|^static const char col_gray2\\[\\] = .*|static const char col_gray2[] = "#333333";|' dwm/config.h
sed -i 's|^static const char col_gray3\\[\\] = .*|static const char col_gray3[] = "#eeeeee";|' dwm/config.h
sed -i 's|^static const char col_gray4\\[\\] = .*|static const char col_gray4[] = "#ffffff";|' dwm/config.h
# Use the "accent" color slot as same dark gray to get a cohesive noir look
sed -i 's|^static const char col_cyan\\[\\] = .*|static const char col_cyan[]  = "#333333";|' dwm/config.h
# Colors array will automatically pick these variables (no need to rewrite it)

# Super as MOD (Windows key)
sed -i 's/#define MODKEY .*/#define MODKEY Mod4Mask/' dwm/config.h

# Include XF86 keys once (needed for volume/brightness)
grep -q 'XF86keysym.h' dwm/config.h || sed -i '1 i #include <X11/XF86keysym.h>' dwm/config.h

# Define extra spawn commands only if absent (rofi, pcmanfm, slock, volume/brightness, flameshot)
append_if_absent() {
  local pat="$1"; shift
  grep -q "$pat" dwm/config.h || printf "%s\n" "$*" >> dwm/config.h
}

append_if_absent 'static const char \*roficmd\[\]' \
'static const char *roficmd[]  = { "rofi", "-show", "drun", NULL };'
append_if_absent 'static const char \*pcmanfm\[\]' \
'static const char *pcmanfm[]  = { "pcmanfm", NULL };'
append_if_absent 'static const char \*slockcmd\[\]' \
'static const char *slockcmd[] = { "slock", NULL };'
append_if_absent 'static const char \*vup\[\]' \
'static const char *vup[]   = { "pactl", "set-sink-volume", "@DEFAULT_SINK@", "+5%", NULL };'
append_if_absent 'static const char \*vdown\[\]' \
'static const char *vdown[] = { "pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%", NULL };'
append_if_absent 'static const char \*vmute\[\]' \
'static const char *vmute[] = { "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle", NULL };'
append_if_absent 'static const char \*bup\[\]' \
'static const char *bup[]   = { "brightnessctl", "set", "+5%", NULL };'
append_if_absent 'static const char \*bdown\[\]' \
'static const char *bdown[] = { "brightnessctl", "set", "5%-", NULL };'
append_if_absent 'static const char \*flameshot\[\]' \
'static const char *flameshot[] = { "flameshot", "gui", NULL };'

# Restart helper function (if missing)
append_if_absent 'restartdwm' \
'// Re-exec dwm to restart cleanly
static void restartdwm(const Arg *arg) { execvp("dwm", (char *const[]){"dwm", NULL}); }'

# Replace the default "quit" binding (MOD|Shift|q) with restartdwm (safe awk transform)
awk '
  BEGIN{inkeys=0}
  /static Key keys\[/ {inkeys=1}
  inkeys && /^\};/ {inkeys=0}
  {
    if (inkeys && $0 ~ /MODKEY/ && $0 ~ /ShiftMask/ && $0 ~ /XK_q/ && $0 ~ /quit/) {
      sub(/quit/, "restartdwm")
    }
    print
  }
' dwm/config.h > dwm/config.h.tmp && mv dwm/config.h.tmp dwm/config.h

# Append our requested extra keybinds exactly once (guard by marker)
if ! grep -q '/* ALPI custom keys */' dwm/config.h; then
  # Insert just before end of keys[] array
  awk '
    BEGIN{inkeys=0}
    /static Key keys\[/ {inkeys=1}
    inkeys && /^\};/ {
      print "/* ALPI custom keys */"
      print "\t{ MODKEY,               XK_p,                    spawn,          {.v = dmenucmd } },"
      print "\t{ MODKEY,               XK_m,                    spawn,          {.v = roficmd } },"
      print "\t{ MODKEY,               XK_f,                    spawn,          {.v = pcmanfm } },"
      print "\t{ MODKEY,               XK_q,                    killclient,     {0} },"
      print "\t{ MODKEY,               XK_Escape,               spawn,          {.v = slockcmd } },"
      print "\t{ 0,                    XF86XK_AudioLowerVolume, spawn,          {.v = vdown } },"
      print "\t{ 0,                    XF86XK_AudioRaiseVolume, spawn,          {.v = vup } },"
      print "\t{ 0,                    XF86XK_AudioMute,        spawn,          {.v = vmute } },"
      print "\t{ 0,                    XF86XK_MonBrightnessUp,  spawn,          {.v = bup } },"
      print "\t{ 0,                    XF86XK_MonBrightnessDown,spawn,          {.v = bdown } },"
      print "\t{ 0,                    XK_Print,                spawn,          {.v = flameshot } },"
      print $0; inkeys=0; next
    }
    {print}
  ' dwm/config.h > dwm/config.h.tmp && mv dwm/config.h.tmp dwm/config.h
fi

# Make sure we didn’t accidentally include fibonacci or other local includes
sed -i '/fibonacci\.c/d' dwm/config.h

say "Building & installing dwm..."
make -C dwm clean
sudo make -C dwm install

# --------------------------------------------------------------------
# Status bar script (battery | wifi | YYYY-MM-DD (WW) | HH:MM)
# --------------------------------------------------------------------
say "Installing simple elegant dwm status bar..."
install -Dm755 /dev/stdin "$LOCAL_BIN/dwm-status.sh" <<'EOF'
#!/usr/bin/env bash
# battery (if laptop) | wifi (if connected) | YYYY-MM-DD (v.WW) | HH:MM
set -euo pipefail
battery() {
  shopt -s nullglob; local bats=(/sys/class/power_supply/BAT*); shopt -u nullglob
  [ ${#bats[@]} -gt 0 ] || return 0
  local b="${bats[0]}"; local cap stat
  cap="$(cat "$b/capacity" 2>/dev/null || echo "?")"
  stat="$(cat "$b/status" 2>/dev/null || echo "?")"
  case "$stat" in Charging) stat="CHR";; Discharging) stat="DIS";; Full) stat="FUL";; *) stat="UNK";; esac
  printf "🔋 %s%% %s" "$cap" "$stat"
}
wifi() {
  local ssid=""
  command -v iwgetid >/dev/null && ssid="$(iwgetid -r 2>/dev/null || true)"
  [ -n "$ssid" ] || ssid="$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1 | cut -d: -f1 || true)"
  [ -n "$ssid" ] && printf "📶 %s" "$ssid"
}
while :; do
  parts=()
  b="$(battery || true)"; [ -n "${b:-}" ] && parts+=("$b")
  w="$(wifi || true)";    [ -n "${w:-}" ] && parts+=("$w")
  d="$(date +'%Y-%m-%d (%V) | %H:%M')"; parts+=("$d")
  IFS=' | ' read -r line <<< "${parts[*]}"
  xsetroot -name "$line"
  sleep 10
done
EOF

# --------------------------------------------------------------------
# Rofi noir theme (matches the palette used elsewhere)
# --------------------------------------------------------------------
say "Writing rofi noir theme..."
cat > "$ROFI_DIR/config.rasi" <<EOF
configuration { font: "${FONT_NAME} 11"; show-icons: true; }
* { bg: #111111; fg: #eeeeee; selbg: #333333; selfg: #ffffff; acc: #8f8f8f; }
window   { transparency: "real"; background-color: @bg; border: 2; border-color: @selbg; }
mainbox  { background-color: @bg; }
listview { background-color: @bg; fixed-height: true; }
element selected { background-color: @selbg; text-color: @selfg; }
element  { text-color: @fg; }
inputbar { children: [prompt,entry]; background-color: @bg; text-color: @fg; }
prompt   { text-color: @acc; }
EOF

# --------------------------------------------------------------------
# .xinitrc (SE keyboard, nitrogen restore, picom, status, dwm)
# --------------------------------------------------------------------
say "Creating .xinitrc (Swedish keyboard, nitrogen restore, picom, status, dwm)..."
cat > "$XINIT" <<'EOF'
#!/bin/sh
# Swedish keyboard in X
setxkbmap se

# Restore wallpaper (nitrogen) if available
command -v nitrogen >/dev/null && nitrogen --restore &

# Compositor for st transparency
command -v picom >/dev/null && picom --experimental-backends &

# Status bar updater
~/.local/bin/dwm-status.sh &

# Solid background fallback
xsetroot -solid "#111111"

# Start dwm
exec dwm
EOF
chmod 644 "$XINIT"

say "Suckless step complete."
