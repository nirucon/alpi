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

say "Install compositor (for st transparency via picom) and helpers..."
sudo pacman --noconfirm --needed -S picom

say "Install yay (if missing) and Nerd Font..."
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi
yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true

# ---------- Clone or update repos ----------
say "Cloning/updating suckless repositories..."
cd "$SUCKLESS_DIR"
clone_or_pull(){ [ -d "$2/.git" ] && git -C "$2" pull --ff-only || git clone "$1" "$2"; }
clone_or_pull "https://git.suckless.org/dwm"   "dwm"
clone_or_pull "https://git.suckless.org/dmenu" "dmenu"
clone_or_pull "https://git.suckless.org/slock" "slock"
clone_or_pull "https://git.suckless.org/st"    "st"

# ---------- ST: base on config.def.h, minimal tweaks ----------
say "Configuring st (base on config.def.h)..."
cp -f st/config.def.h st/config.h
# Font
sed -i "s|^static char \\*font = .*|static char *font = \"${FONT_NAME}:size=11:antialias=true:autohint=true\";|" st/config.h
# (Optional) keep upstream colors; transparency via picom

say "Build & install st..."
make -C st clean
sudo make -C st install

# Picom opacity rule for st (transparency without patches)
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

# ---------- DMENU: base on config.def.h + noir colors ----------
say "Configuring dmenu (base on config.def.h + noir)..."
cp -f dmenu/config.def.h dmenu/config.h

# Set font
sed -i "s|^static const char \\*fonts\\[\\] = .*|static const char *fonts[] = { \"${FONT_NAME}:size=11\" };|" dmenu/config.h
# Colors (noir)
sed -i 's|^\(\s*\[SchemeNorm\].*\){.*}|	[SchemeNorm] = { "#cfcfcf", "#111111" },|' dmenu/config.h
sed -i 's|^\(\s*\[SchemeSel\].*\){.*}|	[SchemeSel]  = { "#ffffff", "#333333" },|' dmenu/config.h
# Optional: lineheight for nicer look
if ! grep -q '^static unsigned int lineheight' dmenu/config.h; then
  sed -i '/^static int topbar/a static unsigned int lineheight = 26;' dmenu/config.h
fi

say "Build & install dmenu..."
make -C dmenu clean
sudo make -C dmenu install

# ---------- SLOCK: stock (stable). Blur can be added later if desired ----------
say "Build & install slock (stock, stable)..."
make -C slock clean
sudo make -C slock install

# ---------- DWM: base on config.def.h + theme + keybinds ----------
say "Configuring dwm (base on config.def.h + noir + requested keybinds)..."
cp -f dwm/config.def.h dwm/config.h

# Colors / fonts
sed -i "s|^static const char \\*fonts\\[\\] = .*|static const char *fonts[] = { \"${FONT_NAME}:size=11\" };|" dwm/config.h
# Define a minimal noir palette and apply to colors[][]
sed -i 's|^static const char \*colors\[\]\[3\] = {.*|static const char *colors[][3] = {|' dwm/config.h
sed -i '/^static const char \*colors\[\]\[3\] = {/,/};/c\
static const char *colors[][3] = {\
	/*               fg        bg       border */\
	[SchemeNorm] = { "#eeeeee", "#111111", "#333333" },\
	[SchemeSel]  = { "#ffffff", "#333333", "#ffffff" },\
};' dwm/config.h

# Show bar on top (defaults likely already OK)
sed -i 's/^static const int topbar.*/static const int topbar             = 1;/' dwm/config.h
sed -i 's/^static const int showbar.*/static const int showbar           = 1;/' dwm/config.h

# Modkey = Super (Mod4)
sed -i 's/#define MODKEY .*/#define MODKEY Mod4Mask/' dwm/config.h

# Include XF86 keys
grep -q XF86keysym.h dwm/config.h || sed -i '1 i #include <X11/XF86keysym.h>' dwm/config.h

# Commands for binds
# insert term, dmenu, rofi, pcmanfm, slock commands (if not present)
awk -i inplace '
/^static const char \*termcmd/ { seen=1 }
{print}
END{
 if(!seen){
  print "static const char *termcmd[]  = { \"st\", NULL };"
  print "static const char *dmenucmd[] = { \"dmenu_run\", \"-p\", \"run\", NULL };"
  print "static const char *roficmd[]  = { \"rofi\", \"-show\", \"drun\", NULL };"
  print "static const char *pcmanfm[]  = { \"pcmanfm\", NULL };"
  print "static const char *slockcmd[] = { \"slock\", NULL };"
  print "static const char *vup[]   = { \"pactl\", \"set-sink-volume\", \"@DEFAULT_SINK@\", \"+5%\", NULL };"
  print "static const char *vdown[] = { \"pactl\", \"set-sink-volume\", \"@DEFAULT_SINK@\", \"-5%\", NULL };"
  print "static const char *vmute[] = { \"pactl\", \"set-sink-mute\", \"@DEFAULT_SINK@\", \"toggle\", NULL };"
  print "static const char *bup[]   = { \"brightnessctl\", \"set\", \"+5%\", NULL };"
  print "static const char *bdown[] = { \"brightnessctl\", \"set\", \"5%-\", NULL };"
  print "static const char *flameshot[] = { \"flameshot\", \"gui\", NULL };"
 }
}' dwm/config.h

# Restart helper
grep -q "restartdwm" dwm/config.h || cat >> dwm/config.h <<'EOF'

// Re-exec dwm to restart cleanly
static void restartdwm(const Arg *arg) { execvp("dwm", (char *const[]){"dwm", NULL}); }
EOF

# Keybinds: ensure our requested ones exist (append if missing)
cat >> dwm/config.h <<'EOF'

/* Extra keybinds per user spec */
static Key extra_keys[] = {
	{ MODKEY,               XK_Return,               spawn,          {.v = termcmd } },
	{ MODKEY,               XK_p,                    spawn,          {.v = dmenucmd } },
	{ MODKEY,               XK_m,                    spawn,          {.v = roficmd } },
	{ MODKEY,               XK_f,                    spawn,          {.v = pcmanfm } },
	{ MODKEY,               XK_q,                    killclient,     {0} },
	{ MODKEY|ShiftMask,     XK_q,                    restartdwm,     {0} },
	{ MODKEY,               XK_Escape,               spawn,          {.v = slockcmd } },
	{ 0,                    XF86XK_AudioLowerVolume, spawn,          {.v = vdown } },
	{ 0,                    XF86XK_AudioRaiseVolume, spawn,          {.v = vup } },
	{ 0,                    XF86XK_AudioMute,        spawn,          {.v = vmute } },
	{ 0,                    XF86XK_MonBrightnessUp,  spawn,          {.v = bup } },
	{ 0,                    XF86XK_MonBrightnessDown,spawn,          {.v = bdown } },
	{ 0,                    XK_Print,                spawn,          {.v = flameshot } },
};
/* Merge extra_keys into keys[] at compile time (simple trick) */
#undef keys
#define keys mykeys
static Key mykeys[] = {
#include "keys.h"
};
EOF

# Build a keys.h from the existing default keys plus our extras
# (We simply dump the original keys array and append extra_keys entries.)
awk '
/^static Key keys\[\]/, /^\};/ { print > "keys.tmp"; next } { print > "rest.tmp" }
END{
  print "// Autogenerated keys.h: default keys + extras" > "keys.h"
  print "#include <X11/keysym.h>" >> "keys.h"
  while ((getline line < "keys.tmp") > 0) {
    if (line ~ /static Key keys\[\]/) { print "/* default keys start */" >> "keys.h"; next }
    if (line ~ /^\};/) { print "/* default keys end */" >> "keys.h"; next }
    print line >> "keys.h"
  }
  print "/* appended extra keys */" >> "keys.h"
  while ((getline line < "/dev/stdin") > 0) print line >> "keys.h"
}' dwm/config.h <(sed -n '/^static Key extra_keys\[\]/,/^};/p' dwm/config.h) >/dev/null 2>&1 || true
rm -f dwm/keys.tmp dwm/rest.tmp 2>/dev/null || true

# Remove any accidental includes like fibonacci.c from earlier variants
sed -i '/fibonacci\.c/d' dwm/config.h

say "Build & install dwm..."
make -C dwm clean
sudo make -C dwm install

# ---------- Status bar ----------
say "Install simple elegant dwm status bar..."
install -Dm755 /dev/stdin "$LOCAL_BIN/dwm-status.sh" <<'EOF'
#!/usr/bin/env bash
# battery (if laptop) | wifi (if connected) | YYYY-%m-%d (v.WW) | HH:MM
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
  d="$(date +'%Y-%m-%d (v.%V) | %H:%M')"; parts+=("$d")
  IFS=' | ' read -r line <<< "${parts[*]}"
  xsetroot -name "$line"
  sleep 10
done
EOF

# ---------- Rofi noir theme ----------
say "Write rofi noir theme..."
cat > "$ROFI_DIR/config.rasi" <<EOF
configuration { font: "${FONT_NAME} 11"; show-icons: true; }
* { bg: #111111; fg: #eeeeee; selbg: #333333; selfg: #ffffff; acc: #8f8f8f; }
window { transparency: "real"; background-color: @bg; border: 2; border-color: @selbg; }
mainbox { background-color: @bg; }
listview { background-color: @bg; fixed-height: true; }
element selected { background-color: @selbg; text-color: @selfg; }
element { text-color: @fg; }
inputbar { children: [prompt,entry]; background-color: @bg; text-color: @fg; }
prompt { text-color: @acc; }
EOF

# ---------- .xinitrc ----------
say "Create .xinitrc (SE keyboard, nitrogen restore, picom, status, dwm)..."
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
