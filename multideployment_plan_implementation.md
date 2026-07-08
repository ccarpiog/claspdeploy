# Multi-deployment implementation plan

> **Status:** DRAFT — awaiting approval before implementation.
> **Source requirement:** [multiple_deployments.md](multiple_deployments.md)
> **Goal:** let one Apps Script project drive two or more simultaneous web-app
> deployments, each with its own **stable URL** and its own **access model**
> (e.g. a public parent form + a domain-restricted admin panel), deployable
> individually or all at once with a single command, without ever silently
> changing a deployment's access model.

---

## 1. Decisions locked in

These were confirmed with the user and drive the whole design:

| Topic | Decision |
|---|---|
| **Manifest model** | **Regenerate from config.** One canonical `appsscript.json` in git. Each deployment's `access`/`executeAs` lives in `claspConfig.txt`. Before deploying a given deployment, the tool rewrites the manifest's `webapp` block to match, deploys, then restores the original file. Single source of truth; shared manifest parts (scopes, runtime, libraries) can never drift. |
| **`--all` scope** | **Saved deploy set.** The user picks the deployments once (multi-select); the set is stored in `claspConfig.txt` as `deploySet=`. `claspdeploy --all` redeploys exactly that ordered set every time. The set is editable. |
| **Access capture** | The user creates + configures each deployment in the Apps Script UI first. claspdeploy then **captures** each deployment's access model **once** (best-effort auto, guided-confirm fallback) and stores it. Config is thereafter the source of truth. |
| **Partial failure (`--all`)** | **Stop immediately** on the first failure; report which deployments already succeeded and which never ran. |

## 2. Platform facts established (via Codex + Apps Script knowledge)

1. `clasp deploy --deploymentId <id>` creates a **new immutable version** from the
   current server HEAD (which includes `appsscript.json`, hence its `webapp` block)
   and repoints that deployment ID to the new version. The `/exec` URL is stable
   because the **deployment ID** is stable. → Access model is captured **per version,
   from the manifest, at deploy time.**
2. To give two deployments different access models we must ensure the manifest's
   `webapp` block differs at the moment each is deployed. **No project-level
   (non-versioned) access setting defeats this.**
3. **The live access/executeAs of a deployment is NOT readable** from
   `clasp deployments` or the API `projects.deployments.get` (the web-app entry point
   exposes only the URL). The only authoritative read is: deployment → `versionNumber`
   → fetch that **version's** `appsscript.json` content → parse `webapp`. Exact
   versioned-content API call is flagged **"verify against current docs"**.
4. Deploying a manifest **without** a `webapp` block to a web-app deployment is
   **not** a no-op — it removes the web-app entry point and can break `/exec`. The
   existing `check_webapp_manifest` guard already defends against this and must stay.
5. Redeploying deployment A never changes deployment B (independent version pointers).
   The **real** risk is operational: leaving HEAD/working-tree with the wrong
   manifest and later deploying another deployment from it. The plan neutralizes this
   with a **backup + guaranteed restore** around every deploy.
6. Recommended access models (defaults the tool will offer, user-overridable):
   - Parent form: `access=ANYONE_ANONYMOUS`, `executeAs=USER_DEPLOYING`.
   - Admin panel: `access=DOMAIN`, `executeAs=USER_DEPLOYING` (script runs as the
     deployer so it can read central Sheets/Drive; with `DOMAIN` access,
     `Session.getActiveUser().getEmail()` still returns the signed-in domain user for
     the allowlist check — server must reject blank emails and fail closed).

---

## 3. Configuration schema changes (`claspConfig.txt`)

New keys (all additive, backward-compatible):

```
account=work
activeDeployment=parent

deployment_parent=AKfyc...                 # existing: named deployment ID
deployment_admin=AKfyc...

access_parent=ANYONE_ANONYMOUS            # NEW: per-deployment access model
executeAs_parent=USER_DEPLOYING           # NEW
access_admin=DOMAIN                        # NEW
executeAs_admin=USER_DEPLOYING             # NEW

deploySet=parent,admin                     # NEW: ordered set for --all

deploymentId=AKfyc...                       # existing backward-compat mirror
```

> **Key namespace note:** access-model keys use `access_{name}` / `executeAs_{name}`,
> NOT `deployment_{name}_access`. This deliberately keeps them out of the
> `deployment_` namespace so `list_deployments` (which greps `^deployment_`) can
> never mistake an attribute for a deployment name.

Rules:
- A deployment **with** an `access_{name}` key is "access-managed": its manifest
  is regenerated on every deploy (both `access` and `executeAs` are validated first).
- A deployment **without** those keys behaves exactly as today (deploy touches
  nothing in the manifest). This preserves every existing single-manifest project.
- `deploySet` is a comma-separated, ordered list of existing deployment names.
  Empty/absent → `--all` prompts the user to build it (interactive) or errors
  (non-interactive).

---

## 4. Manifest regeneration mechanism (the core new primitive)

Constraints: **Bash 3.2**, no guaranteed `jq`, no guaranteed `python3`. Must be
atomic and must always restore the working tree.

### 4.1 Regenerate the `webapp` block

`regenerate_manifest_webapp(access, executeAs)` rewrites `appsscript.json` so its
`webapp` block equals exactly:

```json
"webapp": { "access": "<access>", "executeAs": "<executeAs>" }
```

Algorithm (dependency-free, `awk`-based, brace-aware):
1. Resolve the manifest path with the existing `get_manifest_path()`.
2. If a `"webapp"` key exists: replace its **brace-balanced** object value with the
   freshly generated one (handles both pretty-printed and single-line manifests by
   counting `{`/`}` from the `"webapp"` key).
3. If no `"webapp"` key exists: insert the block as a top-level member immediately
   after the opening `{`.
4. Write to a temp file, then `mv` into place (atomic, matches project convention).
5. Validate the result is still parseable-looking (balanced braces, `webapp` present)
   before returning; on any doubt, abort and restore (fail loudly, never deploy a
   malformed manifest).

> **Decision point (implementation):** if the awk brace-replacement proves fiddly for
> unusual formatting, an acceptable alternative is to keep a **base manifest without a
> `webapp` block** (`appsscript.base.json`, canonical in git) and generate
> `appsscript.json = base + injected webapp`. Injection into a known-good base is
> simpler and safer than editing arbitrary JSON. Recommended if the manifest ever
> gains hand-edited complexity. Chosen approach: start with in-place awk replacement;
> fall back to base+inject if needed.

### 4.2 Backup + guaranteed restore

Around any deploy operation:
1. `backup_manifest()` — copy current `appsscript.json` bytes to a temp backup.
2. Install a `trap ... EXIT` that runs `restore_manifest()` unconditionally (normal
   exit, error, or Ctrl-C).
3. `restore_manifest()` — move the backup back over `appsscript.json`.

Net effect: **the working tree is byte-identical after the command**, regardless of
which deployment(s) ran or whether it failed midway. This kills the "left HEAD with
the wrong manifest" risk (fact #5).

### 4.3 Read current `webapp` block (for verification)

`read_manifest_webapp()` → echoes `access` and `executeAs` parsed from the local
`appsscript.json` (sed/awk, same style as `get_root_dir`). Used to assert the
regenerated manifest matches intent **before** push.

---

## 5. Capturing a deployment's access model

The user's model: configure in the Apps Script UI, let claspdeploy capture it.
Because the live value isn't directly readable (fact #3), capture happens **once**,
at the moment a deployment is registered / first becomes access-managed, using a
layered strategy:

**Tier 1 — guided confirm (reliable default, Phase 1).**
When registering a deployment (or converting one to access-managed), prompt:
```
Access model for 'admin' (read it from Apps Script → Deploy → Manage deployments → gear):
  Who has access:
    1) ANYONE_ANONYMOUS   2) ANYONE   3) DOMAIN   4) MYSELF
  Execute as:
    1) USER_DEPLOYING     2) USER_ACCESSING
```
Values are validated (`validate_access_value`, `validate_execute_as_value`) and
stored. Defaults offered per fact #6 to make it one-keypress for the common case.

**Tier 2 — best-effort auto-capture (enhancement, Phase 2, optional).**
Before showing Tier 1, try to auto-fill by:
1. Getting the deployment's `versionNumber` (`claspalt deployments` output or API).
2. Calling the Apps Script API to fetch that **version's** content:
   `GET https://script.googleapis.com/v1/projects/{scriptId}/content?versionNumber={N}`
   with a Bearer token extracted from the active account's credentials
   (`~/.clasprc.json`, already staged by claspalt) and `scriptId` from `.clasp.json`.
3. Parsing the returned `appsscript` file's `webapp` block.
4. Pre-filling the Tier-1 prompt with the discovered values; the user just confirms.
On any failure (API disabled, token expired, no webapp entry, parse error) → silently
fall back to Tier-1 manual entry.

> **Flagged "verify against current docs":** the exact versioned-content endpoint,
> the OAuth scope required (`script.projects` / `script.deployments`), and token
> refresh handling. Tier 2 is strictly additive; Tier 1 must ship first and stand
> alone.

---

## 6. Deploy flows

### 6.1 Single deployment (existing path, upgraded)

`deploy_one(name, desc)`:
1. Resolve deployment ID for `name`.
2. If `name` is **access-managed** (has `_access`): `backup_manifest`, then
   `regenerate_manifest_webapp(access, executeAs)`.
   If not access-managed: leave the manifest untouched (today's behavior).
3. Run the **existing** `check_webapp_manifest` safety check (unchanged — still the
   guard against library conversion). In non-interactive mode a missing/blank webapp
   block still hard-fails.
4. `claspalt push`.
5. `claspalt deploy --deploymentId <id> --description "<desc>"`.
6. `verify_deployment_access(name)` (§7).
7. `restore_manifest` (via the EXIT trap).

The interactive selection prompt (`prompt_deploy_action`) is unchanged for choosing
*which* deployment; it now just feeds `deploy_one`.

### 6.2 All deployments (`--all`)

`deploy_all(desc)`:
1. Load `deploySet`. If empty:
   - interactive → `prompt_deploy_set()` (multi-select) to build it, save, continue;
   - non-interactive → error (fact: point 5 of the requirement — never guess a target).
2. `backup_manifest` once; single EXIT trap restores at the very end.
3. For each `name` in the set, in order:
   - `deploy_one_core(name, desc)` (regenerate → check → push → deploy → verify).
   - **Stop immediately on first failure** (decision). Print a summary:
     `✅ parent` … `❌ admin (push failed)` … `⏭ reports (not attempted)`.
4. Restore the manifest; exit non-zero if any deployment failed.

Because each iteration pushes its own manifest and deploys its own ID, the set can
mix access models freely (public form + domain admin + …) in one command.

### 6.3 Deploy-set management

- Build/edit interactively with a multi-select (reuse the proven `_UI_*` /
  space-to-select pattern from `claspalt.sh`'s `edit_accounts_ui`).
- New flag `--deploy-set` opens that editor; `--list-deployments` output additionally
  marks which deployments are in the set and shows each one's stored access model.

---

## 7. Post-deploy verification (requirement point 4)

`verify_deployment_access(name)` answers "is this deployment still what we intended?"
with two independent layers:

1. **Local pre-push assertion (always):** after regeneration and before push, assert
   `read_manifest_webapp()` equals the stored `_access`/`_executeAs`. Guarantees we
   are about to deploy the intended model.
2. **Behavioral probe (recommended, dependency-light):** after deploy, an anonymous
   `curl -s -o /dev/null -w '%{http_code} %{redirect_url}'` of the deployment's
   `/exec`:
   - `ANYONE_ANONYMOUS` → expect `200` (public form reachable without sign-in).
   - `DOMAIN` / `MYSELF` → expect a redirect to `accounts.google.com` (sign-in forced),
     **not** a `200` serving app content. A `200` here is a loud failure: the
     restricted deployment leaked public.
3. **Metadata verification (rigorous, Phase 2):** re-run the §5 Tier-2 read against the
   **new** version and assert it matches intent. Gated behind the same "verify against
   current docs" flag.

Any verification failure → loud error; in `--all`, triggers the stop-immediately path.

---

## 8. Safety guarantees (requirement point 3)

- **Never change a deployment's access model as a side effect:** access-managed
  deployments always regenerate from stored config, so a routine redeploy reproduces
  the exact model. Non-access-managed deployments never have their manifest touched.
- **Fail loudly:** the existing `check_webapp_manifest` guard stays; the new local
  assertion (§7.1) and behavioral probe (§7.2) turn a wrong access model into a
  non-zero exit with a red banner, not a silent success.
- **Working tree integrity:** backup + trap restore (§4.2) guarantees no lingering
  wrong manifest.
- **`.claspignore` guard:** keep the existing warning if `appsscript.json` is ignored
  (a regenerated manifest that never gets pushed would be a silent no-op).

---

## 9. Non-interactive / CI behavior (requirement point 5)

- `claspdeploy --deployment <name> --yes "msg"` — target ONE deployment unambiguously.
- `claspdeploy --all --yes "msg"` — deploy the saved set unattended (errors if the set
  is empty; never guesses).
- Access-managed deploys in non-interactive mode use stored config directly (no
  prompts). Capture (§5) is interactive-only; a non-interactive deploy of an
  un-captured access-managed deployment errors with guidance to run it interactively
  once.

---

## 10. CLI surface changes (`claspdeploy`)

New / changed flags:

| Flag | Meaning |
|---|---|
| `--all` | Deploy the saved `deploySet`, in order, stop on first failure. |
| `-D, --deployment <name>` | Target one named deployment explicitly (esp. with `--yes`). |
| `--deploy-set` | Open the multi-select editor for the saved set. |
| `-ld, --list-deployments` | (Extended) also show each deployment's access model + set membership. |

Unchanged: `-h`, `-y/--yes`, `-n/--dry-run`, `-l/--log`, `-dd/--delete-deployment`.
`--dry-run` must show the regenerated `webapp` block per targeted deployment and must
**not** push, deploy, or mutate the manifest on disk beyond a preview.

---

## 11. Functions to add / change

**`lib/common.sh` (new):**
- `get_deployment_access(name)` / `set_deployment_access(name, value)`
- `get_deployment_execute_as(name)` / `set_deployment_execute_as(name, value)`
- `is_access_managed(name)`
- `validate_access_value(v)` — `MYSELF|DOMAIN|ANYONE|ANYONE_ANONYMOUS`
- `validate_execute_as_value(v)` — `USER_ACCESSING|USER_DEPLOYING`
- `get_deploy_set()` / `set_deploy_set(csv)` / `is_in_deploy_set(name)`
- `regenerate_manifest_webapp(access, executeAs)`
- `read_manifest_webapp()`
- `backup_manifest()` / `restore_manifest()`
- (Phase 2) `capture_deployment_access(name)` — API read of version manifest

**`claspdeploy.sh` (new/changed):**
- `deploy_one(name, desc)` / `deploy_one_core(name, desc)`
- `deploy_all(desc)`
- `prompt_deploy_set()` — multi-select editor (reuse `_UI_*` pattern)
- `verify_deployment_access(name)`
- Extend `add_deployment_interactive` / `create_new_deployment` with §5 capture
- Extend flag parser with `--all`, `-D/--deployment`, `--deploy-set`
- Extend `list_deployments_cli` with access model + set membership

**`claspalt.sh`:** no functional change (the multi-select UI pattern is reused, not
moved). If `prompt_deploy_set` is shared, consider hoisting the generic multi-select
loop into `lib/common.sh` — evaluate during implementation.

**`install.sh`:** no change to mechanism; new common functions sit inside the existing
`# --- BEGIN/END COMMON FUNCTIONS ---` markers and get embedded automatically.

**`README.md`:** document `--all`, deploy sets, access-managed deployments, the
capture flow, and the config keys.

---

## 12. Edge cases & risks

- **Manifest has no `webapp` originally** but a deployment is access-managed → we
  inject one (§4.1 insertion path). The pre-push assertion confirms it landed.
- **Deploy set references a deleted deployment** → skip with a warning, or hard-error
  under stop-immediately (decide: hard-error is safer/louder — recommended).
- **Deleting a deployment** must also strip its `_access`/`_executeAs` keys and remove
  it from `deploySet` (extend `delete_deployment`).
- **awk replacement on exotic JSON formatting** → mitigated by the base+inject fallback
  (§4.1) and the pre-push validity check.
- **Token expiry during Phase-2 auto-capture** → falls back to manual (§5 Tier 1).
- **`curl` absent** for behavioral probe → probe is skipped with a notice; local
  assertion still runs. Probe is best-effort, not a hard dependency.
- **Bash 3.2 arrays** for the deploy set / multi-select — already proven in
  `edit_accounts_ui`; reuse that idiom (no namerefs, global `_UI_*`).

---

## 13. Testing plan (manual, no test suite exists)

1. `bash -n` on all four scripts after every change.
2. Fresh project: register two deployments (parent + admin), capture access models,
   build a deploy set.
3. `claspdeploy -D parent "..."` → verify manifest regenerated to `ANYONE_ANONYMOUS`,
   working tree clean afterward, probe returns 200.
4. `claspdeploy -D admin "..."` → verify `DOMAIN`, probe returns a login redirect.
5. `claspdeploy --all "..."` → both deploy in order; working tree clean.
6. Force a mid-set failure (e.g. bad ID) → confirm stop-immediately + accurate summary
   + restored manifest.
7. `claspdeploy --all --yes "..."` in a non-TTY → confirm it uses the saved set and
   never prompts; empty set → clean error.
8. Backward compat: an existing single-deployment project (no `_access` keys) deploys
   exactly as before, manifest untouched.
9. `--dry-run` previews each regenerated block and mutates nothing.

---

## 14. Phased implementation checklist

**Phase 1 — core (ships the whole feature reliably): DONE ✅**
- [x] Config helpers: access/executeAs get/set, validators, deploy-set get/set.
- [x] `regenerate_manifest_webapp` (string-aware + depth-aware) + `manifest_has_webapp_block` + backup/restore + trap.
- [x] Tier-1 guided capture in registration + create flows.
- [x] Single-deploy regeneration + safety check + pre-push assertion + model validation.
- [x] `--deployment <name>` targeting.
- [x] `--all` over saved set with stop-immediately + summary.
- [x] `--deploy-set` multi-select editor; extended `--list-deployments`.
- [x] Extend `delete_deployment` to clean access keys + set membership.
- [x] Behavioral `curl` probe in `verify_deployment_access`.
- [x] README + this doc updated; `bash -n` + install-embed clean; tested with stubs.

**Phase 2 — enhancements (optional, additive):**
- [ ] Tier-2 API auto-capture of access model from the version manifest.
- [ ] Metadata verification against the deployed version (rigorous §7.3).
- [ ] (If chosen) hoist generic multi-select into `lib/common.sh`.

## 16. Review outcomes (Fable + Codex)

Phase 1 was reviewed by an independent Fable agent and by Codex. All confirmed
findings were fixed and re-tested:

- **[Fable — critical] Manifest corruption:** `regenerate_manifest_webapp` matched
  the first literal `"webapp"` anywhere, so a manifest containing that string as a
  VALUE (e.g. `"name": "webapp"`, `["webapp"]`) got spliced/corrupted. Rewrote the
  awk to be string-aware AND depth-aware (only the top-level `"webapp":` key) and to
  handle empty `{}` without a trailing comma. Verified against 14 manifest shapes.
- **[found via testing] `check_webapp_manifest`** only detected `webapp` at
  line-start, wrongly rejecting minified manifests. Now matches the key anywhere.
- **[found via testing] Phantom deployments:** `list_deployments` (`^deployment_`)
  matched the old `deployment_{name}_access` keys. Moved access model to a separate
  namespace: `access_{name}` / `executeAs_{name}`.
- **[Codex — high] Premature push:** the single-deploy path pushed before target
  resolution/confirm/regeneration. Reordered so the (single) push happens only after
  resolution, dry-run, confirmation, and regeneration all succeed; the interactive
  create-new path pushes before minting.
- **[Codex — high] Signal trap fell through:** split into `EXIT` (restore) and
  `INT`/`TERM` (restore + exit 130/143).
- **[Codex — medium] `backup_manifest`** made idempotent (keeps the pristine
  original, no temp-file leak).
- **[Codex — medium] `delete_config_key`** now uses literal-prefix matching, not a
  `grep` regex.
- **[Codex — medium] comma-in-name CSV risk:** non-issue —
  `validate_deployment_name` already restricts names to `[A-Za-z0-9_-]+`.
- **[Codex — low] Partial access model:** deploy paths now validate both
  `access` + `executeAs` before regenerating and refuse loudly on a corrupt config.

**Second Fable pass (independent, found what Codex's first pass missed):**

- **[Fable — CRITICAL] Batch manifest inheritance:** in `--all`, an unmanaged member
  deployed with the *previous* member's regenerated manifest (a public form followed
  by an unmanaged admin panel → admin silently goes public). Fixed: each member
  restores the pristine manifest (`cp` from the backup) before regen/push.
- **[Fable — high] Here-string EOF:** `prompt_deploy_set`'s capture loop read `[y/N]`
  answers from its own here-string, so a 1-member set hit EOF and `set -e` killed the
  script. Fixed: iterate the in-memory arrays.
- **[Fable — high] Unvalidated `-D` name:** `-D 'prod.'` regex-matched `prod2`. Fixed:
  `validate_deployment_name` on the flag + `read_config_value`/`delete_config_key`
  switched to literal (non-regex) matching.
- **[Fable — medium] `--all` skipped `.claspignore` guard** → fixed (fatal when a set
  member is access-managed). **[Fable — medium] validators never called** → fixed
  (both deploy paths validate before regen). **[Fable — low] mktemp 600 perms leaked
  onto `appsscript.json`** → fixed (mode preserved across mv). **[Fable — low]
  `is_in_deploy_set` vs trimmed names** → fixed. Plus nits (printf, remove-from-set
  guard, wording).

**Final Codex verification pass (of the post-fix diff):**

- **C1 fix was incomplete:** the pristine-restore `cp` was unguarded and `set -e` is
  suppressed inside the `if deploy_set_member` call, so a failed `cp` could still
  deploy the wrong manifest. Fixed: the restore is now checked and returns failure.
- **Single-deploy lacked the `.claspignore` fatal guard** (only `--all` had it) →
  added to the managed single-deploy path.

Every finding across all four review rounds is fixed and verified with hermetic,
stubbed tests (push counting, manifest-content capture per push, perms, restore).

---

## 15. Open items — resolved

1. **Auto-capture (§5 Tier 2):** **DEFERRED to Phase 2.** Phase 1 ships Tier-1
   guided-confirm capture only. The exact Apps Script versioned-content API call,
   OAuth scope, and token handling get verified against current docs before Tier 2.
2. **awk vs base+inject (§4.1):** **DECIDED — in-place `awk`** (string-aware brace
   matching), keeping the single canonical `appsscript.json` in git. Base+inject
   remains the documented fallback if a manifest ever proves too irregular.
3. **Deploy-set referencing a missing deployment (§12):** **DECIDED — hard-error.**
   `--all` validates every member exists before doing anything and aborts loudly.
4. **Behavioral probe expectations (§7.2):** the probe is implemented as an
   **informational WARN, never a hard failure**, and inspects the anonymous
   `/exec` redirect host (`accounts.google.com` = sign-in forced;
   `googleusercontent.com` = served). Exact signature to be confirmed empirically on
   the real admin deployment; because it is WARN-only it cannot spuriously break
   `--all`.
