#!/usr/bin/env bash
# alpi.sh — Arch Linux Post Install Orchestrator
# Author: Nicklas Rudolfsson (NIRUCON)
#
# Orchestrates:
#   core, apps, suckless, statusbar, lookandfeel, optimize
#
# Highlights:
# - `--nirucon` correctly maps to `--source nirucon` for install_suckless.sh
# - `--jobs` is forwarded ONLY to scripts that actually support it
# - `--only` / `--skip` / `--dry-run` supported

set -Eeuo pipefail

#######################################
# Pretty logging
#######################################
COLOR_RESET="\033[0m"
COLOR_INFO="\033[1;34m"
COLOR_OK="\033[1;32m"
COLOR_WARN="\033[1;33m"
COLOR_ERR="\033[1;31m"

say()  { printf "${COLOR_INFO}[*]${COLOR_RESET} %s\n" "$*"; }
ok()   { printf "${COLOR_OK}[ok]${COLOR_RESET} %s\n" "$*"; }
warn() { printf "${COLOR_WARN}[WARN]${COLOR_RESET} %s\n" "$*"; }
err()  { printf "${COLOR_ERR}[ERR]${COLOR_RESET} %s\n" "$*" >&2; }
die()  { err "$@"; exit 1; }

trap 'err "Aborted on line $LINENO (command: ${BASH_COMMAND:-unknown})"; exit 1' ERR

#######################################
# Paths & components
#######################################
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE="${SCRIPT_DIR}/install_core.sh"
APPS="${SCRIPT_DIR}/install_apps.sh"
SUCK="${SCRIPT_DIR}/install_suckless.sh"
STAT="${SCRIPT_DIR}/install_statusbar.sh"
LOOK="${SCRIPT_DIR}/install_lookandfeel.sh"
OPTM="${SCRIPT_DIR}/install_optimize.sh"

ALL_STEPS=(core apps suckless statusbar lookandfeel optimize)

#######################################
# Defaults
#######################################
JOBS="$(command -v nproc &>/dev/null && nproc || echo 2)"
DRY_RUN=0

# Suckless controls
SCK_SOURCE="vanilla"    # vanilla | nirucon
ASK_SUCKLESS=0
SCK_NO_FONTS=0

# Selection filters
ONLY_STEPS=()
SKIP_STEPS=()

#######################################
# Helpers
#######################################
exists() { [[ -e "$1" ]]; }
is_exec() { [[ -x "$1" ]]; }
ensure_exec() {
  local f="$1"
  exists "$f" || die "Missing script: $f"
  if ! is_exec "$f"; then
    warn "Script not executable: $f — attempting chmod +x"
    chmod +x "$f" || die "Failed to chmod +x $f"
  fi
}

in_array() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 0 # (dummy, caller handles)
}

# Returns 0 (true) if the step should run
should_run() {
  local step="$1"
  if ((${#ONLY_STEPS[@]} > 0)); then
    local found=1
    for s in "${ONLY_STEPS[@]}"; do
      [[ "$s" == "$step" ]] && found=0 && break
    done
    (( found == 0 )) || return 1
  fi
  for s in "${SKIP_STEPS[@]}"; do
    [[ "$s" == "$step" ]] && return 1
  done
  return 0
}

# Check if a script (by path) appears to support a given long flag
supports_flag() {
  local script="$1" flag="$2"
  # Simple static check: look for the literal flag in the script
  # This avoids invoking the script and works even in dry runs.
  grep -q -- "$flag" "$script" 2>/dev/null
}

run_user() {
  local cmd=("$@")
  say "RUN: ${cmd[*]}"
  if (( DRY_RUN == 1 )); then
    ok "Dry-run: command not executed."
  else
    "${cmd[@]}"
    ok "Done: ${cmd[0]}"
  fi
}

#######################################
# Usage
#######################################
usage() {
  cat <<'EOF'
alpi.sh — Orchestrate post-install steps

USAGE:
  ./alpi.sh [flags]

FLAGS:
  --nirucon              Use nirucon/suckless repo (forwards --source nirucon to install_suckless.sh)
  --vanilla              Force vanilla suckless (forwards --source vanilla)
  --ask-suckless         Let install_suckless.sh prompt (no --source forwarded)
  --no-fonts             Forward --no-fonts to install_suckless.sh

  --jobs N               Parallel jobs (forwarded only to scripts that support --jobs)
  --dry-run              Print what would run without executing

  --only <list>          Run only these steps (comma-separated or repeat the flag)
  --skip <list>          Skip these steps (comma-separated or repeat the flag)

  --help                 Show this help

STEPS (for --only/--skip):
  core, apps, suckless, statusbar, lookandfeel, optimize

EXAMPLES:
  ./alpi.sh --nirucon
  ./alpi.sh --only suckless,statusbar --nirucon --dry-run
  ./alpi.sh --skip apps --nirucon
EOF
}

#######################################
# Parse args
#######################################
if (( $# == 0 )); then
  say "No flags provided. Running default flow (vanilla suckless)."
fi

while (( $# )); do
  case "$1" in
    --nirucon)       SCK_SOURCE="nirucon"; shift ;;
    --vanilla)       SCK_SOURCE="vanilla"; shift ;;
    --ask-suckless)  ASK_SUCKLESS=1; shift ;;
    --no-fonts)      SCK_NO_FONTS=1; shift ;;
    --jobs)
      shift
      [[ $# -gt 0 ]] || die "--jobs requires a value"
      [[ "$1" =~ ^[0-9]+$ ]] || die "--jobs must be an integer"
      JOBS="$1"; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --only)
      shift
      [[ $# -gt 0 ]] || die "--only requires a list"
      IFS=',' read -r -a tmp <<< "$1"; ONLY_STEPS+=("${tmp[@]}"); shift ;;
    --skip)
      shift
      [[ $# -gt 0 ]] || die "--skip requires a list"
      IFS=',' read -r -a tmp <<< "$1"; SKIP_STEPS+=("${tmp[@]}"); shift ;;
    --help|-h)       usage; exit 0 ;;
    *)               die "Unknown flag: $1 (see --help)" ;;
  esac
done

#######################################
# Preflight
#######################################
say "Starting alpi.sh"
say "Jobs:            $JOBS"
say "Dry-run:         $DRY_RUN"
say "Suckless source: $SCK_SOURCE (ask-suckless=$ASK_SUCKLESS, no-fonts=$SCK_NO_FONTS)"
((${#ONLY_STEPS[@]} > 0)) && say "Only steps:      ${ONLY_STEPS[*]}"
((${#SKIP_STEPS[@]} > 0)) && say "Skip steps:      ${SKIP_STEPS[*]}"

ensure_exec "$CORE"
ensure_exec "$APPS"
ensure_exec "$SUCK"
ensure_exec "$STAT"
ensure_exec "$LOOK"
ensure_exec "$OPTM"

#######################################
# Step wrappers
#######################################
step_core() {
  should_run core || { warn "Skipping core"; return 0; }
  say "==> Step: core"
  local args=()
  # Forward only supported flags
  supports_flag "$CORE" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)
  # Do NOT forward --jobs unless supported; most cores do not support it
  supports_flag "$CORE" "--jobs"   && args+=(--jobs "$JOBS")
  run_user "$CORE" "${args[@]}"
}

step_apps() {
  should_run apps || { warn "Skipping apps"; return 0; }
  say "==> Step: apps"
  local args=()
  supports_flag "$APPS" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)
  supports_flag "$APPS" "--jobs"    && args+=(--jobs "$JOBS")
  run_user "$APPS" "${args[@]}"
}

step_suckless() {
  should_run suckless || { warn "Skipping suckless"; return 0; }
  say "==> Step: suckless"
  local args=()
  # Many suckless installers support these:
  supports_flag "$SUCK" "--jobs"    && args+=(--jobs "$JOBS")
  supports_flag "$SUCK" "--no-fonts" && (( SCK_NO_FONTS == 1 )) && args+=(--no-fonts)
  supports_flag "$SUCK" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)

  if (( ASK_SUCKLESS == 0 )); then
    # Only add --source if the script supports it
    if supports_flag "$SUCK" "--source"; then
      args+=(--source "$SCK_SOURCE")
    else
      warn "install_suckless.sh does not advertise --source; continuing without it."
    fi
  else
    warn "ask-suckless is active: not sending --source (installer will prompt)."
  fi

  say "Resolved suckless source: $SCK_SOURCE (ask=$ASK_SUCKLESS)"
  run_user "$SUCK" "${args[@]}"
}

step_statusbar() {
  should_run statusbar || { warn "Skipping statusbar"; return 0; }
  say "==> Step: statusbar"
  local args=()
  supports_flag "$STAT" "--jobs"    && args+=(--jobs "$JOBS")
  supports_flag "$STAT" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)
  run_user "$STAT" "${args[@]}"
}

step_lookandfeel() {
  should_run lookandfeel || { warn "Skipping lookandfeel"; return 0; }
  say "==> Step: lookandfeel"
  local args=()
  supports_flag "$LOOK" "--jobs"    && args+=(--jobs "$JOBS")
  supports_flag "$LOOK" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)
  run_user "$LOOK" "${args[@]}"
}

step_optimize() {
  should_run optimize || { warn "Skipping optimize"; return 0; }
  say "==> Step: optimize"
  local args=()
  supports_flag "$OPTM" "--jobs"    && args+=(--jobs "$JOBS")
  supports_flag "$OPTM" "--dry-run" && (( DRY_RUN == 1 )) && args+=(--dry-run)
  run_user "$OPTM" "${args[@]}"
}

#######################################
# Execute in order
#######################################
for step in "${ALL_STEPS[@]}"; do
  case "$step" in
    core)        step_core ;;
    apps)        step_apps ;;
    suckless)    step_suckless ;;
    statusbar)   step_statusbar ;;
    lookandfeel) step_lookandfeel ;;
    optimize)    step_optimize ;;
    *) warn "Unknown step in ALL_STEPS: $step (skipping)";;
  esac
done

ok "All selected steps completed."
