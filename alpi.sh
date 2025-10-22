#!/usr/bin/env bash
# alpi.sh — Arch Linux Post Install Orchestrator
# Author: Nicklas Rudolfsson
#
# Orchestrates: core, apps, suckless, lookandfeel, statusbar, optimize
#
# Changes in this version:
# - Default is now --nirucon (custom setup)
# - Execution order: lookandfeel BEFORE statusbar (statusbar needs scripts from lookandfeel)
# - All logging in English, user-friendly output

set -Eeuo pipefail

#######################################
# Pretty logging
#######################################
COLOR_RESET="\033[0m"
COLOR_INFO="\033[1;34m"
COLOR_OK="\033[1;32m"
COLOR_WARN="\033[1;33m"
COLOR_ERR="\033[1;31m"

say() { printf "${COLOR_INFO}[*]${COLOR_RESET} %s\n" "$*"; }
ok() { printf "${COLOR_OK}[✓]${COLOR_RESET} %s\n" "$*"; }
warn() { printf "${COLOR_WARN}[WARN]${COLOR_RESET} %s\n" "$*"; }
err() { printf "${COLOR_ERR}[ERR]${COLOR_RESET} %s\n" "$*"; }
die() {
  err "$@"
  exit 1
}

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

# IMPORTANT: lookandfeel BEFORE statusbar (statusbar needs scripts from lookandfeel)
ALL_STEPS=(core apps suckless lookandfeel statusbar optimize)

#######################################
# Defaults
#######################################
JOBS="$(command -v nproc &>/dev/null && nproc || echo 2)"
DRY_RUN=0

# Suckless controls (default: nirucon)
SCK_SOURCE="nirucon" # nirucon | vanilla
ASK_SUCKLESS=0
SCK_NO_FONTS=0

# Look&feel repo defaults
LOOK_REPO_DEFAULT="https://github.com/nirucon/suckless_lookandfeel"
LOOK_REPO="$LOOK_REPO_DEFAULT"
LOOK_BRANCH="main"

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

# Returns 0 (true) if the step should run
should_run() {
  local step="$1"
  if ((${#ONLY_STEPS[@]} > 0)); then
    local match=1
    for s in "${ONLY_STEPS[@]}"; do [[ "$s" == "$step" ]] && match=0 && break; done
    ((match == 0)) || return 1
  fi
  for s in "${SKIP_STEPS[@]}"; do [[ "$s" == "$step" ]] && return 1; done
  return 0
}

# Static check if a script file contains a flag
supports_flag() {
  local script="$1" flag="$2"
  grep -q -- "$flag" "$script" 2>/dev/null
}

run_user() {
  local cmd=("$@")
  say "RUN: ${cmd[*]}"
  if ((DRY_RUN == 1)); then
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
alpi.sh — Orchestrate Arch Linux post-install steps

USAGE:
  ./alpi.sh [flags]

FLAGS:
  --nirucon              Use nirucon/suckless repo (DEFAULT)
  --vanilla              Use vanilla suckless (upstream)
  --ask-suckless         Let install_suckless.sh prompt interactively
  --no-fonts             Skip font installation in suckless step

  --look-repo URL        Look&feel repo (default: nirucon/suckless_lookandfeel)
  --look-branch NAME     Look&feel branch (default: main)

  --jobs N               Parallel jobs for compilation
  --dry-run              Preview actions without making changes

  --only <list>          Run only these steps (comma-separated)
  --skip <list>          Skip these steps (comma-separated)

  --help                 Show this help

STEPS (for --only/--skip):
  core, apps, suckless, lookandfeel, statusbar, optimize

EXAMPLES:
  ./alpi.sh                              # Install with nirucon setup (default)
  ./alpi.sh --vanilla                    # Install with vanilla suckless
  ./alpi.sh --only suckless,lookandfeel  # Re-install only suckless + configs
  ./alpi.sh --skip optimize --dry-run    # Preview without system optimizations
EOF
}

#######################################
# Parse args
#######################################
if (($# == 0)); then
  say "No flags provided. Using default: nirucon setup."
fi

while (($#)); do
  case "$1" in
  --nirucon)
    SCK_SOURCE="nirucon"
    shift
    ;;
  --vanilla)
    SCK_SOURCE="vanilla"
    shift
    ;;
  --ask-suckless)
    ASK_SUCKLESS=1
    shift
    ;;
  --no-fonts)
    SCK_NO_FONTS=1
    shift
    ;;

  --look-repo)
    shift
    [[ $# -gt 0 ]] || die "--look-repo requires a URL"
    LOOK_REPO="$1"
    shift
    ;;
  --look-branch)
    shift
    [[ $# -gt 0 ]] || die "--look-branch requires a name"
    LOOK_BRANCH="$1"
    shift
    ;;

  --jobs)
    shift
    [[ $# -gt 0 ]] || die "--jobs requires a value"
    [[ "$1" =~ ^[0-9]+$ ]] || die "--jobs must be an integer"
    JOBS="$1"
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --only)
    shift
    [[ $# -gt 0 ]] || die "--only requires a list"
    IFS=',' read -r -a tmp <<<"$1"
    ONLY_STEPS+=("${tmp[@]}")
    shift
    ;;
  --skip)
    shift
    [[ $# -gt 0 ]] || die "--skip requires a list"
    IFS=',' read -r -a tmp <<<"$1"
    SKIP_STEPS+=("${tmp[@]}")
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *) die "Unknown flag: $1 (see --help)" ;;
  esac
done

#######################################
# Preflight
#######################################
say "Starting ALPI (Arch Linux Post Install)"
say "Jobs:            $JOBS"
say "Dry-run:         $DRY_RUN"
say "Suckless source: $SCK_SOURCE (ask=$ASK_SUCKLESS, no-fonts=$SCK_NO_FONTS)"
say "Look&feel repo:  $LOOK_REPO (branch=$LOOK_BRANCH)"
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
  should_run core || {
    warn "Skipping core"
    return 0
  }
  say "==> Step: core (base system)"
  local args=()
  supports_flag "$CORE" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)
  supports_flag "$CORE" "--jobs" && args+=(--jobs "$JOBS")
  run_user "$CORE" "${args[@]}"
}

step_apps() {
  should_run apps || {
    warn "Skipping apps"
    return 0
  }
  say "==> Step: apps (desktop & development tools)"
  local args=()
  supports_flag "$APPS" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)
  supports_flag "$APPS" "--jobs" && args+=(--jobs "$JOBS")
  run_user "$APPS" "${args[@]}"
}

step_suckless() {
  should_run suckless || {
    warn "Skipping suckless"
    return 0
  }
  say "==> Step: suckless (dwm, st, dmenu, slock)"
  local args=()
  supports_flag "$SUCK" "--jobs" && args+=(--jobs "$JOBS")
  supports_flag "$SUCK" "--no-fonts" && ((SCK_NO_FONTS == 1)) && args+=(--no-fonts)
  supports_flag "$SUCK" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)

  if ((ASK_SUCKLESS == 0)); then
    if supports_flag "$SUCK" "--source"; then
      args+=(--source "$SCK_SOURCE")
    else
      warn "install_suckless.sh does not support --source; continuing without it."
    fi
  else
    warn "ask-suckless is active: installer will prompt for source."
  fi

  say "Resolved suckless source: $SCK_SOURCE"
  run_user "$SUCK" "${args[@]}"
}

step_lookandfeel() {
  should_run lookandfeel || {
    warn "Skipping lookandfeel"
    return 0
  }
  say "==> Step: lookandfeel (configs, themes, scripts)"
  local args=(--repo "$LOOK_REPO" --branch "$LOOK_BRANCH")
  supports_flag "$LOOK" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)
  run_user "$LOOK" "${args[@]}"
}

step_statusbar() {
  should_run statusbar || {
    warn "Skipping statusbar"
    return 0
  }
  say "==> Step: statusbar (dwm status bar)"
  local args=()
  supports_flag "$STAT" "--jobs" && args+=(--jobs "$JOBS")
  supports_flag "$STAT" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)
  run_user "$STAT" "${args[@]}"
}

step_optimize() {
  should_run optimize || {
    warn "Skipping optimize"
    return 0
  }
  say "==> Step: optimize (system tuning)"
  local args=()
  supports_flag "$OPTM" "--jobs" && args+=(--jobs "$JOBS")
  supports_flag "$OPTM" "--dry-run" && ((DRY_RUN == 1)) && args+=(--dry-run)

  if ((EUID != 0)); then
    warn "Step 'optimize' requires root — running with sudo."
    run_user sudo "$OPTM" "${args[@]}"
  else
    run_user "$OPTM" "${args[@]}"
  fi
}

#######################################
# Execute in order
#######################################
for step in "${ALL_STEPS[@]}"; do
  case "$step" in
  core) step_core ;;
  apps) step_apps ;;
  suckless) step_suckless ;;
  lookandfeel) step_lookandfeel ;;
  statusbar) step_statusbar ;;
  optimize) step_optimize ;;
  *) warn "Unknown step in ALL_STEPS: $step (skipping)" ;;
  esac
done

ok "All selected steps completed!"
say "Reboot recommended to apply all changes."
say "Start X session with: startx"
