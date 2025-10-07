# claspdeploy

A bash script that simplifies deploying Google Apps Script projects to the same deployment ID using clasp.

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
