#!/usr/bin/env bash
# claspalt - Multi-account credential manager for clasp
# Usage: claspalt [CLASP_ARGS...]
#
# Switches to the correct Google account credentials before running clasp.
# Credentials are stored in ~/.config/claspalt/{account}.json
# Project account configuration is stored in claspConfig.txt

set -euo pipefail

# Configuration paths
CLASPALT_CONFIG_DIR="$HOME/.config/claspalt"
CLASP_CREDENTIALS="$HOME/.clasprc.json"
LOCAL_CONFIG_FILE="claspConfig.txt"
OLD_DEPLOYMENT_FILE="deploymentId.txt"

# ============================================================================
# Helper Functions
# ============================================================================

##
# Displays an error message and exits
# @param {string} $1 - Error message to display
##
show_error() {
  echo "❌ ERROR: $1" >&2
  exit 1
} # End of function show_error()

##
# Checks if clasp is installed
##
check_clasp_installed() {
  if ! command -v clasp &> /dev/null; then
    show_error "clasp is not installed. Install it with: npm install -g @google/clasp"
  fi
} # End of function check_clasp_installed()

##
# Ensures the global claspalt config directory exists with proper permissions
##
ensure_config_dir() {
  if [[ ! -d "$CLASPALT_CONFIG_DIR" ]]; then
    mkdir -p "$CLASPALT_CONFIG_DIR"
    chmod 700 "$CLASPALT_CONFIG_DIR"
    echo "📁 Created credentials directory: $CLASPALT_CONFIG_DIR" >&2
  fi
} # End of function ensure_config_dir()

##
# Lists all available account names from the config directory
# @returns List of account names (without .json extension)
##
list_accounts() {
  if [[ -d "$CLASPALT_CONFIG_DIR" ]]; then
    find "$CLASPALT_CONFIG_DIR" -maxdepth 1 -name "*.json" -exec basename {} .json \; 2>/dev/null | sort
  fi
} # End of function list_accounts()

##
# Reads a value from claspConfig.txt
# @param {string} $1 - Key to read (e.g., "account" or "deploymentId")
# @returns The value associated with the key, or empty string if not found
##
read_config_value() {
  local key="$1"
  if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    # Use anchored regex to match key at start of line only
    # Use || true to avoid exit on no match due to set -e + pipefail
    grep "^${key}=" "$LOCAL_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
  fi
} # End of function read_config_value()

##
# Writes or updates a value in claspConfig.txt
# @param {string} $1 - Key to write
# @param {string} $2 - Value to write
##
write_config_value() {
  local key="$1"
  local value="$2"

  if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    # Check if key exists using fixed string matching
    if grep -q "^${key}=" "$LOCAL_CONFIG_FILE" 2>/dev/null; then
      # Update existing key using a temp file for compatibility
      local temp_file
      temp_file=$(mktemp)
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "${key}="* ]]; then
          echo "${key}=${value}"
        else
          echo "$line"
        fi
      done < "$LOCAL_CONFIG_FILE" > "$temp_file"
      mv "$temp_file" "$LOCAL_CONFIG_FILE"
    else
      # Append new key
      echo "${key}=${value}" >> "$LOCAL_CONFIG_FILE"
    fi
  else
    # Create new file
    echo "${key}=${value}" > "$LOCAL_CONFIG_FILE"
  fi
} # End of function write_config_value()

##
# Validates that an account name contains only allowed characters
# @param {string} $1 - Account name to validate
# @returns 0 if valid, 1 if invalid
##
validate_account_name() {
  local name="$1"
  if [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    return 0
  else
    return 1
  fi
} # End of function validate_account_name()

##
# Displays help text and usage information
##
show_help() {
  cat << 'EOF'
claspalt - Multi-account credential manager for clasp

USAGE:
  claspalt [OPTIONS]
  claspalt [CLASP_COMMANDS...]

OPTIONS:
  -h, --help     Show this help
  -l, --list     List available accounts
  -e, --edit     Interactive account management

DESCRIPTION:
  claspalt allows managing multiple Google accounts for clasp.
  Credentials are stored in ~/.config/claspalt/{account}.json
  Project configuration is saved in claspConfig.txt

EXAMPLES:
  claspalt --help              Show this help
  claspalt --list              List all accounts
  claspalt --edit              Open interactive account manager
  claspalt push                Run 'clasp push' with the configured account
  claspalt deploy -d "v1.0"    Run 'clasp deploy' with the configured account

FILES:
  ~/.config/claspalt/          Credentials directory
  claspConfig.txt              Project configuration (account and deploymentId)

EOF
} # End of function show_help()

##
# Lists all available accounts for CLI output
# Marks the active account if claspConfig.txt exists in current directory
##
list_accounts_cli() {
  local accounts
  accounts=$(list_accounts)

  if [[ -z "$accounts" ]]; then
    echo "No saved accounts."
    echo "Use 'claspalt --edit' to add an account."
    return
  fi

  # Check for active account in current directory
  local active_account=""
  if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    active_account=$(read_config_value "account")
  fi

  # Print each account, marking the active one
  while IFS= read -r account; do
    if [[ "$account" == "$active_account" ]]; then
      echo "$account (active)"
    else
      echo "$account"
    fi
  done <<< "$accounts"
} # End of function list_accounts_cli()

# Global state for interactive UI (Bash 3.2 compatible - no namerefs)
_UI_ACCOUNTS=()
_UI_SELECTED=()
_UI_CURSOR=0
_UI_MESSAGE=""
_UI_ACTIVE_ACCOUNT=""

##
# Draws the interactive account management UI
# Uses global _UI_* variables for state (Bash 3.2 compatible)
##
draw_edit_ui() {
  # Clear screen
  tput clear

  # Header
  echo "══════════════════════════════════════════"
  echo "       CLASPALT - Account Management"
  echo "══════════════════════════════════════════"
  echo ""

  # Account list
  if [[ ${#_UI_ACCOUNTS[@]} -eq 0 ]]; then
    echo "  (No saved accounts)"
  else
    local i=0
    for account in "${_UI_ACCOUNTS[@]}"; do
      local prefix="  "
      local checkbox="[ ]"
      local suffix=""

      # Cursor indicator
      if [[ $i -eq $_UI_CURSOR ]]; then
        prefix="> "
      fi

      # Selection checkbox
      if [[ ${_UI_SELECTED[$i]} -eq 1 ]]; then
        checkbox="[x]"
      fi

      # Active account marker
      if [[ "$account" == "$_UI_ACTIVE_ACCOUNT" ]]; then
        suffix=" (active)"
      fi

      echo "${prefix}${checkbox} $((i + 1)). ${account}${suffix}"
      ((i++)) || true
    done
  fi

  echo ""

  # Status message if any
  if [[ -n "$_UI_MESSAGE" ]]; then
    echo "$_UI_MESSAGE"
    echo ""
  fi

  # Footer with commands
  echo "──────────────────────────────────────────"
  echo "  [A]dd   [D]elete selected   [Q]uit"
  echo "  Space: select/deselect"
  echo "  ↑/↓: navigate"
  echo "──────────────────────────────────────────"
} # End of function draw_edit_ui()

##
# Deletes selected accounts after confirmation
# Uses global _UI_* variables for state (Bash 3.2 compatible)
# @returns 0 if deleted, 1 if cancelled
##
delete_selected_accounts() {
  # Count selected accounts
  local count=0
  local will_delete_active=false
  local i=0
  for account in "${_UI_ACCOUNTS[@]}"; do
    if [[ ${_UI_SELECTED[$i]} -eq 1 ]]; then
      ((count++)) || true
      if [[ "$account" == "$_UI_ACTIVE_ACCOUNT" ]]; then
        will_delete_active=true
      fi
    fi
    ((i++)) || true
  done

  if [[ $count -eq 0 ]]; then
    return 1
  fi

  # Show warning if deleting active account
  if [[ "$will_delete_active" == true ]]; then
    echo ""
    echo "⚠️  WARNING: You are about to delete the active account in this project."
    echo "   You will need to select another account the next time you use claspalt."
  fi

  # Confirmation prompt
  echo ""
  local plural=""
  [[ $count -gt 1 ]] && plural="s"
  read -r -p "Are you sure you want to delete $count account${plural}? (y/N): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    return 1
  fi

  # Delete selected account files
  i=0
  for account in "${_UI_ACCOUNTS[@]}"; do
    if [[ ${_UI_SELECTED[$i]} -eq 1 ]]; then
      rm -f "$CLASPALT_CONFIG_DIR/${account}.json"
    fi
    ((i++)) || true
  done

  return 0
} # End of function delete_selected_accounts()

##
# Reloads the account list into UI state arrays
# Uses global _UI_* variables (Bash 3.2 compatible)
##
reload_ui_accounts() {
  _UI_ACCOUNTS=()
  _UI_SELECTED=()
  local accounts
  accounts=$(list_accounts)
  if [[ -n "$accounts" ]]; then
    while IFS= read -r account; do
      _UI_ACCOUNTS+=("$account")
      _UI_SELECTED+=(0)
    done <<< "$accounts"
  fi
  # Clamp cursor to valid range
  if [[ ${#_UI_ACCOUNTS[@]} -eq 0 ]]; then
    _UI_CURSOR=0
  elif [[ $_UI_CURSOR -ge ${#_UI_ACCOUNTS[@]} ]]; then
    _UI_CURSOR=$((${#_UI_ACCOUNTS[@]} - 1))
  fi
} # End of function reload_ui_accounts()

##
# Interactive account management UI (3270-terminal style)
# Allows viewing, adding, and deleting accounts
##
edit_accounts_ui() {
  # Require interactive terminal
  if [[ ! -t 0 ]]; then
    show_error "Edit mode requires an interactive terminal"
  fi

  ensure_config_dir

  # Initialize UI state
  _UI_ACCOUNTS=()
  _UI_SELECTED=()
  _UI_CURSOR=0
  _UI_MESSAGE=""

  # Get active account if in a project directory
  _UI_ACTIVE_ACCOUNT=""
  if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    _UI_ACTIVE_ACCOUNT=$(read_config_value "account")
  fi

  # Initial load
  reload_ui_accounts

  # Main UI loop
  while true; do
    draw_edit_ui
    _UI_MESSAGE=""

    # Read single keypress
    local key
    IFS= read -rsn1 key

    # Handle escape sequences (arrow keys)
    if [[ "$key" == $'\e' ]]; then
      local seq
      IFS= read -rsn2 -t 0.1 seq || true
      case "$seq" in
        '[A') # Up arrow
          if [[ ${#_UI_ACCOUNTS[@]} -gt 0 ]] && [[ $_UI_CURSOR -gt 0 ]]; then
            ((_UI_CURSOR--)) || true
          fi
          ;;
        '[B') # Down arrow
          if [[ ${#_UI_ACCOUNTS[@]} -gt 0 ]] && [[ $_UI_CURSOR -lt $((${#_UI_ACCOUNTS[@]} - 1)) ]]; then
            ((_UI_CURSOR++)) || true
          fi
          ;;
      esac
      continue
    fi

    # Handle regular keys
    case "$key" in
      ' ') # Space - toggle selection
        if [[ ${#_UI_ACCOUNTS[@]} -gt 0 ]]; then
          if [[ ${_UI_SELECTED[$_UI_CURSOR]} -eq 0 ]]; then
            _UI_SELECTED[$_UI_CURSOR]=1
          else
            _UI_SELECTED[$_UI_CURSOR]=0
          fi
        fi
        ;;
      [Aa]) # A - Add account
        tput clear
        local new_account
        new_account=$(create_new_account)
        if [[ -n "$new_account" ]]; then
          reload_ui_accounts
          _UI_MESSAGE="✅ Account '$new_account' added"
        fi
        ;;
      [Dd]) # D - Delete selected
        if delete_selected_accounts; then
          reload_ui_accounts
          _UI_MESSAGE="✅ Accounts deleted"
        else
          # Check if nothing was selected
          local has_selection=false
          for s in "${_UI_SELECTED[@]}"; do
            [[ $s -eq 1 ]] && has_selection=true && break
          done
          if [[ "$has_selection" == false ]] && [[ ${#_UI_ACCOUNTS[@]} -gt 0 ]]; then
            _UI_MESSAGE="⚠️  No accounts selected"
          fi
        fi
        ;;
      [Qq]) # Q - Quit
        tput clear
        # Clean up global state
        _UI_ACCOUNTS=()
        _UI_SELECTED=()
        _UI_CURSOR=0
        _UI_MESSAGE=""
        _UI_ACTIVE_ACCOUNT=""
        return
        ;;
    esac
  done
} # End of function edit_accounts_ui()

##
# Prompts user to select an existing account or create a new one
# Uses a loop instead of recursion to avoid stack overflow
# @returns Selected or created account name via echo
##
prompt_account_selection() {
  while true; do
    local accounts
    accounts=$(list_accounts)

    # All menu output goes to stderr so it displays when called via $()
    echo "" >&2
    echo "🔐 Select a Google account:" >&2
    echo "" >&2

    local count=0
    local account_array=()

    if [[ -n "$accounts" ]]; then
      while IFS= read -r account; do
        count=$((count + 1))
        account_array+=("$account")
        echo "  $count) $account" >&2
      done <<< "$accounts"
      echo "" >&2
    else
      echo "  (No saved accounts)" >&2
      echo "" >&2
    fi

    echo "  N) Create new account" >&2
    echo "" >&2

    local choice
    read -r -p "Selection (number or N): " choice

    if [[ "$choice" =~ ^[Nn]$ ]]; then
      create_new_account
      return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
      # Only the account name goes to stdout (return value)
      echo "${account_array[$((choice - 1))]}"
      return
    else
      echo "❌ Invalid selection. Try again." >&2
    fi
  done
} # End of function prompt_account_selection()

##
# Creates a new account by running clasp login and saving credentials
# Uses a loop instead of recursion to avoid stack overflow
# @returns The new account name via echo
##
create_new_account() {
  ensure_config_dir

  while true; do
    local name

    # All prompts go to stderr so they display when called via $()
    echo "" >&2
    read -r -p "Name for the new account (letters, numbers, hyphens and underscores only): " name

    # Validate name
    if ! validate_account_name "$name"; then
      echo "❌ Invalid name. Use only letters, numbers, hyphens and underscores." >&2
      continue
    fi

    # Check if account already exists
    if [[ -f "$CLASPALT_CONFIG_DIR/${name}.json" ]]; then
      echo "❌ An account with that name already exists." >&2
      continue
    fi

    echo "" >&2
    echo "⚠️  IMPORTANT: Make sure the active browser is connected to the correct Google account." >&2
    echo "" >&2
    read -r -p "Press Enter when ready to continue..."

    echo "" >&2
    echo "🔑 Logging in with clasp..." >&2

    # Run clasp login (redirect stdout to stderr so it doesn't pollute return value)
    if ! clasp login >&2; then
      show_error "clasp login failed"
    fi

    # Save credentials atomically (copy to temp, then move)
    if [[ -f "$CLASP_CREDENTIALS" ]]; then
      local temp_file
      temp_file=$(mktemp)
      cp "$CLASP_CREDENTIALS" "$temp_file"
      chmod 600 "$temp_file"
      mv "$temp_file" "$CLASPALT_CONFIG_DIR/${name}.json"
      echo "" >&2
      echo "✅ Credentials saved for account: $name" >&2
    else
      show_error "Credentials not found in $CLASP_CREDENTIALS"
    fi

    # Only the account name goes to stdout (return value)
    echo "$name"
    return
  done
} # End of function create_new_account()

##
# Switches to the specified account by copying its credentials
# @param {string} $1 - Account name to switch to
##
switch_to_account() {
  local account="$1"
  local account_file="$CLASPALT_CONFIG_DIR/${account}.json"

  if [[ ! -f "$account_file" ]]; then
    echo ""
    echo "⚠️  Credentials not found for account: $account"
    echo ""
    echo "What would you like to do?"
    echo "  1) Create the account '$account' now"
    echo "  2) Select another account"
    echo ""

    local choice
    read -r -p "Selection [1/2]: " choice

    if [[ "$choice" == "1" ]]; then
      ensure_config_dir

      echo ""
      echo "⚠️  IMPORTANT: Make sure the active browser is connected to the correct Google account."
      echo ""
      read -r -p "Press Enter when ready to continue..."

      echo ""
      echo "🔑 Logging in with clasp..."

      if ! clasp login; then
        show_error "clasp login failed"
      fi

      if [[ -f "$CLASP_CREDENTIALS" ]]; then
        # Atomic copy
        local temp_file
        temp_file=$(mktemp)
        cp "$CLASP_CREDENTIALS" "$temp_file"
        chmod 600 "$temp_file"
        mv "$temp_file" "$account_file"
        echo ""
        echo "✅ Credentials saved for account: $account"
      else
        show_error "Credentials not found in $CLASP_CREDENTIALS"
      fi
    else
      local new_account
      new_account=$(prompt_account_selection)
      write_config_value "account" "$new_account"
      account="$new_account"
      account_file="$CLASPALT_CONFIG_DIR/${account}.json"
    fi
  fi

  # Copy credentials atomically to clasp's expected location
  local temp_file
  temp_file=$(mktemp)
  cp "$account_file" "$temp_file"
  chmod 600 "$temp_file"
  mv "$temp_file" "$CLASP_CREDENTIALS"
} # End of function switch_to_account()

##
# Migrates from old deploymentId.txt to new claspConfig.txt format
##
migrate_from_old_format() {
  echo ""
  echo "📋 Old deploymentId.txt file detected. Migrating to the new format..."

  # Read old deployment ID
  local deployment_id
  deployment_id=$(<"$OLD_DEPLOYMENT_FILE")
  deployment_id=${deployment_id//$'\r'/}
  deployment_id="${deployment_id#"${deployment_id%%[![:space:]]*}"}"
  deployment_id="${deployment_id%"${deployment_id##*[![:space:]]}"}"

  # Prompt for account selection
  local account
  account=$(prompt_account_selection)

  # Write new config file
  write_config_value "deploymentId" "$deployment_id"
  write_config_value "account" "$account"

  # Remove old file
  rm -f "$OLD_DEPLOYMENT_FILE"

  echo ""
  echo "✅ Migration completed. New file: $LOCAL_CONFIG_FILE"
  echo "   Old file deleted: $OLD_DEPLOYMENT_FILE"
} # End of function migrate_from_old_format()

##
# Initializes a new project configuration
##
init_new_project() {
  echo ""
  echo "📋 No project configuration found."

  # Prompt for account selection
  local account
  account=$(prompt_account_selection)

  # Write config file with account
  write_config_value "account" "$account"

  echo ""
  echo "✅ Configuration saved to $LOCAL_CONFIG_FILE"
} # End of function init_new_project()

# ============================================================================
# Main Logic
# ============================================================================

main() {
  # Check clasp is installed
  check_clasp_installed

  # Ensure config directory exists
  ensure_config_dir

  local account=""

  # Determine configuration state and get account
  if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    # claspConfig.txt exists - read account from it
    account=$(read_config_value "account")

    if [[ -z "$account" ]]; then
      # Config exists but no account set - prompt for one
      echo ""
      echo "⚠️  The file $LOCAL_CONFIG_FILE exists but has no account configured."
      account=$(prompt_account_selection)
      write_config_value "account" "$account"
    fi

  elif [[ -f "$OLD_DEPLOYMENT_FILE" ]]; then
    # Old format exists - migrate
    migrate_from_old_format
    account=$(read_config_value "account")

  else
    # No config at all - initialize
    init_new_project
    account=$(read_config_value "account")
  fi

  # Switch to the account
  switch_to_account "$account"

  # If no arguments passed, just confirm the switch
  if [[ $# -eq 0 ]]; then
    echo ""
    echo "✅ Active account: $account"
    echo "💡 Use 'claspalt <command>' to run clasp commands"
    exit 0
  fi

  # Run clasp with all provided arguments
  exec clasp "$@"
} # End of function main()

# ============================================================================
# CLI Flag Handling (processed before main to work without clasp installed)
# ============================================================================

##
# Parses CLI flags and exits if a flag is handled
# Must be called before main() to allow --help/--list/--edit without clasp
# @param {string} $@ - All script arguments
##
parse_flags_or_exit() {
  case "${1:-}" in
    --help|-h)
      [[ $# -gt 1 ]] && show_error "Option $1 does not accept additional arguments"
      show_help
      exit 0
      ;;
    --list|-l)
      [[ $# -gt 1 ]] && show_error "Option $1 does not accept additional arguments"
      list_accounts_cli
      exit 0
      ;;
    --edit|-e)
      [[ $# -gt 1 ]] && show_error "Option $1 does not accept additional arguments"
      edit_accounts_ui
      exit 0
      ;;
  esac
} # End of function parse_flags_or_exit()

# Process flags before main (allows --help without clasp installed)
parse_flags_or_exit "$@"

# Run main with all script arguments
main "$@"
