# claspdeploy

A collection of bash scripts that simplify deploying Google Apps Script projects using clasp. Includes both a general deployment script and a specialized web app deployment script.

## Scripts

### `claspdeploy` - General deployment script
For standard Google Apps Script deployments with persistent deployment ID management.

### `deploy-webapp.sh` - Web app deployment script
Specialized script for deploying Google Apps Script web applications with proper configuration management.

## Features

- **Persistent deployment ID**: Automatically saves and reuses your deployment ID
- **Interactive confirmation**: Prompts before deploying (can be skipped with `--yes`)
- **Dry-run mode**: Preview what would be deployed without actually deploying
- **Switch deployments**: Easily change to a different deployment ID
- **Error handling**: Clear error messages with helpful suggestions
- **Optional logging**: Track deployment history to a log file
- **Deployment URL extraction**: Displays the deployed script URL after success

## Installation

Run the installation script:

```bash
./install.sh
```

This will install `claspdeploy` to `~/bin/` and add it to your PATH.

## Usage

```
claspdeploy [OPTIONS] [DESCRIPTION]
```

### Options

- `-h, --help` - Show help message
- `-y, --yes` - Skip confirmation prompt (useful for CI/CD)
- `-n, --dry-run` - Show what would be deployed without actually deploying
- `-s, --switch-deployment` - Change deployment ID (ignores saved deploymentId.txt)
- `-l, --log` - Enable logging to deployment.log file

### Examples

Basic deployment:
```bash
claspdeploy "Fixed authentication bug"
```

Deployment without confirmation:
```bash
claspdeploy --yes "Automated deployment"
```

Preview deployment without executing:
```bash
claspdeploy --dry-run "Testing new features"
```

Switch to a different deployment:
```bash
claspdeploy --switch-deployment "Deploying to production"
```

Deploy with logging enabled:
```bash
claspdeploy --log "Version 2.0 release"
```

## How it works

1. First run: Lists available deployments and prompts you to select one
2. Saves the deployment ID to `deploymentId.txt`
3. Subsequent runs: Automatically uses the saved deployment ID
4. Pushes code with `clasp push` before deploying
5. Deploys to the saved deployment ID with your description

## Requirements

- [clasp](https://github.com/google/clasp) installed and authenticated
- Bash shell
- A Google Apps Script project already configured with clasp

---

# deploy-webapp.sh

A specialized deployment script for Google Apps Script web applications that maintains stable web app URLs and proper configuration.

## Web App Features

- **Smart deployment strategy**: Prioritizes @HEAD deployment with automatic fallback
- **URL stability**: Maintains consistent web app URLs across updates
- **Configuration management**: Handles `webAppId.txt` and `appsscript.json` settings
- **Clear feedback**: Shows deployment progress and resulting URLs
- **Error recovery**: Automatic fallback mechanisms for deployment issues

## Web App Usage

```bash
# Deploy with a description
./deploy-webapp.sh "Your description of changes"

# Deploy with default description
./deploy-webapp.sh
```

## How the Web App Script Works

1. **Push code** to Google Apps Script
2. **List current deployments** for reference
3. **Attempt @HEAD deployment** (standard for web apps)
4. **Fallback to saved ID** if @HEAD fails
5. **Display web app URLs** for both domain and public access

## Configuration Files

### `webAppId.txt`
Stores your web app deployment ID for URL stability.

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

## Web App Examples

```bash
# Regular update
./deploy-webapp.sh "Added new sorting options"

# Quick fix
./deploy-webapp.sh "Fixed authentication issue"

# Feature release
./deploy-webapp.sh "Version 2.0 - Export functionality"
```

## Web App URLs

The script provides two URL formats:

- **Domain-specific**: `https://script.google.com/a/macros/yourdomain.com/s/[ID]/exec`
- **Public**: `https://script.google.com/macros/s/[ID]/exec`

## First-Time Web App Setup

If you haven't created a web app deployment:

1. Open the Apps Script editor
2. Click Deploy → New deployment
3. Choose "Web app" as the type
4. Configure permissions
5. Save the deployment ID to `webAppId.txt`

## Additional Documentation

For comprehensive web app deployment information, see [DEPLOY-WEBAPP-GUIDE.md](DEPLOY-WEBAPP-GUIDE.md)
