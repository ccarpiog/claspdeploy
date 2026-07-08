# Multiple deployments with different access models

> **Purpose of this document.** It states a capability we need and the constraints around
> it, deliberately **without** analysis of causes or proposed solutions, so whoever picks
> it up can investigate and design with a fresh perspective. Verify everything stated here
> yourself before building on it.

## Background

CompraLibros is a single Google Apps Script project deployed as a web app. It now needs
**two simultaneous web-app deployments of the same script**, with different access models:

| Deployment | Audience | Access model | URL |
|---|---|---|---|
| Parent form | Families (token links) | Anyone, even anonymous — no sign-in | The `/exec` URL embedded in every email sent to families (`urlPedidos`) |
| Admin panel (`?page=admin`) | School office | Restricted to the `colehispanoingles.com` Google Workspace domain — Google forces sign-in | A different `/exec` URL, bookmarked by the office |

The admin panel's security model **depends** on the second deployment enforcing sign-in:
the server code checks the signed-in user's email against an allowlist, and that email is
only trustworthy because Google authenticated it before serving the page. (See
`DEPLOYMENT.md` §7 for the full picture.)

Deployments are currently updated with **claspalt / claspdeploy**
(<https://github.com/ccarpiog/claspalt>), which pushes the local files and redeploys an
existing deployment ID taken from `claspConfig.txt` (named-deployment entries). The
project has a single manifest file, `appsscript.json`, which contains one `webapp`
configuration block.

## What we need to be able to do

1. **Run two (or more) deployments of the same script at the same time**, each with its
   own access model and its own **permanently stable URL**. Neither URL may ever change:
   the parent URL is printed in emails already sent; the admin URL is bookmarked.
2. **Ship new code to both deployments as part of the normal release routine**, from the
   command line, without a fragile sequence of steps that someone has to remember.
3. **Guarantee that updating a deployment never changes its access model.** In
   particular, the domain-restricted deployment must never end up publicly accessible as
   a side effect of a routine redeploy — and if that ever happens it must fail loudly,
   not silently.
4. **Verify, after any deploy, that each deployment still has its intended access
   model** — some check a human (or script) can run that answers "is the admin
   deployment still domain-restricted?" with certainty.
5. **Target a specific deployment unambiguously in non-interactive use** (scripts,
   CI, `--yes` runs), so an automated deploy can never act on the "wrong" deployment.
6. **Keep the current account handling** (claspalt's per-account credentials via
   `claspConfig.txt`) working as-is.

## Constraints and facts to take into account

- One Apps Script project, one `appsscript.json` in the repository, one `webapp` block
  in it. The two deployments need **different** web-app access settings.
- The Apps Script UI can create and edit deployments with per-deployment access
  settings; `clasp` interacts with deployments through the Apps Script API. How the
  API-driven path treats per-deployment web-app settings **must be carefully researched on the web**


## Relevant files

- `appsscript.json` — the single manifest with the `webapp` block.
- `claspConfig.txt` — claspalt account + named deployment IDs (do not commit secrets).
- claspalt repository: <https://github.com/ccarpiog/claspalt> (`claspdeploy.sh`).
