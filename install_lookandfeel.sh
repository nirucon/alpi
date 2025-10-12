#!/usr/bin/env bash
# install_lookandfeel.sh
#
# Purpose:
#   - Copy *all relevant* files from this repository into the correct locations
#     under your $HOME (dotfiles, app configs, themes) and to ~/.local/bin for scripts.
#   - Always create a timestamped backup when a destination file already exists.
#   - Be robust: continue when optional sources are missing, never error on empty globs.
#   - Make every installed *.sh executable (chmod +x / mode 755).
#
# Usage:
#   1) Make executable: chmod +x ./install_lookandfeel.sh
#   2) Run from the repo root: ./install_lookandfeel.sh
#      (Optional) Run from anywhere and point to repo: ./install_lookandfeel.sh /path/to/repo
#
# Notes:
#   - This installer is conservative: it skips obvious non-config files like README, LICENSE, images, archives.
#   - Root-level *.sh are treated as user tools and installed into ~/.local/bin.
#   - If you keep configs under ./config or ./.config, they are mirrored into ~/.config preserving the tree.
#   - Common single-file configs in the repo root (picom.conf, alacritty.toml, dunstrc, rofi .rasi, etc.)
#     are mapped to sensible defaults under ~/.config/<app>/...
#   - Dotfiles in the repo root (e.g., .bashrc, .bash_aliases, .inputrc) are installed to $HOME.
#
#   Adjust the SPECIAL_MAP section if you add more single-file configs at the repo root.

set -Eeuo pipefail
shopt -s nullglob dotglob

# ---------- Pretty logging ----------
ts()   { date +"%Y-%m-%d %H:%M:%S"; }
log()  { printf "[%s] %s\n" "$(ts)" "$*"; }
ok()   { printf "\e[32m[%s] %s\e[0m\n" "$(ts)" "$*"; }
warn() { printf "\e[33m[%s] %s\e[0m\n" "$(ts)" "$*"; }
err()  { printf "\e[31m[%s] %s\e[0m\n" "$(ts)" "$*"; }

# ---------- Detect repo root ----------
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -ge 1 ]]; then
  SRC_DIR="$(cd -- "$1" && pwd)"
fi
log "Repo root: $SRC_DIR"

# ---------- Helpers ----------
# Backup then "install" (copy) a single file.
# $1 = source file, $2 = destination file, $3 = numeric mode (e.g. 644 or 755)
backup_then_install_file() {
  local src="$1" dst="$2" mode="$3"
  local dst_dir; dst_dir="$(dirname -- "$dst")"
  mkdir -p -- "$dst_dir"
  if [[ -e "$dst" ]]; then
    local bak="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a -- "$dst" "$bak"
    warn "Backup created: $bak"
  fi
  install -Dm"$mode" -- "$src" "$dst"
  ok "Installed: $(basename -- "$src")  ->  $dst  (mode $mode)"
}

# Decide a reasonable "install mode" for a source file.
# - If the source is executable OR looks like a shell script (*.sh), use 755.
# - Otherwise default to 644.
mode_for() {
  local src="$1"
  if [[ -x "$src" ]] || [[ "$src" == *.sh ]]; then
    echo 755
  else
    echo 644
  fi
}

# Install every *.sh from a directory (non-recursive) into ~/.local/bin and ensure +x.
install_sh_to_local_bin() {
  local from_dir="$1"
  local files=( "$from_dir"/*.sh )
  (( ${#files[@]} )) || { log "No *.sh in $from_dir (skipping)."; return 0; }
  mkdir -p -- "$HOME/.local/bin"
  chmod u+rwx "$HOME/.local/bin"
  for f in "${files[@]}"; do
    local name; name="$(basename -- "$f")"
    # Ensure source is executable (not required, but nice hygiene)
    chmod +x -- "$f" || true
    backup_then_install_file "$f" "$HOME/.local/bin/$name" 755
  done
}

# Mirror a directory tree *into* ~/.config/<subtree>.
# Preserves relative layout under the given base directory.
mirror_dir_into_config() {
  local base_dir="$1"      # e.g., "$SRC_DIR/config" or "$SRC_DIR/.config"
  local rel                  # path relative to base_dir
  local src dst mode

  [[ -d "$base_dir" ]] || { log "No directory: $base_dir (skipping)."; return 0; }

  # Find regular files; skip common non-config file types
  while IFS= read -r -d '' src; do
    rel="${src#$base_dir/}"  # relative part
    dst="$HOME/.config/$rel"

    # Skip obvious non-config resource types
    case "$src" in
      *.png|*.jpg|*.jpeg|*.webp|*.gif|*.svg|*.zip|*.tar|*.tar.*|*.gz|*.7z|*.pdf|*.md|*.txt|LICENSE|COPYING)
        # Allow images if they are clearly themes/resources for an app path (rare). Adjust if needed.
        continue
        ;;
    esac

    mode="$(mode_for "$src")"
    backup_then_install_file "$src" "$dst" "$mode"
  done < <(find "$base_dir" -type f -print0)
}

# ---------- STEP 1: Install scripts (*.sh) to ~/.local/bin ----------
log "==> Installing scripts to ~/.local/bin"
# From ./scripts
[[ -d "$SRC_DIR/scripts" ]] && install_sh_to_local_bin "$SRC_DIR/scripts"
# From ./bin
[[ -d "$SRC_DIR/bin" ]] && install_sh_to_local_bin "$SRC_DIR/bin"
# From repo root (top-level *.sh)
install_sh_to_local_bin "$SRC_DIR"

# ---------- STEP 2: Copy common single-file configs from repo root ----------
log "==> Installing well-known single-file configs from repo root"
declare -A SPECIAL_MAP=(
  # Picom
  ["$SRC_DIR/picom.conf"]="$HOME/.config/picom/picom.conf"

  # Alacritty
  ["$SRC_DIR/alacritty.toml"]="$HOME/.config/alacritty/alacritty.toml"

  # Dunst
  ["$SRC_DIR/dunstrc"]="$HOME/.config/dunst/dunstrc"

  # Rofi theme + config
  ["$SRC_DIR/Black-Metal.rasi"]="$HOME/.config/rofi/themes/Black-Metal.rasi"
  ["$SRC_DIR/config.rasi"]="$HOME/.config/rofi/config.rasi"
)

for src in "${!SPECIAL_MAP[@]}"; do
  dst="${SPECIAL_MAP[$src]}"
  if [[ -f "$src" ]]; then
    mode="$(mode_for "$src")"
    backup_then_install_file "$src" "$dst" "$mode"
  else
    log "Not found (optional): $src"
  fi
done

# ---------- STEP 3: Install dotfiles from repo root into $HOME ----------
log "==> Installing root-level dotfiles into \$HOME"
# Include common shells/editor dotfiles while skipping VCS & noise
for src in "$SRC_DIR"/.*; do
  # Skip pseudo entries and VCS/CI directories
  case "$(basename -- "$src")" in
    .|..|.git|.github|.gitignore|.gitattributes|.gitmodules|.DS_Store|.vscode|.idea|.editorconfig)
      continue
      ;;
  esac
  [[ -f "$src" ]] || continue

  # Skip readme/license-like files if they begin with a dot (rare)
  case "$src" in
    *.md|LICENSE|COPYING) continue ;;
  esac

  # Known-good dotfiles (extend as needed)
  case "$(basename -- "$src")" in
    .bashrc|.bash_aliases|.inputrc|.zshrc|.zprofile|.profile|.tmux.conf|.vimrc|.nanorc)
      dst="$HOME/$(basename -- "$src")"
      mode="$(mode_for "$src")"
      backup_then_install_file "$src" "$dst" "$mode"
      ;;
    *)
      # Be conservative: skip unknown hidden files to avoid polluting $HOME.
      log "Skipping unknown dotfile: $src"
      ;;
  esac
done

# ---------- STEP 4: Mirror ./config and ./.config into ~/.config ----------
log "==> Mirroring ./config and ./.config into ~/.config"
mirror_dir_into_config "$SRC_DIR/config"
mirror_dir_into_config "$SRC_DIR/.config"

# ---------- STEP 5: Post-adjustments (optional safety checks) ----------
# Ensure ~/.local/bin is in PATH
if ! command -v awk >/dev/null 2>&1; then
  warn "awk not available; cannot verify PATH."
else
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;  # already present
    *)
      warn "~/.local/bin is not in your PATH."
      warn "Add this line to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
      echo '  export PATH="$HOME/.local/bin:$PATH"'
      ;;
  esac
fi

ok "Done! All applicable files were installed with backups for any pre-existing destinations."
