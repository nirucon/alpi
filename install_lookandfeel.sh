#!/usr/bin/env bash
# install_lookandfeel.sh
#
# Pulls look&feel assets from a Git repo (default: nirucon/suckless_lookandfeel)
# and installs them into sensible locations under $HOME.
#
# Design:
# - Clone/update to ~/.cache/alpi/lookandfeel/<branch>
# - Copy from that repo (NOT from the alpi repo root)
# - Timestamped backups for existing files
# - Skip missing optional files gracefully
# - Make installed *.sh executable (755) in ~/.local/bin if present inside the L&F repo
#
# Flags:
#   --repo URL         (default: https://github.com/nirucon/suckless_lookandfeel)
#   --branch NAME      (default: main)
#   --dry-run          (no changes, show actions)
#   --help             Show help
#
# Examples:
#   ./install_lookandfeel.sh
#   ./install_lookandfeel.sh --repo https://github.com/nirucon/suckless_lookandfeel --branch main

set -Eeuo pipefail
shopt -s nullglob dotglob

# ---------- defaults ----------
REPO_URL="https://github.com/nirucon/suckless_lookandfeel"
BRANCH="main"
DRY_RUN=0

# ---------- logging ----------
ts()   { date +"%Y-%m-%d %H:%M:%S"; }
log()  { printf "[%s] %s\n" "$(ts)" "$*"; }
ok()   { printf "\e[32m[%s] %s\e[0m\n" "$(ts)" "$*"; }
warn() { printf "\e[33m[%s] %s\e[0m\n" "$(ts)" "$*"; }
err()  { printf "\e[31m[%s] %s\e[0m\n" "$(ts)" "$*"; }
die()  { err "$@"; exit 1; }

usage() {
  sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
}

while (( $# )); do
  case "$1" in
    --repo)   shift; [[ $# -gt 0 ]] || die "--repo requires a URL"; REPO_URL="$1"; shift ;;
    --branch) shift; [[ $# -gt 0 ]] || die "--branch requires a name"; BRANCH="$1"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done

# ---------- where to cache ----------
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/alpi/lookandfeel"
DEST_DIR="$CACHE_BASE/$BRANCH"
mkdir -p -- "$CACHE_BASE"

# ---------- clone/update ----------
if [[ -d "$DEST_DIR/.git" ]]; then
  log "Updating look&feel repo at: $DEST_DIR"
  if (( DRY_RUN == 0 )); then
    git -C "$DEST_DIR" fetch --all --prune
    git -C "$DEST_DIR" checkout "$BRANCH"
    git -C "$DEST_DIR" reset --hard "origin/$BRANCH"
  else
    log "(dry-run) git -C \"$DEST_DIR\" fetch/checkout/reset"
  fi
else
  log "Cloning look&feel repo -> $DEST_DIR"
  if (( DRY_RUN == 0 )); then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST_DIR"
  else
    log "(dry-run) git clone --depth 1 --branch \"$BRANCH\" \"$REPO_URL\" \"$DEST_DIR\""
  fi
fi

log "Using source tree: $DEST_DIR (branch=$BRANCH)"

# ---------- helpers ----------
backup_then_install_file() {
  local src="$1" dst="$2" mode="$3"
  local dst_dir; dst_dir="$(dirname -- "$dst")"
  [[ -f "$src" ]] || { warn "Missing source (skipping): $src"; return 0; }

  if (( DRY_RUN == 1 )); then
    log "(dry-run) install $src -> $dst (mode $mode)"
    return 0
  fi

  mkdir -p -- "$dst_dir"
  if [[ -e "$dst" ]]; then
    local ts; ts="$(date +%Y%m%d_%H%M%S)"
    cp -a -- "$dst" "${dst}.bak.${ts}"
    log "Backup: $dst -> ${dst}.bak.${ts}"
  fi
  install -m "$mode" "$src" "$dst"
  ok "Installed: $src -> $dst (mode $mode)"
}

install_sh_to_local_bin() {
  local from_dir="$1"
  local files=( "$from_dir"/*.sh )
  (( ${#files[@]} )) || { log "No *.sh in $from_dir (skipping)."; return 0; }
  mkdir -p -- "$HOME/.local/bin"
  chmod u+rwx "$HOME/.local/bin"
  for f in "${files[@]}"; do
    backup_then_install_file "$f" "$HOME/.local/bin/$(basename -- "$f")" 755
  done
}

mirror_dir_into_config() {
  local base_dir="$1"
  [[ -d "$base_dir" ]] || { log "No directory: $base_dir (skipping)."; return 0; }

  while IFS= read -r -d '' src; do
    local rel="${src#$base_dir/}"
    local dst="$HOME/.config/$rel"
    backup_then_install_file "$src" "$dst" 644
  done < <(find "$base_dir" -type f -print0)
}

# ---------- install from the L&F repo ----------
log "==> Installing from look&feel repository"

# 1) Scripts inside the look&feel repo (optional)
[[ -d "$DEST_DIR/scripts" ]] && install_sh_to_local_bin "$DEST_DIR/scripts"
[[ -d "$DEST_DIR/bin"     ]] && install_sh_to_local_bin "$DEST_DIR/bin"

# 2) Well-known single-file configs at repo root (optional; adjust if your repo differs)
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

# 4) Copy dotfiles from L&F repo root into $HOME (optional)
for df in "$DEST_DIR"/.*; do
  base="$(basename -- "$df")"
  [[ -f "$df" ]] || continue
  [[ "$base" == "." || "$base" == ".." || "$base" =~ ^\.git ]] && continue
  case "$base" in
    .bashrc|.zshrc|.bash_aliases|.inputrc|.Xresources|.xinitrc|.profile)
      backup_then_install_file "$df" "$HOME/$base" 644
      ;;
    *) : ;;
  esac
done

# 5) PATH notice
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *)
    warn "~/.local/bin is not in your PATH."
    warn "Add this line to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac

ok "Done! Look&feel files have been installed from $REPO_URL (branch: $BRANCH)."
