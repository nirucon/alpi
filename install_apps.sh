#!/usr/bin/env bash
# install_apps.sh — application layer for Arch
# Purpose: Install desktop apps & developer tools via pacman and (optionally) yay,
#          without removing anything from your previous apps list.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${CYN}[APPS]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_apps.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || { fail "Do not run as root."; exit 1; }

# ───────── Flags ─────────
DRY_RUN=0
USE_YAY=1
USE_FILES=1  # optionally extend lists via ./apps-pacman.txt and ./apps-yay.txt

usage(){ cat <<'EOF'
install_apps.sh — options
  --no-yay      Do not install yay or any AUR packages
  --no-files    Ignore ./apps-pacman.txt and ./apps-yay.txt even if present
  --dry-run     Print actions without changing the system
  -h|--help     Show this help

Design:
• Keeps ALL apps from your previous script.
• You can extend via apps-pacman.txt / apps-yay.txt (one package per line). Duplicates are removed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-yay)   USE_YAY=0; shift;;
    --no-files) USE_FILES=0; shift;;
    --dry-run)  DRY_RUN=1; shift;;
    -h|--help)  usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ───────── Helpers ─────────
# If passed one string → run through a shell (allows pipes/&&).
# If passed multiple args → run as argv list (ideal for arrays: "${arr[@]}").
run(){
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
  else
    if [[ $# -eq 1 ]]; then
      bash -lc "$1"
    else
      "$@"
    fi
  fi
}
read_list(){ local f="$1"; [[ -f "$f" ]] || return 0; grep -vE '^\s*#' "$f" | awk 'NF' ; }
unique(){ awk '!x[$0]++'; }

append_once() {
  # Append a line to a file only if it's not already present (exact match)
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# ───────── Your original lists (UNCHANGED) ─────────
PACMAN_PKGS_BASE=(
  # Desktop utilities
  nitrogen           # wallpaper manager (restore on start)
  arandr             # display layout
  pcmanfm            # file manager
  gvfs               # virtual FS (needed for automount in pcmanfm)
  gvfs-mtp gvfs-gphoto2 gvfs-afc
  udisks2            # disks backend
  udiskie            # optional automount helper (tray if you want)
  cmus               # terminal music player
  cava               # audio visualizer
  flameshot          # screenshots
  picom              # compositor (also used by st transparency)
  lxappearance       # gtk theming
  maim               # screenshot alt
  alacritty          # terminal 2
  fastfetch          # fetchinfo
  slop               #
  xclip              #
  dunst              # notify
  libnotify          # notify
  materia-gtk-theme  # pcmanfm styling
  papirus-icon-theme # pcmanfm styling
  gimp               #
  nextcloud-client   # sync stuff
  mpv                #
  jq                 #
  fzf                #
  btop               # sysinfo
  localsend          # 

  # Neovim + tooling (LazyVim deps)
  neovim
  ripgrep            # telescope live_grep
  fd                 # fast file finder (telescope)
  lazygit            # TUI git client (optional but nice)
  python-pynvim      # python provider
  nodejs npm         # node provider (LSPs, formatters via Mason)
  git
)

YAY_PKGS_BASE=(
  ttf-jetbrains-mono-nerd  # nice mono font
  brave-bin                # browser
  spotify                  # music (cmus is better ofc)
  xautolock                # lock screen
  timeshift-autosnap       # snaps
)

# ───────── Optional extension via files ─────────
mapfile -t PACMAN_FROM_FILE < <( (( USE_FILES==1 )) && read_list ./apps-pacman.txt || true )
mapfile -t YAY_FROM_FILE    < <( (( USE_FILES==1 )) && read_list ./apps-yay.txt    || true )

# Merge + dedupe (your base first; file adds come after)
PACMAN_PKGS=( "${PACMAN_PKGS_BASE[@]}" "${PACMAN_FROM_FILE[@]}" )
YAY_PKGS=(    "${YAY_PKGS_BASE[@]}"    "${YAY_FROM_FILE[@]}"    )
mapfile -t PACMAN_PKGS < <(printf '%s\n' "${PACMAN_PKGS[@]}" | unique)
mapfile -t YAY_PKGS    < <(printf '%s\n' "${YAY_PKGS[@]}"    | unique)

# ───────── Install pacman apps ─────────
step "Installing pacman apps (${#PACMAN_PKGS[@]})"
if (( ${#PACMAN_PKGS[@]} > 0 )); then
  run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
else
  say "No pacman apps to install"
fi

# ───────── Install yay + AUR apps (optional) ─────────
if (( USE_YAY==1 )); then
  if ! command -v yay >/dev/null 2>&1; then
    step "Installing yay-bin (AUR helper)"
    tmp="$(mktemp -d)"
    run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    ( cd "$tmp/yay-bin" && run makepkg -si --noconfirm )
    rm -rf "$tmp"
  fi
  if (( ${#YAY_PKGS[@]} > 0 )); then
    step "Installing AUR apps via yay (${#YAY_PKGS[@]})"
    run yay -S --needed --noconfirm "${YAY_PKGS[@]}"
  else
    say "No AUR apps to install"
  fi
else
  warn "--no-yay set: skipping AUR apps"
fi

# ───────── Neovim (LazyVim bootstrap) ─────────
NVIM_DIR="$HOME/.config/nvim"
LAZY_STARTER_REPO="https://github.com/LazyVim/starter"
if command -v nvim >/dev/null 2>&1; then
  if [[ ! -d "$NVIM_DIR" ]]; then
    step "Bootstrapping LazyVim"
    run git clone --depth=1 "$LAZY_STARTER_REPO" "$NVIM_DIR"
    ( cd "$NVIM_DIR" && run rm -rf .git )
    # First-time plugin sync (non-fatal if it fails headless)
    run nvim --headless "+Lazy! sync" +qa || true
    say "LazyVim starter installed to $NVIM_DIR"
  else
    say "Neovim config exists ($NVIM_DIR) — leaving as-is"
  fi
else
  warn "Neovim not found; skipping LazyVim bootstrap"
fi

# ───────── Ensure EDITOR vars and PATH (idempotent) ─────────
BASH_PROFILE="$HOME/.bash_profile"
append_once 'export EDITOR=nvim' "$BASH_PROFILE"
append_once 'export VISUAL=nvim' "$BASH_PROFILE"
if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  append_once 'export PATH="$HOME/.local/bin:$PATH"' "$BASH_PROFILE"
fi

cat <<'EOT'
========================================================
Apps installation complete

• All apps from your previous script are included by default
• pacman apps installed with --needed (no duplicates)
• AUR apps installed via yay (auto-installed if missing)
• (Optional) LazyVim bootstrapped if no ~/.config/nvim exists
========================================================
EOT
