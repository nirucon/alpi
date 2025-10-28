#!/bin/bash
# install_lookandfeel.sh
#
# Pulls look&feel assets from a Git repo (default: nirucon/suckless_lookandfeel)
# and installs them into sensible locations under $HOME.
#
# NEW in this version:
# - CLEAR directory structure: repo mirrors where files should go
# - dotfiles/ -> $HOME (dotfiles like .bashrc, .bash_aliases)
# - config/ -> ~/.config/ (application configs)
# - local/bin/ -> ~/.local/bin/ (scripts, made executable)
# - local/share/ -> ~/.local/share/ (themes, data files)
# - .xinitrc and .bash_profile are PROTECTED (never overwrite)
# - Timestamped backups for all other files
# - Creates xinitrc hooks instead of modifying .xinitrc directly
# - Downloads wallpapers.zip and extracts to ~/Pictures/Wallpapers

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

REPOSITORY STRUCTURE:
  Your lookandfeel repo should follow this structure (it mirrors where files go):
  
  suckless_lookandfeel/
  ├── dotfiles/              -> $HOME/
  │   ├── .bashrc            -> ~/.bashrc
  │   ├── .bash_aliases      -> ~/.bash_aliases
  │   ├── .Xresources        -> ~/.Xresources
  │   └── .inputrc           -> ~/.inputrc
  ├── config/                -> ~/.config/
  │   ├── picom/
  │   │   └── picom.conf     -> ~/.config/picom/picom.conf
  │   ├── alacritty/
  │   │   └── alacritty.toml -> ~/.config/alacritty/alacritty.toml
  │   ├── dunst/
  │   │   └── dunstrc        -> ~/.config/dunst/dunstrc
  │   └── rofi/
  │       └── config.rasi    -> ~/.config/rofi/config.rasi
  ├── local/                 -> ~/.local/
  │   ├── bin/               -> ~/.local/bin/ (made executable)
  │   │   ├── wallrotate.sh  -> ~/.local/bin/wallrotate.sh (755)
  │   │   └── dwm-status.sh  -> ~/.local/bin/dwm-status.sh (755)
  │   └── share/             -> ~/.local/share/
  │       └── rofi/
  │           └── themes/
  │               └── Black-Metal.rasi
  └── README.md
  
PROTECTED FILES (never overwritten):
  • .xinitrc         (managed by install_suckless.sh)
  • .bash_profile    (managed by install_apps.sh)
  
ALL OTHER FILES:
  • Installed with timestamped backup (.bak.YYYYMMDD_HHMMSS)
  • Scripts in local/bin/ are made executable (755)
  • Everything else gets 644 permissions

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

# ───────── Protected files (managed by other scripts) ─────────
PROTECTED_FILES=(.xinitrc .bash_profile)

is_protected() {
  local filename="$1"
  for protected in "${PROTECTED_FILES[@]}"; do
    [[ "$filename" == "$protected" ]] && return 0
  done
  return 1
}

# ───────── Core installation functions ─────────

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
    local backup_ts
    backup_ts="$(date +%Y%m%d_%H%M%S)"
    cp -a -- "$dst" "${dst}.bak.${backup_ts}"
    log "Backup: $dst -> ${dst}.bak.${backup_ts}"
  fi
  
  install -m "$mode" "$src" "$dst"
  ok "Installed: $src -> $dst (mode $mode)"
}

# Mirror directory structure from source to destination
# Usage: mirror_tree SOURCE_DIR DEST_DIR MODE
# Example: mirror_tree "$DEST_DIR/config" "$HOME/.config" 644
mirror_tree() {
  local src_base="$1"
  local dst_base="$2"
  local file_mode="$3"
  
  [[ -d "$src_base" ]] || {
    log "No directory: $src_base (skipping)."
    return 0
  }

  log "Mirroring $src_base -> $dst_base"
  
  while IFS= read -r -d '' src_file; do
    # Get relative path from source base
    local rel_path="${src_file#$src_base/}"
    local dst_file="$dst_base/$rel_path"
    
    # Check if this is a protected file (only applies to dotfiles)
    local basename
    basename="$(basename -- "$src_file")"
    if [[ "$dst_base" == "$HOME" ]] && is_protected "$basename"; then
      if [[ -f "$dst_file" ]]; then
        warn "Protected file exists: $basename (managed by other install scripts)"
        warn "Skipping to avoid conflicts. To merge manually:"
        warn "  diff $dst_file $src_file"
        continue
      fi
    fi
    
    backup_then_install_file "$src_file" "$dst_file" "$file_mode"
  done < <(find "$src_base" -type f -print0)
}

# Install scripts from local/bin/ with executable permissions
install_local_bin() {
  local src_dir="$DEST_DIR/local/bin"
  
  [[ -d "$src_dir" ]] || {
    log "No directory: $src_dir (skipping scripts)"
    return 0
  }

  log "Installing scripts from local/bin/ to ~/.local/bin/"
  mirror_tree "$src_dir" "$HOME/.local/bin" 755
}

# Install data files from local/share/
install_local_share() {
  local src_dir="$DEST_DIR/local/share"
  
  [[ -d "$src_dir" ]] || {
    log "No directory: $src_dir (skipping local/share)"
    return 0
  }

  log "Installing data files from local/share/ to ~/.local/share/"
  mirror_tree "$src_dir" "$HOME/.local/share" 644
}

# Install config files from config/
install_config() {
  local src_dir="$DEST_DIR/config"
  
  [[ -d "$src_dir" ]] || {
    log "No directory: $src_dir (skipping config)"
    return 0
  }

  log "Installing config files from config/ to ~/.config/"
  mirror_tree "$src_dir" "$HOME/.config" 644
}

# Install dotfiles from dotfiles/
install_dotfiles() {
  local src_dir="$DEST_DIR/dotfiles"
  
  [[ -d "$src_dir" ]] || {
    log "No directory: $src_dir (skipping dotfiles)"
    return 0
  }

  log "Installing dotfiles from dotfiles/ to ~/"
  mirror_tree "$src_dir" "$HOME" 644
}

# ───────── Wallpaper download and extraction ─────────
download_and_extract_wallpapers() {
  set +e  # Disable exit on error for this function
  
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

  mkdir -p -- "$dest"
  ok "Created wallpaper directory: $dest"

  # Check for required tools
  if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    warn "Neither wget nor curl found. Skipping wallpaper download."
    set -e
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    warn "unzip not found. Skipping wallpaper extraction."
    set -e
    return 1
  fi

  # Determine download tool
  local download_tool=""
  if command -v wget >/dev/null 2>&1; then
    download_tool="wget"
  else
    download_tool="curl"
  fi

  log "Using $download_tool for downloads"
  
  local temp_zip="$CACHE_BASE/wallpapers.zip"
  
  # Download
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
    if curl -s -f -o "$temp_zip" "$url" 2>/dev/null; then
      ok "Downloaded wallpapers.zip successfully"
    else
      err "Failed to download wallpapers.zip"
      rm -f "$temp_zip" 2>/dev/null || true
      set -e
      return 1
    fi
  fi

  # Verify file
  if [[ ! -s "$temp_zip" ]]; then
    err "Downloaded file is empty"
    rm -f "$temp_zip" 2>/dev/null || true
    set -e
    return 1
  fi

  # Extract
  log "Extracting wallpapers to $dest..."
  if unzip -q -o "$temp_zip" -d "$dest" 2>/dev/null; then
    ok "Wallpapers extracted successfully"
    
    local count
    count=$(find "$dest" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | wc -l)
    ok "Found $count wallpaper file(s) in $dest"
  else
    err "Failed to extract wallpapers.zip"
    rm -f "$temp_zip" 2>/dev/null || true
    set -e
    return 1
  fi

  rm -f "$temp_zip" 2>/dev/null || true
  ok "Cleaned up temporary files"

  set -e
  return 0
}

# ───────── Legacy support (backwards compatibility) ─────────

# Check for old repo structure and provide migration guidance
check_legacy_structure() {
  local needs_migration=0
  
  # Check for files directly in repo root (old style)
  if [[ -f "$DEST_DIR/.bashrc" ]] || [[ -f "$DEST_DIR/picom.conf" ]]; then
    needs_migration=1
  fi
  
  # Check for old scripts/ directory (should be local/bin/ now)
  if [[ -d "$DEST_DIR/scripts" ]] && [[ ! -d "$DEST_DIR/local/bin" ]]; then
    needs_migration=1
  fi
  
  if ((needs_migration == 1)); then
    warn "=========================================="
    warn "OLD REPOSITORY STRUCTURE DETECTED"
    warn "=========================================="
    warn "Your repo uses the old structure with files in the root."
    warn ""
    warn "For best results, restructure your repo:"
    warn "  1. Create these directories: dotfiles/, config/, local/bin/, local/share/"
    warn "  2. Move .bashrc, .bash_aliases etc. -> dotfiles/"
    warn "  3. Move picom.conf, alacritty.toml etc. -> config/picom/, config/alacritty/"
    warn "  4. Move scripts/*.sh -> local/bin/"
    warn "  5. Move themes -> local/share/rofi/themes/"
    warn ""
    warn "This script will still work with the old structure (legacy mode)"
    warn "but the new structure is clearer and more maintainable."
    warn "=========================================="
  fi
}

# Install using legacy structure (for backwards compatibility)
install_legacy() {
  log "Using legacy installation mode (old repo structure)"
  
  # Old style: dotfiles directly in repo root
  log "Processing legacy dotfiles from repo root..."
  for df in "$DEST_DIR"/.*; do
    local base
    base="$(basename -- "$df")"
    [[ -f "$df" ]] || continue
    [[ "$base" == "." || "$base" == ".." || "$base" =~ ^\.git ]] && continue

    if is_protected "$base"; then
      if [[ -f "$HOME/$base" ]]; then
        warn "Protected file exists: $base (skipping)"
        continue
      fi
    fi

    case "$base" in
    .bashrc | .bash_aliases | .zshrc | .inputrc | .Xresources | .profile)
      backup_then_install_file "$df" "$HOME/$base" 644
      ;;
    esac
  done
  
  # Old style: scripts/ directory
  if [[ -d "$DEST_DIR/scripts" ]]; then
    log "Installing scripts from legacy scripts/ directory"
    mkdir -p "$HOME/.local/bin"
    for script in "$DEST_DIR/scripts"/*.sh; do
      [[ -f "$script" ]] || continue
      backup_then_install_file "$script" "$HOME/.local/bin/$(basename -- "$script")" 755
    done
  fi
  
  # Old style: specific config files in root
  declare -A LEGACY_MAP=(
    ["$DEST_DIR/picom.conf"]="$HOME/.config/picom/picom.conf"
    ["$DEST_DIR/alacritty.toml"]="$HOME/.config/alacritty/alacritty.toml"
    ["$DEST_DIR/dunstrc"]="$HOME/.config/dunst/dunstrc"
    ["$DEST_DIR/Black-Metal.rasi"]="$HOME/.local/share/rofi/themes/Black-Metal.rasi"
    ["$DEST_DIR/config.rasi"]="$HOME/.config/rofi/config.rasi"
  )
  
  for src in "${!LEGACY_MAP[@]}"; do
    dst="${LEGACY_MAP[$src]}"
    [[ -f "$src" ]] && backup_then_install_file "$src" "$dst" 644
  done
  
  # Old style: config/ or .config/ directories
  [[ -d "$DEST_DIR/config" ]] && mirror_tree "$DEST_DIR/config" "$HOME/.config" 644
  [[ -d "$DEST_DIR/.config" ]] && mirror_tree "$DEST_DIR/.config" "$HOME/.config" 644
}

# ───────── Main installation logic ─────────

log "==> Installing from look&feel repository"

# Check if repo uses new structure
HAS_NEW_STRUCTURE=0
if [[ -d "$DEST_DIR/dotfiles" ]] || [[ -d "$DEST_DIR/local" ]] || [[ -d "$DEST_DIR/config" ]]; then
  HAS_NEW_STRUCTURE=1
fi

if ((HAS_NEW_STRUCTURE == 1)); then
  log "Using new repository structure (recommended)"
  
  # Install in order
  install_dotfiles      # dotfiles/ -> ~/
  install_config        # config/ -> ~/.config/
  install_local_bin     # local/bin/ -> ~/.local/bin/ (executable)
  install_local_share   # local/share/ -> ~/.local/share/
  
else
  check_legacy_structure
  install_legacy
fi

# Wallpapers (works for both structures)
download_and_extract_wallpapers "$WALLPAPER_URL" "$WALLPAPER_DIR"

# ───────── Create xinitrc hooks ─────────
log "Creating xinitrc hooks in ~/.config/xinitrc.d/"

# Hook for compositor
cat >"$XINITRC_HOOKS/10-compositor.sh" <<'EOF'
#!/bin/sh
# Compositor hook (picom)
# Created by install_lookandfeel.sh

command -v picom >/dev/null 2>&1 && picom &
EOF
chmod +x "$XINITRC_HOOKS/10-compositor.sh"

# Hook for wallpaper (uses feh)
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

# ───────── PATH notice ─────────
case ":$PATH:" in
*":$HOME/.local/bin:"*) : ;;
*)
  warn "~/.local/bin is not in your PATH."
  warn "Add this line to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
  warn "Or log out and back in (install_apps.sh should have added it to ~/.bash_profile)"
  ;;
esac

# ───────── Summary ─────────
cat <<EOT
========================================================
Look&feel installation complete

Repository structure: $(((HAS_NEW_STRUCTURE == 1)) && echo "NEW (recommended)" || echo "LEGACY (consider migrating)")

- Dotfiles installed to ~/ with timestamped backups
- Config files synced to ~/.config/
- Scripts installed to ~/.local/bin/ (made executable)
- Data files installed to ~/.local/share/
- Xinitrc hooks created in ~/.config/xinitrc.d/
- Wallpapers downloaded to ~/Pictures/Wallpapers
- Protected files (.xinitrc, .bash_profile) were not modified

Repository: $REPO_URL (branch: $BRANCH)
Local cache: $DEST_DIR
Wallpapers: $WALLPAPER_DIR

Your old files are backed up as:
  ~/.bashrc.bak.YYYYMMDD_HHMMSS
  ~/.bash_aliases.bak.YYYYMMDD_HHMMSS

To update in the future:
  ./alpi.sh --only lookandfeel
  
To restore old files:
  mv ~/.bashrc.bak.YYYYMMDD_HHMMSS ~/.bashrc
========================================================
EOT
