# claspdeploy

A collection of bash scripts that simplify deploying Google Apps Script projects using clasp. Includes multi-account credential management for seamlessly switching between Google accounts without repeated logins.

## Overview

If you work with multiple Google Apps Script projects across different Google accounts, you know the pain of constantly running `clasp login` to switch accounts. This toolset solves that problem by:

- Storing credentials for each Google account separately
- Automatically switching to the correct account based on project configuration
- Providing an interactive UI for managing accounts

## Scripts Included

| Script | Description |
|--------|-------------|
| `claspalt` | Multi-account credential manager - use instead of `clasp` |
| `claspdeploy` | Deployment script with persistent deployment ID management |

## Quick Start

### Installation

```bash
git clone https://github.com/yourusername/claspdeploy.git
cd claspdeploy
./install.sh
```

This installs `claspalt` and `claspdeploy` to `~/bin/` and creates the credentials directory at `~/.config/claspalt/`.

### Basic Usage

```bash
# In any clasp project directory:
claspalt push              # Push code using the configured account
claspdeploy "Bug fix"      # Push and deploy with a description
```

On first run, you'll be prompted to select or create an account.

---

## claspalt - Multi-Account Credential Manager

### What it does

`claspalt` is a drop-in replacement for `clasp` that automatically switches to the correct Google account before running any clasp command.

### Command-Line Options

```
claspalt [OPTIONS]
claspalt [CLASP_COMMANDS...]

OPTIONS:
  -h, --help     Show help message
  -l, --list     List all saved accounts
  -e, --edit     Open interactive account manager
```

### Managing Accounts

**List all accounts:**
```bash
claspalt --list
```
Output:
```
account-personal
account-work (active)
account-client
```
The `(active)` marker shows which account is configured for the current project directory.

**Interactive account manager:**
```bash
claspalt --edit
```
Opens a terminal UI where you can:
- Navigate with arrow keys (↑/↓)
- Select accounts with Space
- Add new accounts with `A`
- Delete selected accounts with `D`
- Quit with `Q`

```
══════════════════════════════════════════
       CLASPALT - Account Management
══════════════════════════════════════════

> [ ] 1. account-personal
  [x] 2. account-work
  [ ] 3. account-client

──────────────────────────────────────────
  [A]dd   [D]elete selected   [Q]uit
  Space: select/deselect
  ↑/↓: navigate
──────────────────────────────────────────
```

### Using claspalt with clasp commands

Use `claspalt` exactly like you would use `clasp`:

```bash
claspalt push              # Push code
claspalt pull              # Pull code
claspalt deployments       # List deployments
claspalt open              # Open in browser
claspalt status            # Show status
```

### First-Time Setup

When you run `claspalt` in a new project:

1. You'll see a list of existing accounts (if any)
2. Select an account number or press `N` to create a new one
3. For new accounts:
   - Enter a name (e.g., "work", "personal", "client-abc")
   - Make sure the correct browser profile is active
   - Complete the Google OAuth flow
4. The account is saved and associated with the project

### How Credentials Work

```
~/.config/claspalt/
├── work.json           # Credentials for "work" account
├── personal.json       # Credentials for "personal" account
└── client-abc.json     # Credentials for "client-abc" account

your-project/
└── claspConfig.txt     # Contains: account=work, deploymentId=...
```

When you run `claspalt push`:
1. Reads `claspConfig.txt` to find the account name
2. Copies `~/.config/claspalt/work.json` to `~/.clasprc.json`
3. Runs `clasp push`

---

## claspdeploy - Deployment Script

### What it does

`claspdeploy` solves a common problem when developing Google Apps Script web apps: **keeping the same URL across multiple deployments**.

When you run `clasp deploy`, it creates a new deployment with a new URL. But during development, you want to test with a consistent URL that you can bookmark or share. `claspdeploy` saves your deployment ID and reuses it on every deploy, so your web app URL stays the same after each `clasp push`.

**Main use case**: Reusing a deployment ID easily from the command line so you can keep the same URL for testing after every `clasp push`.

`claspdeploy` combines `clasp push` and `clasp deploy` into a single command, managing your deployment ID automatically.

### Usage

```bash
claspdeploy [OPTIONS] [DESCRIPTION]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-y, --yes` | Skip confirmation prompt |
| `-n, --dry-run` | Preview without deploying |
| `-s, --switch-deployment` | Change deployment ID |
| `-l, --log` | Enable logging to deployment.log |

### Examples

```bash
# Basic deployment
claspdeploy "Fixed authentication bug"

# CI/CD deployment (no prompts)
claspdeploy --yes "Automated deployment"

# Preview what would happen
claspdeploy --dry-run "Testing"

# Switch to a different deployment
claspdeploy --switch-deployment "Moving to production"

# Deploy with logging
claspdeploy --log "Version 2.0"
```

### First Run

On first run in a new project:
1. Select or create a Google account
2. View available deployments
3. Select which deployment to use
4. Configuration is saved to `claspConfig.txt`

---

## Configuration Files

### claspConfig.txt

Each project has a `claspConfig.txt` file:

```
account=work
deploymentId=AKfycbwXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### Migration from deploymentId.txt

If your project has an old `deploymentId.txt` file, it will be automatically migrated on first run:
- You'll select an account
- `claspConfig.txt` is created with both values
- `deploymentId.txt` is deleted

---

## Requirements

- [clasp](https://github.com/google/clasp) - Google's Apps Script CLI
- Bash shell (works with macOS default bash 3.2+)
- A Google Apps Script project configured with clasp (`.clasp.json` present)

### Installing clasp

```bash
npm install -g @google/clasp
clasp login  # Initial login (claspalt will manage accounts after this)
```

---

## Troubleshooting

### "clasp is not installed"
Install clasp with `npm install -g @google/clasp`

### Account credentials expired
Delete the account file and recreate:
```bash
rm ~/.config/claspalt/accountname.json
claspalt  # Will prompt to recreate
```

### Wrong account being used
Check which account is configured:
```bash
claspalt --list
cat claspConfig.txt
```

### Interactive editor not working
The `--edit` option requires an interactive terminal. It won't work when piped or in non-TTY contexts.

---

## License

MIT License - feel free to use and modify.
