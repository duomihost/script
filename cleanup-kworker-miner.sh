#!/usr/bin/env bash
# Safe cleanup tool for the known fake kworker/XMRig infection chain.
set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly KWORKER_DIR="/var/local/kworker"
readonly KTHREAD_DIR="/var/local/kthreadd"
readonly KWORKER_UNIT="/etc/systemd/system/kworker.service"
readonly KTHREAD_UNIT="/etc/systemd/system/kthread.service"
readonly KTHREAD_CRON="/etc/cron.d/kthread"
readonly BACKUP_ROOT="/var/backups/kworker-miner-cleanup"

APPLY=false
FOUND=false
KWORKER_FOUND=false
KTHREAD_FOUND=false

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage:
  sudo ./${SCRIPT_NAME}             Check only (no changes)
  sudo ./${SCRIPT_NAME} --apply     Remove the confirmed infection chain
  ./${SCRIPT_NAME} --help

Targets:
  ${KWORKER_DIR}
  ${KTHREAD_DIR}
  ${KWORKER_UNIT}
  ${KTHREAD_UNIT}
  ${KTHREAD_CRON}
EOF
}

die() {
  error "$*"
  exit 1
}

contains_pattern() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] && grep -aEq -- "$pattern" "$file" 2>/dev/null
}

unit_references_path() {
  local unit="$1"
  local path="$2"
  [[ -f "$unit" ]] && grep -Fq -- "$path" "$unit" 2>/dev/null
}

detect() {
  info "Checking for the known kworker/XMRig infection chain..."

  if unit_references_path "$KWORKER_UNIT" "$KWORKER_DIR" \
    || contains_pattern "$KWORKER_DIR/c" 'supportxmr|kryptex|c3pool' \
    || contains_pattern "$KWORKER_DIR/kworker.sh" '/var/local/kworker|--config=\./c'; then
    FOUND=true
    KWORKER_FOUND=true
    warn "Detected the fake kworker miner payload or service."
  fi

  if unit_references_path "$KTHREAD_UNIT" "$KTHREAD_DIR" \
    || contains_pattern "$KTHREAD_CRON" '/var/local/kthreadd' \
    || contains_pattern "$KTHREAD_DIR/watch.sh" 'kthread\.service|--service-worker'; then
    FOUND=true
    KTHREAD_FOUND=true
    warn "Detected the associated kthread watchdog or persistence."
  fi

  local proc_path exe_path
  for proc_path in /proc/[0-9]*; do
    [[ -e "$proc_path/exe" ]] || continue
    exe_path="$(readlink -f "$proc_path/exe" 2>/dev/null || true)"
    case "$exe_path" in
      "$KWORKER_DIR"/*)
        FOUND=true
        KWORKER_FOUND=true
        warn "Detected running payload: PID ${proc_path##*/} -> ${exe_path}"
        ;;
      "$KTHREAD_DIR"/*)
        FOUND=true
        KTHREAD_FOUND=true
        warn "Detected running watchdog: PID ${proc_path##*/} -> ${exe_path}"
        ;;
    esac
  done
}

backup_evidence() {
  local backup_dir="$1"
  local source_file relative_path destination

  install -d -m 0700 -- "$backup_dir"

  {
    printf 'Collected: %s\n' "$(date --iso-8601=seconds)"
    printf 'Hostname: %s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf '\nFile metadata and SHA-256 hashes:\n'
    find "$KWORKER_DIR" "$KTHREAD_DIR" -xdev -maxdepth 2 -type f \
      -exec stat -c '%y %U %G %a %s %n' {} \; 2>/dev/null || true
    find "$KWORKER_DIR" "$KTHREAD_DIR" -xdev -maxdepth 2 -type f \
      -exec sha256sum {} \; 2>/dev/null || true
  } >"$backup_dir/evidence.txt"
  chmod 0600 "$backup_dir/evidence.txt"

  for source_file in "$KWORKER_UNIT" "$KTHREAD_UNIT" "$KTHREAD_CRON"; do
    [[ -f "$source_file" ]] || continue
    relative_path="${source_file#/}"
    destination="$backup_dir/$relative_path"
    install -d -m 0700 -- "${destination%/*}"
    install -m 0600 -- "$source_file" "$destination"
  done

  ok "Evidence and text configuration backed up to ${backup_dir}"
}

stop_payload_processes() {
  local proc_path exe_path pid
  local -a pids=()

  for proc_path in /proc/[0-9]*; do
    [[ -e "$proc_path/exe" ]] || continue
    exe_path="$(readlink -f "$proc_path/exe" 2>/dev/null || true)"
    case "$exe_path" in
      "$KWORKER_DIR"/*|"$KTHREAD_DIR"/*)
        pids+=("${proc_path##*/}")
        ;;
    esac
  done

  ((${#pids[@]} == 0)) && return 0

  info "Stopping malicious processes: ${pids[*]}"
  kill -TERM -- "${pids[@]}" 2>/dev/null || true
  sleep 2

  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

remove_unit() {
  local unit_name="$1"
  local unit_file="$2"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "$unit_name" 2>/dev/null || true
  fi
  [[ -e "$unit_file" || -L "$unit_file" ]] && rm -f -- "$unit_file"
}

clean() {
  local timestamp backup_dir
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup_dir="${BACKUP_ROOT}/${timestamp}"

  backup_evidence "$backup_dir"

  if $KWORKER_FOUND; then
    remove_unit "kworker.service" "$KWORKER_UNIT"
  fi
  if $KTHREAD_FOUND; then
    remove_unit "kthread.service" "$KTHREAD_UNIT"
  fi

  stop_payload_processes

  if $KTHREAD_FOUND && [[ -f "$KTHREAD_CRON" ]] \
    && contains_pattern "$KTHREAD_CRON" '/var/local/kthreadd'; then
    rm -f -- "$KTHREAD_CRON"
  fi

  $KWORKER_FOUND && [[ -d "$KWORKER_DIR" ]] && rm -rf -- "$KWORKER_DIR"
  $KTHREAD_FOUND && [[ -d "$KTHREAD_DIR" ]] && rm -rf -- "$KTHREAD_DIR"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl reset-failed kworker.service kthread.service 2>/dev/null || true
  fi
}

verify() {
  local failed=false
  local proc_path exe_path mining_connections

  for proc_path in /proc/[0-9]*; do
    [[ -e "$proc_path/exe" ]] || continue
    exe_path="$(readlink -f "$proc_path/exe" 2>/dev/null || true)"
    case "$exe_path" in
      "$KWORKER_DIR"/*|"$KTHREAD_DIR"/*)
        error "Malicious process still running: PID ${proc_path##*/} -> ${exe_path}"
        failed=true
        ;;
    esac
  done

  for path in "$KWORKER_UNIT" "$KTHREAD_UNIT" "$KTHREAD_CRON" \
    "$KWORKER_DIR" "$KTHREAD_DIR"; do
    if [[ -e "$path" || -L "$path" ]]; then
      error "Residual path remains: ${path}"
      failed=true
    fi
  done

  if command -v ss >/dev/null 2>&1; then
    mining_connections="$(
      ss -Htpn 2>/dev/null \
        | grep -E ':(3333|7029|19999)([[:space:]]|$)' \
        || true
    )"
    if [[ -n "$mining_connections" ]]; then
      warn "A connection to a known mining-pool port remains."
      warn "This can be a short-lived TCP closing state or a different process; inspect it manually:"
      printf '%s\n' "$mining_connections"
    else
      ok "No active connection to the known mining-pool ports was found."
    fi
  fi

  if $failed; then
    die "Verification failed. Manual investigation is required."
  fi

  ok "Cleanup verified: no malicious payload or persistence remains."
}

main() {
  case "${1:-}" in
    "")
      ;;
    --apply)
      APPLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown option: $1"
      ;;
  esac

  (($# <= 1)) || die "Only one option is supported."

  if $APPLY && ((EUID != 0)); then
    die "Run with sudo or as root when using --apply."
  fi

  detect

  if ! $FOUND; then
    ok "Already configured. The known infection chain was not found."
    exit 0
  fi

  if ! $APPLY; then
    warn "Check-only mode: no changes were made."
    info "Review the findings, then run: sudo ./${SCRIPT_NAME} --apply"
    exit 2
  fi

  clean
  verify
}

main "$@"
