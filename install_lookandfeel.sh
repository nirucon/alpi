#!/bin/bash
# install_lookandfeel.sh
#
# Pulls look&feel assets from a Git repo (default: nirucon/suckless_lookandfeel)
# and installs them into sensible locations under $HOME.
#
# Changes in this version:
# - .xinitrc and .bash_profile are PROTECTED (never overwrite)
# - .bashrc and .bash_aliases CAN be installed from repo (with timestamped backup)
# - Creates xinitrc hooks instead of modifying .xinitrc directly
# - Installs ALL .sh scripts from repo's scripts/ folder to ~/.local/bin/
# - Downloads wallpapers.zip and extracts to ~/Pictures/Wallpapers
# - Fixed error handling to not exit prematurely
# - UPDATED: Uses feh instead of nitrogen for wallpaper management
#
# Design:
# - Clone/update to ~/.cache/alpi/lookandfeel/<branch>
# - Copy from that repo (NOT from the alpi repo root)
# - Timestamped backups for existing files
# - Skip missing optional files gracefully
# - Make installed *.sh executable (755) in ~/.local/bin
# - Download and extract wallpapers.zip
#
# Flags:
#   --repo URL         (default: https://github.com/nirucon/suckless_lookandfeel)
#   --branch NAME      (default: main)
#   --dry-run          (no changes, show actions)
#   --help             Show help

set -eEu -o pipefail
shopt -s nullglob dotglob

# ───────── Defaults ─────────
REPO_URL="https://github.com/nirucon/suckless_lookandfeel"
BRANCH="main"
DRY_RUN=0
WALLPAPER_URL="https://n.rudolfsson.net/dl/wallpapers/wallpapers.zip"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

# ───────── Logging ─────────
ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { printf "[%s] %s\n" "$(ts)" "$*"; }
ok() { printf "\e[32m[%s] ✓ %s\e[0m\n" "$(ts)" "$*"; }
warn() { printf "\e[33m[%s] ⚠ %s\e[0m\n" "$(ts)" "$*"; }
err() { printf "\e[31m[%s] ✗ %s\e[0m\n" "$(ts)" "$*"; }
die() {
  err "$@"
  exit 1
}

usage() {
  cat <<'EOF'
install_lookandfeel.sh – Install configs, themes, scripts, and wallpapers

USAGE:
  ./install_lookandfeel.sh [options]

OPTIONS:
  --repo URL         Git repository URL (default: nirucon/suckless_lookandfeel)
  --branch NAME      Branch to checkout (default: main)
  --dry-run          Preview actions without making changes
  --help             Show this help

DESIGN:
  • Clones repo to ~/.cache/alpi/lookandfeel/<branch>
  • Installs ALL .sh scripts from scripts/ to ~/.local/bin/
  • Copies config files to ~/.config/
  • Installs dotfiles (.bashrc, .bash_aliases, etc.) with backup
  • Creates xinitrc hooks (does NOT modify .xinitrc)
  • Downloads and extracts wallpapers.zip to ~/Pictures/Wallpapers
  • Uses feh for wallpaper management (replaced nitrogen)
  
PROTECTED FILES (never overwritten):
  • .xinitrc         (managed by install_suckless.sh)
  • .bash_profile    (managed by install_apps.sh)
  
INSTALLABLE WITH BACKUP:
  • .bashrc          (your custom shell config)
  • .bash_aliases    (your aliases and functions)
  • .Xresources      (X11 settings)
  • .inputrc         (readline config)

EXAMPLES:
  ./install_lookandfeel.sh
  ./install_lookandfeel.sh --branch dev --dry-run
EOF
}

while (($#)); do
  case "$1" in
  --repo)
    shift
    [[ $# -gt 0 ]] || die "--repo requires a URL"
    REPO_URL="$1"
    shift
    ;;
  --branch)
    shift
    [[ $# -gt 0 ]] || die "--branch requires a name"
    BRANCH="$1"
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *) die "Unknown argument: $1 (use --help)" ;;
  esac
done

# ───────── Where to cache ─────────
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/alpi/lookandfeel"
DEST_DIR="$CACHE_BASE/$BRANCH"
XINITRC_HOOKS="$HOME/.config/xinitrc.d"

mkdir -p -- "$CACHE_BASE" "$XINITRC_HOOKS"

# ───────── Clone/update repo ─────────
if [[ -d "$DEST_DIR/.git" ]]; then
  log "Updating look&feel repo at: $DEST_DIR"
  if ((DRY_RUN == 0)); then
    git -C "$DEST_DIR" fetch --all --prune
    git -C "$DEST_DIR" checkout "$BRANCH"
    git -C "$DEST_DIR" reset --hard "origin/$BRANCH"
  else
    log "(dry-run) git -C \"$DEST_DIR\" fetch/checkout/reset"
  fi
else
  log "Cloning look&feel repo -> $DEST_DIR"
  if ((DRY_RUN == 0)); then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST_DIR"
  else
    log "(dry-run) git clone --depth 1 --branch \"$BRANCH\" \"$REPO_URL\" \"$DEST_DIR\""
  fi
fi

log "Using source tree: $DEST_DIR (branch=$BRANCH)"

# ───────── Helpers ─────────
backup_then_install_file() {
  local src="$1" dst="$2" mode="$3"
  local dst_dir
  dst_dir="$(dirname -- "$dst")"
  [[ -f "$src" ]] || {
    warn "Missing source (skipping): $src"
    return 0
  }

  if ((DRY_RUN == 1)); then
    log "(dry-run) install $src -> $dst (mode $mode)"
    return 0
  fi

  mkdir -p -- "$dst_dir"
  if [[ -e "$dst" ]]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -a -- "$dst" "${dst}.bak.${ts}"
    log "Backup: $dst -> ${dst}.bak.${ts}"
  fi
  install -m "$mode" "$src" "$dst"
  ok "Installed: $src -> $dst (mode $mode)"
}

install_sh_to_local_bin() {
  local from_dir="$1"
  local files=("$from_dir"/*.sh)
  ((${#files[@]})) || {
    log "No *.sh in $from_dir (skipping)."
    return 0
  }

  mkdir -p -- "$HOME/.local/bin"
  chmod u+rwx "$HOME/.local/bin"

  log "Installing scripts from $from_dir to ~/.local/bin/"
  for f in "${files[@]}"; do
    backup_then_install_file "$f" "$HOME/.local/bin/$(basename -- "$f")" 755
  done
}

mirror_dir_into_config() {
  local base_dir="$1"
  [[ -d "$base_dir" ]] || {
    log "No directory: $base_dir (skipping)."
    return 0
  }

  log "Mirroring $base_dir -> ~/.config/"
  while IFS= read -r -d '' src; do
    local rel="${src#$base_dir/}"
    local dst="$HOME/.config/$rel"
    backup_then_install_file "$src" "$dst" 644
  done < <(find "$base_dir" -type f -print0)
}

# ───────── Wallpaper download and extraction ─────────
download_and_extract_wallpapers() {
  # Disable exit on error for this function
  set +e
  
  local url="$1"
  local dest="$2"

  log "==> Downloading wallpapers from $url"

  if ((DRY_RUN == 1)); then
    log "(dry-run) Would create directory: $dest"
    log "(dry-run) Would download wallpapers.zip from: $url"
    log "(dry-run) Would extract to: $dest"
    set -e
    return 0
  fi

  # Create wallpaper directory
  mkdir -p -- "$dest"
  ok "Created wallpaper directory: $dest"

  # Check for required tools
  if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    warn "Neither wget nor curl found. Skipping wallpaper download."
    warn "Install wget or curl to enable wallpaper downloads."
    set -e
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    warn "unzip not found. Skipping wallpaper extraction."
    warn "Install unzip to enable wallpaper extraction."
    set -e
    return 1
  fi

  # Determine which download tool to use
  local download_tool=""
  if command -v wget >/dev/null 2>&1; then
    download_tool="wget"
  else
    download_tool="curl"
  fi

  log "Using $download_tool for downloads"
  
  # Temporary file for the zip
  local temp_zip="$CACHE_BASE/wallpapers.zip"
  
  # Download the zip file
  log "Downloading wallpapers.zip..."
  if [[ "$download_tool" == "wget" ]]; then
    if wget -q -O "$temp_zip" "$url" 2>/dev/null; then
      ok "Downloaded wallpapers.zip successfully"
    else
      err "Failed to download wallpapers.zip"
      rm -f "$temp_zip" 2>/dev/null || true
      set -e
      return 1
    fi
  else
    # curl approach
    if curl -s -f -o "$temp_zip" "$url" 2>/dev/null; then
      ok "Downloaded wallpapers.zip successfully"
    else
      err "Failed to download wallpapers.zip"
      rm -f "$temp_zip" 2>/dev/null || true
      set -e
      return 1
    fi
  fi

  # Verify the file is not empty
  if [[ ! -s "$temp_zip" ]]; then
    err "Downloaded file is empty"
    rm -f "$temp_zip" 2>/dev/null || true
    set -e
    return 1
  fi

  # Extract the zip file
  log "Extracting wallpapers to $dest..."
  if unzip -q -o "$temp_zip" -d "$dest" 2>/dev/null; then
    ok "Wallpapers extracted successfully"
    
    # Count extracted files
    local count
    count=$(find "$dest" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | wc -l)
    ok "Found $count wallpaper file(s) in $dest"
  else
    err "Failed to extract wallpapers.zip"
    rm -f "$temp_zip" 2>/dev/null || true
    set -e
    return 1
  fi

  # Clean up temporary zip file
  rm -f "$temp_zip" 2>/dev/null || true
  ok "Cleaned up temporary files"

  # Re-enable exit on error
  set -e
  return 0
}

# ───────── Protected files (managed by other scripts) ─────────
# .xinitrc is managed by install_suckless.sh (creates minimal template with hooks)
# .bash_profile is managed by install_apps.sh (adds PATH and EDITOR exports)
# .bashrc and .bash_aliases CAN come from lookandfeel repo (for nirucon users)
PROTECTED_FILES=(.xinitrc .bash_profile)

is_protected() {
  local filename="$1"
  for protected in "${PROTECTED_FILES[@]}"; do
    [[ "$filename" == "$protected" ]] && return 0
  done
  return 1
}

# ───────── Install from the look&feel repo ─────────
log "==> Installing from look&feel repository"

# 1) Scripts from repo's scripts/ or bin/ folders
# ALL .sh files are installed automatically to ~/.local/bin/
[[ -d "$DEST_DIR/scripts" ]] && install_sh_to_local_bin "$DEST_DIR/scripts"
[[ -d "$DEST_DIR/bin" ]] && install_sh_to_local_bin "$DEST_DIR/bin"

# 2) Well-known single-file configs at repo root (optional)
declare -A SPECIAL_MAP=(
  ["$DEST_DIR/picom.conf"]="$HOME/.config/picom/picom.conf"
  ["$DEST_DIR/alacritty.toml"]="$HOME/.config/alacritty/alacritty.toml"
  ["$DEST_DIR/dunstrc"]="$HOME/.config/dunst/dunstrc"
  ["$DEST_DIR/Black-Metal.rasi"]="$HOME/.local/share/rofi/themes/Black-Metal.rasi"
  ["$DEST_DIR/config.rasi"]="$HOME/.config/rofi/config.rasi"
)

for src in "${!SPECIAL_MAP[@]}"; do
  dst="${SPECIAL_MAP[$src]}"
  [[ -f "$src" ]] && backup_then_install_file "$src" "$dst" 644 || log "Not found (optional): $src"
done

# 3) Mirror ./config or ./.config from the look&feel repo into $HOME/.config
mirror_dir_into_config "$DEST_DIR/config"
mirror_dir_into_config "$DEST_DIR/.config"

# 4) Copy dotfiles from look&feel repo root into $HOME
log "Processing dotfiles from repo root..."
for df in "$DEST_DIR"/.*; do
  base="$(basename -- "$df")"
  [[ -f "$df" ]] || continue
  [[ "$base" == "." || "$base" == ".." || "$base" =~ ^\.git ]] && continue

  # Check if protected (only .xinitrc and .bash_profile)
  if is_protected "$base"; then
    if [[ -f "$HOME/$base" ]]; then
      warn "Protected file exists: $base (managed by other install scripts)"
      warn "Skipping to avoid conflicts. To merge manually:"
      warn "  diff $HOME/$base $df"
      continue
    fi
  fi

  # Install dotfiles with backup (including .bashrc and .bash_aliases)
  case "$base" in
  .bashrc)
    log "Installing .bashrc from lookandfeel repo (backup created if exists)"
    backup_then_install_file "$df" "$HOME/$base" 644
    ;;
  .bash_aliases)
    log "Installing .bash_aliases from lookandfeel repo (backup created if exists)"
    backup_then_install_file "$df" "$HOME/$base" 644
    ;;
  .zshrc | .inputrc | .Xresources | .profile)
    backup_then_install_file "$df" "$HOME/$base" 644
    ;;
  *)
    log "Skipping unknown dotfile: $base"
    ;;
  esac
done

# 5) Download and extract wallpapers
download_and_extract_wallpapers "$WALLPAPER_URL" "$WALLPAPER_DIR"

# 6) Create xinitrc hooks for autostart programs
log "Creating xinitrc hooks in ~/.config/xinitrc.d/"

# Hook for compositor
cat >"$XINITRC_HOOKS/10-compositor.sh" <<'EOF'
#!/bin/sh
# Compositor hook (picom)
# Created by install_lookandfeel.sh

command -v picom >/dev/null 2>&1 && picom &
EOF
chmod +x "$XINITRC_HOOKS/10-compositor.sh"

# Hook for wallpaper (UPDATED: uses feh instead of nitrogen)
cat >"$XINITRC_HOOKS/20-wallpaper.sh" <<'EOF'
#!/bin/sh
# Wallpaper hook (feh + wallrotate)
# Created by install_lookandfeel.sh

# Restore last wallpaper (if ~/.fehbg exists)
[ -f "$HOME/.fehbg" ] && "$HOME/.fehbg" &

# Wallpaper rotation script (if installed)
[ -x "$HOME/.local/bin/wallrotate.sh" ] && "$HOME/.local/bin/wallrotate.sh" &
EOF
chmod +x "$XINITRC_HOOKS/20-wallpaper.sh"

# Hook for notifications
cat >"$XINITRC_HOOKS/25-notifications.sh" <<'EOF'
#!/bin/sh
# Notification daemon hook (dunst)
# Created by install_lookandfeel.sh

command -v dunst >/dev/null 2>&1 && dunst &
EOF
chmod +x "$XINITRC_HOOKS/25-notifications.sh"

# Hook for cloud sync
cat >"$XINITRC_HOOKS/50-nextcloud.sh" <<'EOF'
#!/bin/sh
# Cloud sync hook (Nextcloud)
# Created by install_lookandfeel.sh

command -v nextcloud >/dev/null 2>&1 && nextcloud --background &
EOF
chmod +x "$XINITRC_HOOKS/50-nextcloud.sh"

# Hook for polkit agent
cat >"$XINITRC_HOOKS/60-polkit.sh" <<'EOF'
#!/bin/sh
# Polkit authentication agent hook
# Created by install_lookandfeel.sh

if command -v /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 >/dev/null 2>&1; then
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
fi
EOF
chmod +x "$XINITRC_HOOKS/60-polkit.sh"

ok "Created xinitrc hooks (these will be sourced by ~/.xinitrc)"

# 7) PATH notice
case ":$PATH:" in
*":$HOME/.local/bin:"*) : ;;
*)
  warn "~/.local/bin is not in your PATH."
  warn "Add this line to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
  warn "Or log out and back in (install_apps.sh should have added it to ~/.bash_profile)"
  ;;
esac

cat <<EOT
========================================================
Look&feel installation complete

- Scripts installed from repo to ~/.local/bin/
  (ALL .sh files from scripts/ folder are now executable)
- Config files synced to ~/.config/
- Dotfiles installed with timestamped backups:
  - .bashrc (from lookandfeel repo)
  - .bash_aliases (from lookandfeel repo)
  - .Xresources, .inputrc, etc.
- Xinitrc hooks created in ~/.config/xinitrc.d/
- Wallpapers downloaded and extracted to ~/Pictures/Wallpapers
- Protected files (.xinitrc, .bash_profile) were not modified
- UPDATED: Now uses feh for wallpaper management (replaced nitrogen)

Repository: $REPO_URL (branch: $BRANCH)
Local cache: $DEST_DIR
Wallpapers: $WALLPAPER_DIR

Your old dotfiles are backed up as:
  ~/.bashrc.bak.YYYYMMDD_HHMMSS
  ~/.bash_aliases.bak.YYYYMMDD_HHMMSS

To update in the future:
  ./alpi.sh --only lookandfeel
  
To restore old dotfiles:
  mv ~/.bashrc.bak.YYYYMMDD_HHMMSS ~/.bashrc
========================================================
EOT
