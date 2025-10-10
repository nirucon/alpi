#!/usr/bin/env bash
# SUCKLESS: Build latest dwm/dmenu/st/slock; apply noir theme, keybinds, status bar, rofi theme.
# Includes: Mod=Super (Mod4), nice fonts, transparency for st (needs picom), blurred slock (try patch, fallback stock).

set -euo pipefail
say(){ printf "\033[1;35m[SUCK]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[SUCK]\033[0m %s\n" "$*"; }

SUCKLESS_DIR="$HOME/.config/suckless"
LOCAL_BIN="$HOME/.local/bin"
ROFI_DIR="$HOME/.config/rofi"
XINIT="$HOME/.xinitrc"

mkdir -p "$SUCKLESS_DIR" "$LOCAL_BIN" "$ROFI_DIR"

say "Installing build-time dependencies and compositor (for st transparency)..."
sudo pacman --noconfirm --needed -S picom

say "Installing yay (if missing) and Nerd Fonts..."
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi
# A nice monospace: JetBrainsMono Nerd Font (AUR)
yay --noconfirm --needed -S ttf-jetbrains-mono-nerd

font_name="JetBrainsMono Nerd Font"

say "Cloning/updating suckless repositories..."
cd "$SUCKLESS_DIR"
clone_or_pull(){ [ -d "$2/.git" ] && git -C "$2" pull --ff-only || git clone "$1" "$2"; }
clone_or_pull "https://git.suckless.org/dwm"   "dwm"
clone_or_pull "https://git.suckless.org/dmenu" "dmenu"
clone_or_pull "https://git.suckless.org/slock" "slock"
clone_or_pull "https://git.suckless.org/st"    "st"

# ---------- Noir palette ----------
# Black/Gray/White carefully matched
FG="#eeeeee"; BG="#111111"; FG_DIM="#cfcfcf"
ACC="#8f8f8f"; SEL_BG="#333333"; SEL_FG="#ffffff"
# st needs alpha via patch (we'll attempt); also prepare colors

# ---------- dmenu config.h ----------
say "Writing noir config for dmenu..."
cat > dmenu/config.h <<EOF
static int topbar = 1;
static const char *fonts[] = { "${font_name}:size=11" };
static const char *prompt      = NULL;
static const char *colors[SchemeLast][2] = {
	/*               fg       bg       */
	[SchemeNorm] = { "${FG_DIM}", "${BG}" },
	[SchemeSel]  = { "${SEL_FG}", "${SEL_BG}" },
	[SchemeOut]  = { "${FG}",    "${SEL_BG}" },
};
static unsigned int lines      = 0;
static unsigned int lineheight = 26;
static const char worddelimiters[] = " ";
EOF

# ---------- st config.h (noir + alpha) ----------
say "Preparing noir config for st (with alpha)..."
cat > st/config.h <<'EOF'
/* See LICENSE file for copyright and license details. */
static char *font = "JetBrainsMono Nerd Font:size=11:antialias=true:autohint=true";
static int borderpx = 12;
static unsigned int alpha = 220; /* 0..255 (needs alpha patch + compositor) */
static char *termname = "st-256color";
unsigned int tabspaces = 8;
/* Colors (noir) */
static const char *colorname[] = {
  "#111111", "#ff5555", "#50fa7b", "#f1fa8c",
  "#bd93f9", "#ff79c6", "#8be9fd", "#bbbbbb",
  "#44475a", "#ff6e6e", "#69ff94", "#ffffa5",
  "#d6b3ff", "#ff92d0", "#a4ffff", "#ffffff",
};
unsigned int defaultfg = 15;
unsigned int defaultbg = 0;
unsigned int defaultcs = 15;
unsigned int defaultrcs = 8;
EOF

# Try to apply the alpha patch for st (best-effort)
say "Attempting to patch st with alpha..."
(
  cd st
  # Fetch alpha patch (common filename); ignore if already patched or if patch fails.
  curl -fsSLO https://st.suckless.org/patches/alpha/st-alpha-0.9.0.diff || true
  patch -p1 < st-alpha-0.9.0.diff || warn "st alpha patch failed (maybe already applied)."
) || true

# ---------- slock: try blur patch ----------
say "Attempting to enable blur effect for slock (best-effort)..."
(
  cd slock
  # Known blur patches vary by version; try a common one, fallback to stock.
  curl -fsSLO https://tools.suckless.org/slock/patches/blur-pixelated/slock-1.4-blur-pixelated.diff || true
  patch -p1 < slock-1.4-blur-pixelated.diff || warn "slock blur patch failed; continuing with stock slock."
) || true

# ---------- dwm config.h ----------
# Mod = Super (Mod4). Keybinds per your spec. Simple statusbar via xsetroot script.
say "Writing dwm config with Super as mod and requested keybinds..."
cat > dwm/config.h <<'EOF'
/* Appearance */
static const unsigned int borderpx  = 2;
static const unsigned int snap      = 10;
static const int showbar            = 1;
static const int topbar             = 1;
static const char *fonts[]          = { "JetBrainsMono Nerd Font:size=11" };
static const char col_bg[]          = "#111111";
static const char col_fg[]          = "#eeeeee";
static const char col_border[]      = "#333333";
static const char col_selbg[]       = "#333333";
static const char col_selfg[]       = "#ffffff";
static const char *colors[][3]      = {
	/*               fg        bg       border   */
	[SchemeNorm] = { col_fg,   col_bg,  col_border },
	[SchemeSel]  = { col_selfg,col_selbg,col_selfg },
};

/* Tagging */
static const char *tags[] = { "1","2","3","4","5","6","7","8","9" };

/* Layout(s) */
#include "fibonacci.c" /* optional; remove if unwanted */
static const float mfact     = 0.55; /* master size factor */
static const int nmaster     = 1;    /* clients in master area */
static const int resizehints = 1;    /* obey size hints */
static const Layout layouts[] = {
	{ "[]=",      tile },
	{ "><>",      NULL },    /* floating */
	{ "[M]",      monocle },
};

/* Key definitions */
#define MODKEY Mod4Mask /* Super (Windows) key */
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} }

#include <X11/XF86keysym.h>

/* Helper for spawning shell commands */
static const char *termcmd[]  = { "st", NULL };
static const char *dmenucmd[] = { "dmenu_run", "-p", "run", NULL };
static const char *roficmd[]  = { "rofi", "-show", "drun", NULL };
static const char *pcmanfm[]  = { "pcmanfm", NULL };
static const char *slockcmd[] = { "slock", NULL };

/* Volume/Brightness via pipewire+pactl and brightnessctl */
static const char *vup[]   = { "pactl", "set-sink-volume", "@DEFAULT_SINK@", "+5%", NULL };
static const char *vdown[] = { "pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%", NULL };
static const char *vmute[] = { "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle", NULL };
static const char *bup[]   = { "brightnessctl", "set", "+5%", NULL };
static const char *bdown[] = { "brightnessctl", "set", "5%-", NULL };
static const char *flameshot[] = { "flameshot", "gui", NULL };

/* Restart dwm helper (re-exec) */
static void restartdwm(const Arg *arg) { execvp("dwm", (char *const[]){ "dwm", NULL }); }

/* Commands */
static Key keys[] = {
	/* modifier             key                      function        argument */
	{ MODKEY,               XK_Return,               spawn,          {.v = termcmd } },

	/* Specified bindings */
	{ MODKEY,               XK_p,                    spawn,          {.v = dmenucmd } },   /* dmenu */
	{ MODKEY,               XK_m,                    spawn,          {.v = roficmd } },    /* rofi */
	{ MODKEY,               XK_f,                    spawn,          {.v = pcmanfm } },    /* pcmanfm */
	{ MODKEY,               XK_q,                    killclient,     {0} },                /* close window */
	{ MODKEY|ShiftMask,     XK_q,                    restartdwm,     {0} },                /* restart dwm */
	{ MODKEY,               XK_Escape,               spawn,          {.v = slockcmd } },   /* lock (slock) */

	/* Media keys */
	{ 0,                    XF86XK_AudioLowerVolume, spawn,          {.v = vdown } },
	{ 0,                    XF86XK_AudioRaiseVolume, spawn,          {.v = vup } },
	{ 0,                    XF86XK_AudioMute,        spawn,          {.v = vmute } },
	{ 0,                    XF86XK_MonBrightnessUp,  spawn,          {.v = bup } },
	{ 0,                    XF86XK_MonBrightnessDown,spawn,          {.v = bdown } },

	/* PrintScreen -> flameshot */
	{ 0,                    XK_Print,                spawn,          {.v = flameshot } },

	/* Layout & focus basics */
	{ MODKEY,               XK_b,                    togglebar,      {0} },
	{ MODKEY,               XK_j,                    focusstack,     {.i = +1 } },
	{ MODKEY,               XK_k,                    focusstack,     {.i = -1 } },
	{ MODKEY,               XK_h,                    setmfact,       {.f = -0.05} },
	{ MODKEY,               XK_l,                    setmfact,       {.f = +0.05} },
	{ MODKEY,               XK_space,                setlayout,      {0} },
	{ MODKEY,               XK_Tab,                  view,           {0} },

	/* Tags */
	TAGKEYS(                XK_1,                    0)
	TAGKEYS(                XK_2,                    1)
	TAGKEYS(                XK_3,                    2)
	TAGKEYS(                XK_4,                    3)
	TAGKEYS(                XK_5,                    4)
	TAGKEYS(                XK_6,                    5)
	TAGKEYS(                XK_7,                    6)
	TAGKEYS(                XK_8,                    7)
	TAGKEYS(                XK_9,                    8)
};

/* Mouse (unchanged minimal) */
static Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
EOF

# Optional: small helper included in dwm source for fibonacci (can be removed safely)
cat > dwm/fibonacci.c <<'EOF'
/* minimal placeholder to satisfy include; remove the include in config.h if undesired */
static void tile(Monitor *m) { _tile(m); } /* fallback to built-in tile if present */
EOF

# ---------- Build & install ----------
build_install(){
  say "Building $1..."
  make -C "$1" clean
  sudo make -C "$1" install
}
build_install dmenu
build_install st
build_install slock
build_install dwm

# ---------- Status bar ----------
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
  d="$(date +'%Y-%m-%d (v.%V) | %H:%M')"; parts+=("$d")
  IFS=' | ' read -r line <<< "${parts[*]}"
  xsetroot -name "$line"
  sleep 10
done
EOF

# ---------- Rofi noir theme ----------
say "Writing rofi noir theme..."
install -Dm644 /dev/stdin "$ROFI_DIR/config.rasi" <<EOF
configuration { font: "${font_name} 11"; show-icons: true; }
* { bg: ${BG}; fg: ${FG}; selbg: ${SEL_BG}; selfg: ${SEL_FG}; acc: ${ACC}; }
window { transparency: "real"; background-color: @bg; border: 2; border-color: @selbg; }
mainbox { background-color: @bg; }
listview { background-color: @bg; fixed-height: true; }
element selected { background-color: @selbg; text-color: @selfg; }
element { text-color: @fg; }
inputbar { children: [prompt,entry]; background-color: @bg; text-color: @fg; }
prompt { text-color: @acc; }
EOF

# ---------- .xinitrc ----------
say "Creating .xinitrc (Swedish keyboard, picom, nitrogen restore, status, dwm)..."
install -m 644 /dev/stdin "$XINIT" <<'EOF'
#!/bin/sh
# Swedish keyboard in X
setxkbmap se

# Restore wallpaper (nitrogen) if available
command -v nitrogen >/dev/null && nitrogen --restore &

# Compositor for st transparency
command -v picom >/dev/null && picom --experimental-backends &

# Status bar updater
~/.local/bin/dwm-status.sh &

# Solid background fallback (if nitrogen missing)
xsetroot -solid "#111111"

# Start dwm
exec dwm
EOF

say "Suckless step complete."
