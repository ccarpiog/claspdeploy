# Common functions shared between claspdeploy and claspalt
# This file is embedded into each script during installation

# --- BEGIN COMMON FUNCTIONS ---

# Configuration
CONFIG_FILE="claspConfig.txt"

##
# Displays an error message and exits
# @param {string} $1 - Error message to display
##
show_error() {
  echo "Error: $1" >&2
  exit 1
} # End of function show_error()

##
# Reads a value from claspConfig.txt
# @param {string} $1 - Key to read (e.g., "account" or "deploymentId")
# @returns The value associated with the key, or empty string if not found
##
read_config_value() {
  local key="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    # Literal (non-regex) left-anchored match of "key=" via awk index(), so a key
    # containing regex metacharacters can never match the wrong line, and a key
    # that is a prefix of another (e.g. deployment_prod vs deployment_prod2) is
    # not confused. Everything after the first '=' is the value (values may
    # contain '='). Use || true to avoid set -e + pipefail exit on no match.
    awk -v k="$key" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$CONFIG_FILE" 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
  fi
} # End of function read_config_value()

##
# Writes or updates a value in claspConfig.txt
# @param {string} $1 - Key to write
# @param {string} $2 - Value to write
##
write_config_value() {
  local key="$1"
  local value="$2"

  if [[ -f "$CONFIG_FILE" ]]; then
    # Check if key exists using fixed string matching
    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
      # Update existing key using a temp file for compatibility
      local temp_file
      temp_file=$(mktemp)
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "${key}="* ]]; then
          echo "${key}=${value}"
        else
          echo "$line"
        fi
      done < "$CONFIG_FILE" > "$temp_file"
      mv "$temp_file" "$CONFIG_FILE"
    else
      # Append new key
      echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
  else
    # Create new file
    echo "${key}=${value}" > "$CONFIG_FILE"
  fi
} # End of function write_config_value()

##
# Checks if running in an interactive terminal
# @returns 0 if interactive, 1 if not
##
is_interactive() {
  [[ -t 0 ]]
} # End of function is_interactive()

##
# Validates that a deployment name uses only allowed characters
# @param {string} $1 - Name to validate
# @returns 0 if valid, 1 if invalid
##
validate_deployment_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    return 1
  fi
  # Only allow alphanumeric, underscore, and hyphen
  if [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    return 0
  else
    return 1
  fi
} # End of function validate_deployment_name()

##
# Reads the rootDir value from .clasp.json.
# Uses sed for Bash 3.2 compatibility (no jq dependency).
# @returns The rootDir value via echo (stdout), or empty string if absent
##
get_root_dir() {
  if [[ -f ".clasp.json" ]]; then
    # Match "rootDir" anywhere on a line so both pretty-printed and compact
    # (single-line) .clasp.json files are handled.
    sed -n 's/.*"rootDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ".clasp.json" 2>/dev/null | head -1 | tr -d '\r' || true
  fi
} # End of function get_root_dir()

##
# Resolves the path to appsscript.json by reading rootDir from .clasp.json.
# Falls back to ./appsscript.json if .clasp.json is missing or has no rootDir.
# @returns The resolved path via echo (stdout)
##
get_manifest_path() {
  local root_dir
  root_dir=$(get_root_dir)
  if [[ -z "$root_dir" ]]; then
    root_dir="."
  fi
  echo "${root_dir}/appsscript.json"
} # End of function get_manifest_path()

##
# Checks that appsscript.json contains a "webapp" configuration block.
# This is critical to prevent clasp deploy from silently converting a Web app
# deployment into a Library (a known clasp bug where the deployment type is
# not preserved when the manifest lacks webapp config).
# @returns 0 if webapp config is present, 1 if manifest is missing, 2 if webapp key is missing
##
check_webapp_manifest() {
  local manifest_path
  manifest_path=$(get_manifest_path)

  if [[ ! -f "$manifest_path" ]]; then
    return 1
  fi

  # Match the "webapp": key anywhere on a line so both pretty-printed and compact
  # (single-line / minified) manifests are detected correctly.
  if grep -Eq '"webapp"[[:space:]]*:' "$manifest_path" 2>/dev/null; then
    return 0
  else
    return 2
  fi
} # End of function check_webapp_manifest()

##
# Lists all named deployments from claspConfig.txt
# Outputs one deployment name per line, sorted alphabetically
# No output if none found
##
list_deployments() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # Match lines starting with deployment_ and extract the name part
    grep "^deployment_" "$CONFIG_FILE" 2>/dev/null | sed 's/^deployment_\([^=]*\)=.*/\1/' | sort || true
  fi
} # End of function list_deployments()

##
# Returns the currently active deployment name
# @returns The active deployment name, or empty string if not set
##
get_active_deployment_name() {
  read_config_value "activeDeployment"
} # End of function get_active_deployment_name()

##
# Returns the deployment ID of the currently active deployment
# Falls back to the plain deploymentId key for backward compatibility
# @returns The deployment ID string, or empty if not found
##
get_active_deployment_id() {
  local active_name
  active_name=$(read_config_value "activeDeployment")
  if [[ -n "$active_name" ]]; then
    local id
    id=$(read_config_value "deployment_${active_name}")
    if [[ -n "$id" ]]; then
      echo "$id"
      return
    fi
    # Named deployment missing — fall through to backward compat
  fi
  # Backward compatibility: fall back to plain deploymentId
  read_config_value "deploymentId"
} # End of function get_active_deployment_id()

##
# Saves a named deployment to the config file
# @param {string} $1 - Deployment name
# @param {string} $2 - Deployment ID
##
save_deployment() {
  local name="$1"
  local id="$2"
  write_config_value "deployment_${name}" "$id"
} # End of function save_deployment()

##
# Sets which named deployment is active
# Also mirrors the deployment ID to the deploymentId key for backward compatibility
# @param {string} $1 - Deployment name (must already exist in config)
##
set_active_deployment() {
  local name="$1"
  local id
  id=$(read_config_value "deployment_${name}")
  write_config_value "activeDeployment" "$name"
  # Mirror the ID to deploymentId for backward compatibility
  write_config_value "deploymentId" "$id"
} # End of function set_active_deployment()

##
# Removes a named deployment from the config file
# If the deleted deployment was the active one, clears activeDeployment and deploymentId
# @param {string} $1 - Deployment name to delete
##
delete_deployment() {
  local name="$1"
  local active_name

  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi

  # Remove the deployment ID line and any per-deployment access model keys.
  delete_config_key "deployment_${name}"
  delete_config_key "access_${name}"
  delete_config_key "executeAs_${name}"

  # Drop the deployment from the saved deploy set if it was a member.
  remove_from_deploy_set "$name"

  # If this was the active deployment, clear activeDeployment and deploymentId
  active_name=$(read_config_value "activeDeployment")
  if [[ "$active_name" == "$name" ]]; then
    write_config_value "activeDeployment" ""
    write_config_value "deploymentId" ""
  fi
} # End of function delete_deployment()

##
# Removes a single key line from claspConfig.txt (matches "key=" at line start).
# Uses a temp file for Bash 3.2 compatibility. No-op if the config file is absent.
# @param {string} $1 - Exact config key to remove
##
delete_config_key() {
  local key="$1"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi
  # Literal prefix match (no regex) so a key with unusual characters can never
  # delete unrelated lines. Mirrors the matching used by write_config_value.
  local temp_file line
  temp_file=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "${key}="* ]]; then
      printf '%s\n' "$line"
    fi
  done < "$CONFIG_FILE" > "$temp_file"
  mv "$temp_file" "$CONFIG_FILE"
} # End of function delete_config_key()

##
# Returns the stored web app access value for a deployment (empty if none).
# Stored under a SEPARATE key namespace (access_{name}) so that list_deployments'
# "^deployment_" scan never mistakes an attribute for a deployment name.
# @param {string} $1 - Deployment name
# @returns The access value via stdout
##
get_deployment_access() {
  read_config_value "access_${1}"
} # End of function get_deployment_access()

##
# Returns the stored executeAs value for a deployment (empty if none).
# @param {string} $1 - Deployment name
# @returns The executeAs value via stdout
##
get_deployment_execute_as() {
  read_config_value "executeAs_${1}"
} # End of function get_deployment_execute_as()

##
# Stores the web app access model (access + executeAs) for a deployment.
# Uses the access_{name} / executeAs_{name} key namespace (see get_deployment_access).
# @param {string} $1 - Deployment name
# @param {string} $2 - Access value
# @param {string} $3 - executeAs value
##
set_deployment_access_model() {
  local name="$1"
  write_config_value "access_${name}" "$2"
  write_config_value "executeAs_${name}" "$3"
} # End of function set_deployment_access_model()

##
# Checks whether a deployment is "access-managed" (has a stored access value).
# Access-managed deployments get their manifest webapp block regenerated on deploy.
# @param {string} $1 - Deployment name
# @returns 0 if access-managed, 1 otherwise
##
is_access_managed() {
  local access
  access=$(get_deployment_access "$1")
  [[ -n "$access" ]]
} # End of function is_access_managed()

##
# Validates a web app access value against the values Apps Script accepts.
# @param {string} $1 - Access value to validate
# @returns 0 if valid, 1 otherwise
##
validate_access_value() {
  case "$1" in
    MYSELF|DOMAIN|ANYONE|ANYONE_ANONYMOUS) return 0 ;;
    *) return 1 ;;
  esac
} # End of function validate_access_value()

##
# Validates an executeAs value against the values Apps Script accepts.
# @param {string} $1 - executeAs value to validate
# @returns 0 if valid, 1 otherwise
##
validate_execute_as_value() {
  case "$1" in
    USER_ACCESSING|USER_DEPLOYING) return 0 ;;
    *) return 1 ;;
  esac
} # End of function validate_execute_as_value()

##
# Returns the saved deploy set as a comma-separated string (empty if unset).
# @returns The deploySet CSV via stdout
##
get_deploy_set() {
  read_config_value "deploySet"
} # End of function get_deploy_set()

##
# Stores the saved deploy set.
# @param {string} $1 - Comma-separated, ordered list of deployment names
##
set_deploy_set() {
  write_config_value "deploySet" "$1"
} # End of function set_deploy_set()

##
# Emits the saved deploy set as one deployment name per line (nothing if unset).
# @returns Deployment names via stdout, one per line
##
get_deploy_set_names() {
  local csv
  csv=$(get_deploy_set)
  if [[ -n "$csv" ]]; then
    echo "$csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true
  fi
} # End of function get_deploy_set_names()

##
# Checks whether a deployment name is a member of the saved deploy set.
# @param {string} $1 - Deployment name
# @returns 0 if a member, 1 otherwise
##
is_in_deploy_set() {
  local name="$1"
  local current
  # Compare against the normalized (trimmed) names so a hand-edited "a, b" set is
  # consistent with get_deploy_set_names.
  while IFS= read -r current; do
    [[ "$current" == "$name" ]] && return 0
  done <<< "$(get_deploy_set_names)"
  return 1
} # End of function is_in_deploy_set()

##
# Removes a deployment name from the saved deploy set, preserving order.
# @param {string} $1 - Deployment name to remove
##
remove_from_deploy_set() {
  local name="$1"
  # Nothing to do (and don't create a clutter deploySet= line) if no set exists.
  if [[ -z "$(get_deploy_set)" ]]; then
    return 0
  fi
  local result=""
  local current
  while IFS= read -r current; do
    if [[ -n "$current" && "$current" != "$name" ]]; then
      if [[ -z "$result" ]]; then
        result="$current"
      else
        result="${result},${current}"
      fi
    fi
  done <<< "$(get_deploy_set_names)"
  # End of loop rebuilding the deploy set without the removed name
  set_deploy_set "$result"
} # End of function remove_from_deploy_set()

# Path to the temporary backup of appsscript.json used to restore the working tree
# after a deploy that regenerated the webapp block. Empty when nothing is backed up.
_MANIFEST_BACKUP=""

##
# Backs up the current appsscript.json so it can be restored after deploying.
# Sets the global _MANIFEST_BACKUP to the temp file path (empty if no manifest exists).
##
backup_manifest() {
  # Idempotent: keep the FIRST backup (the pristine original). A second call must
  # never overwrite it or leak the previous temp file.
  if [[ -n "$_MANIFEST_BACKUP" && -f "$_MANIFEST_BACKUP" ]]; then
    return 0
  fi
  local manifest_path
  manifest_path=$(get_manifest_path)
  if [[ ! -f "$manifest_path" ]]; then
    _MANIFEST_BACKUP=""
    return 0
  fi
  _MANIFEST_BACKUP=$(mktemp)
  cp "$manifest_path" "$_MANIFEST_BACKUP"
} # End of function backup_manifest()

##
# Restores appsscript.json from the backup made by backup_manifest(), if any.
# Safe to call unconditionally (e.g. from an EXIT trap); no-op when nothing is backed up.
##
restore_manifest() {
  if [[ -n "$_MANIFEST_BACKUP" && -f "$_MANIFEST_BACKUP" ]]; then
    local manifest_path mode
    manifest_path=$(get_manifest_path)
    # Preserve the current manifest's permissions across the restore mv.
    mode=$(stat -f '%Lp' "$manifest_path" 2>/dev/null || stat -c '%a' "$manifest_path" 2>/dev/null || echo "")
    mv "$_MANIFEST_BACKUP" "$manifest_path"
    if [[ -n "$mode" ]]; then chmod "$mode" "$manifest_path"; fi
    _MANIFEST_BACKUP=""
  fi
} # End of function restore_manifest()

##
# Verifies that appsscript.json currently contains the exact webapp block for the
# given access model. Used as a pre-push assertion so we never deploy the wrong model.
# @param {string} $1 - Access value
# @param {string} $2 - executeAs value
# @returns 0 if the exact block is present, 1 otherwise
##
manifest_has_webapp_block() {
  local access="$1"
  local execute_as="$2"
  local manifest_path
  manifest_path=$(get_manifest_path)
  local newblock="\"webapp\": {\"access\": \"${access}\", \"executeAs\": \"${execute_as}\"}"
  [[ -f "$manifest_path" ]] && grep -Fq "$newblock" "$manifest_path"
} # End of function manifest_has_webapp_block()

##
# Regenerates the "webapp" block of appsscript.json with the given access model.
# Replaces an existing brace-balanced "webapp" object (string-aware, so braces inside
# string values are ignored) or inserts one right after the top-level opening brace if
# absent. Writes atomically via a temp file. Bash 3.2 compatible; uses awk, no jq.
# @param {string} $1 - Web app access value (e.g. ANYONE_ANONYMOUS, DOMAIN)
# @param {string} $2 - executeAs value (USER_DEPLOYING, USER_ACCESSING)
# @returns 0 on success, 1 on failure (manifest missing or unbalanced/malformed)
##
regenerate_manifest_webapp() {
  local access="$1"
  local execute_as="$2"
  local manifest_path
  manifest_path=$(get_manifest_path)

  if [[ ! -f "$manifest_path" ]]; then
    return 1
  fi

  local newblock="\"webapp\": {\"access\": \"${access}\", \"executeAs\": \"${execute_as}\"}"

  local temp_file
  temp_file=$(mktemp)

  # awk reads the whole file and, walking it character by character while tracking
  # string context (so quotes/braces inside string VALUES are ignored) and brace
  # depth, locates the TOP-LEVEL "webapp" KEY (a depth-1 string token followed by
  # ':'). It then replaces that key's brace-balanced object value with newblock.
  # If there is no top-level webapp key it inserts the block after the first '{'
  # (with no trailing comma when the root object is empty). It exits non-zero on a
  # malformed/unbalanced manifest so we never write garbage.
  if ! awk -v newblock="$newblock" '
    function is_ws(ch) { return (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") }
    { content = content $0 "\n" }
    END {
      n = length(content)

      # Pass 1: find the top-level "webapp" key (string-aware, depth-aware).
      instr = 0; esc = 0; depth = 0; keyStart = 0; i = 1
      while (i <= n) {
        c = substr(content, i, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") { instr = 0 }
          i++
          continue
        }
        if (c == "{") { depth++; i++; continue }
        if (c == "}") { depth--; i++; continue }
        if (c == "\"") {
          # Read this string token to its closing quote.
          j = i + 1; str = ""; e2 = 0
          while (j <= n) {
            cc = substr(content, j, 1)
            if (e2) { str = str cc; e2 = 0; j++; continue }
            if (cc == "\\") { e2 = 1; j++; continue }
            if (cc == "\"") break
            str = str cc; j++
          }
          # A top-level key named webapp: depth 1, followed by optional ws then ":".
          if (depth == 1 && str == "webapp") {
            k = j + 1
            while (k <= n && is_ws(substr(content, k, 1))) k++
            if (k <= n && substr(content, k, 1) == ":") { keyStart = i; break }
          }
          i = j + 1
          continue
        }
        i++
      }

      if (keyStart == 0) {
        # No top-level webapp key: insert after the first "{".
        b = index(content, "{")
        if (b == 0) { exit 3 }
        p = b + 1
        while (p <= n && is_ws(substr(content, p, 1))) p++
        if (p <= n && substr(content, p, 1) == "}") {
          # Empty root object: insert without a trailing comma.
          printf "%s\n  %s\n%s", substr(content, 1, b), newblock, substr(content, p)
        } else {
          printf "%s\n  %s,%s", substr(content, 1, b), newblock, substr(content, b + 1)
        }
        exit 0
      }

      # Locate the value object: the ":" after the key, then its opening "{".
      m = keyStart + 1
      while (m <= n && substr(content, m, 1) != ":") m++
      if (m > n) { exit 3 }
      b = m + 1
      while (b <= n && substr(content, b, 1) != "{") {
        if (!is_ws(substr(content, b, 1))) { exit 3 }
        b++
      }
      if (b > n) { exit 3 }

      # Brace-match the value object (string-aware) to find its closing "}".
      depth = 0; instr = 0; esc = 0; j = b
      while (j <= n) {
        c = substr(content, j, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") { instr = 0 }
        } else {
          if (c == "\"") { instr = 1 }
          else if (c == "{") { depth++ }
          else if (c == "}") { depth--; if (depth == 0) break }
        }
        j++
      }
      if (depth != 0) { exit 3 }
      printf "%s%s%s", substr(content, 1, keyStart - 1), newblock, substr(content, j + 1)
      exit 0
    }
  ' "$manifest_path" > "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi

  # Sanity: the generated file must contain our exact block, or we refuse to use it.
  if ! grep -Fq "$newblock" "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi

  # Preserve the manifest's permissions (mktemp files are 600, which would
  # otherwise leak onto appsscript.json via the mv).
  local mode
  mode=$(stat -f '%Lp' "$manifest_path" 2>/dev/null || stat -c '%a' "$manifest_path" 2>/dev/null || echo "")
  mv "$temp_file" "$manifest_path"
  if [[ -n "$mode" ]]; then chmod "$mode" "$manifest_path"; fi
  return 0
} # End of function regenerate_manifest_webapp()

# --- END COMMON FUNCTIONS ---
