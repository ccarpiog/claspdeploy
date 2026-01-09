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
    show_error "clasp no está instalado. Instálalo con: npm install -g @google/clasp"
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
    echo "🔐 Selecciona una cuenta de Google:" >&2
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
      echo "  (No hay cuentas guardadas)" >&2
      echo "" >&2
    fi

    echo "  N) Crear nueva cuenta" >&2
    echo "" >&2

    local choice
    read -r -p "Selección (número o N): " choice

    if [[ "$choice" =~ ^[Nn]$ ]]; then
      create_new_account
      return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
      # Only the account name goes to stdout (return value)
      echo "${account_array[$((choice - 1))]}"
      return
    else
      echo "❌ Selección no válida. Inténtalo de nuevo." >&2
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
    read -r -p "Nombre para la nueva cuenta (solo letras, números, guiones y guiones bajos): " name

    # Validate name
    if ! validate_account_name "$name"; then
      echo "❌ Nombre no válido. Usa solo letras, números, guiones y guiones bajos." >&2
      continue
    fi

    # Check if account already exists
    if [[ -f "$CLASPALT_CONFIG_DIR/${name}.json" ]]; then
      echo "❌ Ya existe una cuenta con ese nombre." >&2
      continue
    fi

    echo "" >&2
    echo "⚠️  IMPORTANTE: Asegúrate de que el navegador activo está conectado a la cuenta de Google correcta." >&2
    echo "" >&2
    read -r -p "Pulsa Enter cuando estés listo para continuar..."

    echo "" >&2
    echo "🔑 Iniciando sesión con clasp..." >&2

    # Run clasp login (redirect stdout to stderr so it doesn't pollute return value)
    if ! clasp login >&2; then
      show_error "clasp login ha fallado"
    fi

    # Save credentials atomically (copy to temp, then move)
    if [[ -f "$CLASP_CREDENTIALS" ]]; then
      local temp_file
      temp_file=$(mktemp)
      cp "$CLASP_CREDENTIALS" "$temp_file"
      chmod 600 "$temp_file"
      mv "$temp_file" "$CLASPALT_CONFIG_DIR/${name}.json"
      echo "" >&2
      echo "✅ Credenciales guardadas para la cuenta: $name" >&2
    else
      show_error "No se encontraron credenciales en $CLASP_CREDENTIALS"
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
    echo "⚠️  No se encontraron credenciales para la cuenta: $account"
    echo ""
    echo "¿Qué deseas hacer?"
    echo "  1) Crear la cuenta '$account' ahora"
    echo "  2) Seleccionar otra cuenta"
    echo ""

    local choice
    read -r -p "Selección [1/2]: " choice

    if [[ "$choice" == "1" ]]; then
      ensure_config_dir

      echo ""
      echo "⚠️  IMPORTANTE: Asegúrate de que el navegador activo está conectado a la cuenta de Google correcta."
      echo ""
      read -r -p "Pulsa Enter cuando estés listo para continuar..."

      echo ""
      echo "🔑 Iniciando sesión con clasp..."

      if ! clasp login; then
        show_error "clasp login ha fallado"
      fi

      if [[ -f "$CLASP_CREDENTIALS" ]]; then
        # Atomic copy
        local temp_file
        temp_file=$(mktemp)
        cp "$CLASP_CREDENTIALS" "$temp_file"
        chmod 600 "$temp_file"
        mv "$temp_file" "$account_file"
        echo ""
        echo "✅ Credenciales guardadas para la cuenta: $account"
      else
        show_error "No se encontraron credenciales en $CLASP_CREDENTIALS"
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
  echo "📋 Detectado archivo deploymentId.txt antiguo. Migrando al nuevo formato..."

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
  echo "✅ Migración completada. Nuevo archivo: $LOCAL_CONFIG_FILE"
  echo "   Archivo antiguo eliminado: $OLD_DEPLOYMENT_FILE"
} # End of function migrate_from_old_format()

##
# Initializes a new project configuration
##
init_new_project() {
  echo ""
  echo "📋 No se encontró configuración de proyecto."

  # Prompt for account selection
  local account
  account=$(prompt_account_selection)

  # Write config file with account
  write_config_value "account" "$account"

  echo ""
  echo "✅ Configuración guardada en $LOCAL_CONFIG_FILE"
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
      echo "⚠️  El archivo $LOCAL_CONFIG_FILE existe pero no tiene cuenta configurada."
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
    echo "✅ Cuenta activa: $account"
    echo "💡 Usa 'claspalt <comando>' para ejecutar comandos de clasp"
    exit 0
  fi

  # Run clasp with all provided arguments
  exec clasp "$@"
} # End of function main()

# Run main with all script arguments
main "$@"
