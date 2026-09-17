#!/usr/bin/env bash
# ==============================================================================
# WorkBuddy Toolbox (wb-toolbox)
# A lightweight power-tool CLI for WorkBuddy AI & CodeBuddy users.
#
# Key Features:
#   - Merge & unhide chat history across multiple accounts into the active session
#   - Save, list, and switch between multiple user profiles / accounts
#   - Inspect active authentication state, token expiration, and database health
#   - Automated fail-safe database and credential backups
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"
APP_NAME="WorkBuddy Toolbox"

# ------------------------------------------------------------------------------
# Colors & Formatting
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET="\033[0m"
  C_BOLD="\033[1m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_RED="\033[31m"
  C_CYAN="\033[36m"
  C_GRAY="\033[90m"
else
  C_RESET=""
  C_BOLD=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_CYAN=""
  C_GRAY=""
fi

log_info()    { echo -e "${C_CYAN}ℹ${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}✔${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_warn()    { echo -e "${C_YELLOW}⚠${C_RESET} ${C_YELLOW}$*${C_RESET}"; }
log_error()   { echo -e "${C_RED}✖${C_RESET} ${C_RED}$*${C_RESET}" >&2; }

# ------------------------------------------------------------------------------
# Path Resolution
# ------------------------------------------------------------------------------
HOME_DIR="${HOME}"

# WorkBuddy AI config and database locations
WORKBUDDY_DIR="${HOME_DIR}/.workbuddy-ai"
DB_FILE="${WORKBUDDY_DIR}/workbuddy.db"
SNAPSHOT_FILE="${WORKBUDDY_DIR}/storage/skeleton/account-snapshot.json"

# Auth storage path resolution (OS-dependent)
if [[ "${OSTYPE}" == "darwin"* ]]; then
  AUTH_DIR="${HOME_DIR}/Library/Application Support/CodeBuddyExtension/Data/Public/auth"
else
  AUTH_DIR="${HOME_DIR}/.local/share/CodeBuddyExtension/Data/Public/auth"
fi
AUTH_FILE="${AUTH_DIR}/workbuddy-desktop-ai.info"
LOGOUT_MARKER="${AUTH_FILE}.logged-out"

# Toolbox data & profiles storage
TOOLBOX_DIR="${HOME_DIR}/.workbuddy-toolbox"
PROFILES_DIR="${TOOLBOX_DIR}/profiles"
BACKUPS_DIR="${TOOLBOX_DIR}/backups"

mkdir -p "${PROFILES_DIR}" "${BACKUPS_DIR}"

# ------------------------------------------------------------------------------
# Helper: JSON Reader (jq with Python3 fallback)
# ------------------------------------------------------------------------------
read_json_value() {
  local json_file="$1"
  local json_path="$2"

  if [[ ! -f "${json_file}" ]]; then
    echo ""
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r "${json_path} // empty" "${json_file}" 2>/dev/null || echo ""
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    with open('${json_file}', 'r', encoding='utf-8') as f:
        data = json.load(f)
    keys = '${json_path}'.strip('.').split('.')
    val = data
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            val = None
            break
    if val is not None and not isinstance(val, (dict, list)):
        print(val)
except Exception:
    pass
" 2>/dev/null || echo ""
  elif command -v node >/dev/null 2>&1; then
    node -e "
try {
  const fs = require('fs');
  const data = JSON.parse(fs.readFileSync('${json_file}', 'utf8'));
  const keys = '${json_path}'.replace(/^\./, '').split('.');
  let val = data;
  for (const k of keys) {
    if (val && typeof val === 'object') val = val[k];
    else { val = undefined; break; }
  }
  if (val !== undefined && typeof val !== 'object') console.log(val);
} catch(e) {}
" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

format_timestamp() {
  local ts="$1"
  if [[ -z "${ts}" || "${ts}" == "null" ]]; then
    echo "N/A"
    return
  fi
  # Convert ms to seconds if needed
  if (( ts > 1000000000000 )); then
    ts=$(( ts / 1000 ))
  fi
  if [[ "${OSTYPE}" == "darwin"* ]]; then
    date -r "${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${ts}"
  else
    date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${ts}"
  fi
}

# ------------------------------------------------------------------------------
# Process & Lock Checks
# ------------------------------------------------------------------------------
is_app_running() {
  pgrep -f "WorkBuddy AI\.app|codebuddy-headless" >/dev/null 2>&1
}

assert_app_stopped() {
  local force="${1:-false}"
  if is_app_running; then
    if [[ "${force}" == "true" ]]; then
      log_warn "WorkBuddy is running. Terminating running processes (--force enabled)..."
      pkill -f "WorkBuddy AI\.app|codebuddy-headless" || true
      sleep 1
    else
      log_warn "WorkBuddy is currently running."
      echo -e "${C_YELLOW}Please close WorkBuddy AI (Cmd + Q) to safely apply changes, or use --force.${C_RESET}"
      read -rp "Do you want to terminate WorkBuddy now? [y/N]: " confirm
      if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        pkill -f "WorkBuddy AI\.app|codebuddy-headless" || true
        sleep 1
        log_success "WorkBuddy stopped."
      else
        log_error "Operation canceled to prevent database lock conflicts."
        exit 1
      fi
    fi
  fi
}

# ------------------------------------------------------------------------------
# Auth State Queries
# ------------------------------------------------------------------------------
get_active_uid() {
  read_json_value "${AUTH_FILE}" ".account.uid"
}

get_active_email() {
  read_json_value "${AUTH_FILE}" ".account.nickname"
}

get_active_uin() {
  read_json_value "${AUTH_FILE}" ".account.uin"
}

get_active_token_exp() {
  read_json_value "${AUTH_FILE}" ".auth.expiresAt"
}

# ------------------------------------------------------------------------------
# Backup Helpers
# ------------------------------------------------------------------------------
backup_database() {
  local tag="${1:-manual}"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_path="${BACKUPS_DIR}/workbuddy_${tag}_${timestamp}.db"

  if [[ -f "${DB_FILE}" ]]; then
    sqlite3 "${DB_FILE}" ".backup '${backup_path}'" 2>/dev/null || cp "${DB_FILE}" "${backup_path}"
    log_info "Database backed up to: ${C_GRAY}${backup_path}${C_RESET}"
    echo "${backup_path}"
  else
    echo ""
  fi
}

backup_auth_file() {
  local tag="${1:-manual}"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_path="${BACKUPS_DIR}/auth_${tag}_${timestamp}.info"

  if [[ -f "${AUTH_FILE}" ]]; then
    cp "${AUTH_FILE}" "${backup_path}"
    log_info "Auth credentials backed up to: ${C_GRAY}${backup_path}${C_RESET}"
  fi
}

# ------------------------------------------------------------------------------
# Command: Status
# ------------------------------------------------------------------------------
cmd_status() {
  echo -e "${C_BOLD}=== WorkBuddy AI Status ===${C_RESET}"
  
  # Process status
  if is_app_running; then
    echo -e "Application:      ${C_GREEN}● Running${C_RESET}"
  else
    echo -e "Application:      ${C_GRAY}○ Not running${C_RESET}"
  fi

  # Auth state
  if [[ -f "${LOGOUT_MARKER}" ]]; then
    echo -e "Login State:      ${C_YELLOW}Logged Out (Logout marker active)${C_RESET}"
  elif [[ -f "${AUTH_FILE}" ]]; then
    local uid email uin exp_ts exp_fmt
    uid="$(get_active_uid)"
    email="$(get_active_email)"
    uin="$(get_active_uin)"
    exp_ts="$(get_active_token_exp)"
    exp_fmt="$(format_timestamp "${exp_ts}")"

    echo -e "Login State:      ${C_GREEN}Authenticated${C_RESET}"
    echo -e "Active Email:     ${C_CYAN}${email:-<unknown>}${C_RESET}"
    echo -e "User ID (UID):    ${uid:-<none>}"
    echo -e "UIN:              ${uin:-<none>}"
    echo -e "Token Valid To:   ${exp_fmt}"
  else
    echo -e "Login State:      ${C_RED}No auth file found${C_RESET}"
  fi

  # Database metrics
  if [[ -f "${DB_FILE}" ]]; then
    local active_uid total_sessions user_sessions other_sessions deleted_sessions
    active_uid="$(get_active_uid)"

    total_sessions=$(sqlite3 "${DB_FILE}" "SELECT count(*) FROM sessions;" 2>/dev/null || echo 0)
    deleted_sessions=$(sqlite3 "${DB_FILE}" "SELECT count(*) FROM sessions WHERE deleted_at IS NOT NULL;" 2>/dev/null || echo 0)

    if [[ -n "${active_uid}" ]]; then
      user_sessions=$(sqlite3 "${DB_FILE}" "SELECT count(*) FROM sessions WHERE user_id = '${active_uid}' AND deleted_at IS NULL;" 2>/dev/null || echo 0)
      other_sessions=$(sqlite3 "${DB_FILE}" "SELECT count(*) FROM sessions WHERE (user_id != '${active_uid}' OR user_id = '' OR user_id IS NULL) AND deleted_at IS NULL;" 2>/dev/null || echo 0)
    else
      user_sessions=0
      other_sessions="${total_sessions}"
    fi

    echo -e "\n${C_BOLD}--- Chat History & Database ---${C_RESET}"
    echo -e "Database Path:    ${C_GRAY}${DB_FILE}${C_RESET}"
    echo -e "Total Sessions:   ${C_BOLD}${total_sessions}${C_RESET}"
    echo -e "Visible to User:  ${C_GREEN}${user_sessions}${C_RESET}"
    if (( other_sessions > 0 )); then
      echo -e "Hidden (Other UID): ${C_YELLOW}${other_sessions}${C_RESET} ${C_YELLOW}(Run 'merge' to make them visible)${C_RESET}"
    else
      echo -e "Hidden (Other UID): 0 (All active sessions mapped)"
    fi
    if (( deleted_sessions > 0 )); then
      echo -e "Soft-Deleted:     ${C_GRAY}${deleted_sessions}${C_RESET}"
    fi
  fi

  # Saved profiles
  local profile_count
  profile_count=$(find "${PROFILES_DIR}" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "\n${C_BOLD}--- Saved Profiles ---${C_RESET}"
  echo -e "Saved Profiles:   ${profile_count} (Run 'list' to view)"
}

# ------------------------------------------------------------------------------
# Command: Merge History (Make all chats visible in active session)
# ------------------------------------------------------------------------------
cmd_merge() {
  local mode="${1:-active}"
  local unhide_deleted="${2:-false}"
  local force="${3:-false}"

  assert_app_stopped "${force}"

  if [[ ! -f "${DB_FILE}" ]]; then
    log_error "WorkBuddy database not found at: ${DB_FILE}"
    exit 1
  fi

  # Backup database before modifying
  backup_database "pre_merge" >/dev/null

  local active_uid
  active_uid="$(get_active_uid)"

  if [[ -z "${active_uid}" && "${mode}" == "active" ]]; then
    log_warn "No active logged-in user detected. Falling back to universal mode ('')."
    mode="universal"
  fi

  local affected=0
  if [[ "${mode}" == "universal" ]]; then
    # In universal mode, set user_id = '' which WorkBuddy's SessionRepository
    # explicitly treats as shared/legacy: visible to ANY logged-in account.
    affected=$(sqlite3 "${DB_FILE}" "UPDATE sessions SET user_id = '' WHERE user_id != '' AND user_id IS NOT NULL; SELECT changes();" 2>/dev/null || echo 0)
    log_success "Universal merge complete: All sessions marked as shared (visible to any account)."
  else
    # In active mode, reassign all sessions to the currently active UID.
    affected=$(sqlite3 "${DB_FILE}" "UPDATE sessions SET user_id = '${active_uid}' WHERE user_id != '${active_uid}' OR user_id IS NULL OR user_id = ''; SELECT changes();" 2>/dev/null || echo 0)
    log_success "Merge complete: Reassigned ${C_BOLD}${affected}${C_RESET}${C_GREEN} sessions to active user [${active_uid}].${C_RESET}"
  fi

  if [[ "${unhide_deleted}" == "true" ]]; then
    local restored
    restored=$(sqlite3 "${DB_FILE}" "UPDATE sessions SET deleted_at = NULL WHERE deleted_at IS NOT NULL; SELECT changes();" 2>/dev/null || echo 0)
    log_success "Restored ${restored} soft-deleted sessions."
  fi

  local total_now
  total_now=$(sqlite3 "${DB_FILE}" "SELECT count(*) FROM sessions WHERE deleted_at IS NULL;" 2>/dev/null || echo 0)
  log_info "Total chat sessions now accessible: ${C_BOLD}${total_now}${C_RESET}"
  echo -e "\n${C_CYAN}Now launch WorkBuddy AI. All conversations will appear in your sidebar!${C_RESET}"
}

# ------------------------------------------------------------------------------
# Command: Save Profile
# ------------------------------------------------------------------------------
cmd_save() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    log_error "Profile name required. Usage: wb-toolbox save <name>"
    exit 1
  fi

  if [[ ! -f "${AUTH_FILE}" ]]; then
    log_error "No active authentication session found at: ${AUTH_FILE}"
    exit 1
  fi

  local uid email
  uid="$(get_active_uid)"
  email="$(get_active_email)"

  local target="${PROFILES_DIR}/${name}.json"
  cp "${AUTH_FILE}" "${target}"
  log_success "Profile '${name}' saved successfully!"
  echo -e "  Account: ${C_CYAN}${email}${C_RESET} (${uid})"
  echo -e "  File:    ${C_GRAY}${target}${C_RESET}"
}

# ------------------------------------------------------------------------------
# Command: List Profiles
# ------------------------------------------------------------------------------
cmd_list() {
  echo -e "${C_BOLD}Saved WorkBuddy Profiles:${C_RESET}\n"
  local active_uid
  active_uid="$(get_active_uid)"

  local count=0
  for profile in "${PROFILES_DIR}"/*.json; do
    [[ -e "${profile}" ]] || continue
    count=$(( count + 1 ))
    local name
    name="$(basename "${profile}" .json)"
    local email uid exp_ts exp_fmt
    email="$(read_json_value "${profile}" ".account.nickname")"
    uid="$(read_json_value "${profile}" ".account.uid")"
    exp_ts="$(read_json_value "${profile}" ".auth.expiresAt")"
    exp_fmt="$(format_timestamp "${exp_ts}")"

    if [[ "${uid}" == "${active_uid}" ]]; then
      echo -e "  ${C_GREEN}● ${name}${C_RESET} ${C_BOLD}(active)${C_RESET}"
    else
      echo -e "  ${C_GRAY}○ ${name}${C_RESET}"
    fi
    echo -e "    Email:     ${email:-<unknown>}"
    echo -e "    UID:       ${uid:-<unknown>}"
    echo -e "    Expires:   ${exp_fmt}"
    echo ""
  done

  if (( count == 0 )); then
    echo -e "  ${C_GRAY}No saved profiles yet. Save current account with:${C_RESET}"
    echo -e "  ${C_CYAN}wb-toolbox save <profile-name>${C_RESET}\n"
  fi
}

# ------------------------------------------------------------------------------
# Command: Switch Profile
# ------------------------------------------------------------------------------
cmd_switch() {
  local name="${1:-}"
  local force="${2:-false}"
  local auto_merge="${3:-true}"

  if [[ -z "${name}" ]]; then
    log_error "Profile name required. Usage: wb-toolbox switch <name>"
    exit 1
  fi

  local target_profile="${PROFILES_DIR}/${name}.json"
  if [[ ! -f "${target_profile}" ]]; then
    log_error "Profile '${name}' not found in ${PROFILES_DIR}"
    exit 1
  fi

  assert_app_stopped "${force}"

  # 1. Back up current active auth file
  backup_auth_file "pre_switch"

  # 2. Copy target profile to active auth path
  mkdir -p "${AUTH_DIR}"
  cp "${target_profile}" "${AUTH_FILE}"
  chmod 600 "${AUTH_FILE}"

  # 3. Remove logout marker if present
  if [[ -f "${LOGOUT_MARKER}" ]]; then
    rm -f "${LOGOUT_MARKER}"
    log_info "Removed logout marker."
  fi

  # 4. Sync UI skeleton cache (prevents header/avatar mismatch on startup)
  local target_uid target_email
  target_uid="$(read_json_value "${target_profile}" ".account.uid")"
  target_email="$(read_json_value "${target_profile}" ".account.nickname")"

  if [[ -f "${SNAPSHOT_FILE}" && -n "${target_uid}" ]]; then
    mkdir -p "$(dirname "${SNAPSHOT_FILE}")"
    cat > "${SNAPSHOT_FILE}" <<EOF
{
  "primary": {
    "version": 1,
    "uid": "${target_uid}",
    "nickname": "${target_email}",
    "type": "personal",
    "editionType": "free",
    "isPro": false,
    "isAdmin": false,
    "oneidAccountId": "",
    "savedAt": $(date +%s)000
  }
}
EOF
    log_info "UI skeleton cache synchronized."
  fi

  log_success "Switched to profile '${name}' (${target_email})!"

  # 5. Automatically merge history so all chats appear in the switched account
  if [[ "${auto_merge}" == "true" ]]; then
    log_info "Synchronizing chat history to active account..."
    cmd_merge "active" "false" "true"
  fi

  echo -e "\n${C_GREEN}Ready! Launch WorkBuddy AI to start using '${name}'.${C_RESET}"
}

# ------------------------------------------------------------------------------
# Command: Delete Profile
# ------------------------------------------------------------------------------
cmd_delete() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    log_error "Profile name required. Usage: wb-toolbox delete <name>"
    exit 1
  fi

  local target_profile="${PROFILES_DIR}/${name}.json"
  if [[ -f "${target_profile}" ]]; then
    rm -f "${target_profile}"
    log_success "Profile '${name}' deleted."
  else
    log_error "Profile '${name}' does not exist."
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Command: Install (Create symlink to PATH)
# ------------------------------------------------------------------------------
cmd_install() {
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  chmod +x "${script_path}"

  local target_dir=""
  if [[ -d "${HOME}/.local/bin" && ":${PATH}:" == *":${HOME}/.local/bin:"* ]]; then
    target_dir="${HOME}/.local/bin"
  elif [[ -w "/usr/local/bin" ]]; then
    target_dir="/usr/local/bin"
  elif [[ -d "${HOME}/bin" && ":${PATH}:" == *":${HOME}/bin:"* ]]; then
    target_dir="${HOME}/bin"
  else
    mkdir -p "${HOME}/.local/bin"
    target_dir="${HOME}/.local/bin"
  fi

  ln -sf "${script_path}" "${target_dir}/wb"
  ln -sf "${script_path}" "${target_dir}/workbuddy-toolbox"
  log_success "Installed successfully as 'wb' and 'workbuddy-toolbox' in ${target_dir}!"
  echo -e "You can now run: ${C_CYAN}wb status${C_RESET} or ${C_CYAN}wb merge${C_RESET} from anywhere."
}

# ------------------------------------------------------------------------------
# Help Screen
# ------------------------------------------------------------------------------
show_help() {
  cat <<EOF
${C_BOLD}${APP_NAME} v${VERSION}${C_RESET}
Manage WorkBuddy accounts, restore lost chat history, and seamlessly switch profiles.

${C_BOLD}USAGE:${C_RESET}
  wb <command> [options]
  ./wb-toolbox.sh <command> [options]

${C_BOLD}PRIMARY COMMANDS:${C_RESET}
  ${C_CYAN}merge${C_RESET}, ${C_CYAN}-m${C_RESET}              Merge all chat history from all accounts into the active session
                        (Options: --universal / --all to make chats shared across all accounts,
                                  --restore-deleted to unhide soft-deleted chats,
                                  --force to auto-terminate running app)
  ${C_CYAN}status${C_RESET}, ${C_CYAN}-s${C_RESET}             Display active account info, token health, and session stats
  ${C_CYAN}save <name>${C_RESET}           Save current logged-in credentials as a named profile
  ${C_CYAN}switch <name>${C_RESET}         Switch to a saved profile and auto-sync chat history
  ${C_CYAN}list${C_RESET}, ${C_CYAN}-l${C_RESET}               List all saved profiles and show the active one
  ${C_CYAN}delete <name>${C_RESET}         Delete a saved profile

${C_BOLD}UTILITY COMMANDS:${C_RESET}
  ${C_CYAN}backup${C_RESET}                Create an instant backup of current database & credentials
  ${C_CYAN}install${C_RESET}               Install 'wb' CLI globally to your PATH
  ${C_CYAN}help${C_RESET}, ${C_CYAN}-h${C_RESET}               Show this help message

${C_BOLD}EXAMPLES:${C_RESET}
  wb merge                      # Reassign all existing conversations to active account
  wb merge --universal          # Make all chats visible to every account
  wb status                     # Check token expiry and conversation counts
  wb save work                  # Save current login as 'work'
  wb switch personal            # Switch to 'personal' account
  wb list                       # View all stored profiles

EOF
}

# ------------------------------------------------------------------------------
# Entrypoint Dispatcher
# ------------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  shift || true

  case "${cmd}" in
    merge|-m|--merge)
      local mode="active"
      local unhide_deleted="false"
      local force="false"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --universal|--all|-a) mode="universal" ;;
          --restore-deleted|--unhide) unhide_deleted="true" ;;
          --force|-f) force="true" ;;
        esac
        shift
      done
      cmd_merge "${mode}" "${unhide_deleted}" "${force}"
      ;;

    status|-s|--status)
      cmd_status
      ;;

    save)
      cmd_save "$@"
      ;;

    switch)
      local name="${1:-}"
      local force="false"
      local auto_merge="true"
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --force|-f) force="true" ;;
          --no-merge) auto_merge="false" ;;
        esac
        shift
      done
      cmd_switch "${name}" "${force}" "${auto_merge}"
      ;;

    list|-l|--list)
      cmd_list
      ;;

    delete|rm)
      cmd_delete "$@"
      ;;

    backup)
      backup_database "manual"
      backup_auth_file "manual"
      log_success "Backup completed."
      ;;

    install)
      cmd_install
      ;;

    help|-h|--help)
      show_help
      ;;

    *)
      log_error "Unknown command: ${cmd}"
      echo "Run 'wb help' for usage instructions."
      exit 1
      ;;
  esac
}

main "$@"
