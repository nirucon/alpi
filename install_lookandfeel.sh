#!/usr/bin/env bash
# install_lookandfeel.sh — themes, dotfiles & helper scripts
# Purpose:
#  - Fetch from REPO_URL (or --from local path)
#  - Install ALL scripts (*.sh) to ~/.local/bin (chmod +x)
#  - Install dotfiles (.bashrc, .bash_aliases, .inputrc) into $HOME
#  - Install configs (alacritty, rofi + themes, dunst, picom) into ~/.config/*
#  - Safe & idempotent with backups
#
# Author:  NIRUCON
# License: MIT (as you like)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────────────────────── UI ─────────────────────────
CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${GRN}[LOOK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_lookandfeel.sh failed — see messages above."' ERR

# ───────────────────── Defaults/args ──────────────────
REPO_URL="${REPO_URL:-https://github.com/nirucon/suckless_lookandfeel}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/suckless_lookandfeel"
LOCAL_BIN="$HOME/.local/bin"
HOME_DOT_TARGET="$HOME"
XCFG="$HOME/.config"

SRC_OVERRIDE=""
DRY_RUN=0
NO_CLONE=0

usage() {
  cat <<'EOF'
install_lookandfeel.sh — options
  --from PATH     Use a local source path instead of cloning the repo
  --no-clone      Don't clone/pull; assume source already exists (cache or --from)
  --dry-run       Print actions only, no changes
  -h, --help      Show this help

What it does:
  • Installs ALL *.sh from source → ~/.local/bin (chmod 755)
  • Installs dotfiles → ~/: .bashrc, .bash_aliases, .inputrc (with backup)
  • Installs configs:
      - picom.conf → ~/.config/picom/picom.conf
      - alacritty.toml → ~/.config/alacritty/alacritty.toml
      - dunstrc → ~/.config/dunst/dunstrc
      - rofi:
          config.rasi → ~/.config/rofi/config.rasi
          any *.rasi theme (e.g. Black-Metal.rasi) → ~/.config/rofi/themes/
Notes:
  • Idempotent, backs up existing files to *.bak.TIMESTAMP before overwrite.
  • Ensures ~/.local/bin exists and is on PATH (via ~/.bash_profile).
EOF
}

# Parse args
while (($#)); do
  case "$1" in
    --from)      SRC_OVERRIDE="${2:-}"; shift 2 ;;
    --no-clone)  NO_CLONE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) warn "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

# ───────────────────── Helpers ────────────────────────
ts() { date +%Y%m%d-%H%M%S; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
  else
    if [[ $# -eq 1 ]]; then bash -lc "$1"; else "$@"; fi
  fi
}

ensure_dir() { run mkdir -p -- "$1"; }
backup_if_exists() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local b="${f}.bak.$(ts)"
  run cp -a -- "$f" "$b"
  warn "Backup: $f → $b"
}
copy_file() {
  # copy_file SRC DST
  local src="$1" dst="$2"
  ensure_dir "$(dirname "$dst")"
  if [[ -e "$src" ]]; then
    backup_if_exists "$dst"
    run install -m 0644 -D -- "$src" "$dst"
    say "Installed: $(basename "$dst") → $dst"
  fi
}
append_once(){
  local line="$1" file="$2"
  if [[ ! -f "$file" ]] || ! grep -qxF "$line" "$file" 2>/dev/null; then
    run bash -lc "printf '%s\n' \"$line\" >> \"$file\""
  fi
}

# ───────────────── Ensure basics ──────────────────────
ensure_dir "$LOCAL_BIN"
ensure_dir "$XCFG"
if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  append_once 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bash_profile"
  say "Ensured PATH for ~/.local/bin in ~/.bash_profile"
fi

# ─────────────── Resolve source directory ─────────────
SRC_DIR=""
if [[ -n "$SRC_OVERRIDE" ]]; then
  [[ -d "$SRC_OVERRIDE" ]] || { fail "--from path not found: $SRC_OVERRIDE"; exit 1; }
  SRC_DIR="$(cd "$SRC_OVERRIDE" && pwd -P)"
  step "Using local source: $SRC_DIR"
else
  SRC_DIR="$CACHE_DIR/repo"
  if [[ $NO_CLONE -eq 1 ]]; then
    [[ -d "$SRC_DIR" ]] || { fail "Cache not found and --no-clone set: $SRC_DIR"; exit 1; }
    step "Using cached source: $SRC_DIR"
  else
    ensure_dir "$CACHE_DIR"
    if [[ -d "$SRC_DIR/.git" ]]; then
      step "Updating cached repo…"
      run git -C "$SRC_DIR" pull --ff-only
    else
      step "Cloning $REPO_URL → $SRC_DIR"
      run git clone --depth 1 "$REPO_URL" "$SRC_DIR"
    fi
  fi
fi

# ───────────────── Install scripts ────────────────────
step "Installing scripts (*.sh) to $LOCAL_BIN"
installed_any=0
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  dest="$LOCAL_BIN/$base"
  backup_if_exists "$dest"
  run install -m 0755 -D -- "$f" "$dest"
  ((installed_any++))
done < <(find "$SRC_DIR" -maxdepth 2 -type f -name "*.sh" -print0)

if (( installed_any == 0 )); then
  warn "No scripts (*.sh) found — skipping."
else
  say "Scripts installed: $installed_any file(s)"
fi

# ───────────────── Dotfiles → $HOME ───────────────────
step "Installing dotfiles to $HOME"
declare -A DOTMAP=(
  [".bashrc"]="$HOME_DOT_TARGET/.bashrc"
  [".bash_aliases"]="$HOME_DOT_TARGET/.bash_aliases"
  [".inputrc"]="$HOME_DOT_TARGET/.inputrc"
)
for src_rel in "${!DOTMAP[@]}"; do
  # accept either leading-dot in repo or without
  if [[ -f "$SRC_DIR/$src_rel" ]]; then
    copy_file "$SRC_DIR/$src_rel" "${DOTMAP[$src_rel]}"
  elif [[ -f "$SRC_DIR/${src_rel#.}" ]]; then
    copy_file "$SRC_DIR/${src_rel#.}" "${DOTMAP[$src_rel]}"
  fi
done

# ───────────────── Configs → ~/.config ────────────────
step "Installing configs to ~/.config"

# Picom
if [[ -f "$SRC_DIR/picom.conf" ]]; then
  copy_file "$SRC_DIR/picom.conf" "$XCFG/picom/picom.conf"
fi

# Alacritty
if [[ -f "$SRC_DIR/alacritty.toml" ]]; then
  copy_file "$SRC_DIR/alacritty.toml" "$XCFG/alacritty/alacritty.toml"
fi

# Dunst
if [[ -f "$SRC_DIR/dunstrc" ]]; then
  copy_file "$SRC_DIR/dunstrc" "$XCFG/dunst/dunstrc"
fi

# Rofi: config.rasi + themes (*.rasi)
if [[ -f "$SRC_DIR/config.rasi" ]]; then
  copy_file "$SRC_DIR/config.rasi" "$XCFG/rofi/config.rasi"
fi
ensure_dir "$XCFG/rofi/themes"
# Copy any *.rasi as theme (e.g. Black-Metal.rasi)
while IFS= read -r -d '' rasi; do
  base="$(basename "$rasi")"
  copy_file "$rasi" "$XCFG/rofi/themes/$base"
done < <(find "$SRC_DIR" -maxdepth 1 -type f -name "*.rasi" -print0)

# Generic: if repo has a top-level "configs" dir, mirror it inside ~/.config
if [[ -d "$SRC_DIR/configs" ]]; then
  step "Mirroring 'configs/' subtree into ~/.config"
  while IFS= read -r -d '' src; do
    rel="${src#"$SRC_DIR/configs/"}"
    dst="$XCFG/$rel"
    copy_file "$src" "$dst"
  done < <(find "$SRC_DIR/configs" -type f -print0)
fi

# ───────────────── Final notes ────────────────────────
cat <<EOF

========================================================
Look & Feel setup complete

• Scripts        → $LOCAL_BIN (755)
• Dotfiles       → $HOME_DOT_TARGET (.bashrc, .bash_aliases, .inputrc)
• Picom          → $XCFG/picom/picom.conf
• Alacritty      → $XCFG/alacritty/alacritty.toml
• Dunst          → $XCFG/dunst/dunstrc
• Rofi config    → $XCFG/rofi/config.rasi
• Rofi themes    → $XCFG/rofi/themes/*.rasi
• Optional 'configs/' subtree mirrored into ~/.config

Re-run safely anytime; existing files get timestamped backups.
Use --dry-run to preview actions.
========================================================
EOF
