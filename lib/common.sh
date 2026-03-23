# Common functions shared between claspdeploy and claspalt
# This file is embedded into each script during installation

# --- BEGIN COMMON FUNCTIONS ---

# Configuration
CONFIG_FILE="claspConfig.txt"

##
# Displays an error message and exits
# @param {string} $1 - Error message to display
##
show_error() {
  echo "Error: $1" >&2
  exit 1
} # End of function show_error()

##
# Reads a value from claspConfig.txt
# @param {string} $1 - Key to read (e.g., "account" or "deploymentId")
# @returns The value associated with the key, or empty string if not found
##
read_config_value() {
  local key="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    # Use anchored regex to match key at start of line only
    # Use || true to avoid exit on no match due to set -e + pipefail
    grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
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

  if [[ -f "$CONFIG_FILE" ]]; then
    # Check if key exists using fixed string matching
    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
      # Update existing key using a temp file for compatibility
      local temp_file
      temp_file=$(mktemp)
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "${key}="* ]]; then
          echo "${key}=${value}"
        else
          echo "$line"
        fi
      done < "$CONFIG_FILE" > "$temp_file"
      mv "$temp_file" "$CONFIG_FILE"
    else
      # Append new key
      echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
  else
    # Create new file
    echo "${key}=${value}" > "$CONFIG_FILE"
  fi
} # End of function write_config_value()

##
# Checks if running in an interactive terminal
# @returns 0 if interactive, 1 if not
##
is_interactive() {
  [[ -t 0 ]]
} # End of function is_interactive()

##
# Validates that a deployment name uses only allowed characters
# @param {string} $1 - Name to validate
# @returns 0 if valid, 1 if invalid
##
validate_deployment_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    return 1
  fi
  # Only allow alphanumeric, underscore, and hyphen
  if [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    return 0
  else
    return 1
  fi
} # End of function validate_deployment_name()

##
# Lists all named deployments from claspConfig.txt
# Outputs one deployment name per line, sorted alphabetically
# No output if none found
##
list_deployments() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # Match lines starting with deployment_ and extract the name part
    grep "^deployment_" "$CONFIG_FILE" 2>/dev/null | sed 's/^deployment_\([^=]*\)=.*/\1/' | sort || true
  fi
} # End of function list_deployments()

##
# Returns the currently active deployment name
# @returns The active deployment name, or empty string if not set
##
get_active_deployment_name() {
  read_config_value "activeDeployment"
} # End of function get_active_deployment_name()

##
# Returns the deployment ID of the currently active deployment
# Falls back to the plain deploymentId key for backward compatibility
# @returns The deployment ID string, or empty if not found
##
get_active_deployment_id() {
  local active_name
  active_name=$(read_config_value "activeDeployment")
  if [[ -n "$active_name" ]]; then
    local id
    id=$(read_config_value "deployment_${active_name}")
    if [[ -n "$id" ]]; then
      echo "$id"
      return
    fi
    # Named deployment missing — fall through to backward compat
  fi
  # Backward compatibility: fall back to plain deploymentId
  read_config_value "deploymentId"
} # End of function get_active_deployment_id()

##
# Saves a named deployment to the config file
# @param {string} $1 - Deployment name
# @param {string} $2 - Deployment ID
##
save_deployment() {
  local name="$1"
  local id="$2"
  write_config_value "deployment_${name}" "$id"
} # End of function save_deployment()

##
# Sets which named deployment is active
# Also mirrors the deployment ID to the deploymentId key for backward compatibility
# @param {string} $1 - Deployment name (must already exist in config)
##
set_active_deployment() {
  local name="$1"
  local id
  id=$(read_config_value "deployment_${name}")
  write_config_value "activeDeployment" "$name"
  # Mirror the ID to deploymentId for backward compatibility
  write_config_value "deploymentId" "$id"
} # End of function set_active_deployment()

##
# Removes a named deployment from the config file
# If the deleted deployment was the active one, clears activeDeployment and deploymentId
# @param {string} $1 - Deployment name to delete
##
delete_deployment() {
  local name="$1"
  local active_name

  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi

  # Remove the deployment_{name} line using a temp file for Bash 3.2 compatibility
  local temp_file
  temp_file=$(mktemp)
  grep -v "^deployment_${name}=" "$CONFIG_FILE" > "$temp_file" || true
  mv "$temp_file" "$CONFIG_FILE"

  # If this was the active deployment, clear activeDeployment and deploymentId
  active_name=$(read_config_value "activeDeployment")
  if [[ "$active_name" == "$name" ]]; then
    write_config_value "activeDeployment" ""
    write_config_value "deploymentId" ""
  fi
} # End of function delete_deployment()

# --- END COMMON FUNCTIONS ---
