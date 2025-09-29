#!/bin/bash
# Usage: ./deploy.sh "Deployment description"
# If no description is provided, it will use "New version".

set -euo pipefail

DESC="${*:-New version}"          # Use all args as description, or default

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
if [[ -f "$DEPLOYMENT_FILE" ]]; then
  DEPLOYMENT_ID=$(<"$DEPLOYMENT_FILE")
  DEPLOYMENT_ID=${DEPLOYMENT_ID//$'\r'/}
  DEPLOYMENT_ID="${DEPLOYMENT_ID#"${DEPLOYMENT_ID%%[![:space:]]*}"}"
  DEPLOYMENT_ID="${DEPLOYMENT_ID%"${DEPLOYMENT_ID##*[![:space:]]}"}"
fi

# If not found, prompt the user and save it
if [[ -z "$DEPLOYMENT_ID" ]]; then
  echo "ℹ️  $DEPLOYMENT_FILE not found or is empty."
  echo "Enter your Apps Script deploymentId and I'll save it in $DEPLOYMENT_FILE:"
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

echo "🚀 Deploying with description: \"$DESC\""
clasp deploy --deploymentId "$DEPLOYMENT_ID" --description "$DESC"