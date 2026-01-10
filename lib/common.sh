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

# --- END COMMON FUNCTIONS ---
