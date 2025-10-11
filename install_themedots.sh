#!/usr/bin/env bash
# install_themedots.sh — install theming & dotfiles
# Source: https://github.com/nirucon/suckless_themedots
# Installs by default:
#   ~/.bashrc
#   ~/.bash_aliases
#   ~/.inputrc
#   ~/.config/dunst/dunstrc
#   ~/.config/alacritty/alacritty.(toml|yml)
#   ~/.config/rofi/config(.rasi)
#
# Usage:
#   ./install_themedots.sh [--repo URL] [--branch BRANCH] [--local PATH] [--include LIST] [--dry-run] [--no-backup]
# Examples:
#   ./install_themedots.sh
#   ./install_themedots.sh --include "bashrc dunst"
#   ./install_themedots.sh --local ~/code/suckless_themedots
#
# Safe & idempotent:
#  • Creates folders if missing
#  • Backs up existing files with timestamp suffix (unless --no-backup)
#  • Skips copy if content is identical
#  • Can be run standalone, independent of other ALPI steps

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Logging ----------
GRN="\033[1;32m"; BLU="\033[1;34m"; YLW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GRN}[DOTS]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

trap 'fail "install_themedots.sh failed. See previous step for details."' ERR

# ---------- Refuse running as root (would write to /root) ----------
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run as root. This script writes to your home directory."
  exit 1
fi

# ---------- Defaults & args ----------
REPO_URL="https://github.com/nirucon/suckless_themedots"
REPO_BRANCH=""
LOCAL_PATH=""
INCLUDE_ITEMS=("bashrc" "bash_aliases" "inputrc" "dunst" "alacritty" "rofi")
DRY_RUN=0
NO_BACKUP=0

usage() {
  cat <<'EOF'
install_themedots.sh — options
  --repo URL         Git repository to pull from (default: nirucon/suckless_themedots)
  --branch BRANCH    Branch/tag to checkout (default: repo default)
  --local PATH       Use an already cloned local path instead of git clone
  --include "items"  Space-separated list among: bashrc bash_aliases inputrc dunst alacritty rofi
                     (extra: rofi_theme_system to install Black-Metal.rasi to /usr/share/rofi/themes)
  --dry-run          Print what would be done without writing files
  --no-backup        Overwrite without creating .bak timestamp (not recommended)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO_URL="$2"; shift 2;;
    --branch)  REPO_BRANCH="$2"; shift 2;;
    --local)   LOCAL_PATH="$2"; shift 2;;
    --include) read -r -a INCLUDE_ITEMS <<<"$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --no-backup) NO_BACKUP=1; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ---------- Acquire repo (clone or use local) ----------
WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/themedots"
REPO_DIR="$WORKDIR/repo"

get_repo() {
  if [[ -n "$LOCAL_PATH" ]]; then
    if [[ -d "$LOCAL_PATH" ]]; then
      REPO_DIR="$LOCAL_PATH"
      say "Using local path: $REPO_DIR"
      return
    else
      fail "--local path does not exist: $LOCAL_PATH"
      exit 1
    fi
  fi

  mkdir -p "$WORKDIR"
  if [[ -d "$REPO_DIR/.git" ]]; then
    say "Updating repository in $REPO_DIR …"
    git -C "$REPO_DIR" fetch --all --prune || warn "git fetch failed (continuing with existing tree)"
    if [[ -n "$REPO_BRANCH" ]]; then
      git -C "$REPO_DIR" checkout "$REPO_BRANCH" || warn "checkout '$REPO_BRANCH' failed; using current branch"
      git -C "$REPO_DIR" pull --ff-only || warn "git pull failed; using current working tree"
    else
      git -C "$REPO_DIR" pull --ff-only || warn "git pull failed; using current working tree"
    fi
  else
    say "Cloning $REPO_URL into $REPO_DIR …"
    git clone "$REPO_URL" "$REPO_DIR"
    if [[ -n "$REPO_BRANCH" ]]; then
      git -C "$REPO_DIR" checkout "$REPO_BRANCH" || warn "checkout '$REPO_BRANCH' failed; using default branch"
    fi
  fi
}

# ---------- Helpers ----------
ts() { date +"%Y%m%d-%H%M%S"; }

# Return first existing file from a list of relative candidates
first_existing() {
  local base="$1"; shift
  local cand
  for cand in "$@"; do
    if [[ -f "$base/$cand" ]]; then
      printf "%s" "$base/$cand"
      return 0
    fi
  done
  return 1
}

ensure_dir() { mkdir -p "$1"; }

same_file() {
  local a="$1" b="$2"
  [[ -f "$a" && -f "$b" ]] && cmp -s -- "$a" "$b"
}

install_file() {
  local src="$1" dest="$2"
  local destdir; destdir="$(dirname -- "$dest")"
  ensure_dir "$destdir"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install: $src -> $dest"
    return 0
  fi
  if [[ -f "$dest" ]]; then
    if same_file "$src" "$dest"; then
      say "Unchanged: $dest"
      return 0
    fi
    if [[ $NO_BACKUP -eq 0 ]]; then
      local bak="${dest}.bak.$(ts)"
      cp -f -- "$dest" "$bak"
      warn "Backed up existing to: $bak"
    fi
  fi
  install -Dm644 -- "$src" "$dest"
  say "Installed: $dest"
}

# ---------- Installers for each item ----------
install_bashrc() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".bashrc" \
      "bash/.bashrc" \
      "home/.bashrc" \
      "dots/.bashrc" \
      "bashrc")" || { warn "No .bashrc found — skipping."; return; }
  install_file "$src" "$HOME/.bashrc"
}

install_bash_aliases() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".bash_aliases" \
      "bash/.bash_aliases" \
      "home/.bash_aliases" \
      "dots/.bash_aliases" \
      "bash_aliases")" || { warn "No .bash_aliases found — skipping."; return; }
  install_file "$src" "$HOME/.bash_aliases"
}

install_inputrc() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".inputrc" \
      "inputrc" \
      "home/.inputrc" \
      "dots/.inputrc")" || { warn "No .inputrc found — skipping."; return; }
  install_file "$src" "$HOME/.inputrc"
}

install_dunst() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".config/dunst/dunstrc" \
      "dunst/dunstrc" \
      "dotconfig/dunst/dunstrc" \
      "config/dunst/dunstrc" \
      "dunstrc")" || { warn "No dunst config found — skipping."; return; }
  install_file "$src" "$HOME/.config/dunst/dunstrc"
}

install_alacritty() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".config/alacritty/alacritty.toml" \
      ".config/alacritty/alacritty.yml" \
      "alacritty/alacritty.toml" \
      "alacritty/alacritty.yml" \
      "dotconfig/alacritty/alacritty.toml" \
      "dotconfig/alacritty/alacritty.yml" \
      "config/alacritty/alacritty.toml" \
      "config/alacritty/alacritty.yml" \
      "alacritty.toml" \
      "alacritty.yml")" || { warn "No alacritty config found — skipping."; return; }
  local dest="$HOME/.config/alacritty/$(basename "$src")"
  install_file "$src" "$dest"
}

install_rofi() {
  local src
  src="$(first_existing "$REPO_DIR" \
      ".config/rofi/config.rasi" \
      ".config/rofi/config" \
      "rofi/config.rasi" \
      "rofi/config" \
      "dotconfig/rofi/config.rasi" \
      "dotconfig/rofi/config" \
      "config/rofi/config.rasi" \
      "config/rofi/config" \
      "config.rasi" \
      "config")" || { warn "No rofi config found — skipping."; return; }
  install_file "$src" "$HOME/.config/rofi/$(basename "$src")"
}

# --- New: system-wide Rofi theme installer ---
install_rofi_theme_system() {
  # Installs Black-Metal.rasi from the repo into /usr/share/rofi/themes/Black-Metal.rasi (requires sudo if not writable)
  local src
  src="$(first_existing "$REPO_DIR" \
      "rofi/themes/Black-Metal.rasi" \
      "themes/Black-Metal.rasi" \
      "Black-Metal.rasi")" || { warn "No Black-Metal.rasi found — skipping."; return; }

  local dest="/usr/share/rofi/themes/Black-Metal.rasi"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install (sudo): $src -> $dest"
    return 0
  fi

  # Ensure destination directory exists (may need sudo)
  if [[ -d "/usr/share/rofi/themes" && -w "/usr/share/rofi/themes" ]]; then
    install -Dm644 -- "$src" "$dest"
  else
    if command -v sudo >/dev/null 2>&1; then
      say "Using sudo to install theme system-wide …"
      sudo mkdir -p "/usr/share/rofi/themes"
      sudo install -Dm644 -- "$src" "$dest"
    else
      fail "Cannot write to /usr/share/rofi/themes and 'sudo' is not available. Install manually."
      return 1
    fi
  fi
  say "Installed system rofi theme: $dest"
}

# ---------- Main ----------
step "Preparing repository"
get_repo

say "Installing items: ${INCLUDE_ITEMS[*]}"
for item in "${INCLUDE_ITEMS[@]}"; do
  case "$item" in
    bashrc)             step "bashrc";             install_bashrc ;;
    bash_aliases)       step "bash_aliases";       install_bash_aliases ;;
    inputrc)            step "inputrc";            install_inputrc ;;
    dunst)              step "dunst";              install_dunst  ;;
    alacritty)          step "alacritty";          install_alacritty ;;
    rofi)               step "rofi";               install_rofi   ;;
    rofi_theme_system)  step "rofi_theme_system";  install_rofi_theme_system ;;
    *) warn "Unknown include item: $item";;
  esac
done

echo
cat <<'EOT'
========================================================
Theming/dotfiles step complete.

Notes:
• Existing files were backed up with a .bak.TIMESTAMP suffix (unless --no-backup).
• Rofi, Alacritty, Dunst must be installed for configs to take effect.
• System theme install: use --include "rofi_theme_system" (will sudo if needed).
• Re-run this script anytime; it is safe and idempotent.
========================================================
EOT
