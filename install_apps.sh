#!/usr/bin/env bash
# APPS: Easy-to-edit lists for pacman & yay packages.

set -euo pipefail
say(){ printf "\033[1;36m[APPS]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }

append_once() {
  # Append a line to a file only if it's not already present (exact match)
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# -----------------------------
# Package lists (edit freely)
# -----------------------------
PACMAN_PKGS=(
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
  nextcloud-client   #

  # Neovim + tooling (LazyVim deps)
  neovim
  ripgrep            # telescope live_grep
  fd                 # fast file finder (telescope)
  lazygit            # TUI git client (optional but nice)
  python-pynvim      # python provider
  nodejs npm         # node provider (LSPs, formatters via Mason)
  git
)

YAY_PKGS=(
  ttf-jetbrains-mono-nerd  # nice mono font
  brave-bin                # browser
  spotify                  # music (cmus is better ofc)
  xautolock                # lock screen
)

# -----------------------------
# Install packages
# -----------------------------
say "Installing pacman apps..."
sudo pacman --noconfirm --needed -S "${PACMAN_PKGS[@]}"

if ! command -v yay >/dev/null 2>&1; then
  say "yay not found; installing yay-bin..."
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin && makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmp"
fi

say "Installing AUR apps via yay..."
yay --noconfirm --needed -S "${YAY_PKGS[@]}"

# -----------------------------
# Neovim + LazyVim bootstrap
# -----------------------------
NVIM_DIR="$HOME/.config/nvim"
LAZY_STARTER_REPO="https://github.com/LazyVim/starter"

if [ ! -d "$NVIM_DIR" ]; then
  say "Setting up Neovim + LazyVim starter (fresh install)..."
  git clone --depth=1 "$LAZY_STARTER_REPO" "$NVIM_DIR"
  # Remove git history so your config is your own
  rm -rf "$NVIM_DIR/.git"

  # First-time plugin install (headless)
  say "Running Lazy sync (headless) for initial plugin install..."
  nvim --headless "+Lazy! sync" +qa || warn "Headless Lazy sync returned non-zero (will complete on first nvim run)."
else
  say "Neovim config already exists at ~/.config/nvim — leaving it untouched."
  say "If you want a fresh LazyVim, back up/remove ~/.config/nvim and re-run this script."
fi

# Optional: set default editors in your shell (non-invasive; add once)
BASH_PROFILE="$HOME/.bash_profile"
append_once 'export EDITOR=nvim' "$BASH_PROFILE"
append_once 'export VISUAL=nvim' "$BASH_PROFILE"

# -----------------------------
# Done
# -----------------------------
say "APPS step complete. To add more apps later, edit PACMAN_PKGS/YAY_PKGS arrays in this file."
say "Neovim + LazyVim is ready. Launch with: nvim"
