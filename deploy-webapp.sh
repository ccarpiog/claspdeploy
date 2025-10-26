#!/usr/bin/env bash
# Proper web app deployment script that maintains configuration

set -euo pipefail

DESC="${1:-New version}"

echo "🚀 Web App Deployment Script"
echo "============================"
echo ""
echo "Description: $DESC"
echo ""

# Push the code first
echo "📤 Pushing code to Google Apps Script..."
if ! clasp push; then
  echo "❌ Push failed. Please fix errors and try again."
  exit 1
fi
echo "✅ Code pushed successfully"
echo ""

# Check current deployments
echo "📋 Current deployments:"
clasp deployments
echo ""

# The correct way to update a web app is to use @HEAD or version number
echo "🔄 Updating web app deployment..."
echo ""

# Try using @HEAD first (most common for web apps)
echo "Attempting to deploy to @HEAD (standard web app deployment)..."
if OUTPUT=$(clasp deploy --deploymentId "@HEAD" --description "$DESC" 2>&1); then
  echo "$OUTPUT"
  echo ""
  echo "✅ Successfully deployed to @HEAD"

  # Save @HEAD as our deployment method
  echo "@HEAD" > deploymentId.txt

  # Extract the web app URL if shown
  if [[ "$OUTPUT" =~ (https://script\.google\.com[^[:space:]]+) ]]; then
    URL="${BASH_REMATCH[1]}"
    echo ""
    echo "🔗 Web App URL: $URL"

    # Extract just the ID from the URL if possible
    if [[ "$URL" =~ /s/([^/]+)/exec ]]; then
      WEB_ID="${BASH_REMATCH[1]}"
      echo "$WEB_ID" > webAppId.txt
      echo "📝 Saved web app ID: $WEB_ID"
    fi
  fi
else
  echo "⚠️  Could not deploy to @HEAD. Error output:"
  echo "$OUTPUT"
  echo ""

  # If @HEAD fails, try the specific deployment ID we have
  if [[ -f "webAppId.txt" ]]; then
    WEB_ID=$(<"webAppId.txt")
    WEB_ID=${WEB_ID//$'\r'/}
    WEB_ID="${WEB_ID#"${WEB_ID%%[![:space:]]*}"}"
    WEB_ID="${WEB_ID%"${WEB_ID##*[![:space:]]}"}"

    echo "Trying deployment with saved ID: $WEB_ID"
    if OUTPUT2=$(clasp deploy --deploymentId "$WEB_ID" --description "$DESC" 2>&1); then
      echo "$OUTPUT2"
      echo ""
      echo "✅ Successfully deployed using saved deployment ID"
    else
      echo "❌ Deployment failed with saved ID too:"
      echo "$OUTPUT2"
      echo ""
      echo "You may need to create a new deployment in the Apps Script editor."
      exit 1
    fi
  else
    echo "❌ No saved deployment ID found."
    echo ""
    echo "Please create a web app deployment manually:"
    echo "1. Open: https://script.google.com/d/1s3FuNg4Eh-agOfgmvcoGSNTg3kFlqSGKbcHK1M4lrBW6-i7p_R05rquK/edit"
    echo "2. Click Deploy → New deployment"
    echo "3. Choose 'Web app' as the type"
    echo "4. Configure and deploy"
    echo "5. Save the deployment ID to webAppId.txt"
    exit 1
  fi
fi

echo ""
echo "📌 Important: The webapp configuration is now in appsscript.json:"
echo "   - Execute as: User accessing the web app"
echo "   - Access: Anyone within the domain"
echo ""

# Show the expected URLs
DOMAIN="colehispanoingles.com"
if [[ -f "webAppId.txt" ]]; then
  WEB_ID=$(<"webAppId.txt")
  WEB_ID=${WEB_ID//$'\r'/}
  WEB_ID="${WEB_ID#"${WEB_ID%%[![:space:]]*}"}"
  WEB_ID="${WEB_ID%"${WEB_ID##*[![:space:]]}"}"

  echo "🔗 Your web app should be accessible at:"
  echo "   https://script.google.com/a/macros/$DOMAIN/s/$WEB_ID/exec"
  echo "   OR"
  echo "   https://script.google.com/macros/s/$WEB_ID/exec"
fi

echo ""
echo "✅ Deployment complete!"