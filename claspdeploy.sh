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
ALL_DEPLOYMENTS=false
EDIT_DEPLOY_SET=false
TARGET_DEPLOYMENT=""
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
  -D, --deployment NAME     Deploy a specific named deployment (unambiguous target)
  --all                     Deploy every deployment in the saved deploy set, in order
  --deploy-set              Edit which deployments belong to the '--all' set
  -ld, --list-deployments   List all named deployments for this project
  -dd, --delete-deployment  Delete a named deployment

DESCRIPTION:
  Optional deployment description. Defaults to "New version" if not provided.

ACCESS-MANAGED DEPLOYMENTS:
  A deployment can store its own web app access model (access + executeAs). Before
  deploying such a deployment, claspdeploy regenerates the appsscript.json webapp
  block to match, then restores your manifest afterwards. This lets one script back
  several deployments with DIFFERENT access models (e.g. a public form + a
  domain-restricted admin panel) without ever changing them by accident.

EXAMPLES:
  claspdeploy "Fixed bug in user authentication"
  claspdeploy --deployment admin "Admin panel update"
  claspdeploy --all "Release to parent form + admin panel"
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
    echo "📋 No saved deployments."
    echo "   Run 'claspdeploy' interactively to create one."
    return
  fi

  local active_name
  active_name=$(get_active_deployment_name)

  echo "📋 Configured deployments:"
  echo ""

  # Print each deployment, marking the active one, its access model, and set membership
  while IFS= read -r name; do
    local dep_id
    dep_id=$(read_config_value "deployment_${name}")

    local model="no access model (deploys as-is)"
    if is_access_managed "$name"; then
      model="$(get_deployment_access "$name") / $(get_deployment_execute_as "$name")"
    fi

    local in_set=""
    if is_in_deploy_set "$name"; then
      in_set=" [in --all set]"
    fi

    if [[ "$name" == "$active_name" ]]; then
      echo "  ▶ $name (active) — $dep_id${in_set}"
    else
      echo "    $name — $dep_id${in_set}"
    fi
    echo "      access: $model"
  done <<< "$deployments"
  # End of loop printing each configured deployment

  local set_csv
  set_csv=$(get_deploy_set)
  echo ""
  if [[ -n "$set_csv" ]]; then
    echo "🚀 Deploy set (--all): $set_csv"
  else
    echo "🚀 Deploy set (--all): (empty — run 'claspdeploy --deploy-set')"
  fi
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

    # Offer to capture the deployment's access model now (the UI-first workflow:
    # create + configure in the Apps Script UI, then register + capture here).
    local set_model
    read -r -p "Set this deployment's web app access model now? [y/N] " set_model
    if [[ "$set_model" =~ ^[Yy]$ ]]; then
      capture_access_model_interactive "$name"
    fi

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
  echo "🆕 Creating a new deployment on the server..." >&2
  echo "" >&2

  # Push current code first so the new deployment is minted from fresh content
  # (the single-deploy path no longer pushes before resolution).
  echo "📤 Pushing current files first..." >&2
  if ! claspalt push >&2; then
    echo "❌ Push failed; cannot create a new deployment." >&2
    return 1
  fi

  local deploy_output
  if ! deploy_output=$(claspalt deploy 2>&1); then
    echo "❌ Failed to create the deployment." >&2
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
    echo "❌ Could not extract the deployment ID from clasp output." >&2
    return 1
  fi

  echo "✅ New deployment created: $dep_id" >&2
  echo "" >&2

  # Prompt user to name the new deployment
  while true; do
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

    # Save the named deployment
    save_deployment "$name" "$dep_id"
    set_active_deployment "$name"
    echo "" >&2
    echo "✅ Deployment '$name' saved with ID: $dep_id" >&2

    # Offer to capture the deployment's access model now. If set, the deploy that
    # follows will regenerate the manifest and apply it to this new deployment.
    local set_model
    read -r -p "Set this deployment's web app access model now? [y/N] " set_model
    if [[ "$set_model" =~ ^[Yy]$ ]]; then
      capture_access_model_interactive "$name"
    fi

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
      echo "🚀 Active deployment: $active_name — $active_id" >&2
      echo "" >&2
      local choice
      read -r -p "Press Enter to use the current deployment, S to select another, N to create a new one: " choice

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
          echo "❌ Cannot create a deployment in dry-run mode." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ Failed to create the deployment. Try again." >&2
          continue
        fi
        echo "$new_name"
        return
      else
        echo "❌ Invalid option. Try again." >&2
      fi

    elif [[ -n "$deployments" ]]; then
      # No active deployment, but deployments exist
      echo "⚠️  No active deployment configured." >&2
      echo "" >&2
      local choice
      read -r -p "Press S to select a deployment, N to create a new one: " choice

      if [[ "$choice" =~ ^[Ss]$ ]]; then
        local selected_name
        selected_name=$(prompt_deployment_selection)
        set_active_deployment "$selected_name"
        echo "$selected_name"
        return
      elif [[ "$choice" =~ ^[Nn]$ ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "❌ Cannot create a deployment in dry-run mode." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ Failed to create the deployment. Try again." >&2
          continue
        fi
        echo "$new_name"
        return
      elif [[ -z "$choice" ]]; then
        echo "❌ No active deployment. Select or create one." >&2
      else
        echo "❌ Invalid option. Try again." >&2
      fi

    else
      # No deployments at all
      echo "⚠️  No deployments configured." >&2
      echo "" >&2
      local choice
      read -r -p "Press N to create a new deployment, S to register an existing one: " choice

      if [[ "$choice" =~ ^[Nn]$ ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "❌ Cannot create a deployment in dry-run mode." >&2
          continue
        fi
        local new_name
        if ! new_name=$(create_new_deployment); then
          echo "❌ Failed to create the deployment. Try again." >&2
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
        echo "❌ No deployments found. Create or register one." >&2
      else
        echo "❌ Invalid option. Try again." >&2
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

##
# Interactively captures a deployment's web app access model and stores it.
# The user reads the values from the Apps Script "Manage deployments" dialog.
# This is the Phase-1 "guided confirm" capture (Tier 1 in the implementation plan).
# All UI goes to stderr so this is safe to call from command-substituted callers.
# @param {string} $1 - Deployment name
##
capture_access_model_interactive() {
  local name="$1"

  echo "" >&2
  echo "🔐 Set the access model for deployment '$name'." >&2
  echo "   Read the current values from the Apps Script editor:" >&2
  echo "   Deploy → Manage deployments → (gear icon) → Web app." >&2
  echo "" >&2

  local access=""
  while true; do
    echo "  Who has access:" >&2
    echo "    1) ANYONE_ANONYMOUS  (public, no sign-in)" >&2
    echo "    2) ANYONE            (public, requires Google sign-in)" >&2
    echo "    3) DOMAIN            (Google Workspace domain only)" >&2
    echo "    4) MYSELF            (only the deploying user)" >&2
    local a
    read -r -p "  Selection [1-4]: " a
    case "$a" in
      1) access="ANYONE_ANONYMOUS"; break ;;
      2) access="ANYONE"; break ;;
      3) access="DOMAIN"; break ;;
      4) access="MYSELF"; break ;;
      *) echo "  ❌ Invalid selection. Try again." >&2 ;;
    esac
  done
  # End of loop prompting for the access value

  local execute_as=""
  while true; do
    echo "" >&2
    echo "  Execute as:" >&2
    echo "    1) USER_DEPLOYING   (runs as you — usual when the app reads shared data)" >&2
    echo "    2) USER_ACCESSING   (runs as the signed-in visitor)" >&2
    local e
    read -r -p "  Selection [1-2]: " e
    case "$e" in
      1) execute_as="USER_DEPLOYING"; break ;;
      2) execute_as="USER_ACCESSING"; break ;;
      *) echo "  ❌ Invalid selection. Try again." >&2 ;;
    esac
  done
  # End of loop prompting for the executeAs value

  set_deployment_access_model "$name" "$access" "$execute_as"
  echo "" >&2
  echo "✅ Access model saved for '$name': $access / $execute_as" >&2
} # End of function capture_access_model_interactive()

##
# Interactive editor for the saved deploy set (the deployments '--all' deploys).
# Uses a numbered toggle list (Bash 3.2 compatible, no raw terminal mode).
# After saving, offers to capture an access model for any selected deployment
# that does not have one yet.
##
prompt_deploy_set() {
  local deployments
  deployments=$(list_deployments)

  if [[ -z "$deployments" ]]; then
    echo "📋 No deployments exist yet. Register or create one first, then build a set."
    return
  fi

  local dep_array=()
  local sel_array=()
  local name
  while IFS= read -r name; do
    dep_array+=("$name")
    if is_in_deploy_set "$name"; then
      sel_array+=(1)
    else
      sel_array+=(0)
    fi
  done <<< "$deployments"
  # End of loop seeding the selection from the current deploy set

  while true; do
    echo ""
    echo "🚀 Select deployments for '--all' (the deploy set):"
    echo ""
    local i=0
    while [[ $i -lt ${#dep_array[@]} ]]; do
      local box="[ ]"
      [[ ${sel_array[$i]} -eq 1 ]] && box="[x]"
      local model=""
      if is_access_managed "${dep_array[$i]}"; then
        model=" — $(get_deployment_access "${dep_array[$i]}")/$(get_deployment_execute_as "${dep_array[$i]}")"
      fi
      echo "  $((i + 1))) ${box} ${dep_array[$i]}${model}"
      i=$((i + 1))
    done
    # End of loop rendering the toggle list
    echo ""
    echo "  Type a number to toggle · 'a' all · 'n' none · 'd' done · 'c' cancel"
    local choice
    read -r -p "  > " choice

    if [[ "$choice" =~ ^[Dd]$ ]]; then
      break
    elif [[ "$choice" =~ ^[Cc]$ ]]; then
      echo "❌ Deploy set unchanged."
      return
    elif [[ "$choice" =~ ^[Aa]$ ]]; then
      i=0
      while [[ $i -lt ${#sel_array[@]} ]]; do sel_array[$i]=1; i=$((i + 1)); done
    elif [[ "$choice" =~ ^[Nn]$ ]]; then
      i=0
      while [[ $i -lt ${#sel_array[@]} ]]; do sel_array[$i]=0; i=$((i + 1)); done
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
      if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#dep_array[@]} ]]; then
        local idx=$((choice - 1))
        if [[ ${sel_array[$idx]} -eq 1 ]]; then
          sel_array[$idx]=0
        else
          sel_array[$idx]=1
        fi
      else
        echo "  ❌ Out of range."
      fi
    else
      echo "  ❌ Invalid input."
    fi
  done
  # End of the toggle selection loop

  # Build the CSV in listed order from the selected entries
  local csv=""
  local i=0
  while [[ $i -lt ${#dep_array[@]} ]]; do
    if [[ ${sel_array[$i]} -eq 1 ]]; then
      if [[ -z "$csv" ]]; then
        csv="${dep_array[$i]}"
      else
        csv="${csv},${dep_array[$i]}"
      fi
    fi
    i=$((i + 1))
  done
  # End of loop building the deploy set CSV

  set_deploy_set "$csv"
  echo ""
  if [[ -z "$csv" ]]; then
    echo "✅ Deploy set cleared."
    return
  fi
  echo "✅ Deploy set saved: $csv"

  # Offer to capture an access model for any selected member that lacks one.
  # Iterate the in-memory arrays (NOT a here-string) so the [y/N] prompt and any
  # capture prompts below read from the terminal rather than piped data.
  local ci=0
  while [[ $ci -lt ${#dep_array[@]} ]]; do
    local nm="${dep_array[$ci]}"
    if [[ ${sel_array[$ci]} -eq 1 ]] && ! is_access_managed "$nm"; then
      echo ""
      local yn
      read -r -p "Deployment '$nm' has no access model (would deploy as-is). Set one now? [y/N] " yn
      if [[ "$yn" =~ ^[Yy]$ ]]; then
        capture_access_model_interactive "$nm"
      fi
    fi
    ci=$((ci + 1))
  done
  # End of loop offering to capture access models
} # End of function prompt_deploy_set()

##
# Best-effort behavioral verification that a deployment's access model is what we
# intended, using an anonymous HTTP request to its /exec URL. This is a heuristic
# WARNING check (never a hard failure): it inspects the redirect host to decide
# whether Google forced sign-in. Requires curl; skipped silently if curl is absent.
# @param {string} $1 - Deployment name
# @param {string} $2 - Deployment ID
##
verify_deployment_access() {
  local name="$1"
  local dep_id="$2"

  # Only meaningful for access-managed deployments.
  if ! is_access_managed "$name"; then
    return 0
  fi
  if ! command -v curl &> /dev/null; then
    echo "ℹ️  Skipping access verification for '$name' (curl not available)."
    return 0
  fi

  local access
  access=$(get_deployment_access "$name")
  local url="https://script.google.com/macros/s/${dep_id}/exec"

  local result code redir
  result=$(curl -s -o /dev/null -m 20 -w '%{http_code}|%{redirect_url}' "$url" 2>/dev/null || echo "000|")
  code="${result%%|*}"
  redir="${result#*|}"

  echo ""
  echo "🔎 Verifying access for '$name' ($access)..."

  # Determine whether Google forced sign-in for the anonymous request.
  local signin="unknown"
  if [[ "$redir" == *accounts.google.com* ]]; then
    signin="forced"
  elif [[ "$redir" == *googleusercontent.com* ]] || [[ "$code" == "200" ]]; then
    signin="none"
  fi

  case "$access" in
    ANYONE_ANONYMOUS)
      if [[ "$signin" == "none" ]]; then
        echo "   ✅ Public deployment served an anonymous request (HTTP $code)."
      else
        echo "   ⚠️  Expected public access but sign-in appears required (HTTP $code)."
        echo "      Verify manually: $url"
      fi
      ;;
    DOMAIN|MYSELF|ANYONE)
      if [[ "$signin" == "forced" ]]; then
        echo "   ✅ Restricted deployment forced sign-in for an anonymous request (HTTP $code)."
      else
        echo "   🚨 WARNING: restricted deployment did NOT force sign-in (HTTP $code)."
        echo "      It may be publicly accessible. Verify immediately: $url"
      fi
      ;;
  esac
} # End of function verify_deployment_access()

##
# Deploys a single named deployment as part of a batch (used by --all).
# Regenerates the manifest for access-managed deployments, runs the webapp safety
# check, pushes, deploys, and verifies. Returns non-zero on any failure WITHOUT
# exiting, so the caller can stop the batch and report cleanly.
# @param {string} $1 - Deployment name
# @param {string} $2 - Deployment description
# @returns 0 on success, 1 on any failure
##
deploy_set_member() {
  local name="$1"
  local desc="$2"

  local dep_id
  dep_id=$(read_config_value "deployment_${name}")
  if [[ -z "$dep_id" ]]; then
    echo "❌ No deployment ID stored for '$name'."
    return 1
  fi

  # CRITICAL: start every member from the pristine manifest so a previous member's
  # regenerated webapp block can never leak into this one. Without this, an
  # unmanaged ("deploys as-is") member would inherit the prior member's access
  # model — e.g. a restricted admin panel could silently go public. cp (not mv)
  # keeps the backup for later members and the EXIT trap. The copy is mandatory:
  # if it fails we must NOT continue (errexit is suppressed inside this function).
  if [[ -n "$_MANIFEST_BACKUP" && -f "$_MANIFEST_BACKUP" ]]; then
    if ! cp "$_MANIFEST_BACKUP" "$(get_manifest_path)"; then
      echo "❌ Could not restore the pristine manifest before deploying '$name'. Aborting."
      return 1
    fi
  fi

  # Access-managed: regenerate the manifest to this deployment's model.
  if is_access_managed "$name"; then
    local acc exe
    acc=$(get_deployment_access "$name")
    exe=$(get_deployment_execute_as "$name")
    # Guard against a corrupt/partial stored model (e.g. hand-edited config).
    if ! validate_access_value "$acc" || ! validate_execute_as_value "$exe"; then
      echo "❌ Invalid stored access model for '$name': '$acc' / '$exe'."
      return 1
    fi
    echo "🔧 Access model: $acc / $exe"
    if ! regenerate_manifest_webapp "$acc" "$exe"; then
      echo "❌ Failed to regenerate the manifest webapp block for '$name'."
      return 1
    fi
    if ! manifest_has_webapp_block "$acc" "$exe"; then
      echo "❌ Manifest verification failed after regeneration for '$name'."
      return 1
    fi
  fi

  # Never deploy a web-app deployment without a webapp block (library conversion trap).
  if ! check_webapp_manifest; then
    echo "❌ appsscript.json has no webapp block; refusing to deploy '$name'."
    return 1
  fi

  echo "📤 Pushing files..."
  if ! claspalt push; then
    echo "❌ Push failed for '$name'."
    return 1
  fi

  echo "📦 Deploying..."
  local out
  if ! out=$(claspalt deploy --deploymentId "$dep_id" --description "$desc" 2>&1); then
    echo "❌ Deploy failed for '$name':"
    printf '%s\n' "$out"
    return 1
  fi
  printf '%s\n' "$out"
  echo "✅ '$name' deployed → https://script.google.com/macros/s/${dep_id}/exec"

  verify_deployment_access "$name" "$dep_id"
  return 0
} # End of function deploy_set_member()

##
# Deploys every deployment in the saved deploy set, in order, stopping immediately
# on the first failure and printing a summary. Validates that all members exist
# before doing anything (hard error otherwise). Backs up the manifest once; the
# EXIT trap restores it. Honors --dry-run and --yes.
# @param {string} $1 - Deployment description
##
deploy_all() {
  local desc="$1"

  local names
  names=$(get_deploy_set_names)

  # Build a set interactively if empty and we can prompt.
  if [[ -z "$names" ]]; then
    if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
      echo "📋 No deploy set configured yet. Let's build one."
      prompt_deploy_set
      names=$(get_deploy_set_names)
    fi
  fi
  if [[ -z "$names" ]]; then
    echo "❌ No deploy set configured. Run 'claspdeploy --deploy-set' first." >&2
    exit 1
  fi

  # Validate every member exists BEFORE doing anything (hard error).
  local missing=""
  local n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if [[ -z "$(read_config_value "deployment_${n}")" ]]; then
      missing="${missing} ${n}"
    fi
  done <<< "$names"
  # End of loop validating deploy set members
  if [[ -n "$missing" ]]; then
    echo "❌ Deploy set references unknown deployment(s):${missing}" >&2
    echo "   Fix the set with 'claspdeploy --deploy-set'." >&2
    exit 1
  fi

  # If appsscript.json is excluded from the push, a regenerated manifest would
  # never reach the server, silently leaving access-managed deployments on their
  # old access model. Fatal when any set member is access-managed.
  if [[ -f ".claspignore" ]] && grep -q "appsscript.json" ".claspignore" 2>/dev/null; then
    local any_managed=false
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      if is_access_managed "$n"; then any_managed=true; fi
    done <<< "$names"
    if [[ "$any_managed" == "true" ]]; then
      echo "❌ .claspignore excludes appsscript.json, but the deploy set has" >&2
      echo "   access-managed deployments whose regenerated manifest would never be" >&2
      echo "   pushed. Remove appsscript.json from .claspignore and retry." >&2
      exit 1
    fi
  fi

  echo ""
  echo "🚀 Deploy set (in order):"
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    local model="deploys as-is"
    if is_access_managed "$n"; then
      model="$(get_deployment_access "$n") / $(get_deployment_execute_as "$n")"
    fi
    echo "   • $n — $(read_config_value "deployment_${n}")  [$model]"
  done <<< "$names"
  # End of loop listing the deploy set

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "🔍 DRY-RUN: would deploy each of the above with description \"$desc\"."
    echo "   No push, deploy, or manifest change will be performed."
    exit 0
  fi

  if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    echo ""
    read -r -p "Deploy all listed deployments? [Y/n] " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Deployment cancelled by user."
      exit 0
    fi
  fi

  # Back up the manifest once; the EXIT trap restores it no matter what happens.
  backup_manifest

  local succeeded=""
  local failed=""
  local not_run=""
  local halted=false

  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if [[ "$halted" == "true" ]]; then
      not_run="${not_run} ${n}"
      continue
    fi
    echo ""
    echo "════════════════════════════════════════"
    echo "▶ Deploying '$n'..."
    if deploy_set_member "$n" "$desc"; then
      succeeded="${succeeded} ${n}"
    else
      failed="$n"
      halted=true
    fi
  done <<< "$names"
  # End of loop deploying each set member (stops on first failure)

  echo ""
  echo "════════════════════════════════════════"
  echo "📋 Deploy summary:"
  [[ -n "$succeeded" ]] && echo "   ✅ Succeeded:${succeeded}"
  [[ -n "$failed" ]] && echo "   ❌ Failed: $failed"
  [[ -n "$not_run" ]] && echo "   ⏭  Not attempted:${not_run}"

  if [[ -n "$failed" ]]; then
    echo ""
    echo "🚨 Batch stopped on the first failure. Your original manifest will be restored on exit."
    exit 1
  fi

  echo ""
  echo "🎉 All deployments in the set completed successfully."
} # End of function deploy_all()

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
    --all)
      ALL_DEPLOYMENTS=true
      shift
      ;;
    -D|--deployment)
      if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
        echo "❌ Option $1 requires a deployment name."
        exit 1
      fi
      TARGET_DEPLOYMENT="$2"
      shift 2
      ;;
    --deploy-set)
      EDIT_DEPLOY_SET=true
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

if [[ "$EDIT_DEPLOY_SET" == "true" ]]; then
  if ! is_interactive; then
    echo "Error: --deploy-set requires an interactive terminal." >&2
    exit 1
  fi
  prompt_deploy_set
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

# Guarantee the working-tree manifest is restored on exit if any deploy path
# regenerated it (access-managed deployments). No-op when nothing was backed up.
# Signals restore AND exit so an interrupt can never fall through into later steps
# (a bare signal trap would return control to the script). restore_manifest is
# idempotent, so the EXIT trap firing afterwards is harmless.
trap 'restore_manifest' EXIT
trap 'restore_manifest; exit 130' INT
trap 'restore_manifest; exit 143' TERM

# Display current date and time
echo "🕐 Deployment started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --all: deploy the saved set (each with its own access model), then stop.
# This path does its own per-deployment push/deploy, so it runs before the
# single-deployment push below.
if [[ "$ALL_DEPLOYMENTS" == "true" ]]; then
  if [[ -n "$TARGET_DEPLOYMENT" ]]; then
    echo "❌ --all and --deployment are mutually exclusive." >&2
    exit 1
  fi
  deploy_all "$DESC"
  exit 0
fi

# NOTE: the push and the Web App Manifest Safety Check happen AFTER target
# resolution, confirmation, and (for access-managed deployments) manifest
# regeneration — see below. This guarantees that a mistyped -D, a cancelled
# deploy, a dry-run, or a failed regeneration never pushes the wrong manifest
# (or any manifest) to Apps Script.

# ============================================================================
# Deployment ID Resolution
# ============================================================================

DEPLOYMENT_ID=""
DEPLOYMENT_NAME=""

# Handle old-style migration first (only when no explicit target and interactive/no --yes)
old_style_id=$(read_config_value "deploymentId")
old_style_name=$(get_active_deployment_name)
if [[ -z "$TARGET_DEPLOYMENT" ]] && [[ -n "$old_style_id" ]] && [[ -z "$old_style_name" ]]; then
  # Old-style deploymentId exists but no activeDeployment — migration scenario
  if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    DEPLOYMENT_NAME=$(migrate_single_deployment)
    DEPLOYMENT_ID=$(get_active_deployment_id)
  fi
  # If non-interactive or --yes, fall through to use old ID below
fi

if [[ -n "$TARGET_DEPLOYMENT" ]]; then
  # Explicit target (-D/--deployment): unambiguous, works with --yes.
  if ! validate_deployment_name "$TARGET_DEPLOYMENT"; then
    echo "Error: invalid deployment name '$TARGET_DEPLOYMENT'." >&2
    echo "   Use only letters, numbers, hyphens and underscores." >&2
    exit 1
  fi
  DEPLOYMENT_NAME="$TARGET_DEPLOYMENT"
  DEPLOYMENT_ID=$(read_config_value "deployment_${DEPLOYMENT_NAME}")
  if [[ -z "$DEPLOYMENT_ID" ]]; then
    echo "Error: deployment '$TARGET_DEPLOYMENT' not found in claspConfig.txt." >&2
    echo "Run 'claspdeploy --list-deployments' to see configured deployments." >&2
    exit 1
  fi
elif is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
  # Interactive deployment selection prompt
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
    echo "Error: No deployment configured and running in non-interactive mode." >&2
    echo "Run interactively first to configure, or use --yes with an already configured project." >&2
    exit 1
  fi
fi
# End of deployment ID resolution

# Determine whether this deployment carries its own access model.
MANAGED_ACCESS=""
MANAGED_EXECUTE_AS=""
if [[ -n "$DEPLOYMENT_NAME" ]] && is_access_managed "$DEPLOYMENT_NAME"; then
  MANAGED_ACCESS=$(get_deployment_access "$DEPLOYMENT_NAME")
  MANAGED_EXECUTE_AS=$(get_deployment_execute_as "$DEPLOYMENT_NAME")
fi

# Show the deployment info (name + ID when available)
echo ""
echo "🚀 Ready to deploy with description: \"$DESC\""
if [[ -n "$DEPLOYMENT_NAME" ]]; then
  echo "   Deployment: $DEPLOYMENT_NAME — $DEPLOYMENT_ID"
else
  echo "   Deployment ID: $DEPLOYMENT_ID"
fi
if [[ -n "$MANAGED_ACCESS" ]]; then
  echo "   Access model: $MANAGED_ACCESS / $MANAGED_EXECUTE_AS (manifest will be regenerated)"
fi

# Dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "🔍 DRY-RUN MODE: No actual deployment will be performed"
  echo ""
  if [[ -n "$MANAGED_ACCESS" ]]; then
    echo "Would regenerate the appsscript.json webapp block to:"
    echo "   \"webapp\": {\"access\": \"$MANAGED_ACCESS\", \"executeAs\": \"$MANAGED_EXECUTE_AS\"}"
    echo "Then push and:"
  fi
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

# Access-managed deployments: regenerate the manifest to this deployment's access
# model BEFORE pushing, so only the correct manifest is ever sent. The EXIT trap
# restores the original manifest afterwards, so the working tree is left unchanged.
if [[ -n "$MANAGED_ACCESS" ]]; then
  # Fatal: if appsscript.json is excluded from the push, the regenerated access
  # model would never reach the server, silently leaving the old model in place.
  if [[ -f ".claspignore" ]] && grep -q "appsscript.json" ".claspignore" 2>/dev/null; then
    echo "❌ .claspignore excludes appsscript.json; the regenerated access model for"
    echo "   '$DEPLOYMENT_NAME' would never be pushed. Remove it from .claspignore and retry."
    exit 1
  fi
  # Guard against a corrupt/partial stored model (e.g. hand-edited config).
  if ! validate_access_value "$MANAGED_ACCESS" || ! validate_execute_as_value "$MANAGED_EXECUTE_AS"; then
    echo "❌ Invalid stored access model for '$DEPLOYMENT_NAME': $MANAGED_ACCESS / $MANAGED_EXECUTE_AS"
    echo "   Re-register its access model and try again."
    exit 1
  fi
  echo ""
  echo "🔧 Applying access model for '$DEPLOYMENT_NAME': $MANAGED_ACCESS / $MANAGED_EXECUTE_AS"
  backup_manifest
  if ! regenerate_manifest_webapp "$MANAGED_ACCESS" "$MANAGED_EXECUTE_AS"; then
    echo "❌ Failed to regenerate the appsscript.json webapp block. Deployment aborted."
    exit 1
  fi
  if ! manifest_has_webapp_block "$MANAGED_ACCESS" "$MANAGED_EXECUTE_AS"; then
    echo "❌ Manifest verification failed after regeneration. Deployment aborted."
    exit 1
  fi
fi

# ============================================================================
# Web App Manifest Safety Check
# ============================================================================
# clasp deploy --deploymentId can silently convert a Web app into a Library if
# appsscript.json lacks a "webapp" section. Check the manifest we are about to
# push/deploy (already regenerated above for access-managed deployments).

# Use if/else to capture exit code safely under set -e
if check_webapp_manifest; then
  WEBAPP_CHECK=0
else
  WEBAPP_CHECK=$?
fi

# Also warn if .claspignore excludes appsscript.json from being pushed
if [[ -f ".claspignore" ]] && grep -q "appsscript.json" ".claspignore" 2>/dev/null; then
  echo ""
  echo "⚠️  WARNING: .claspignore appears to exclude appsscript.json"
  echo "   This means your local manifest may not be pushed to the server,"
  echo "   even if it contains webapp config locally."
  echo ""
fi

if [[ "$WEBAPP_CHECK" -eq 1 ]]; then
  echo ""
  echo "🚨🚨🚨 WARNING 🚨🚨🚨"
  echo "⚠️  appsscript.json not found at: $(get_manifest_path)"
  echo "   Without a manifest, clasp may change your deployment type."
  echo ""
  if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    read -r -p "Continue anyway? This may convert your Web app to a Library. [y/N] " webapp_confirm
    if [[ ! "$webapp_confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Deployment cancelled. Add appsscript.json with a webapp section first."
      exit 1
    fi
  else
    echo "❌ Cannot deploy safely in non-interactive mode without webapp manifest."
    echo "   Add a \"webapp\" section to appsscript.json first. Example:"
    echo '   { "webapp": { "access": "ANYONE", "executeAs": "USER_DEPLOYING" } }'
    exit 1
  fi
elif [[ "$WEBAPP_CHECK" -eq 2 ]]; then
  echo ""
  echo "🚨🚨🚨 WARNING 🚨🚨🚨"
  echo "⚠️  appsscript.json does NOT contain a \"webapp\" section."
  echo "   This is a known clasp bug: deploying without webapp config can silently"
  echo "   convert your Web app deployment into a Library, breaking your URL."
  echo ""
  echo "   To fix, add this to appsscript.json:"
  echo '   "webapp": { "access": "ANYONE", "executeAs": "USER_DEPLOYING" }'
  echo ""
  echo "   Valid access values: MYSELF, DOMAIN, ANYONE, ANYONE_ANONYMOUS"
  echo "   Valid executeAs values: USER_ACCESSING, USER_DEPLOYING"
  echo ""
  if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    read -r -p "Continue anyway? This may convert your Web app to a Library. [y/N] " webapp_confirm
    if [[ ! "$webapp_confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Deployment cancelled. Fix appsscript.json first."
      exit 1
    fi
  else
    echo "❌ Cannot deploy safely in non-interactive mode without webapp config."
    exit 1
  fi
fi
# End of Web App Manifest Safety Check

# Push the (possibly regenerated) manifest and code, then deploy. This is the
# single push for the run — it happens only after resolution, confirmation, and
# regeneration have all succeeded.
echo ""
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

# Behavioral access-model verification for access-managed deployments (WARN-only).
verify_deployment_access "$DEPLOYMENT_NAME" "$DEPLOYMENT_ID"

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
