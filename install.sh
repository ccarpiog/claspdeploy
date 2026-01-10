#!/usr/bin/env bash
# Install script for claspdeploy tools
# Embeds shared functions from lib/common.sh into each script

set -euo pipefail

# Get the directory where the install script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

##
# Displays an error message and exits
# @param {string} $1 - Error message to display
##
show_error() {
  echo "Error: $1" >&2
  exit 1
} # End of function show_error()

##
# Detects the OS type
# @returns "macos" or "linux"
##
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
} # End of function detect_os()

##
# Detects the appropriate shell config file
# @returns Path to the shell config file
##
detect_shell_config() {
  # Check which shell is being used
  local shell_name
  shell_name=$(basename "$SHELL")

  case "$shell_name" in
    zsh)
      echo "$HOME/.zshrc"
      ;;
    bash)
      # On macOS, bash uses .bash_profile for login shells
      if [[ "$(detect_os)" == "macos" ]] && [[ -f "$HOME/.bash_profile" ]]; then
        echo "$HOME/.bash_profile"
      elif [[ -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
      else
        echo "$HOME/.profile"
      fi
      ;;
    *)
      # Fall back to .profile for other shells
      echo "$HOME/.profile"
      ;;
  esac
} # End of function detect_shell_config()

##
# Embeds common.sh content into a script, replacing the marker section
# @param {string} $1 - Source script path
# @param {string} $2 - Destination script path
##
embed_common_functions() {
  local src="$1"
  local dest="$2"
  local common_file="$SCRIPT_DIR/lib/common.sh"

  if [[ ! -f "$common_file" ]]; then
    show_error "lib/common.sh not found at $common_file"
  fi

  # Read the common functions between markers
  local common_content
  common_content=$(awk '
    /^# --- BEGIN COMMON FUNCTIONS ---$/ { in_block=1; next }
    /^# --- END COMMON FUNCTIONS ---$/ { in_block=0 }
    in_block { print }
  ' "$common_file")

  if [[ -z "$common_content" ]]; then
    show_error "No common functions found between markers in $common_file"
  fi

  # Create a temp file for the output
  local temp_file
  temp_file=$(mktemp)

  # Process the source file and embed common functions
  local in_marker=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "# --- BEGIN COMMON FUNCTIONS ---" ]]; then
      echo "$line" >> "$temp_file"
      echo "$common_content" >> "$temp_file"
      in_marker=true
    elif [[ "$line" == "# --- END COMMON FUNCTIONS ---" ]]; then
      echo "$line" >> "$temp_file"
      in_marker=false
    elif [[ "$in_marker" == false ]]; then
      echo "$line" >> "$temp_file"
    fi
  done < "$src"

  # Move temp file to destination
  mv "$temp_file" "$dest"
  chmod +x "$dest"
} # End of function embed_common_functions()

# Main installation logic
echo "Installing claspdeploy tools..."
echo ""

# Create bin directory if it doesn't exist
mkdir -p "$HOME/bin"

# Create claspalt config directory if it doesn't exist
mkdir -p "$HOME/.config/claspalt"
chmod 700 "$HOME/.config/claspalt"

# Check that source files exist
if [[ ! -f "$SCRIPT_DIR/claspalt.sh" ]]; then
  show_error "claspalt.sh not found in $SCRIPT_DIR"
fi

if [[ ! -f "$SCRIPT_DIR/claspdeploy.sh" ]]; then
  show_error "claspdeploy.sh not found in $SCRIPT_DIR"
fi

if [[ ! -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  show_error "lib/common.sh not found in $SCRIPT_DIR"
fi

# Install claspalt (must be installed first as claspdeploy depends on it)
echo "Installing claspalt..."
embed_common_functions "$SCRIPT_DIR/claspalt.sh" "$HOME/bin/claspalt"
echo "  -> $HOME/bin/claspalt"

# Install claspdeploy
echo "Installing claspdeploy..."
embed_common_functions "$SCRIPT_DIR/claspdeploy.sh" "$HOME/bin/claspdeploy"
echo "  -> $HOME/bin/claspdeploy"

# Detect shell config file
SHELL_CONFIG=$(detect_shell_config)

# Add bin to PATH if not already there
if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$SHELL_CONFIG" 2>/dev/null; then
  echo "" >> "$SHELL_CONFIG"
  echo '# Added by claspdeploy installer' >> "$SHELL_CONFIG"
  echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_CONFIG"
  echo ""
  echo "Added \$HOME/bin to PATH in $SHELL_CONFIG"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Installed:"
echo "  - claspalt: Multi-account credential manager for clasp"
echo "  - claspdeploy: Deploy Google Apps Script projects"
echo ""
echo "Please restart your terminal or run 'source $SHELL_CONFIG' to use these commands."
