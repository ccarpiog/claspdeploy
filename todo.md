# TODO — Prompt for deployment description

> **STATUS: ✅ DONE (2026-07-24).** Implemented in `claspdeploy.sh`: the unconditional
> default was removed and a guarded interactive prompt added after deployment-ID
> resolution. A `read ... || true` guard was added (Codex review) so EOF/Ctrl-D under
> `set -e` falls back to the default instead of aborting. Verified via `bash -n` and a
> 6-scenario isolated harness. See `PROGRESS.md` and `.claude/reviews/phase1-description-prompt.md`.

## Goal

When `claspdeploy` runs **without a description argument**, prompt the user to type a
deployment description. Only if the user presses Enter on an empty prompt, fall back to
the current default `"New version"`.

## Current behavior

- `DESC` starts empty ([claspdeploy.sh:31](claspdeploy.sh#L31)).
- A positional argument sets `DESC="$*"` ([claspdeploy.sh:566](claspdeploy.sh#L566)).
- If no argument was given, `DESC` is unconditionally defaulted to `"New version"`
  ([claspdeploy.sh:589](claspdeploy.sh#L589)) — the user is never asked.
- `DESC` is first *read* much later: the "Ready to deploy" summary
  ([claspdeploy.sh:729](claspdeploy.sh#L729)), the dry-run summary
  ([claspdeploy.sh:741](claspdeploy.sh#L741)), and the actual deploy call
  ([claspdeploy.sh:758](claspdeploy.sh#L758)). Between line 589 and 729 `DESC` is not used,
  so the defaulting can safely move later.

## Desired behavior (matrix)

| Scenario                                   | Result                                            |
| ------------------------------------------ | ------------------------------------------------- |
| Description given as CLI arg               | Use it (unchanged)                                |
| No arg, interactive, no `--yes`            | **Prompt**; use typed text, or `"New version"` if empty |
| No arg, `--yes` (CI/unattended)            | `"New version"` silently, no prompt               |
| No arg, non-interactive shell (piped)      | `"New version"` silently, cannot prompt           |

Rationale for the guard: `--yes` and non-interactive shells must never block on a prompt,
otherwise CI/piped usage would hang. This mirrors how the existing confirmation and
deployment-selection prompts are already gated on `is_interactive && SKIP_CONFIRMATION == false`.

## Implementation steps (all in `claspdeploy.sh`)

1. **Remove the unconditional default.** Delete the line
   `DESC="${DESC:-New version}"` at [claspdeploy.sh:589](claspdeploy.sh#L589) (and its
   `# Set default description if none provided` comment). Defaulting moves to step 2 so the
   value is still empty when we reach the prompt.
   - Verify `DESC` is not read anywhere between the old line 589 and the new prompt location
     (currently true — see "Current behavior").

2. **Add the prompt block** after the deployment-ID resolution block
   (after `# End of deployment ID resolution`, [claspdeploy.sh:725](claspdeploy.sh#L725))
   and before the "Ready to deploy" summary ([claspdeploy.sh:727](claspdeploy.sh#L727)).
   Placing it here (rather than before the `claspalt push`) means we only ask once the push
   has succeeded and the deployment target is known, grouping it with the other interactive
   prompts. Proposed block:

   ```bash
   # Prompt for a deployment description if none was provided on the command line
   if [[ -z "$DESC" ]]; then
     if is_interactive && [[ "$SKIP_CONFIRMATION" == "false" ]]; then
       read -r -p "📝 Enter a deployment description (press Enter for \"New version\"): " DESC
     fi
     # Fall back to the default if still empty (blank input, --yes, or non-interactive)
     DESC="${DESC:-New version}"
   fi
   ```
   - Uses the same inline `read -r -p` pattern as the existing confirmation prompt
     ([claspdeploy.sh:748](claspdeploy.sh#L748)), so no new helper function is needed and the
     "prompts-to-stderr" convention (which only applies to stdout-returning functions) does
     not come into play.

3. **Update the documentation strings** so they describe the new behavior:
   - Header comment [claspdeploy.sh:3](claspdeploy.sh#L3):
     `# If no description is provided, it will use "New version".`
     → mention that an interactive run prompts for one, defaulting to `"New version"` on empty input.
   - Help text `DESCRIPTION:` section [claspdeploy.sh:58-59](claspdeploy.sh#L58-L59):
     note that when omitted in an interactive session the user is prompted, and that
     `--yes` / non-interactive runs use `"New version"` silently.

## Verification

- [x] `bash -n claspalt.sh claspdeploy.sh lib/common.sh install.sh` passes (exit 0).
- [x] No-args interactive: prompt appears; typed text is used; empty input → `"New version"`.
      (Verified via isolated harness scenarios 2 & 3, since a full deploy needs a live
      clasp project not present in this repo.)
- [x] `"My description"` positional arg: no prompt, description used as before (scenario 1).
- [x] `--yes`: no prompt, `"New version"` used (scenario 4).
- [x] Non-interactive context: no hang, `"New version"` used (scenario 5).
- [x] EOF/Ctrl-D under `set -e`: falls back to `"New version"`, no abort (scenario 6, added
      per Codex review).
- [x] `--dry-run` (interactive): prompt fires and the dry-run summary shows the entered
      description — confirmed by code path (prompt block precedes both the summary and the
      dry-run branch; `--dry-run` does not set `SKIP_CONFIRMATION`).
- [x] No regression to `--list-deployments` / `--delete-deployment`: both `exit 0` well
      before the prompt block.

## Notes / decisions to confirm

- No changes needed in `lib/common.sh` or `claspalt.sh`.
- Since `--yes` already skips confirmation, it also skips this description prompt — the
  description prompt is intentionally tied to `SKIP_CONFIRMATION == false`. Confirm this is
  the desired coupling (alternative: a separate flag), but coupling to `--yes` matches the
  existing "unattended = no prompts" contract.
