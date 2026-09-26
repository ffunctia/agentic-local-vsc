#!/usr/bin/env bash
# ============================================================
# Agentic Local Version Control (LVC) — Core Engine v2
# .local_version_control/bin/lvc.sh
#
# Usage:
#   lvc.sh <PROJECT_NAME> <COMMAND> [OPTIONS]
#
# Arguments:
#   PROJECT_NAME  (required, always $1) — name of the project
#   COMMAND       (required, always $2) — one of the commands below
#
# Commands:
#   --new_version       Create a new snapshot of the project
#   --load_version      Restore the project to a saved snapshot
#   --rollback          Undo the last --load_version operation
#   --status / --changes  Show version history and current state
#   --list_versions     List all available snapshots for the project
#   --structure         Display the file tree of a snapshot
#   --compare_version   Diff two snapshots (token-optimized)
#   --show_file         Print one file from a snapshot
#   --delete_version    Remove a specific snapshot
#   --clean             Purge oldest snapshots beyond MAX_VERSIONS
#   --tag               Tag a snapshot with a friendly name
#   --update_commit     Update the commit message of a snapshot
#   --help              Print this command reference
# ============================================================

set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LVC_ROOT="$(dirname "$SCRIPT_DIR")"          # .local_version_control/
DEFAULTS_CONF="$LVC_ROOT/system_defaults.conf"

# ── Load system defaults ─────────────────────────────────────
if [[ ! -f "$DEFAULTS_CONF" ]]; then
    echo "[LVC ERROR] system_defaults.conf not found at: $DEFAULTS_CONF" >&2
    exit 1
fi
# shellcheck source=../system_defaults.conf
source "$DEFAULTS_CONF"

# ── Positional arguments ─────────────────────────────────────
PROJECT_NAME="${1:-}"
COMMAND="${2:-}"

if [[ -z "$PROJECT_NAME" ]]; then
    echo "[LVC ERROR] PROJECT_NAME (arg 1) is required." >&2
    exit 1
fi

if [[ -z "$COMMAND" ]]; then
    echo "[LVC ERROR] COMMAND (arg 2) is required." >&2
    exit 1
fi

# ── Derived paths ─────────────────────────────────────────────
VERSIONS_ROOT="${STORAGE_DIR}/${PROJECT_NAME}"
COMMITS_FILE="${VERSIONS_ROOT}/commits.md"
TEMP_VERSION_ID="v_temp"
TEMP_VERSION_DIR="${VERSIONS_ROOT}/${TEMP_VERSION_ID}"

# ── Token-guard threshold ──────────────────────────────────────
# If --compare_version output exceeds this many lines, print a warning
# and truncate, protecting the agent's context window.
DIFF_LINE_LIMIT="${DIFF_LINE_LIMIT:-200}"

# ── Status display: max rows shown from commits.md ────────────
STATUS_MAX_ROWS="${STATUS_MAX_ROWS:-20}"

# ============================================================
# HELPERS
# ============================================================

# Return the project root (directory containing .bob_skills/).
# Walks up from CWD; falls back to CWD if not found.
_find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.bob_skills" ]]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

PROJECT_ROOT="$(_find_project_root)"

# ── Directories/files that are ALWAYS excluded from every operation ──
# .bob_skills/ — LVC system files; never change and must never be overwritten
# .local_version_control/ — engine source; excluded from project workspace ops
# .git/ — version control metadata
_ALWAYS_EXCLUDE=(
    --exclude=".bob_skills/"
    --exclude=".local_version_control/"
    --exclude=".git/"
)

# Collect per-project overrides from .lvcignore if present, then merge
# with the comma-separated IGNORE_DIRS from system_defaults.conf.
# Emits one --exclude=<pattern> per line.
_build_excludes() {
    local excludes=()

    # System-wide patterns from system_defaults.conf
    IFS=',' read -ra PARTS <<< "${IGNORE_DIRS:-}"
    for part in "${PARTS[@]}"; do
        part="${part// /}"
        [[ -n "$part" ]] && excludes+=(--exclude="$part")
    done

    # Per-project overrides from .lvcignore in the project root
    local lvcignore="${PROJECT_ROOT}/.lvcignore"
    if [[ -f "$lvcignore" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip blank lines and comments
            [[ -z "$line" || "$line" == \#* ]] && continue
            excludes+=(--exclude="$line")
        done < "$lvcignore"
    fi

    printf '%s\n' "${excludes[@]}"
}

# Collect all --exclude args (user-defined + always-excluded) into an array
# Usage: _collect_excludes myarray
_collect_excludes() {
    local -n _arr="$1"
    _arr=()
    while IFS= read -r excl; do
        [[ -n "$excl" ]] && _arr+=("$excl")
    done < <(_build_excludes)
    _arr+=("${_ALWAYS_EXCLUDE[@]}")
}

# Ensure storage directory and commits.md exist for this project
_ensure_versions_dir() {
    mkdir -p "$VERSIONS_ROOT"
    if [[ ! -f "$COMMITS_FILE" ]]; then
        {
            echo "# Commits — ${PROJECT_NAME}"
            echo ""
            echo "| Version | Timestamp | Message | Tags |"
            echo "|---------|-----------|---------|------|"
        } > "$COMMITS_FILE"
    fi
}

# List all snapshot version IDs (vN dirs only, not v_temp), sorted oldest→newest
_list_snapshot_ids() {
    [[ ! -d "$VERSIONS_ROOT" ]] && return
    find "$VERSIONS_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'v[0-9]*' \
        | sed 's|.*/||' \
        | sort -t'v' -k2 -n
}

# Count snapshots (excludes v_temp)
_snapshot_count() {
    _list_snapshot_ids | wc -l | tr -d ' '
}

# Next version ID: v(N+1)
_next_version_id() {
    local latest
    latest="$(_list_snapshot_ids | tail -1)"
    if [[ -z "$latest" ]]; then
        echo "v1"
    else
        echo "v$(( ${latest#v} + 1 ))"
    fi
}

# Append a row to commits.md
_append_commit() {
    local version_id="$1" timestamp="$2" message="$3" tags="${4:-}"
    echo "| ${version_id} | ${timestamp} | ${message} | ${tags} |" >> "$COMMITS_FILE"
}

# Escape a version ID for use as a fixed-string sed pattern
_escape_for_sed() {
    printf '%s\n' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'
}

# Delete a snapshot directory and its row in commits.md
_remove_snapshot() {
    local vid="$1"
    rm -rf "${VERSIONS_ROOT:?}/${vid}"
    local esc
    esc="$(_escape_for_sed "$vid")"
    sed -i "/^| ${esc} /d" "$COMMITS_FILE"
}

# Pretty-print a directory tree without requiring the `tree` binary.
# Skips .bob_skills entries in the tree output.
_print_tree() {
    local base="$1" prefix="${2:-}"
    local entries=()
    while IFS= read -r -d $'\0' entry; do
        entries+=("$entry")
    done < <(find "$base" -maxdepth 1 -mindepth 1 \
                 ! -name '.bob_skills' \
                 ! -name '.local_version_control' \
                 ! -name '.git' \
                 -print0 | sort -z)

    local count="${#entries[@]}" i=0
    for entry in "${entries[@]}"; do
        i=$(( i + 1 ))
        local name
        name="$(basename "$entry")"
        if [[ $i -eq $count ]]; then
            echo "${prefix}└── ${name}"
            local new_prefix="${prefix}    "
        else
            echo "${prefix}├── ${name}"
            local new_prefix="${prefix}│   "
        fi
        [[ -d "$entry" ]] && _print_tree "$entry" "$new_prefix"
    done
}

# ============================================================
# COMMAND IMPLEMENTATIONS
# ============================================================

# ------------------------------------------------------------
# fn_new_version  ["commit message"]
#   Snapshots the project (excluding .bob_skills/, .git/, etc.)
#   and enforces MAX_VERSIONS.
# ------------------------------------------------------------
fn_new_version() {
    local message="${3:-No message provided}"
    _ensure_versions_dir

    local version_id
    version_id="$(_next_version_id)"
    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[LVC] Creating snapshot ${version_id} for project '${PROJECT_NAME}'..."
    mkdir -p "$snapshot_dir"

    local excl_args=()
    _collect_excludes excl_args

    if command -v rsync &>/dev/null; then
        rsync -a --quiet "${excl_args[@]}" "${PROJECT_ROOT}/" "${snapshot_dir}/"
    else
        cp -r "${PROJECT_ROOT}/." "${snapshot_dir}/"
    fi

    _append_commit "$version_id" "$timestamp" "$message" ""

    # Enforce MAX_VERSIONS: prune oldest if over limit
    local count
    count="$(_snapshot_count)"
    if [[ "$count" -gt "$MAX_VERSIONS" ]]; then
        local oldest
        oldest="$(_list_snapshot_ids | head -1)"
        echo "[LVC] MAX_VERSIONS (${MAX_VERSIONS}) reached — purging oldest snapshot: ${oldest}"
        _remove_snapshot "$oldest"
    fi

    echo "[LVC] Snapshot ${version_id} saved. (${timestamp})"
    echo "[LVC] Message: ${message}"
}

# ------------------------------------------------------------
# fn_load_version  [vX]  [file_path]
#   Saves current state to v_temp first (rollback point), then
#   restores either a full snapshot or a single file.
#   .bob_skills/ is never overwritten during restore.
# ------------------------------------------------------------
fn_load_version() {
    local version_id="${3:-}" file_path="${4:-}"
    _ensure_versions_dir

    # Default: latest snapshot
    if [[ -z "$version_id" ]]; then
        version_id="$(_list_snapshot_ids | tail -1)"
        [[ -z "$version_id" ]] && { echo "[LVC ERROR] No snapshots found." >&2; exit 1; }
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    # Safety: capture current workspace to v_temp (rollback point)
    echo "[LVC] Capturing current workspace into '${TEMP_VERSION_ID}' (rollback point)..."
    rm -rf "${TEMP_VERSION_DIR}"
    mkdir -p "${TEMP_VERSION_DIR}"

    local excl_args=()
    _collect_excludes excl_args

    if command -v rsync &>/dev/null; then
        rsync -a --quiet "${excl_args[@]}" "${PROJECT_ROOT}/" "${TEMP_VERSION_DIR}/"
    else
        cp -r "${PROJECT_ROOT}/." "${TEMP_VERSION_DIR}/"
    fi

    if [[ -n "$file_path" ]]; then
        # Single-file restore
        local src="${snapshot_dir}/${file_path}"
        [[ ! -f "$src" ]] && { echo "[LVC ERROR] File '${file_path}' not found in snapshot '${version_id}'." >&2; exit 1; }
        local dest="${PROJECT_ROOT}/${file_path}"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        echo "[LVC] Restored '${file_path}' from snapshot ${version_id}."
    else
        # Full project restore — never touch .bob_skills/
        echo "[LVC] Restoring full project from snapshot ${version_id}..."
        if command -v rsync &>/dev/null; then
            rsync -a --quiet --delete "${excl_args[@]}" "${snapshot_dir}/" "${PROJECT_ROOT}/"
        else
            cp -r "${snapshot_dir}/." "${PROJECT_ROOT}/"
        fi
        echo "[LVC] Project restored to snapshot ${version_id}."
    fi

    echo "[LVC] Rollback point saved as '${TEMP_VERSION_ID}'. Run --rollback to undo."
}

# ------------------------------------------------------------
# fn_rollback
#   Restores the v_temp pre-load state and deletes it.
#   .bob_skills/ is preserved.
# ------------------------------------------------------------
fn_rollback() {
    [[ ! -d "$TEMP_VERSION_DIR" ]] && {
        echo "[LVC ERROR] No rollback point found. Run --load_version first to create one." >&2
        exit 1
    }

    echo "[LVC] Rolling back workspace to pre-load state (${TEMP_VERSION_ID})..."

    local excl_args=()
    _collect_excludes excl_args

    if command -v rsync &>/dev/null; then
        rsync -a --quiet --delete "${excl_args[@]}" "${TEMP_VERSION_DIR}/" "${PROJECT_ROOT}/"
    else
        cp -r "${TEMP_VERSION_DIR}/." "${PROJECT_ROOT}/"
    fi

    rm -rf "$TEMP_VERSION_DIR"
    echo "[LVC] Rollback complete. '${TEMP_VERSION_ID}' has been cleared."
}

# ------------------------------------------------------------
# fn_status  (alias: --changes)
#   Shows snapshot table (last STATUS_MAX_ROWS rows) and a
#   file-level diff against the latest snapshot.
#   Excludes .bob_skills/ and .git/ from the diff.
# ------------------------------------------------------------
fn_status() {
    _ensure_versions_dir

    local count
    count="$(_snapshot_count)"
    local remaining=$(( MAX_VERSIONS - count ))

    echo "╔══════════════════════════════════════════════════════╗"
    echo "  LVC Status — Project: ${PROJECT_NAME}"
    printf "  Snapshots: %d / %d   (%d slot(s) remaining)\n" "$count" "$MAX_VERSIONS" "$remaining"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$count" -eq 0 ]]; then
        echo "  No snapshots yet. Use --new_version \"message\" to create one."
        return
    fi

    # Show commits table header + last STATUS_MAX_ROWS data rows
    local header
    header="$(head -4 "$COMMITS_FILE")"
    echo "$header"
    local data_rows
    data_rows="$(tail -n +5 "$COMMITS_FILE" | grep -v '^[[:space:]]*$' || true)"
    local total_rows
    total_rows="$(echo "$data_rows" | grep -c '.' || true)"
    if [[ "$total_rows" -gt "$STATUS_MAX_ROWS" ]]; then
        echo "  ... $((total_rows - STATUS_MAX_ROWS)) older snapshot(s) omitted (use --list_versions to see all)"
        echo "$data_rows" | tail -n "$STATUS_MAX_ROWS"
    else
        echo "$data_rows"
    fi
    echo ""

    # File-level changes since latest snapshot
    local latest
    latest="$(_list_snapshot_ids | tail -1)"
    local snapshot_dir="${VERSIONS_ROOT}/${latest}"

    echo "── Changes since ${latest} ───────────────────────────"
    local diff_output
    diff_output="$(diff -rq \
        --exclude=".bob_skills" \
        --exclude=".local_version_control" \
        --exclude=".git" \
        "${snapshot_dir}/" "${PROJECT_ROOT}/" 2>/dev/null || true)"

    if [[ -z "$diff_output" ]]; then
        echo "  No changes detected."
    else
        echo "$diff_output"
    fi
    echo ""
}

# ------------------------------------------------------------
# fn_list_versions
#   Lists all snapshots with index, size, and commit message.
# ------------------------------------------------------------
fn_list_versions() {
    _ensure_versions_dir

    local ids
    ids="$(_list_snapshot_ids)"
    if [[ -z "$ids" ]]; then
        echo "[LVC] No snapshots found for project '${PROJECT_NAME}'."
        return
    fi

    echo "Snapshots for '${PROJECT_NAME}' (oldest → newest):"
    echo ""
    local i=0
    while IFS= read -r vid; do
        i=$(( i + 1 ))
        local snap_dir="${VERSIONS_ROOT}/${vid}"
        local size
        size="$(du -sh "$snap_dir" 2>/dev/null | cut -f1)"
        local msg
        msg="$(grep "^| ${vid} " "$COMMITS_FILE" 2>/dev/null | head -1 \
              | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}')"
        local tag
        tag="$(grep "^| ${vid} " "$COMMITS_FILE" 2>/dev/null | head -1 \
              | awk -F'|' '{gsub(/^ +| +$/, "", $5); print $5}')"
        local tag_str=""
        [[ -n "$tag" ]] && tag_str=" [${tag}]"
        printf "  %2d.  %-8s  %6s   %s%s\n" "$i" "$vid" "$size" "$msg" "$tag_str"
    done <<< "$ids"
    echo ""
}

# ------------------------------------------------------------
# fn_structure  [vX]
#   Shows the file tree of a snapshot. Skips .bob_skills/,
#   .local_version_control/, and .git/ (LVC system dirs).
# ------------------------------------------------------------
fn_structure() {
    local version_id="${3:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" ]]; then
        version_id="$(_list_snapshot_ids | tail -1)"
        [[ -z "$version_id" ]] && { echo "[LVC ERROR] No snapshots found." >&2; exit 1; }
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    echo "File tree of snapshot ${version_id} (${PROJECT_NAME}):"
    echo "${version_id}/"
    _print_tree "$snapshot_dir" ""
    echo ""
}

# ------------------------------------------------------------
# fn_compare_version  [vX]  [vY]  [file_path (optional)]
#
# Token-optimized diff:
#   - Uses --minimal to guarantee the shortest possible edit script.
#   - Only 1 line of context (instead of the default 3) — enough for an
#     agent to locate a change without loading surrounding boilerplate.
#   - Ignores blank lines and whitespace-only changes.
#   - Excludes .bob_skills/, .git/, .local_version_control/ from dir diffs.
#   - Truncates output at DIFF_LINE_LIMIT lines and warns the agent.
# ------------------------------------------------------------
fn_compare_version() {
    local version_a="${3:-}" version_b="${4:-}" file_path="${5:-}"
    _ensure_versions_dir

    local all_ids
    all_ids="$(_list_snapshot_ids)"
    [[ -z "$all_ids" ]] && { echo "[LVC ERROR] No snapshots available to compare." >&2; exit 1; }

    # ── Resolve default versions ──────────────────────────────
    if [[ -z "$version_a" && -z "$version_b" ]]; then
        version_b="$(_list_snapshot_ids | tail -1)"
        version_a="$(_list_snapshot_ids | tail -2 | head -1)"
        if [[ "$version_a" == "$version_b" ]]; then
            echo "[LVC] Only one snapshot exists — comparing ${version_b} against current workspace."
            version_a="$version_b"
            version_b="current"
        fi
    elif [[ -z "$version_b" ]]; then
        version_b="current"
    fi

    # ── Resolve directories ───────────────────────────────────
    local dir_a dir_b
    if [[ "$version_a" == "current" ]]; then
        dir_a="$PROJECT_ROOT"
    else
        dir_a="${VERSIONS_ROOT}/${version_a}"
        [[ ! -d "$dir_a" ]] && { echo "[LVC ERROR] Snapshot '${version_a}' does not exist." >&2; exit 1; }
    fi

    if [[ "$version_b" == "current" ]]; then
        dir_b="$PROJECT_ROOT"
    else
        dir_b="${VERSIONS_ROOT}/${version_b}"
        [[ ! -d "$dir_b" ]] && { echo "[LVC ERROR] Snapshot '${version_b}' does not exist." >&2; exit 1; }
    fi

    echo "── Diff: ${version_a} → ${version_b} ───────────────────────────"

    # ── Run token-optimized diff ──────────────────────────────
    # --minimal      : shortest edit script (prevents hunk explosion on insertions)
    # -U1            : 1 line of context only (vs default 3)
    # --ignore-blank-lines / --ignore-space-change : suppress whitespace noise
    local raw_diff=""
    if [[ -n "$file_path" ]]; then
        raw_diff="$(diff \
            --minimal \
            -U1 \
            --ignore-blank-lines \
            --ignore-space-change \
            "${dir_a}/${file_path}" "${dir_b}/${file_path}" 2>/dev/null || true)"
    else
        raw_diff="$(diff \
            --minimal \
            -rU1 \
            --ignore-blank-lines \
            --ignore-space-change \
            --exclude=".bob_skills" \
            --exclude=".local_version_control" \
            --exclude=".git" \
            "$dir_a" "$dir_b" 2>/dev/null || true)"
    fi

    if [[ -z "$raw_diff" ]]; then
        echo "  No differences found."
        echo ""
        return
    fi

    # ── Token guard: truncate if output is too large ──────────
    local line_count
    line_count="$(echo "$raw_diff" | wc -l | tr -d ' ')"

    if [[ "$line_count" -gt "$DIFF_LINE_LIMIT" ]]; then
        echo "$raw_diff" | head -n "$DIFF_LINE_LIMIT"
        echo ""
        echo "⚠  [LVC WARNING] Diff truncated at ${DIFF_LINE_LIMIT} lines (total: ${line_count} lines)."
        echo "   To keep your context window clean, compare individual files:"
        echo "   bash .bob_skills/local_version_control/commands/lvc.sh --compare_version ${version_a} ${version_b} <file_path>"
    else
        echo "$raw_diff"
    fi
    echo ""
}

# ------------------------------------------------------------
# fn_show_file  [vX]  [file_path]
#   Prints the contents of a single file from a past snapshot.
# ------------------------------------------------------------
fn_show_file() {
    local version_id="${3:-}" file_path="${4:-}"
    _ensure_versions_dir

    [[ -z "$version_id" || -z "$file_path" ]] && {
        echo "[LVC ERROR] Usage: --show_file <vX> <file_path>" >&2; exit 1
    }

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    local full_path="${snapshot_dir}/${file_path}"
    [[ ! -f "$full_path" ]] && { echo "[LVC ERROR] File '${file_path}' not found in snapshot '${version_id}'." >&2; exit 1; }

    echo "── ${version_id}/${file_path} ────────────────────────────────"
    cat "$full_path"
    echo ""
}

# ------------------------------------------------------------
# fn_delete_version  [vX]
#   Permanently deletes a snapshot. Refuses if it is the last one.
# ------------------------------------------------------------
fn_delete_version() {
    local version_id="${3:-}"
    _ensure_versions_dir

    [[ -z "$version_id" ]] && { echo "[LVC ERROR] Usage: --delete_version <vX>" >&2; exit 1; }

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    local count
    count="$(_snapshot_count)"
    if [[ "$count" -le 1 && "$version_id" != "$TEMP_VERSION_ID" ]]; then
        echo "[LVC ERROR] Cannot delete the only remaining snapshot ('${version_id}')." >&2
        exit 1
    fi

    _remove_snapshot "$version_id"
    echo "[LVC] Snapshot '${version_id}' deleted."
}

# ------------------------------------------------------------
# fn_clean
#   Purges oldest snapshots until count <= MAX_VERSIONS.
# ------------------------------------------------------------
fn_clean() {
    _ensure_versions_dir

    local count
    count="$(_snapshot_count)"
    if [[ "$count" -le "$MAX_VERSIONS" ]]; then
        echo "[LVC] Storage within limit (${count}/${MAX_VERSIONS}). Nothing to purge."
        return
    fi

    local purge_count=$(( count - MAX_VERSIONS ))
    echo "[LVC] Purging ${purge_count} oldest snapshot(s)..."

    local i=0
    while IFS= read -r vid; do
        [[ $i -ge $purge_count ]] && break
        _remove_snapshot "$vid"
        echo "[LVC]   Deleted: ${vid}"
        i=$(( i + 1 ))
    done < <(_list_snapshot_ids)

    echo "[LVC] Clean complete."
}

# ------------------------------------------------------------
# fn_tag  [vX]  [tag_name]
#   Applies a tag label to a snapshot's commits.md row.
#   Uses field-aware Python replacement to avoid regex fragility.
# ------------------------------------------------------------
fn_tag() {
    local version_id="${3:-}" tag_name="${4:-}"
    _ensure_versions_dir

    [[ -z "$version_id" || -z "$tag_name" ]] && {
        echo "[LVC ERROR] Usage: --tag <vX> <tag_name>" >&2; exit 1
    }

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    if ! grep -qF "| ${version_id} " "$COMMITS_FILE"; then
        echo "[LVC ERROR] No commit entry found for '${version_id}'." >&2; exit 1
    fi

    # Use Python for safe field-aware column replacement (Bug 9 fix)
    python3 - "$COMMITS_FILE" "$version_id" "$tag_name" <<'PYEOF'
import sys
commits_file, vid, tag = sys.argv[1], sys.argv[2], sys.argv[3]
with open(commits_file, 'r') as f:
    lines = f.readlines()
out = []
for line in lines:
    if line.startswith(f"| {vid} "):
        parts = line.rstrip('\n').split('|')
        # parts: ['', version, timestamp, message, tags, '']
        if len(parts) >= 5:
            parts[4] = f" {tag} "
        line = '|'.join(parts) + '\n'
    out.append(line)
with open(commits_file, 'w') as f:
    f.writelines(out)
PYEOF

    echo "[LVC] Tag '${tag_name}' applied to snapshot '${version_id}'."
}

# ------------------------------------------------------------
# fn_update_commit  [vX]  "new_message"
#   Replaces the message column for a specific snapshot row.
# ------------------------------------------------------------
fn_update_commit() {
    local version_id="${3:-}" new_message="${4:-}"
    _ensure_versions_dir

    [[ -z "$version_id" || -z "$new_message" ]] && {
        echo "[LVC ERROR] Usage: --update_commit <vX> \"new message\"" >&2; exit 1
    }

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    [[ ! -d "$snapshot_dir" ]] && { echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2; exit 1; }

    if ! grep -qF "| ${version_id} " "$COMMITS_FILE"; then
        echo "[LVC ERROR] No commit entry found for '${version_id}'." >&2; exit 1
    fi

    python3 - "$COMMITS_FILE" "$version_id" "$new_message" <<'PYEOF'
import sys
commits_file, vid, new_msg = sys.argv[1], sys.argv[2], sys.argv[3]
with open(commits_file, 'r') as f:
    lines = f.readlines()
out = []
for line in lines:
    if line.startswith(f"| {vid} "):
        parts = line.rstrip('\n').split('|')
        # parts: ['', version, timestamp, message, tags, '']
        if len(parts) >= 5:
            parts[3] = f" {new_msg} "
        line = '|'.join(parts) + '\n'
    out.append(line)
with open(commits_file, 'w') as f:
    f.writelines(out)
PYEOF

    echo "[LVC] Commit message for '${version_id}' updated."
}

# ------------------------------------------------------------
# fn_help
# ------------------------------------------------------------
fn_help() {
    cat <<'HELP'
Agentic Local Version Control (LVC) — Command Reference

  Usage (via pass-through shim):
    bash .bob_skills/local_version_control/commands/lvc.sh <COMMAND> [OPTIONS]

  Snapshot Management
    --new_version "message"          Create a new snapshot with a commit message
    --load_version [vX] [file]       Restore a full snapshot or a single file
    --rollback                        Undo the last --load_version (uses v_temp)
    --delete_version <vX>            Delete a specific snapshot (min 1 kept)
    --clean                           Purge oldest snapshots beyond MAX_VERSIONS

  Inspection
    --status / --changes             Show snapshot table and workspace diff
    --list_versions                  List all snapshots with size and tags
    --structure [vX]                 Show file tree of a snapshot
    --show_file <vX> <file>         Print one file from a past snapshot

  Comparison (token-optimized)
    --compare_version [vX [vY [file]]]
        Diff two snapshots. Defaults: latest-1 → latest.
        Use "current" as a version to compare against the live workspace.
        Output is capped at DIFF_LINE_LIMIT lines to protect context windows.

  Metadata
    --tag <vX> <tag_name>            Apply a tag label to a snapshot
    --update_commit <vX> "message"   Update the commit message of a snapshot

  Per-project exclusions
    Create a .lvcignore file in the project root (same syntax as .gitignore).
    Lines starting with # are comments. Example:
      logs/
      *.log
      tmp/

  Configuration (system_defaults.conf)
    STORAGE_DIR      — where snapshots are stored (default: ~/Documents/.local_versions)
    MAX_VERSIONS     — maximum snapshots per project (default: 10)
    IGNORE_DIRS      — comma-separated global exclusion patterns
    DIFF_LINE_LIMIT  — max diff lines before truncation warning (default: 200)
    STATUS_MAX_ROWS  — max snapshot rows shown in --status (default: 20)
HELP
}

# ============================================================
# MAIN — Command dispatch
# ============================================================
case "$COMMAND" in
    --new_version)      fn_new_version "$@" ;;
    --load_version)     fn_load_version "$@" ;;
    --rollback)         fn_rollback ;;
    --status|--changes) fn_status ;;
    --list_versions)    fn_list_versions ;;
    --structure)        fn_structure "$@" ;;
    --compare_version)  fn_compare_version "$@" ;;
    --show_file)        fn_show_file "$@" ;;
    --delete_version)   fn_delete_version "$@" ;;
    --clean)            fn_clean ;;
    --tag)              fn_tag "$@" ;;
    --update_commit)    fn_update_commit "$@" ;;
    --help)             fn_help ;;
    *)
        echo "[LVC ERROR] Unknown command: '$COMMAND'" >&2
        echo "Run --help for the full command reference." >&2
        exit 1
        ;;
esac
