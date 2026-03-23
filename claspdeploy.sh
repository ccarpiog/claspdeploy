#!/usr/bin/env bash
# Usage: claspdeploy [OPTIONS] "Deployment description"
# If no description is provided, it will use "New version".
#
# This script uses claspalt for multi-account credential management.
# Project configuration is stored in claspConfig.txt

set -euo pipefail

# --- BEGIN COMMON FUNCTIONS ---
# These functions are embedded by install.sh from lib/common.sh
# During development, source the file directly:
if [[ -f "$(dirname "$0")/lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  source "$(dirname "$0")/lib/common.sh"
elif [[ -f "$(dirname "$0")/../lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  source "$(dirname "$0")/../lib/common.sh"
else
  echo "Error: lib/common.sh not found. Run install.sh or execute from the repo." >&2
  exit 1
fi
# --- END COMMON FUNCTIONS ---

# Default values
DRY_RUN=false
SKIP_CONFIRMATION=false
SWITCH_DEPLOYMENT=false
ENABLE_LOGGING=false
LIST_DEPLOYMENTS=false
ADD_DEPLOYMENT=false
DELETE_DEPLOYMENT=false
DESC=""

# ============================================================================
# Helper Functions
# ============================================================================

##
# Displays help text and usage information
##
show_help() {
  cat << EOF
Usage: claspdeploy [OPTIONS] [DESCRIPTION]

Deploy Google Apps Script projects using clasp with persistent deployment ID.
Uses claspalt for multi-account credential management.

OPTIONS:
  -h, --help                Show this help message
  -y, --yes                 Skip confirmation prompt (for CI/CD)
  -n, --dry-run             Show what would be deployed without actually deploying
  -s, --switch-deployment   Switch to a different named deployment
  -l, --log                 Enable logging to deployment.log file
  -ld, --list-deployments   List all named deployments for this project
  -a, --add-deployment      Add a new named deployment
  -dd, --delete-deployment  Delete a named deployment

DESCRIPTION:
  Optional deployment description. Defaults to "New version" if not provided.

EXAMPLES:
  claspdeploy "Fixed bug in user authentication"
  claspdeploy --yes "Automated deployment"
  claspdeploy --dry-run "Test changes"
  claspdeploy --list-deployments
  claspdeploy --add-deployment
  claspdeploy --switch-deployment

EOF
  exit 0
} # End of function show_help()

##
# Lists all named deployments for CLI output, marking the active one with (activo).
# If no deployments exist, shows an informational message.
##
list_deployments_cli() {
  local deployments
  deployments=$(list_deployments)

  if [[ -z "$deployments" ]]; then
    echo "📋 No hay deployments guardados."
    echo "   Usa 'claspdeploy --add-deployment' para agregar uno."
    return
  fi

  local active_name
  active_name=$(get_active_deployment_name)

  echo "📋 Deployments configurados:"
  echo ""

  # Print each deployment, marking the active one
  while IFS= read -r name; do
    local dep_id
    dep_id=$(read_config_value "deployment_${name}")
    if [[ "$name" == "$active_name" ]]; then
      echo "  ▶ $name (activo) — $dep_id"
    else
      echo "    $name — $dep_id"
    fi
  done <<< "$deployments"
} # End of function list_deployments_cli()

##
# Prompts user to select an existing named deployment or create a new one.
# All UI output goes to stderr so the selected name can be captured via stdout.
# Uses a loop instead of recursion to avoid stack overflow.
# @returns The selected or created deployment name via echo (stdout)
##
prompt_deployment_selection() {
  while true; do
    local deployments
    deployments=$(list_deployments)

    echo "" >&2
    echo "🚀 Selecciona un deployment:" >&2
    echo "" >&2

    local count=0
    local dep_array=()

    if [[ -n "$deployments" ]]; then
      local active_name
      active_name=$(get_active_deployment_name)

      while IFS= read -r name; do
        count=$((count + 1))
        dep_array+=("$name")
        local dep_id
        dep_id=$(read_config_value "deployment_${name}")
        local marker=""
        if [[ "$name" == "$active_name" ]]; then
          marker=" (activo)"
        fi
        echo "  $count) $name${marker} — $dep_id" >&2
      done <<< "$deployments"
      # End of loop printing existing deployments
      echo "" >&2
    else
      echo "  (No hay deployments guardados)" >&2
      echo "" >&2
    fi

    echo "  N) Crear nuevo deployment" >&2
    echo "" >&2

    local choice
    read -r -p "Selección (número o N): " choice

    if [[ "$choice" =~ ^[Nn]$ ]]; then
      add_deployment_interactive
      return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
      local selected_name="${dep_array[$((choice - 1))]}"
      echo "$selected_name"
      return
    else
      echo "❌ Selección inválida. Inténtalo de nuevo." >&2
    fi
  done
} # End of function prompt_deployment_selection()

##
# Prompts for a deployment name and ID, showing clasp deployments output to help.
# Saves the new named deployment to the config file.
# All UI output goes to stderr so the name can be captured via stdout.
# @returns The new deployment name via echo (stdout)
##
add_deployment_interactive() {
  while true; do
    echo "" >&2
    echo "📋 Deployments disponibles en el servidor:" >&2
    echo "" >&2
    if ! claspalt deployments >&2; then
      echo "❌ No se pudieron listar los deployments. Verifica la autenticación de clasp." >&2
      exit 1
    fi
    echo "" >&2

    # Prompt for a name
    local name
    read -r -p "Nombre para este deployment (letras, números, guiones y guiones bajos): " name

    if ! validate_deployment_name "$name"; then
      echo "❌ Nombre inválido. Usa solo letras, números, guiones y guiones bajos." >&2
      continue
    fi

    # Check if name already exists
    local existing_id
    existing_id=$(read_config_value "deployment_${name}")
    if [[ -n "$existing_id" ]]; then
      echo "❌ Ya existe un deployment con ese nombre." >&2
      continue
    fi

    # Prompt for the deployment ID
    local dep_id
    echo "" >&2
    echo "Copia y pega uno de los deployment IDs de arriba:" >&2
    read -r -p "> " dep_id

    # Clean input
    dep_id=${dep_id//$'\r'/}
    dep_id="${dep_id#"${dep_id%%[![:space:]]*}"}"
    dep_id="${dep_id%"${dep_id##*[![:space:]]}"}"

    if [[ -z "$dep_id" ]]; then
      echo "❌ El deployment ID no puede estar vacío." >&2
      continue
    fi

    # Save the named deployment
    save_deployment "$name" "$dep_id"
    echo "" >&2
    echo "✅ Deployment '$name' guardado con ID: $dep_id" >&2

    # Only the name goes to stdout (return value)
    echo "$name"
    return
  done
} # End of function add_deployment_interactive()

##
# Migrates an old-style deploymentId (without a name) to the new named deployment format.
# Prompts the user to assign a name to the existing deployment ID.
# All UI output goes to stderr so the name can be captured via stdout.
# @returns The new deployment name via echo (stdout)
##
migrate_single_deployment() {
  local old_id
  old_id=$(read_config_value "deploymentId")

  echo "" >&2
  echo "🔄 Se encontró un deployment ID existente sin nombre: $old_id" >&2
  echo "   El nuevo formato usa deployments con nombre para facilitar la gestión." >&2
  echo "" >&2

  while true; do
    local name
    read -r -p "Asigna un nombre a este deployment (ej: produccion, staging): " name

    if ! validate_deployment_name "$name"; then
      echo "❌ Nombre inválido. Usa solo letras, números, guiones y guiones bajos." >&2
      continue
    fi

    # Check if name already exists
    local existing_id
    existing_id=$(read_config_value "deployment_${name}")
    if [[ -n "$existing_id" ]]; then
      echo "❌ Ya existe un deployment con ese nombre." >&2
      continue
    fi

    # Save with the new format
    save_deployment "$name" "$old_id"
    set_active_deployment "$name"
    echo "" >&2
    echo "✅ Deployment migrado: '$name' → $old_id" >&2

    # Only the name goes to stdout (return value)
    echo "$name"
    return
  done
} # End of function migrate_single_deployment()

##
# Prompts user to select a named deployment to delete, then removes it.
# Shows existing deployments and asks for confirmation before deleting.
##
delete_deployment_interactive() {
  local deployments
  deployments=$(list_deployments)

  if [[ -z "$deployments" ]]; then
    echo "📋 No hay deployments guardados para eliminar."
    return
  fi

  local active_name
  active_name=$(get_active_deployment_name)

  echo ""
  echo "📋 Deployments configurados:"
  echo ""

  local count=0
  local dep_array=()

  while IFS= read -r name; do
    count=$((count + 1))
    dep_array+=("$name")
    local dep_id
    dep_id=$(read_config_value "deployment_${name}")
    local marker=""
    if [[ "$name" == "$active_name" ]]; then
      marker=" (activo)"
    fi
    echo "  $count) $name${marker} — $dep_id"
  done <<< "$deployments"
  # End of loop printing deployments for deletion

  echo ""
  echo "  0) Cancelar"
  echo ""

  local choice
  read -r -p "Selecciona el deployment a eliminar (número): " choice

  if [[ "$choice" == "0" ]]; then
    echo "❌ Operación cancelada."
    return
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
    local selected_name="${dep_array[$((choice - 1))]}"
    local selected_id
    selected_id=$(read_config_value "deployment_${selected_name}")

    # Warn if deleting the active deployment
    if [[ "$selected_name" == "$active_name" ]]; then
      echo ""
      echo "⚠️  ATENCIÓN: Estás a punto de eliminar el deployment activo."
      echo "   Necesitarás seleccionar otro deployment la próxima vez que despliegues."
    fi

    echo ""
    read -r -p "¿Eliminar deployment '$selected_name' ($selected_id)? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
      delete_deployment "$selected_name"
      echo "✅ Deployment '$selected_name' eliminado."
    else
      echo "❌ Operación cancelada."
    fi
  else
    echo "❌ Selección inválida."
  fi
} # End of function delete_deployment_interactive()

# ============================================================================
# CLI Flag Handling
# ============================================================================

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -y|--yes)
      SKIP_CONFIRMATION=true
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -s|--switch-deployment)
      SWITCH_DEPLOYMENT=true
      shift
      ;;
    -l|--log)
      ENABLE_LOGGING=true
      shift
      ;;
    -ld|--list-deployments)
      LIST_DEPLOYMENTS=true
      shift
      ;;
    -a|--add-deployment)
      ADD_DEPLOYMENT=true
      shift
      ;;
    -dd|--delete-deployment)
      DELETE_DEPLOYMENT=true
      shift
      ;;
    -*)
      echo "❌ Opción desconocida: $1"
      echo "Usa --help para información de uso"
      exit 1
      ;;
    *)
      # All remaining arguments are part of the description
      DESC="$*"
      break
      ;;
  esac
done
# End of command-line argument parsing

# Handle deployment management flags (exit early, no deployment needed)
if [[ "$LIST_DEPLOYMENTS" == "true" ]]; then
  list_deployments_cli
  exit 0
fi

if [[ "$ADD_DEPLOYMENT" == "true" ]]; then
  if ! is_interactive; then
    echo "Error: --add-deployment requiere una terminal interactiva." >&2
    exit 1
  fi
  add_deployment_interactive > /dev/null
  exit 0
fi

if [[ "$DELETE_DEPLOYMENT" == "true" ]]; then
  if ! is_interactive; then
    echo "Error: --delete-deployment requiere una terminal interactiva." >&2
    exit 1
  fi
  delete_deployment_interactive
  exit 0
fi

# Set default description if none provided
DESC="${DESC:-New version}"

# Check that claspalt is available
if ! command -v claspalt &> /dev/null; then
  echo "Error: claspalt is not installed or not in PATH." >&2
  echo "Please run install.sh or add ~/bin to your PATH." >&2
  exit 1
fi

# Display current date and time
echo "🕐 Deployment started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# First, push local files to Apps Script using claspalt
echo "📤 Pushing local files to Apps Script..."
if ! claspalt push; then
  echo ""
  echo "🚨🚨🚨 ATTENTION! 🚨🚨🚨"
  echo "❌ ERROR: clasp push has failed"
  echo "💡 Possible causes:"
  echo "   • Syntax errors in local files"
  echo "   • Authentication problems with Google"
  echo "   • Interrupted internet connection"
  echo "   • .claspignore files blocking necessary files"
  echo ""
  echo "🔧 Please review the errors above and try again."
  echo "   No deployment will be performed until clasp push works correctly."
  echo ""
  exit 1
fi
echo "✅ Files sent correctly"
echo ""

# ============================================================================
# Deployment ID Resolution
# ============================================================================

DEPLOYMENT_ID=""
DEPLOYMENT_NAME=""

if [[ "$SWITCH_DEPLOYMENT" == "true" ]]; then
  # --- Switch deployment mode ---
  # Show current active deployment info
  local_active_name=$(get_active_deployment_name)
  local_active_id=$(get_active_deployment_id)

  if [[ -n "$local_active_name" ]]; then
    echo "🔄 Deployment activo actual: $local_active_name — $local_active_id"
  elif [[ -n "$local_active_id" ]]; then
    echo "🔄 Deployment ID actual (sin nombre): $local_active_id"
  fi
  echo ""

  # Check for interactive terminal
  if ! is_interactive; then
    echo "Error: --switch-deployment requiere una terminal interactiva." >&2
    exit 1
  fi

  # Prompt user to pick/create a different deployment
  DEPLOYMENT_NAME=$(prompt_deployment_selection)
  set_active_deployment "$DEPLOYMENT_NAME"
  DEPLOYMENT_ID=$(get_active_deployment_id)

  echo ""
  echo "✅ Deployment activo cambiado a: $DEPLOYMENT_NAME"
else
  # --- Normal mode: resolve the active deployment ---
  DEPLOYMENT_NAME=$(get_active_deployment_name)
  DEPLOYMENT_ID=$(get_active_deployment_id)

  if [[ -n "$DEPLOYMENT_ID" ]] && [[ -z "$DEPLOYMENT_NAME" ]]; then
    # Old-style deploymentId exists but no activeDeployment — migration scenario
    if is_interactive; then
      DEPLOYMENT_NAME=$(migrate_single_deployment)
      DEPLOYMENT_ID=$(get_active_deployment_id)
    fi
    # If non-interactive, just use the old ID without a name (backward compatible)

  elif [[ -z "$DEPLOYMENT_ID" ]]; then
    # No deployment ID found at all
    if ! is_interactive; then
      echo "Error: No hay deployment configurado y se ejecuta en modo no interactivo." >&2
      echo "Ejecuta de forma interactiva primero para configurar, o usa --yes con un proyecto preconfigurado." >&2
      exit 1
    fi

    # No config at all — prompt to set one up
    echo "ℹ️  No hay deployment configurado en $CONFIG_FILE."
    DEPLOYMENT_NAME=$(prompt_deployment_selection)
    set_active_deployment "$DEPLOYMENT_NAME"
    DEPLOYMENT_ID=$(get_active_deployment_id)
  fi
  # If both DEPLOYMENT_NAME and DEPLOYMENT_ID are set, nothing to do
fi
# End of deployment ID resolution

# Show the deployment info (name + ID when available)
echo ""
echo "🚀 Listo para desplegar con descripción: \"$DESC\""
if [[ -n "$DEPLOYMENT_NAME" ]]; then
  echo "   Deployment: $DEPLOYMENT_NAME — $DEPLOYMENT_ID"
else
  echo "   Deployment ID: $DEPLOYMENT_ID"
fi

# Dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "🔍 DRY-RUN MODE: No actual deployment will be performed"
  echo ""
  echo "Would execute: claspalt deploy --deploymentId \"$DEPLOYMENT_ID\" --description \"$DESC\""
  exit 0
fi

# Confirmation prompt (unless --yes was used)
if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
  echo ""
  read -r -p "¿Proceder con el despliegue? [S/n] " confirm
  confirm=${confirm:-S}  # Default to S if just Enter is pressed
  if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
    echo "❌ Despliegue cancelado por el usuario."
    exit 0
  fi
fi

echo ""
echo "📦 Desplegando..."
if ! DEPLOY_OUTPUT=$(claspalt deploy --deploymentId "$DEPLOYMENT_ID" --description "$DESC" 2>&1); then
  echo ""
  echo "🚨🚨🚨 DEPLOYMENT FAILED! 🚨🚨🚨"
  echo "❌ ERROR: clasp deploy has failed"
  echo ""
  echo "$DEPLOY_OUTPUT"
  echo ""
  echo "💡 Possible causes:"
  echo "   • The deployment ID is invalid or doesn't exist"
  echo "   • Authentication problems with Google"
  echo "   • The pushed code has errors that prevent deployment"
  echo "   • Insufficient permissions"
  echo ""
  exit 1
fi

echo "$DEPLOY_OUTPUT"
echo ""
echo "✅ ¡Despliegue exitoso!"

# Construct and display the web app URL
WEBAPP_URL="https://script.google.com/macros/s/${DEPLOYMENT_ID}/exec"
echo ""
echo "🌐 Web app URL: $WEBAPP_URL"

# Also extract any additional URL from clasp output if available
if [[ "$DEPLOY_OUTPUT" =~ https://script\.google\.com/[^[:space:]]+ ]]; then
  DEPLOYMENT_URL="${BASH_REMATCH[0]}"
  if [[ "$DEPLOYMENT_URL" != "$WEBAPP_URL" ]]; then
    echo "🔗 Deployment URL: $DEPLOYMENT_URL"
  fi
fi

# Display completion timestamp
COMPLETION_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "🕐 Deployment completed at: $COMPLETION_TIME"

# Log deployment to file (only if --log flag is used)
if [[ "$ENABLE_LOGGING" == "true" ]]; then
  LOG_FILE="deployment.log"
  {
    echo "----------------------------------------"
    echo "Deployment Time: $COMPLETION_TIME"
    echo "Deployment Name: ${DEPLOYMENT_NAME:-N/A}"
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Description: $DESC"
    echo "Web app URL: $WEBAPP_URL"
    echo "----------------------------------------"
    echo ""
  } >> "$LOG_FILE"

  echo ""
  echo "📝 Deployment logged to $LOG_FILE"
fi

# Extract version number from deployment output if available
if [[ "$DEPLOY_OUTPUT" =~ [Vv]ersion[[:space:]]+([0-9]+) ]]; then
  VERSION_NUMBER="${BASH_REMATCH[1]}"
  echo "📌 Deployment version: $VERSION_NUMBER"
elif [[ "$DEPLOY_OUTPUT" =~ @([0-9]+) ]]; then
  # Alternative: extract from deployment ID format
  VERSION_NUMBER="${BASH_REMATCH[1]}"
  echo "📌 Deployment ID version: $VERSION_NUMBER"
fi
