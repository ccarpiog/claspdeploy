# Plan: claspalt.sh - Multi-Account Clasp Credential Manager

## Status: COMPLETED

All steps have been implemented and reviewed.

## Overview

Create a system to manage multiple Google accounts for clasp, eliminating the need for repeated `clasp login` commands when switching between projects.

## Architecture

### Files Involved

1. **Global credentials storage**: `~/.config/claspalt/`
   - One JSON file per account (e.g., `admisiones.json`, `servicios.json`)
   - Each file is a copy of `~/.clasprc.json` for that account

2. **Local project config**: `claspConfig.txt` (replaces `deploymentId.txt`)
   - Plain text format:
     ```
     deploymentId=AKfycbw...
     account=admisiones
     ```

3. **Scripts**:
   - `claspalt.sh` - New script: switches credentials and calls clasp
   - `claspdeploy.sh` - Modified: uses claspalt.sh instead of calling clasp directly

---

## Implementation Steps

### Step 1: Create claspalt.sh

The script will:

1. **Read local config** (`claspConfig.txt`):
   - If exists: extract `account` value
   - If not exists but `deploymentId.txt` exists: trigger migration (Step 1.1)
   - If neither exists: prompt for account selection/creation

2. **Load account credentials**:
   - Look for `~/.config/claspalt/{account}.json`
   - If found: copy to `~/.clasprc.json`
   - If not found: prompt to create new account (Step 1.2)

3. **Execute clasp** with all passed arguments

#### Step 1.1: Migration from deploymentId.txt

When `deploymentId.txt` exists but `claspConfig.txt` doesn't:

1. Read deployment ID from `deploymentId.txt`
2. Show list of existing accounts from `~/.config/claspalt/`
3. Offer option to create new account
4. User selects or creates account
5. Write `claspConfig.txt` with both values
6. Delete `deploymentId.txt` (or keep as backup? - will delete for cleanliness)

#### Step 1.2: New Account Creation

When user chooses to create a new account:

1. Prompt for account name (alphanumeric + underscores only)
2. Validate name doesn't already exist
3. Display message: "Please ensure the correct browser/profile is active for this Google account"
4. Wait for user confirmation (press Enter)
5. Run `clasp login`
6. Copy resulting `~/.clasprc.json` to `~/.config/claspalt/{name}.json`
7. Update `claspConfig.txt` with the new account name

#### Step 1.3: First Run (No Config Files)

When neither `claspConfig.txt` nor `deploymentId.txt` exist:

1. Show existing accounts from `~/.config/claspalt/`
2. Offer option to create new account
3. After selection/creation, prompt for deployment ID (show `clasp deployments` output)
4. Write `claspConfig.txt`

### Step 2: Modify claspdeploy.sh

Update to use `claspalt.sh` instead of calling `clasp` directly:

1. Replace `clasp push` with `claspalt push`
2. Replace `clasp deploy` with `claspalt deploy`
3. Replace `clasp deployments` with `claspalt deployments`
4. Change `DEPLOYMENT_FILE` from `deploymentId.txt` to `claspConfig.txt`
5. Update reading logic to parse `deploymentId=` format
6. Update saving logic to preserve `account=` when saving deployment ID

### Step 3: Update install.sh

Add installation of `claspalt.sh`:

1. Copy `claspalt.sh` to `$HOME/bin/claspalt`
2. Make executable
3. Create `~/.config/claspalt/` directory if it doesn't exist

### Step 4: Update README.md

Document:

1. New multi-account workflow
2. `claspConfig.txt` format
3. Account management commands
4. Migration from old `deploymentId.txt` system

---

## File Formats

### ~/.config/claspalt/{account}.json

Exact copy of `~/.clasprc.json`:

```json
{
  "oauth2ClientSettings": {
    "clientId": "...",
    "clientSecret": "...",
    "redirectUri": "http://localhost"
  },
  "token": {
    "access_token": "...",
    "refresh_token": "...",
    "scope": "...",
    "token_type": "Bearer",
    "expiry_date": 1700000000000
  }
}
```

### claspConfig.txt

Simple key=value format:

```
deploymentId=AKfycbwXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
account=admisiones
```

---

## Edge Cases to Handle

1. **No accounts exist yet**: Guide user through first account creation
2. **Account file missing**: Offer to recreate via `clasp login`
3. **Invalid/expired credentials**: clasp will fail; user must recreate account
4. **Account name with special characters**: Validate alphanumeric + underscore only
5. **claspConfig.txt exists but account field missing**: Prompt for account selection
6. **~/.config/claspalt/ directory doesn't exist**: Create it automatically

---

## Command Examples

```bash
# Using claspalt directly (passes all args to clasp)
claspalt push
claspalt deploy --deploymentId "xxx" --description "test"
claspalt pull
claspalt open

# Using claspdeploy (now uses claspalt internally)
claspdeploy "New feature"
claspdeploy --dry-run "Test"
```

---

## Testing Checklist

- [ ] Fresh project with no config files
- [ ] Project with only `deploymentId.txt` (migration)
- [ ] Project with `claspConfig.txt` (normal flow)
- [ ] Creating first account (no accounts in ~/.config/claspalt/)
- [ ] Selecting existing account
- [ ] Creating additional account
- [ ] Switching between accounts (different projects)
- [ ] claspdeploy.sh works with new system
- [ ] All clasp commands work through claspalt

---

## Implementation Notes

### Files Created/Modified

1. **claspalt.sh** (NEW) - Multi-account credential manager
2. **claspdeploy.sh** (MODIFIED) - Now uses claspalt instead of clasp
3. **install.sh** (MODIFIED) - Installs both scripts, creates config directory
4. **README.md** (MODIFIED) - Added multi-account documentation

### Key Design Decisions

- Used anchored regex (`^key=`) for config parsing to avoid substring matches
- Atomic file operations (temp file + mv) for credential switching
- Proper permissions (700 for dir, 600 for credential files)
- `|| true` guards for grep to handle set -e + pipefail
- Loops instead of recursion for prompts to avoid stack overflow

### Known Limitations

- Concurrent runs may race on `~/.clasprc.json` (shared global state)
- CI/CD with `--yes` may still prompt if account/config is missing
- `sed -i ''` syntax is macOS-specific (Linux uses `sed -i`)

