# claspalt and claspdeploy

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
| `claspdeploy` | Deployment script with named deployment management |

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

**Main use case**: Managing multiple named deployments (e.g., production and development) so you can keep stable URLs and switch between them easily.

`claspdeploy` combines `clasp push` and `clasp deploy` into a single command, managing your deployment IDs automatically.

### Usage

```bash
claspdeploy [OPTIONS] [DESCRIPTION]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-y, --yes` | Skip confirmation and deployment selection prompts (for CI/CD) |
| `-n, --dry-run` | Preview without deploying |
| `-l, --log` | Enable logging to deployment.log |
| `-D, --deployment NAME` | Deploy a specific named deployment (unambiguous target) |
| `--all` | Deploy every deployment in the saved deploy set, in order |
| `--deploy-set` | Edit which deployments belong to the `--all` set |
| `-ld, --list-deployments` | List all named deployments (with access models and set membership) |
| `-dd, --delete-deployment` | Delete a named deployment |

### Examples

```bash
# Basic deployment
claspdeploy "Fixed authentication bug"

# CI/CD deployment (no prompts)
claspdeploy --yes "Automated deployment"

# Preview what would happen
claspdeploy --dry-run "Testing"

# Deploy with logging
claspdeploy --log "Version 2.0"
```

### Managing Named Deployments

You can store multiple named deployment IDs per project. During each interactive deploy, you are prompted to select, switch, or create a deployment:

```
🚀 Deployment activo: prod — AKfycbwXXXXXXXXXXXXXXXX

Pulsa Enter para usar el deployment actual, S para seleccionar otro, N para crear uno nuevo:
```

- **Enter** — deploy using the active deployment
- **S** — open a selection menu to pick or register a deployment
- **N** — create a new deployment on the server and name it

```bash
# List all named deployments
claspdeploy --list-deployments

# Delete a named deployment
claspdeploy --delete-deployment
```

### Multiple deployments with different access models

One Apps Script project can back several web-app deployments that each need a
**different access model** — for example a public parent form and a
domain-restricted admin panel — while keeping their URLs permanently stable.

The web-app access settings (`webapp.access` + `webapp.executeAs`) live inside the
versioned `appsscript.json`. A deployment can store its own access model in
`claspConfig.txt`; such a deployment is **access-managed**. Before deploying an
access-managed deployment, `claspdeploy`:

1. regenerates the `appsscript.json` `webapp` block to that deployment's model,
2. pushes and deploys,
3. verifies (an anonymous request to the restricted deployment must be redirected
   to sign-in; a public one must serve directly), and
4. restores your original `appsscript.json`, leaving the working tree unchanged.

Deployments **without** a stored access model deploy exactly as before — the
manifest is never touched — so existing single-deployment projects are unaffected.

**Capturing an access model.** The intended workflow is: create and configure the
deployment in the Apps Script UI (Deploy → Manage deployments), then register it in
`claspdeploy` and set its access model once, reading the values from the UI's gear
dialog. You are offered this when registering or creating a deployment, and when
building a deploy set. After that, the stored config is the source of truth and is
reproduced on every redeploy.

**Deploying several at once (`--all`).** Choose the deployments once to build a
saved, ordered *deploy set*:

```bash
claspdeploy --deploy-set          # multi-select editor; also captures access models
```

Then deploy them all with a single command:

```bash
claspdeploy --all "Release to parent form + admin panel"
```

`--all` deploys the set in order, each with its own access model, and **stops
immediately** on the first failure, printing a summary of what succeeded, what
failed, and what was not attempted. Your `appsscript.json` is restored regardless.

To deploy just one deployment unambiguously (e.g. in CI):

```bash
claspdeploy --deployment admin --yes "Admin panel update"
```

### First Run

On first run in a new project:
1. Select or create a Google account (via claspalt)
2. View available deployments from the server
3. Name and select a deployment to use
4. Configuration is saved to `claspConfig.txt`

---

## Configuration Files

### claspConfig.txt

Each project has a `claspConfig.txt` file:

```
account=work
activeDeployment=parent
deployment_parent=AKfycbwXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
deployment_admin=AKfycbwYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
access_parent=ANYONE_ANONYMOUS
executeAs_parent=USER_DEPLOYING
access_admin=DOMAIN
executeAs_admin=USER_DEPLOYING
deploySet=parent,admin
deploymentId=AKfycbwXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

- `activeDeployment` — name of the currently active deployment
- `deployment_{name}` — named deployment ID entries
- `access_{name}` / `executeAs_{name}` — per-deployment web-app access model
  (present only for access-managed deployments)
- `deploySet` — comma-separated, ordered list of deployments for `--all`
- `deploymentId` — backward-compatible mirror of the active deployment's ID

> Deployment names are restricted to letters, numbers, hyphens and underscores, so
> they are always safe as config-key suffixes and as `deploySet` CSV values.

### Migration from old formats

**From single `deploymentId`**: If your project has only a `deploymentId=` entry (no named deployments), you'll be prompted to assign it a name on first interactive run.

**From `deploymentId.txt`**: If your project has an old `deploymentId.txt` file, it will be automatically migrated on first run:
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
