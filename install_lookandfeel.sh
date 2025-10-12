#!/usr/bin/env bash
# install_lookandfeel.sh — theme, dotfiles & helper scripts
# Purpose: Pull files from https://github.com/nirucon/suckless_lookandfeel (or a local path),
#          install helper scripts to ~/.local/bin (chmod +x), and place picom.conf correctly.
# Author:  Nicklas Rudolfsson (NIRUCON)

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${GRN}[LOOK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; exit 1; }

# ───────── Helpers ─────────
timestamp() { date +%Y%m%d-%H%M%S; }

backup_dir () {
  # Create a side-by-side backup of a directory: /path/dir -> /path/dir.bak.TIMESTAMP
  local d="${1:-}"
  [[ -z "$d" ]] && fail "backup_dir: missing directory argument"
  d="${d%/}"
  [[ -e "$d" ]] || return 0
  local b="${d}.bak.$(timestamp)"
  cp -a -- "$d" "$b"
  say "Backup created: $b"
}

backup_file () {
  # Create a versioned backup of a single file if it exists
  local f="${1:-}"
  [[ -z "$f" ]] && fail "backup_file: missing file argument"
  if [[ -e "$f" ]]; then
    local b="${f}.bak.$(timestamp)"
    cp -a -- "$f" "$b"
    say "Backup created: $b"
  fi
}

ensure_dir() { mkdir -p -- "$1"; }

# ───────── Parse args ─────────
SRC_DIR=""
REPO_URL="https://github.com/nirucon/suckless_lookandfeel"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/suckless_lookandfeel"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      SRC_DIR="${2:-}"; shift 2 || fail "--from requires a path"
      ;;
    --repo)
      REPO_URL="${2:-}"; shift 2 || fail "--repo requires a URL"
      ;;
    *)
      fail "Unknown argument: $1 (supported: --from PATH, --repo URL)"
      ;;
  esac
done

# ───────── Acquire source ─────────
if [[ -n "${SRC_DIR}" ]]; then
  [[ -d "$SRC_DIR" ]] || fail "--from path not found: $SRC_DIR"
  say "Using local source: $SRC_DIR"
else
  step "Preparing repo cache"
  ensure_dir "$(dirname "$CACHE_DIR")"
  if [[ -d "$CACHE_DIR/.git" ]]; then
    say "Updating cache at $CACHE_DIR"
    git -C "$CACHE_DIR" fetch --all --prune
    git -C "$CACHE_DIR" reset --hard origin/HEAD || git -C "$CACHE_DIR" reset --hard HEAD
  else
    say "Cloning $REPO_URL -> $CACHE_DIR"
    if command -v git >/dev/null 2>&1; then
      git clone --depth 1 "$REPO_URL" "$CACHE_DIR"
    else
      fail "git is required to clone the repository. Provide --from PATH to use a local source."
    fi
  fi
  SRC_DIR="$CACHE_DIR"
fi

[[ -d "$SRC_DIR" ]] || fail "No source directory available."

# ───────── Determine script sources ─────────
SCRIPTS_SRC=""
if [[ -d "$SRC_DIR/scripts" ]]; then
  SCRIPTS_SRC="$SRC_DIR/scripts"
elif [[ -d "$SRC_DIR/bin" ]]; then
  SCRIPTS_SRC="$SRC_DIR/bin"
else
  # fallback: pick executable files at depth 1-2
  mapfile -t found_execs < <(find "$SRC_DIR" -maxdepth 2 -type f -perm -111 2>/dev/null || true)
  if (( ${#found_execs[@]} == 0 )); then
    warn "No obvious 'scripts' or 'bin' directory and no executables found; continuing without script install."
  fi
fi

# ───────── Install to ~/.local/bin ─────────
LOCAL_BIN="$HOME/.local/bin"
ensure_dir "$LOCAL_BIN"

if [[ -n "${SCRIPTS_SRC:-}" && -d "$SCRIPTS_SRC" ]]; then
  step "Installing helper scripts to $LOCAL_BIN"
  # Back up the entire directory once (side-by-side backup), then overlay copy.
  backup_dir "$LOCAL_BIN"
  # Copy everything from the source scripts dir into LOCAL_BIN (preserve attributes).
  rsync -a --delete -- "$SCRIPTS_SRC"/ "$LOCAL_BIN"/ 2>/dev/null || cp -a -- "$SCRIPTS_SRC"/. "$LOCAL_BIN"/
  chmod -R u+rx,go+rx "$LOCAL_BIN" || true
  say "Scripts installed to $LOCAL_BIN"
fi

# ───────── Install picom.conf ─────────
CONFIG_DIR="$HOME/.config/picom"
ensure_dir "$CONFIG_DIR"

picom_src=""
for candidate in \
  "$SRC_DIR/picom.conf" \
  "$SRC_DIR/config/picom/picom.conf" \
  "$SRC_DIR/.config/picom/picom.conf" \
  "$SRC_DIR/picom/picom.conf"
do
  if [[ -f "$candidate" ]]; then
    picom_src="$candidate"
    break
  fi
done

if [[ -n "$picom_src" ]]; then
  step "Installing picom.conf"
  backup_file "$CONFIG_DIR/picom.conf"
  cp -a -- "$picom_src" "$CONFIG_DIR/picom.conf"
  say "picom.conf installed → $CONFIG_DIR/picom.conf"
else
  warn "picom.conf not found in source; skipping."
fi

# ───────── Ensure PATH contains ~/.local/bin ─────────
export_marker="# Added by install_lookandfeel.sh"
ensure_path() {
  local shell_rc="$1"
  [[ -f "$shell_rc" ]] || return 0
  if ! grep -q '\.local/bin' "$shell_rc"; then
    {
      echo ""
      echo "$export_marker"
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$shell_rc"
    say "PATH updated in $shell_rc"
  fi
}

ensure_path "$HOME/.bash_profile"
ensure_path "$HOME/.bashrc"
ensure_path "$HOME/.zshrc"

cat <<'EOT'
========================================================
Look & Feel setup complete

• Scripts → ~/.local/bin (755)
• picom.conf → ~/.config/picom/picom.conf (backup if existed)
• PATH ensured for ~/.local/bin (via shell rc files)

Re-run safely anytime; only changed files are updated.
========================================================
EOT
