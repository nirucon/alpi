#!/usr/bin/env bash
# install_lookandfeel.sh — theme, dotfiles & helper scripts
# Purpose: Pull files from https://github.com/nirucon/suckless_lookandfeel (or a local path),
#          install all scripts to ~/.local/bin (chmod +x), and place picom.conf correctly.
# Author:  Nicklas Rudolfsson (NIRUCON)
# Output:  Clear, English-only messages. Safe, idempotent, with backups.

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
CYN="\033[1;36m"; YLW="\033[1;33m"; RED="\033[1;31m"; BLU="\033[1;34m"; GRN="\033[1;32m"; NC="\033[0m"
say()  { printf "${GRN}[LOOK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
trap 'fail "install_lookandfeel.sh failed. See previous messages for details."' ERR

# ───────── Defaults / args ─────────
REPO_URL="${REPO_URL:-https://github.com/nirucon/suckless_lookandfeel}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/suckless_lookandfeel"
LOCAL_BIN="$HOME/.local/bin"
PICOM_DIR="$HOME/.config/picom"
PICOM_CFG="$PICOM_DIR/picom.conf"

SRC_OVERRIDE=""      # --from /path/to/local-source (optional)
DRY_RUN=0
NO_CLONE=0          # --no-clone if you only want to install from an existing local source

usage(){ cat <<'EOF'
install_lookandfeel.sh — options
  --from PATH     Use a local source path instead of cloning the repo
  --no-clone      Do not clone/pull; assume the source already exists (with --from or in cache)
  --dry-run       Print actions without changing the system
  -h|--help       Show this help

Installs:
• All scripts found in the source → ~/.local/bin (chmod +x)
• picom.conf → ~/.config/picom/picom.conf (backup if exists)

Notes:
• Safe to run multiple times; existing files are backed up with .bak.TIMESTAMP before overwrite.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)     SRC_OVERRIDE="$2"; shift 2;;
    --no-clone) NO_CLONE=1; shift;;
    --dry-run)  DRY_RUN=1; shift;;
    -h|--help)  usage; exit 0;;
    *) warn "Unknown argument: $1"; usage; exit 1;;
  esac
done

# ───────── Helpers ─────────
ts() { date +"%Y%m%d-%H%M%S"; }
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
ensure_dir(){ mkdir -p "$1"; }
backup_if_exists(){
  local f="$1"
  [[ -e "$f" ]] || return 0
  local b="${f}.bak.$(ts)"
  run cp -a -- "$f" "$b"
  warn "Backup: $f -> $b"
}
append_once(){ local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }

# ───────── Ensure basics ─────────
ensure_dir "$LOCAL_BIN" "$PICOM_DIR"
if ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
  append_once 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bash_profile"
fi

# ───────── Resolve source directory ─────────
SRC_DIR=""
if [[ -n "$SRC_OVERRIDE" ]]; then
  # Use local override
  if [[ -d "$SRC_OVERRIDE" ]]; then
    SRC_DIR="$SRC_OVERRIDE"
    say "Using local source: $SRC_DIR"
  else
    fail "--from path not found: $SRC_OVERRIDE"
  fi
else
  # Use cached clone
  SRC_DIR="$CACHE_DIR"
  if (( NO_CLONE == 0 )); then
    if command -v git >/dev/null 2>&1; then
      if [[ -d "$SRC_DIR/.git" ]]; then
        step "Updating look & feel repo in cache"
        ( cd "$SRC_DIR" && run git fetch --all --prune && run git pull --ff-only ) || warn "git pull failed; proceeding with existing tree"
      else
        step "Cloning look & feel repo"
        ensure_dir "$(dirname "$SRC_DIR")"
        run git clone "$REPO_URL" "$SRC_DIR"
      fi
    else
      warn "git not found; cannot clone. Falling back to existing cache (if present)."
    fi
  fi
fi

# Final guard
[[ -d "$SRC_DIR" ]] || fail "No source directory available. Use --from PATH or ensure cache exists."

# ───────── Install scripts → ~/.local/bin ─────────
# Strategy:
#  1) Prefer a top-level 'scripts' or 'bin' directory if present.
#  2) Otherwise, take any executable files under the repo (depth-limited) that look like scripts.
step "Installing helper scripts to $LOCAL_BIN"
mapfile -t candidate_dirs < <(printf '%s\n' "$SRC_DIR/scripts" "$SRC_DIR/bin")
installed_any=0
did_copy=0

copy_script(){
  local src="$1" dst="$LOCAL_BIN/$(basename "$src")"
  backup_if_exists "$dst"
  run install -Dm755 -- "$src" "$dst"
  installed_any=1
}

for d in "${candidate_dirs[@]}"; do
  if [[ -d "$d" ]]; then
    while IFS= read -r -d '' f; do
      copy_script "$f"
      did_copy=1
    done < <(find "$d" -maxdepth 1 -type f -print0)
  fi
done

if (( did_copy == 0 )); then
  # Fallback: find likely scripts anywhere in repo (depth-limited to avoid huge trees)
  while IFS= read -r -d '' f; do
    # Heuristic: executable and either shebang or .sh extension
    if [[ -x "$f" ]] || head -n1 "$f" 2>/dev/null | grep -qE '^#!'; then
      copy_script "$f"
    fi
  done < <(find "$SRC_DIR" -maxdepth 2 -type f \( -name "*.sh" -o -perm -111 \) -print0)
fi

if (( installed_any == 0 )); then
  warn "No scripts found to install. This is fine if the repo only contained configs."
else
  say "Scripts installed to $LOCAL_BIN"
fi

# ───────── Install picom.conf ─────────
# Accept common locations inside the repo.
step "Placing picom.conf"
PICOM_CANDIDATES=(
  "$SRC_DIR/picom.conf"
  "$SRC_DIR/config/picom/picom.conf"
  "$SRC_DIR/.config/picom/picom.conf"
  "$SRC_DIR/picom/picom.conf"
)

placed=0
for cand in "${PICOM_CANDIDATES[@]}"; do
  if [[ -f "$cand" ]]; then
    backup_if_exists "$PICOM_CFG"
    run install -Dm644 -- "$cand" "$PICOM_CFG"
    say "Installed picom.conf from: $cand"
    placed=1
    break
  fi
done
if (( placed == 0 )); then
  warn "picom.conf not found in the source; skipping (this will not block other steps)."
fi

cat <<'EOT'
========================================================
Look & Feel setup complete

• Scripts → ~/.local/bin (755)
• picom.conf → ~/.config/picom/picom.conf (backup if existed)
• PATH ensured for ~/.local/bin (via ~/.bash_profile)

Re-run safely anytime; only changed files are updated.
========================================================
EOT
