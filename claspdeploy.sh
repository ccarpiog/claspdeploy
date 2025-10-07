#!/usr/bin/env bash
# Usage: claspdeploy [OPTIONS] "Deployment description"
# If no description is provided, it will use "New version".

set -euo pipefail

# Default values
DRY_RUN=false
SKIP_CONFIRMATION=false
SWITCH_DEPLOYMENT=false
ENABLE_LOGGING=false
DESC=""

# Function to display help
show_help() {
  cat << EOF
Usage: claspdeploy [OPTIONS] [DESCRIPTION]

Deploy Google Apps Script projects using clasp with persistent deployment ID.

OPTIONS:
  -h, --help              Show this help message
  -y, --yes               Skip confirmation prompt (for CI/CD)
  -n, --dry-run           Show what would be deployed without actually deploying
  -s, --switch-deployment Change deployment ID (ignores saved deploymentId.txt)
  -l, --log               Enable logging to deployment.log file

DESCRIPTION:
  Optional deployment description. Defaults to "New version" if not provided.

EXAMPLES:
  claspdeploy "Fixed bug in user authentication"
  claspdeploy --yes "Automated deployment"
  claspdeploy --dry-run "Test changes"

EOF
  exit 0
}

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

# Set default description if none provided
DESC="${DESC:-New version}"

# Display current date and time
echo "🕐 Deployment started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# First, push local files to Apps Script
echo "📤 Pushing local files to Apps Script..."
if ! clasp push; then
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

DEPLOYMENT_FILE="deploymentId.txt"
DEPLOYMENT_ID=""

# Try to read deploymentId from file (trim CR and surrounding whitespace)
# unless --switch-deployment flag is used
if [[ "$SWITCH_DEPLOYMENT" == "false" && -f "$DEPLOYMENT_FILE" ]]; then
  DEPLOYMENT_ID=$(<"$DEPLOYMENT_FILE")
  DEPLOYMENT_ID=${DEPLOYMENT_ID//$'\r'/}
  DEPLOYMENT_ID="${DEPLOYMENT_ID#"${DEPLOYMENT_ID%%[![:space:]]*}"}"
  DEPLOYMENT_ID="${DEPLOYMENT_ID%"${DEPLOYMENT_ID##*[![:space:]]}"}"
fi

# If switching deployment, notify user
if [[ "$SWITCH_DEPLOYMENT" == "true" ]]; then
  if [[ -f "$DEPLOYMENT_FILE" ]]; then
    OLD_ID=$(<"$DEPLOYMENT_FILE")
    OLD_ID=${OLD_ID//$'\r'/}
    OLD_ID="${OLD_ID#"${OLD_ID%%[![:space:]]*}"}"
    OLD_ID="${OLD_ID%"${OLD_ID##*[![:space:]]}"}"
    echo "🔄 Switching from saved deployment ID: $OLD_ID"
    echo ""
  fi
fi

# If not found, list deployments and prompt the user
if [[ -z "$DEPLOYMENT_ID" ]]; then
  if [[ "$SWITCH_DEPLOYMENT" == "false" ]]; then
    echo "ℹ️  $DEPLOYMENT_FILE not found or is empty."
  fi
  echo ""
  echo "📋 Current deployments:"
  echo ""
  if ! clasp deployments; then
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

  printf '%s\n' "$DEPLOYMENT_ID" > "$DEPLOYMENT_FILE"
  echo "✅ Saved in $DEPLOYMENT_FILE"
fi

echo ""
echo "🚀 Ready to deploy with description: \"$DESC\""
echo "   Deployment ID: $DEPLOYMENT_ID"

# Dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "🔍 DRY-RUN MODE: No actual deployment will be performed"
  echo ""
  echo "Would execute: clasp deploy --deploymentId \"$DEPLOYMENT_ID\" --description \"$DESC\""
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
if ! DEPLOY_OUTPUT=$(clasp deploy --deploymentId "$DEPLOYMENT_ID" --description "$DESC" 2>&1); then
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

# Extract and display deployment URL if available
if [[ "$DEPLOY_OUTPUT" =~ https://script\.google\.com/[^[:space:]]+ ]]; then
  DEPLOYMENT_URL="${BASH_REMATCH[0]}"
  echo "🔗 Deployment URL: $DEPLOYMENT_URL"
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
    if [[ -n "${DEPLOYMENT_URL:-}" ]]; then
      echo "URL: $DEPLOYMENT_URL"
    fi
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