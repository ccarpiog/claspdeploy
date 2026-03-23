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
ENABLE_LOGGING=false
LIST_DEPLOYMENTS=false
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

In interactive mode, after pushing files you will be prompted to select,
switch, or create a deployment before deploying.

OPTIONS:
  -h, --help                Show this help message
  -y, --yes                 Skip confirmation prompt and deployment selection (for CI/CD)
  -n, --dry-run             Show what would be deployed without actually deploying
  -l, --log                 Enable logging to deployment.log file
  -ld, --list-deployments   List all named deployments for this project
  -dd, --delete-deployment  Delete a named deployment

DESCRIPTION:
  Optional deployment description. Defaults to "New version" if not provided.

EXAMPLES:
  claspdeploy "Fixed bug in user authentication"
  claspdeploy --yes "Automated deployment"
  claspdeploy --dry-run "Test changes"
  claspdeploy --list-deployments

EOF
  exit 0
} # End of function show_help()

##
# Lists all named deployments for CLI output, marking the active one with (active).
# If no deployments exist, shows an informational message.
##
list_deployments_cli() {
  local deployments
  deployments=$(list_deployments)

  if [[ -z "$deployments" ]]; then
    echo "📋 No hay deployments guardados."
    echo "   Ejecuta 'claspdeploy' de forma interactiva para crear uno."
    return
  fi

  local active_name
  active_name=$(get_active_deployment_name)

  echo "📋 Configured deployments:"
  echo ""

  # Print each deployment, marking the active one
  while IFS= read -r name; do
    local dep_id
    dep_id=$(read_config_value "deployment_${name}")
    if [[ "$name" == "$active_name" ]]; then
      echo "  ▶ $name (active) — $dep_id"
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
    echo "🚀 Select a deployment:" >&2
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
          marker=" (active)"
        fi
        echo "  $count) $name${marker} — $dep_id" >&2
      done <<< "$deployments"
      # End of loop printing existing deployments
      echo "" >&2
    else
      echo "  (No saved deployments)" >&2
      echo "" >&2
    fi

    echo "  N) Create new deployment" >&2
    echo "" >&2

    local choice
    read -r -p "Selection (number or N): " choice

    if [[ "$choice" =~ ^[Nn]$ ]]; then
      add_deployment_interactive
      return
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
      local selected_name="${dep_array[$((choice - 1))]}"
      echo "$selected_name"
      return
    else
      echo "❌ Invalid selection. Try again." >&2
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
    echo "📋 Available deployments on the server:" >&2
    echo "" >&2
    if ! claspalt deployments >&2; then
      echo "❌ Failed to list deployments. Please check your clasp authentication." >&2
      exit 1
    fi
    echo "" >&2

    # Prompt for a name
    local name
    read -r -p "Name for this deployment (letters, numbers, hyphens and underscores only): " name

    if ! validate_deployment_name "$name"; then
      echo "❌ Invalid name. Use only letters, numbers, hyphens and underscores." >&2
      continue
    fi

    # Check if name already exists
    local existing_id
    existing_id=$(read_config_value "deployment_${name}")
    if [[ -n "$existing_id" ]]; then
      echo "❌ A deployment with that name already exists." >&2
      continue
    fi

    # Prompt for the deployment ID
    local dep_id
    echo "" >&2
    echo "Copy and paste one of the deployment IDs above:" >&2
    read -r -p "> " dep_id

    # Clean input
    dep_id=${dep_id//$'\r'/}
    dep_id="${dep_id#"${dep_id%%[![:space:]]*}"}"
    dep_id="${dep_id%"${dep_id##*[![:space:]]}"}"

    if [[ -z "$dep_id" ]]; then
      echo "❌ The deployment ID cannot be empty." >&2
      continue
    fi

    # Save the named deployment
    save_deployment "$name" "$dep_id"
    echo "" >&2
    echo "✅ Deployment '$name' saved with ID: $dep_id" >&2

    # Only the name goes to stdout (return value)
    echo "$name"
    return
  done
} # End of function add_deployment_interactive()

##
# Creates a brand new deployment on the server by running claspalt deploy (without --deploymentId).
# Parses the new deployment ID from the output, prompts the user to name it, saves it,
# and sets it as the active deployment.
# All UI output goes to stderr so the name can be captured via stdout.
# @returns The new deployment name via echo (stdout)
##
create_new_deployment() {
  echo "" >&2
  echo "🆕 Creando un nuevo deployment en el servidor..." >&2
  echo "" >&2

  local deploy_output
  if ! deploy_output=$(claspalt deploy 2>&1); then
    echo "❌ Error al crear el deployment." >&2
    echo "$deploy_output" >&2
    return 1
  fi

  # Show the deploy output to the user
  echo "$deploy_output" >&2
  echo "" >&2

  # Parse the deployment ID from the output (starts with "AKfyc")
  local dep_id=""
  if [[ "$deploy_output" =~ (AKfyc[^[:space:]]+) ]]; then
    dep_id="${BASH_REMATCH[1]}"
    # Remove trailing period if present
    dep_id="${dep_id%.}"
  fi

  if [[ -z "$dep_id" ]]; then
    echo "❌ No se pudo extraer el ID del deployment de la salida de clasp." >&2
    return 1
  fi

  echo "✅ Nuevo deployment creado: $dep_id" >&2
  echo "" >&2

  # Prompt user to name the new deployment
  while true; do
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

    # Save the named deployment
    save_deployment "$name" "$dep_id"
    set_active_deployment "$name"
    echo "" >&2
    echo "✅ Deployment '$name' guardado con ID: $dep_id" >&2

    # Only the name goes to stdout (return value)
    echo "$name"
    return
  done
  # End of loop prompting for deployment name
} # End of function create_new_deployment()

##
# Shows an interactive deployment action prompt after push and before deploy.
# Allows the user to proceed with the active deployment, switch to another, or create a new one.
# All UI output goes to stderr so the selected name can be captured via stdout.
# @returns The selected deployment name via echo (stdout)
##
prompt_deploy_action() {
  local active_name
  local active_id
  local deployments

  while true; do
    active_name=$(get_active_deployment_name)
    active_id=$(get_active_deployment_id)
    deployments=$(list_deployments)

    echo "" >&2

    if [[ -n "$active_name" ]] && [[ -n "$active_id" ]]; then
      # There IS an active deployment
      echo "🚀 Deployment activo: $active_name — $active_id" >&2
      echo "" >&2
      local choice
      read -r -p "Pulsa Enter para usar el deployment actual, S para seleccionar otro, N para crear uno nuevo: " choice

      if [[ -z "$choice" ]]; then
        # Enter pressed — use active deployment
        echo "$active_name"
        return
      elif [[ "$choice" =~ ^[Ss]$ ]]; then
        # Select another deployment
        local selected_name
        selected_name=$(prompt_deployment_selection)
        set_active_deployment "$selected_name"
        echo "$selected_name"
        return
      elif [[ "$choice" =~ ^[Nn]$ ]]; then
        # Create new deployment (blocked in dry-run mode)
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "❌ No se puede crear un deployment en modo dry-run." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ No se pudo crear el deployment. Inténtalo de nuevo." >&2
          continue
        fi
        echo "$new_name"
        return
      else
        echo "❌ Opción no válida. Inténtalo de nuevo." >&2
      fi

    elif [[ -n "$deployments" ]]; then
      # No active deployment, but deployments exist
      echo "⚠️  No hay deployment activo configurado." >&2
      echo "" >&2
      local choice
      read -r -p "Pulsa S para seleccionar un deployment, N para crear uno nuevo: " choice

      if [[ "$choice" =~ ^[Ss]$ ]]; then
        local selected_name
        selected_name=$(prompt_deployment_selection)
        set_active_deployment "$selected_name"
        echo "$selected_name"
        return
      elif [[ "$choice" =~ ^[Nn]$ ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "❌ No se puede crear un deployment en modo dry-run." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ No se pudo crear el deployment. Inténtalo de nuevo." >&2
          continue
        fi
        echo "$new_name"
        return
      elif [[ -z "$choice" ]]; then
        echo "❌ No hay deployment activo. Selecciona o crea uno." >&2
      else
        echo "❌ Opción no válida. Inténtalo de nuevo." >&2
      fi

    else
      # No deployments at all
      echo "⚠️  No hay deployments configurados." >&2
      echo "" >&2
      local choice
      read -r -p "Pulsa N para crear un nuevo deployment, S para registrar uno existente: " choice

      if [[ "$choice" =~ ^[Nn]$ ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "❌ No se puede crear un deployment en modo dry-run." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ No se pudo crear el deployment. Inténtalo de nuevo." >&2
          continue
        fi
        echo "$new_name"
        return
      elif [[ "$choice" =~ ^[Ss]$ ]]; then
        local selected_name
        selected_name=$(add_deployment_interactive)
        set_active_deployment "$selected_name"
        echo "$selected_name"
        return
      elif [[ -z "$choice" ]]; then
        echo "❌ No hay deployments. Crea o registra uno." >&2
      else
        echo "❌ Opción no válida. Inténtalo de nuevo." >&2
      fi
    fi
  done
  # End of main selection loop
} # End of function prompt_deploy_action()

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
  echo "🔄 Found an existing deployment ID without a name: $old_id" >&2
  echo "   The new format uses named deployments for easier management." >&2
  echo "" >&2

  while true; do
    local name
    read -r -p "Assign a name to this deployment (e.g.: production, staging): " name

    if ! validate_deployment_name "$name"; then
      echo "❌ Invalid name. Use only letters, numbers, hyphens and underscores." >&2
      continue
    fi

    # Check if name already exists
    local existing_id
    existing_id=$(read_config_value "deployment_${name}")
    if [[ -n "$existing_id" ]]; then
      echo "❌ A deployment with that name already exists." >&2
      continue
    fi

    # Save with the new format
    save_deployment "$name" "$old_id"
    set_active_deployment "$name"
    echo "" >&2
    echo "✅ Deployment migrated: '$name' → $old_id" >&2

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
    echo "📋 No saved deployments to delete."
    return
  fi

  local active_name
  active_name=$(get_active_deployment_name)

  echo ""
  echo "📋 Configured deployments:"
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
      marker=" (active)"
    fi
    echo "  $count) $name${marker} — $dep_id"
  done <<< "$deployments"
  # End of loop printing deployments for deletion

  echo ""
  echo "  0) Cancel"
  echo ""

  local choice
  read -r -p "Select the deployment to delete (number): " choice

  if [[ "$choice" == "0" ]]; then
    echo "❌ Operation cancelled."
    return
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
    local selected_name="${dep_array[$((choice - 1))]}"
    local selected_id
    selected_id=$(read_config_value "deployment_${selected_name}")

    # Warn if deleting the active deployment
    if [[ "$selected_name" == "$active_name" ]]; then
      echo ""
      echo "⚠️  WARNING: You are about to delete the active deployment."
      echo "   You will need to select another deployment the next time you deploy."
    fi

    echo ""
    read -r -p "Delete deployment '$selected_name' ($selected_id)? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      delete_deployment "$selected_name"
      echo "✅ Deployment '$selected_name' deleted."
    else
      echo "❌ Operation cancelled."
    fi
  else
    echo "❌ Invalid selection."
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
    -l|--log)
      ENABLE_LOGGING=true
      shift
      ;;
    -ld|--list-deployments)
      LIST_DEPLOYMENTS=true
      shift
      ;;
    -dd|--delete-deployment)
      DELETE_DEPLOYMENT=true
      shift
      ;;
    -*)
      echo "❌ Unknown option: $1"
      echo "Use --help for usage information"
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

if [[ "$DELETE_DEPLOYMENT" == "true" ]]; then
  if ! is_interactive; then
    echo "Error: --delete-deployment requires an interactive terminal." >&2
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

# Handle old-style migration first (if needed, only in interactive mode without --yes)
old_style_id=$(read_config_value "deploymentId")
old_style_name=$(get_active_deployment_name)
if [[ -n "$old_style_id" ]] && [[ -z "$old_style_name" ]]; then
  # Old-style deploymentId exists but no activeDeployment — migration scenario
  if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    DEPLOYMENT_NAME=$(migrate_single_deployment)
    DEPLOYMENT_ID=$(get_active_deployment_id)
  fi
  # If non-interactive or --yes, fall through to use old ID below
fi

# Interactive deployment selection prompt
if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
  DEPLOYMENT_NAME=$(prompt_deploy_action)
  DEPLOYMENT_ID=$(read_config_value "deployment_${DEPLOYMENT_NAME}")
  # Fallback for migration case where name might not have a deployment_ entry
  if [[ -z "$DEPLOYMENT_ID" ]]; then
    DEPLOYMENT_ID=$(get_active_deployment_id)
  fi
else
  # Non-interactive or --yes: use active deployment silently
  DEPLOYMENT_NAME=$(get_active_deployment_name)
  DEPLOYMENT_ID=$(get_active_deployment_id)
  if [[ -z "$DEPLOYMENT_ID" ]]; then
    echo "Error: No hay deployment configurado y el modo es no interactivo." >&2
    echo "Ejecuta de forma interactiva primero para configurar, o usa --yes con un proyecto ya configurado." >&2
    exit 1
  fi
fi
# End of deployment ID resolution

# Show the deployment info (name + ID when available)
echo ""
echo "🚀 Ready to deploy with description: \"$DESC\""
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
  read -r -p "Proceed with deployment? [Y/n] " confirm
  confirm=${confirm:-Y}  # Default to Y if just Enter is pressed
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled by user."
    exit 0
  fi
fi

echo ""
echo "📦 Deploying..."
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
echo "✅ Deployment successful!"

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
