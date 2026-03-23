## DONE: Named deployment support (2026-03-23)

**Original request:** claspdeploy should support multiple named deployment IDs (like claspalt does for accounts), so users can easily switch between production and development deployments.

**What was implemented:**

### lib/common.sh — 7 new functions
- `validate_deployment_name()` — validates name characters
- `list_deployments()` — lists all named deployments from config
- `get_active_deployment_name()` / `get_active_deployment_id()` — resolve active deployment
- `save_deployment()` / `set_active_deployment()` / `delete_deployment()` — CRUD for named deployments

### claspdeploy.sh — new CLI flags and functions
- `--list-deployments` / `-ld` — list all named deployments, marking the active one
- `--add-deployment` / `-a` — interactively add a new named deployment
- `--delete-deployment` / `-dd` — interactively delete a named deployment
- `--switch-deployment` / `-s` — enhanced to work with named deployments

### Config format (claspConfig.txt)
```
account=work
activeDeployment=prod
deployment_prod=AKfycbwXXXX
deployment_dev=AKfycbwYYYY
deploymentId=AKfycbwXXXX    # backward compat mirror
```

### Backward compatibility
- Old projects with just `deploymentId=` continue to work
- Interactive migration prompts user to name the existing deployment
- `deploymentId` key is kept in sync as a mirror for any external tools
