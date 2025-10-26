# 📚 deploy-webapp.sh - Complete Usage Guide

## Overview

`deploy-webapp.sh` is the primary deployment script for updating your Google Classroom Feed web application. It ensures proper web app deployment configuration and maintains your stable web app URL.

## Prerequisites

Before using this script, ensure you have:

1. **Google Apps Script project** properly configured
2. **clasp installed and authenticated** (`npm install -g @google/clasp` and `clasp login`)
3. **A proper web app deployment** created through the Apps Script editor
4. **Execute permissions** for the script (`chmod +x deploy-webapp.sh`)

## Basic Usage

```bash
# Deploy with a description
./deploy-webapp.sh "Your description of changes"

# Deploy with default description ("New version")
./deploy-webapp.sh
```

## How It Works

The script follows this workflow:

1. **Push Code** - Uploads your local files to Google Apps Script
2. **Check Deployments** - Lists current deployments for reference
3. **Deploy to @HEAD** - Attempts to update the standard web app deployment
4. **Fallback to Saved ID** - If @HEAD fails, uses the deployment ID from `webAppId.txt`
5. **Update Configuration Files** - Saves deployment information for future use
6. **Display URLs** - Shows your web app URLs for both domain and public access

## Features

### 🚀 Smart Deployment Strategy
- Prioritizes @HEAD deployment (standard for web apps)
- Automatic fallback to saved deployment ID
- Preserves your web app URL across updates

### 📋 Configuration Management
- Reads from `webAppId.txt` for deployment ID
- Updates `deploymentId.txt` with successful deployment method
- Uses webapp settings from `appsscript.json`

### 🔍 Clear Feedback
- Shows push progress
- Lists current deployments
- Displays deployment results
- Provides web app URLs

### ⚡ Error Handling
- Validates code push before deployment
- Provides clear error messages
- Suggests solutions for common issues

## Configuration Files

The script uses these configuration files:

### `appsscript.json`
Contains webapp configuration:
```json
{
  "webapp": {
    "access": "DOMAIN",
    "executeAs": "USER_ACCESSING"
  }
}
```

### `webAppId.txt`
Stores your web app deployment ID:
```
AKfycbwKrPKHJygaj3qD1A6jtYM9arT-ENdKWx3QYs3sEkQLWSGxpQyc_JPxdQFVXdl-lg
```

### `deploymentId.txt`
Tracks the deployment method (@HEAD or specific ID):
```
@HEAD
```

## Example Scenarios

### Regular Update
```bash
./deploy-webapp.sh "Added new sorting options to feed"
```
Output:
```
🚀 Web App Deployment Script
============================
📤 Pushing code to Google Apps Script...
✅ Code pushed successfully
🔄 Updating web app deployment...
✅ Successfully deployed to @HEAD
🔗 Your web app should be accessible at:
   https://script.google.com/a/macros/colehispanoingles.com/s/[ID]/exec
```

### Quick Fix
```bash
./deploy-webapp.sh "Hotfix for login issue"
```

### Feature Release
```bash
./deploy-webapp.sh "Version 2.0 - Added export functionality"
```

## Troubleshooting

### Error: "Push failed"
**Cause:** Syntax errors in your code or authentication issues
**Solution:**
- Check your code for JavaScript errors
- Run `clasp login` to re-authenticate

### Error: "Could not deploy to @HEAD"
**Cause:** @HEAD deployment doesn't exist or isn't accessible
**Solution:**
- The script will automatically try your saved deployment ID
- If that fails, create a new web app deployment in the Apps Script editor

### Error: "No saved deployment ID found"
**Cause:** Missing `webAppId.txt` file
**Solution:**
1. Open Apps Script editor
2. Deploy → New deployment → Web app
3. Save the deployment ID to `webAppId.txt`

### URL Returns 404
**Cause:** Deployment isn't properly configured as a web app
**Solution:**
1. Create a new web app deployment through the Apps Script editor
2. Update `webAppId.txt` with the new ID

## Best Practices

### 1. Always Test Locally First
Before deploying, ensure your code works:
- No syntax errors
- All functions are defined
- HTML/CSS is valid

### 2. Use Descriptive Messages
```bash
# Good
./deploy-webapp.sh "Fixed date formatting in assignment cards"

# Less helpful
./deploy-webapp.sh "Bug fix"
```

### 3. Regular Deployments
Deploy frequently with small changes rather than large batches:
- Easier to track issues
- Simpler rollback if needed
- Clear deployment history

### 4. Monitor Deployment Output
Always check:
- Push succeeded
- Deployment completed
- URLs are displayed correctly

## URL Formats

The script provides two URL formats:

### Domain-Specific URL (Recommended)
```
https://script.google.com/a/macros/colehispanoingles.com/s/[DEPLOYMENT_ID]/exec
```
- For users within your Google Workspace domain
- Automatic authentication with domain accounts

### Public URL
```
https://script.google.com/macros/s/[DEPLOYMENT_ID]/exec
```
- May not work if app is domain-restricted
- Useful for testing or public access

## Script Comparison

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `deploy-webapp.sh` | **Primary deployment script** | ✅ Always use this |
| `claspdeploy.sh` | General deployment | ❌ Don't use |
| `claspdeployTemp.sh` | Old problematic version | ❌ Never use |
| Direct `clasp deploy` | Manual deployment | ❌ Avoid |

## Maintenance

### Updating the Script
If you need to modify the deployment process:
1. Edit `deploy-webapp.sh`
2. Test with a small change first
3. Document any new features

### Backing Up Configuration
Keep backups of:
- `webAppId.txt` - Your deployment ID
- `appsscript.json` - Project configuration
- Deployment URLs

## Quick Command Reference

```bash
# Standard deployment
./deploy-webapp.sh "Description"

# Check current deployments
clasp deployments

# Open Apps Script editor
clasp open

# Open deployed web app
clasp open --webapp

# Push without deploying (testing)
clasp push

# Check project status
clasp status
```

## Important Notes

⚠️ **First Time Setup:** If you haven't created a proper web app deployment yet, you must:
1. Go to the Apps Script editor
2. Create a new deployment as "Web app"
3. Configure with appropriate permissions
4. Save the deployment ID

✅ **After Setup:** Once you have a proper web app deployment, this script handles everything automatically.

📌 **URL Stability:** Using this script correctly ensures your web app URL remains constant across updates.

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Verify all configuration files exist
3. Ensure you have a proper web app deployment
4. Review the deployment output for specific errors

---

*Last updated: October 2024*
*Script version: 1.0*
*For: Google Classroom Feed project*