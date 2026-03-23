## ~~Deployment selection prompt on every run~~ ✅ DONE

Implemented: interactive deployment selection prompt shown after push, before deploy.

- `prompt_deploy_action()` shows Enter/S/N options depending on state (active deployment, no active, no deployments)
- `create_new_deployment()` creates a server-side deployment via `claspalt deploy`, parses the ID, and prompts for a name
- `--yes` and non-interactive mode skip the prompt and use the active deployment silently
- `--dry-run` blocks the N (create new) option to prevent server-side side effects
- Removed `--switch-deployment` and `--add-deployment` flags (replaced by in-flow prompt)
- Kept `--list-deployments` and `--delete-deployment` as standalone utility commands
