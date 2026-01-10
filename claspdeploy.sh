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
DESC=""

##
# Function to display help
##
show_help() {
  cat << EOF
Usage: claspdeploy [OPTIONS] [DESCRIPTION]

Deploy Google Apps Script projects using clasp with persistent deployment ID.
Uses claspalt for multi-account credential management.

OPTIONS:
  -h, --help              Show this help message
  -y, --yes               Skip confirmation prompt (for CI/CD)
  -n, --dry-run           Show what would be deployed without actually deploying
  -s, --switch-deployment Change deployment ID (ignores saved claspConfig.txt)
  -l, --log               Enable logging to deployment.log file

DESCRIPTION:
  Optional deployment description. Defaults to "New version" if not provided.

EXAMPLES:
  claspdeploy "Fixed bug in user authentication"
  claspdeploy --yes "Automated deployment"
  claspdeploy --dry-run "Test changes"

EOF
  exit 0
} # End of function show_help()

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

DEPLOYMENT_ID=""

# Try to read deploymentId from claspConfig.txt (unless --switch-deployment flag is used)
if [[ "$SWITCH_DEPLOYMENT" == "false" ]]; then
  DEPLOYMENT_ID=$(read_config_value "deploymentId")
fi

# If switching deployment, notify user
if [[ "$SWITCH_DEPLOYMENT" == "true" ]]; then
  OLD_ID=$(read_config_value "deploymentId")
  if [[ -n "$OLD_ID" ]]; then
    echo "🔄 Switching from saved deployment ID: $OLD_ID"
    echo ""
  fi
fi

# If not found, list deployments and prompt the user
if [[ -z "$DEPLOYMENT_ID" ]]; then
  # Check for interactive terminal before prompting
  if ! is_interactive; then
    echo "Error: No deploymentId configured and running in non-interactive mode." >&2
    echo "Please run interactively first to configure, or use --yes with a pre-configured project." >&2
    exit 1
  fi

  if [[ "$SWITCH_DEPLOYMENT" == "false" ]]; then
    echo "ℹ️  No deploymentId found in $CONFIG_FILE."
  fi
  echo ""
  echo "📋 Current deployments:"
  echo ""
  if ! claspalt deployments; then
    echo "❌ Failed to list deployments. Please check your clasp authentication."
    exit 1
  fi
  echo ""
  echo "Copy and paste one of the deployment IDs above:"
  read -r -p "> " DEPLOYMENT_ID
  # Clean input
  DEPLOYMENT_ID=${DEPLOYMENT_ID//$'\r'/}
  DEPLOYMENT_ID="${DEPLOYMENT_ID#"${DEPLOYMENT_ID%%[![:space:]]*}"}"
  DEPLOYMENT_ID="${DEPLOYMENT_ID%"${DEPLOYMENT_ID##*[![:space:]]}"}"

  if [[ -z "$DEPLOYMENT_ID" ]]; then
    echo "❌ The deploymentId cannot be empty."
    exit 1
  fi

  write_config_value "deploymentId" "$DEPLOYMENT_ID"
  echo "✅ Saved in $CONFIG_FILE"
fi

echo ""
echo "🚀 Ready to deploy with description: \"$DESC\""
echo "   Deployment ID: $DEPLOYMENT_ID"

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
