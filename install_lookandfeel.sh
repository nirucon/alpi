#!/usr/bin/env bash
# install_lookandfeel.sh — apply theme, dotfiles & helper scripts
# Purpose: Install a curated set of shell/GUI config files and copy all helper scripts
#          from a cloned theme repo into ~/.local/bin.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------ Pretty logging ------------------------
GRN="\033[1;32m"; BLU="\033[1;34m"; YLW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
say()  { printf "${GRN}[LOOK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

trap 'fail "install_lookandfeel.sh failed. See previous step for details."' ERR

# ------------------------ Safety check -------------------------
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  fail "Do not run as root. This script writes to your HOME."; exit 1
fi

# ------------------------ Defaults & args ----------------------
REPO_URL="https://github.com/nirucon/suckless_lookandfeel"
REPO_BRANCH=""
LOCAL_PATH=""
DRY_RUN=0
NO_BACKUP=0

usage() {
  cat <<'EOF'
install_lookandfeel.sh — options
  --repo URL         Git repository to pull from (default: nirucon/suckless_lookandfeel)
  --branch BRANCH    Branch/tag to checkout (default: repo default)
  --local PATH       Use an already cloned local path instead of git clone
  --dry-run          Print what would be done without writing files
  --no-backup        Overwrite without creating .bak timestamp (NOT recommended)

Notes:
• All executable helper scripts found in the repo will be installed to ~/.local/bin and chmod +x.
• picom.conf will be placed at ~/.config/picom/picom.conf
• You can extend the FILE_MAP easily (see section below).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO_URL="$2"; shift 2;;
    --branch)  REPO_BRANCH="$2"; shift 2;;
    --local)   LOCAL_PATH="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --no-backup) NO_BACKUP=1; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ------------------------ Acquire repo -------------------------
WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/lookandfeel"
REPO_DIR="$WORKDIR/repo"

get_repo() {
  if [[ -n "$LOCAL_PATH" ]]; then
    [[ -d "$LOCAL_PATH" ]] || { fail "--local path does not exist: $LOCAL_PATH"; exit 1; }
    REPO_DIR="$LOCAL_PATH"; say "Using local path: $REPO_DIR"; return
  fi
  mkdir -p "$WORKDIR"
  if [[ -d "$REPO_DIR/.git" ]]; then
    say "Updating repository in $REPO_DIR …"
    git -C "$REPO_DIR" fetch --all --prune || warn "git fetch failed (continuing with existing tree)"
    if [[ -n "$REPO_BRANCH" ]]; then
      git -C "$REPO_DIR" checkout "$REPO_BRANCH" || warn "checkout '$REPO_BRANCH' failed; using current branch"
    fi
    git -C "$REPO_DIR" pull --ff-only || warn "git pull failed; using current working tree"
  else
    say "Cloning $REPO_URL into $REPO_DIR …"
    git clone "$REPO_URL" "$REPO_DIR"
    [[ -n "$REPO_BRANCH" ]] && git -C "$REPO_DIR" checkout "$REPO_BRANCH" || true
  fi
}

# ------------------------ Helpers ------------------------------
ts() { date +"%Y%m%d-%H%M%S"; }
ensure_dir(){ mkdir -p "$1"; }

same_file(){ local a="$1" b="$2"; [[ -f "$a" && -f "$b" ]] && cmp -s -- "$a" "$b"; }

backup_if_needed(){
  local dest="$1"
  [[ $NO_BACKUP -eq 1 ]] && return 0
  if [[ -f "$dest" || -d "$dest" ]]; then
    local bak="${dest}.bak.$(ts)"
    if [[ -d "$dest" ]]; then
      cp -a "$dest" "$bak"
    else
      cp -f -- "$dest" "$bak"
    fi
    warn "Backed up existing to: $bak"
  fi
}

install_file(){
  local src="$1" dest="$2" mode="${3:-644}"
  ensure_dir "$(dirname -- "$dest")"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install: $src -> $dest (mode $mode)"; return 0
  fi
  if [[ -f "$dest" ]]; then
    if same_file "$src" "$dest"; then
      say "Unchanged: $dest"; return 0
    fi
  fi
  backup_if_needed "$dest"
  install -Dm"$mode" -- "$src" "$dest"
  say "Installed: $dest"
}

copy_scripts_to_local_bin(){
  local bin="$HOME/.local/bin"; ensure_dir "$bin"
  step "Copying helper scripts to $bin"
  # Executables: *.sh marked executable OR files in scripts/ marked executable
  mapfile -t candidates < <(find "$REPO_DIR" \( -path "$REPO_DIR/.git" -prune \) -o \
                                  \( -type f \( -name "*.sh" -o -path "*/scripts/*" \) -print \))
  local n=0
  for f in "${candidates[@]}"; do
    # Skip obvious config files that happen to end with .sh in some repos
    [[ "$(basename "$f")" =~ ^(install|setup)lookandfeel\.sh$ ]] && continue
    local dest="$bin/$(basename "$f")"
    if [[ $DRY_RUN -eq 1 ]]; then
      say "[dry-run] Would copy script: $f -> $dest (chmod +x)"; ((n++)); continue
    fi
    install -Dm755 -- "$f" "$dest"
    chmod +x "$dest" || true
    ((n++))
  done
  say "Scripts installed: $n"
}

# ------------------------ File map (easy to extend) ------------
# Add entries as: "RELATIVE_SOURCE => DESTINATION"
# The first existing source among variations will be used.
# You can append more variations by space-separating them on the left side.

# shellcheck disable=SC1083
read -r -d '' FILE_MAP <<'MAP'
# bash
.bashrc bash/.bashrc home/.bashrc dots/.bashrc bashrc => ~/.bashrc
.bash_aliases bash/.bash_aliases home/.bash_aliases dots/.bash_aliases bash_aliases => ~/.bash_aliases
.inputrc inputrc home/.inputrc dots/.inputrc => ~/.inputrc

# dunst
.config/dunst/dunstrc dunst/dunstrc dotconfig/dunst/dunstrc config/dunst/dunstrc dunstrc => ~/.config/dunst/dunstrc

# alacritty (toml or yml)
.config/alacritty/alacritty.toml alacritty/alacritty.toml config/alacritty/alacritty.toml alacritty.toml => ~/.config/alacritty/alacritty.toml
.config/alacritty/alacritty.yml  alacritty/alacritty.yml  config/alacritty/alacritty.yml  alacritty.yml  => ~/.config/alacritty/alacritty.yml

# rofi
.config/rofi/config.rasi rofi/config.rasi config/rofi/config.rasi config.rasi => ~/.config/rofi/config.rasi
.config/rofi/config      rofi/config      config/rofi/config      config      => ~/.config/rofi/config

# picom (explicit request)
.config/picom/picom.conf picom/picom.conf config/picom/picom.conf picom.conf => ~/.config/picom/picom.conf
MAP

# ------------------------ Resolver ------------------------------
first_existing(){ local base="$1"; shift; local c; for c in "$@"; do [[ -f "$base/$c" ]] && { printf "%s" "$base/$c"; return 0; }; done; return 1; }

apply_file_map(){
  step "Installing config files"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local left right
    left="${line%%=>*}"; right="${line#*=>}"
    left="${left%%[[:space:]]}"; right="${right##[[:space:]]}"

    # Split left by spaces into variations
    read -r -a variants <<<"$left"
    # Expand tilde in destination
    local dest; dest="${right/#~/$HOME}"

    local src; src=""
    if src="$(first_existing "$REPO_DIR" "${variants[@]}")"; then
      install_file "$src" "$dest" 644
    else
      warn "Source not found for: $dest (variants: ${variants[*]}) — skipping"
    fi
  done <<< "$FILE_MAP"
}

# ------------------------ Optional: Rofi theme system-wide ------
install_rofi_theme_system(){
  local src
  src="$(first_existing "$REPO_DIR" rofi/themes/Black-Metal.rasi themes/Black-Metal.rasi Black-Metal.rasi || true)"
  [[ -n "$src" ]] || { warn "No Black-Metal.rasi found — skipping system theme."; return 0; }
  local dest="/usr/share/rofi/themes/Black-Metal.rasi"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install (sudo): $src -> $dest"; return 0
  fi
  if [[ -w "/usr/share/rofi/themes" ]]; then
    install -Dm644 -- "$src" "$dest"
  else
    command -v sudo >/dev/null 2>&1 || { warn "sudo not available; cannot install system theme"; return 0; }
    say "Using sudo to install system theme…"
    sudo mkdir -p "/usr/share/rofi/themes"
    sudo install -Dm644 -- "$src" "$dest"
  fi
  say "Installed system rofi theme: $dest"
}

# ------------------------ Main ---------------------------------
step "Preparing repository"
get_repo

apply_file_map
copy_scripts_to_local_bin

# Uncomment/commnet to install the system rofi theme automatically.
install_rofi_theme_system

cat <<'EOT'
\n========================================================
Look & Feel complete

• Config files installed to ~/.config and HOME. Existing files were backed up (.bak.TIMESTAMP) unless --no-backup.
• All helper scripts found in the repo have been copied to ~/.local/bin and marked executable.
• picom.conf was ensured at ~/.config/picom/picom.conf
• Re-run anytime; safe and idempotent.

Extend later:
• Add more lines to FILE_MAP (left: possible repo paths; right: destination path).
• Drop additional scripts into the repo; they will be installed to ~/.local/bin.
========================================================
EOT
