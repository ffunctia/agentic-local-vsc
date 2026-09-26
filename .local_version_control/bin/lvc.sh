#!/usr/bin/env bash
# ============================================================
# Agentic Local Version Control (LVC) — Core Engine
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

# ── Helpers ──────────────────────────────────────────────────

# Return the project root (the directory that contains the .bob_skills folder).
# We walk up from the CWD until we find it, or fall back to CWD.
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

# Build the rsync/cp exclude arguments from IGNORE_DIRS
_build_excludes() {
    local excludes=()
    IFS=',' read -ra PARTS <<< "${IGNORE_DIRS:-}"
    for part in "${PARTS[@]}"; do
        part="${part// /}"   # trim spaces
        [[ -n "$part" ]] && excludes+=(--exclude="$part")
    done
    printf '%s\n' "${excludes[@]}"
}

# Ensure the versions directory for this project exists
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

# List all snapshot version IDs (vN directories), sorted oldest→newest
_list_snapshot_ids() {
    if [[ ! -d "$VERSIONS_ROOT" ]]; then
        return
    fi
    # Find directories named v<number> only (not v_temp)
    find "$VERSIONS_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'v[0-9]*' \
        | sed 's|.*/||' \
        | sort -t'v' -k2 -n
}

# Return the next version ID (e.g. v4 when v3 is the latest)
_next_version_id() {
    local latest
    latest="$(_list_snapshot_ids | tail -1)"
    if [[ -z "$latest" ]]; then
        echo "v1"
    else
        local num="${latest#v}"
        echo "v$((num + 1))"
    fi
}

# Append a row to commits.md
_append_commit() {
    local version_id="$1"
    local timestamp="$2"
    local message="$3"
    local tags="${4:-}"
    echo "| ${version_id} | ${timestamp} | ${message} | ${tags} |" >> "$COMMITS_FILE"
}

# Count existing snapshots (excluding v_temp)
_snapshot_count() {
    _list_snapshot_ids | wc -l | tr -d ' '
}

# Pretty-print a directory tree (works without the `tree` binary)
_print_tree() {
    local base="$1"
    local prefix="${2:-}"
    local entries=()
    while IFS= read -r -d $'\0' entry; do
        entries+=("$entry")
    done < <(find "$base" -maxdepth 1 -mindepth 1 -print0 | sort -z)

    local count="${#entries[@]}"
    local i=0
    for entry in "${entries[@]}"; do
        i=$((i + 1))
        local name
        name="$(basename "$entry")"
        if [[ $i -eq $count ]]; then
            echo "${prefix}└── ${name}"
            local new_prefix="${prefix}    "
        else
            echo "${prefix}├── ${name}"
            local new_prefix="${prefix}│   "
        fi
        if [[ -d "$entry" ]]; then
            _print_tree "$entry" "$new_prefix"
        fi
    done
}

# ============================================================
# COMMAND IMPLEMENTATIONS
# ============================================================

# ------------------------------------------------------------
# fn_new_version  ["commit message"]
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

    # Build exclude list
    local rsync_excludes=()
    while IFS= read -r excl; do
        [[ -n "$excl" ]] && rsync_excludes+=("$excl")
    done < <(_build_excludes)

    # Always exclude the LVC system dirs and .git
    rsync_excludes+=(--exclude=".local_version_control/" --exclude=".git/")

    if command -v rsync &>/dev/null; then
        rsync -a --quiet "${rsync_excludes[@]}" "${PROJECT_ROOT}/" "${snapshot_dir}/"
    else
        # Fallback: cp -r (less precise exclusions)
        cp -r "${PROJECT_ROOT}/." "${snapshot_dir}/"
    fi

    _append_commit "$version_id" "$timestamp" "$message" ""

    # Enforce MAX_VERSIONS
    local count
    count="$(_snapshot_count)"
    if [[ "$count" -gt "$MAX_VERSIONS" ]]; then
        local oldest
        oldest="$(_list_snapshot_ids | head -1)"
        echo "[LVC] MAX_VERSIONS (${MAX_VERSIONS}) reached — purging oldest snapshot: ${oldest}"
        rm -rf "${VERSIONS_ROOT:?}/${oldest}"
        # Remove its row from commits.md
        local escaped_oldest
        escaped_oldest="$(printf '%s\n' "$oldest" | sed 's/[[\.*^$()+?{|]/\\&/g')"
        sed -i "/^| ${escaped_oldest} /d" "$COMMITS_FILE"
    fi

    echo "[LVC] Snapshot ${version_id} saved. (${timestamp})"
    echo "[LVC] Message: ${message}"
}

# ------------------------------------------------------------
# fn_load_version  [vX]  [file_path]
# ------------------------------------------------------------
fn_load_version() {
    local version_id="${3:-}"
    local file_path="${4:-}"
    _ensure_versions_dir

    # Resolve version_id (default: latest)
    if [[ -z "$version_id" ]]; then
        version_id="$(_list_snapshot_ids | tail -1)"
        if [[ -z "$version_id" ]]; then
            echo "[LVC ERROR] No snapshots found for project '${PROJECT_NAME}'." >&2
            exit 1
        fi
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    # Safety: capture current state into v_temp before overwriting
    echo "[LVC] Capturing current workspace into '${TEMP_VERSION_ID}' (rollback point)..."
    rm -rf "${TEMP_VERSION_DIR}"
    mkdir -p "${TEMP_VERSION_DIR}"

    local rsync_excludes=()
    while IFS= read -r excl; do
        [[ -n "$excl" ]] && rsync_excludes+=("$excl")
    done < <(_build_excludes)
    rsync_excludes+=(--exclude=".local_version_control/" --exclude=".git/")

    if command -v rsync &>/dev/null; then
        rsync -a --quiet "${rsync_excludes[@]}" "${PROJECT_ROOT}/" "${TEMP_VERSION_DIR}/"
    else
        cp -r "${PROJECT_ROOT}/." "${TEMP_VERSION_DIR}/"
    fi

    if [[ -n "$file_path" ]]; then
        # Single-file restore
        local src="${snapshot_dir}/${file_path}"
        if [[ ! -f "$src" ]]; then
            echo "[LVC ERROR] File '${file_path}' not found in snapshot '${version_id}'." >&2
            exit 1
        fi
        local dest="${PROJECT_ROOT}/${file_path}"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        echo "[LVC] Restored '${file_path}' from snapshot ${version_id}."
    else
        # Full project restore
        echo "[LVC] Restoring full project from snapshot ${version_id}..."
        if command -v rsync &>/dev/null; then
            rsync -a --quiet --delete \
                --exclude=".local_version_control/" --exclude=".git/" \
                "${snapshot_dir}/" "${PROJECT_ROOT}/"
        else
            cp -r "${snapshot_dir}/." "${PROJECT_ROOT}/"
        fi
        echo "[LVC] Project restored to snapshot ${version_id}."
    fi

    echo "[LVC] Rollback point saved as '${TEMP_VERSION_ID}'. Run --rollback to undo."
}

# ------------------------------------------------------------
# fn_rollback
# ------------------------------------------------------------
fn_rollback() {
    if [[ ! -d "$TEMP_VERSION_DIR" ]]; then
        echo "[LVC ERROR] No rollback point found. Run --load_version first to create one." >&2
        exit 1
    fi

    echo "[LVC] Rolling back workspace to pre-load state (${TEMP_VERSION_ID})..."

    if command -v rsync &>/dev/null; then
        rsync -a --quiet --delete \
            --exclude=".local_version_control/" --exclude=".git/" \
            "${TEMP_VERSION_DIR}/" "${PROJECT_ROOT}/"
    else
        cp -r "${TEMP_VERSION_DIR}/." "${PROJECT_ROOT}/"
    fi

    rm -rf "$TEMP_VERSION_DIR"
    echo "[LVC] Rollback complete. '${TEMP_VERSION_ID}' has been cleared."
}

# ------------------------------------------------------------
# fn_status  (alias: --changes)
# ------------------------------------------------------------
fn_status() {
    _ensure_versions_dir

    local count
    count="$(_snapshot_count)"
    local remaining=$((MAX_VERSIONS - count))

    echo "╔══════════════════════════════════════════════════════╗"
    echo "  LVC Status — Project: ${PROJECT_NAME}"
    echo "  Snapshots: ${count} / ${MAX_VERSIONS}   (${remaining} slot(s) remaining)"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$count" -eq 0 ]]; then
        echo "  No snapshots found."
        return
    fi

    # Print commits.md table
    cat "$COMMITS_FILE"
    echo ""

    # Show pending changes vs. latest snapshot
    local latest
    latest="$(_list_snapshot_ids | tail -1)"
    local snapshot_dir="${VERSIONS_ROOT}/${latest}"

    echo "── Changes since ${latest} ───────────────────────────"
    local diff_output
    diff_output="$(diff -rq \
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
        i=$((i + 1))
        local snap_dir="${VERSIONS_ROOT}/${vid}"
        local size
        size="$(du -sh "$snap_dir" 2>/dev/null | cut -f1)"
        # Pull commit message from commits.md
        local msg
        msg="$(grep "^| ${vid} " "$COMMITS_FILE" 2>/dev/null | head -1 | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}')"
        printf "  %2d.  %-8s  %6s   %s\n" "$i" "$vid" "$size" "$msg"
    done <<< "$ids"
    echo ""
}

# ------------------------------------------------------------
# fn_structure  [vX]
# ------------------------------------------------------------
fn_structure() {
    local version_id="${3:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" ]]; then
        version_id="$(_list_snapshot_ids | tail -1)"
        if [[ -z "$version_id" ]]; then
            echo "[LVC ERROR] No snapshots found." >&2
            exit 1
        fi
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    echo "File tree of snapshot ${version_id} (${PROJECT_NAME}):"
    echo "${version_id}/"
    _print_tree "$snapshot_dir" ""
    echo ""
}

# ------------------------------------------------------------
# fn_compare_version  [vX]  [vY]  [file_path (optional)]
# ------------------------------------------------------------
fn_compare_version() {
    local version_a="${3:-}"
    local version_b="${4:-}"
    local file_path="${5:-}"
    _ensure_versions_dir

    local all_ids
    all_ids="$(_list_snapshot_ids)"

    if [[ -z "$all_ids" ]]; then
        echo "[LVC ERROR] No snapshots available to compare." >&2
        exit 1
    fi

    # Defaults: compare second-to-last vs. latest (or latest vs. current)
    if [[ -z "$version_a" && -z "$version_b" ]]; then
        version_b="$(_list_snapshot_ids | tail -1)"
        version_a="$(_list_snapshot_ids | tail -2 | head -1)"
        if [[ "$version_a" == "$version_b" ]]; then
            echo "[LVC] Only one snapshot exists — comparing ${version_b} against current workspace."
            version_a="current"
        fi
    elif [[ -z "$version_b" ]]; then
        version_b="current"
    fi

    local dir_a dir_b
    if [[ "$version_a" == "current" ]]; then
        dir_a="$PROJECT_ROOT"
    else
        dir_a="${VERSIONS_ROOT}/${version_a}"
        if [[ ! -d "$dir_a" ]]; then
            echo "[LVC ERROR] Snapshot '${version_a}' does not exist." >&2; exit 1
        fi
    fi

    if [[ "$version_b" == "current" ]]; then
        dir_b="$PROJECT_ROOT"
    else
        dir_b="${VERSIONS_ROOT}/${version_b}"
        if [[ ! -d "$dir_b" ]]; then
            echo "[LVC ERROR] Snapshot '${version_b}' does not exist." >&2; exit 1
        fi
    fi

    echo "── Diff: ${version_a} → ${version_b} ───────────────────────────"
    if [[ -n "$file_path" ]]; then
        diff -u --ignore-blank-lines --ignore-space-change \
            "${dir_a}/${file_path}" "${dir_b}/${file_path}" || true
    else
        diff -rU3 --ignore-blank-lines --ignore-space-change \
            --exclude=".local_version_control" --exclude=".git" \
            "$dir_a" "$dir_b" || true
    fi
    echo ""
}

# ------------------------------------------------------------
# fn_show_file  [vX]  [file_path]
# ------------------------------------------------------------
fn_show_file() {
    local version_id="${3:-}"
    local file_path="${4:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" || -z "$file_path" ]]; then
        echo "[LVC ERROR] Usage: --show_file <vX> <file_path>" >&2
        exit 1
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    local full_path="${snapshot_dir}/${file_path}"
    if [[ ! -f "$full_path" ]]; then
        echo "[LVC ERROR] File '${file_path}' not found in snapshot '${version_id}'." >&2
        exit 1
    fi

    echo "── ${version_id}/${file_path} ────────────────────────────────"
    cat "$full_path"
    echo ""
}

# ------------------------------------------------------------
# fn_delete_version  [vX]
# ------------------------------------------------------------
fn_delete_version() {
    local version_id="${3:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" ]]; then
        echo "[LVC ERROR] Usage: --delete_version <vX>" >&2
        exit 1
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    # Refuse to delete the sole remaining snapshot
    local count
    count="$(_snapshot_count)"
    if [[ "$count" -le 1 && "$version_id" != "$TEMP_VERSION_ID" ]]; then
        echo "[LVC ERROR] Cannot delete the only remaining snapshot ('${version_id}')." >&2
        exit 1
    fi

    rm -rf "${snapshot_dir}"

    # Remove row from commits.md
    local escaped
    escaped="$(printf '%s\n' "$version_id" | sed 's/[[\.*^$()+?{|]/\\&/g')"
    sed -i "/^| ${escaped} /d" "$COMMITS_FILE"

    echo "[LVC] Snapshot '${version_id}' deleted."
}

# ------------------------------------------------------------
# fn_clean
# ------------------------------------------------------------
fn_clean() {
    _ensure_versions_dir

    local count
    count="$(_snapshot_count)"
    if [[ "$count" -le "$MAX_VERSIONS" ]]; then
        echo "[LVC] Storage within limit (${count}/${MAX_VERSIONS}). Nothing to purge."
        return
    fi

    local purge_count=$((count - MAX_VERSIONS))
    echo "[LVC] Purging ${purge_count} oldest snapshot(s)..."

    local i=0
    while IFS= read -r vid; do
        [[ $i -ge $purge_count ]] && break
        rm -rf "${VERSIONS_ROOT:?}/${vid}"
        local escaped
        escaped="$(printf '%s\n' "$vid" | sed 's/[[\.*^$()+?{|]/\\&/g')"
        sed -i "/^| ${escaped} /d" "$COMMITS_FILE"
        echo "[LVC]   Deleted: ${vid}"
        i=$((i + 1))
    done < <(_list_snapshot_ids)

    echo "[LVC] Clean complete."
}

# ------------------------------------------------------------
# fn_tag  [vX]  [tag_name]
# ------------------------------------------------------------
fn_tag() {
    local version_id="${3:-}"
    local tag_name="${4:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" || -z "$tag_name" ]]; then
        echo "[LVC ERROR] Usage: --tag <vX> <tag_name>" >&2
        exit 1
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    # Update the Tags column (5th pipe-delimited field) in commits.md
    local escaped
    escaped="$(printf '%s\n' "$version_id" | sed 's/[[\.*^$()+?{|]/\\&/g')"
    if ! grep -q "^| ${escaped} " "$COMMITS_FILE"; then
        echo "[LVC ERROR] No commit entry found for '${version_id}'." >&2
        exit 1
    fi

    sed -i "s/^| ${escaped} \(.*\)|[^|]*|$/| ${escaped} \1| ${tag_name} |/" "$COMMITS_FILE"
    echo "[LVC] Tag '${tag_name}' applied to snapshot '${version_id}'."
}

# ------------------------------------------------------------
# fn_update_commit  [vX]  "new_message"
# ------------------------------------------------------------
fn_update_commit() {
    local version_id="${3:-}"
    local new_message="${4:-}"
    _ensure_versions_dir

    if [[ -z "$version_id" || -z "$new_message" ]]; then
        echo "[LVC ERROR] Usage: --update_commit <vX> \"new message\"" >&2
        exit 1
    fi

    local snapshot_dir="${VERSIONS_ROOT}/${version_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "[LVC ERROR] Snapshot '${version_id}' does not exist." >&2
        exit 1
    fi

    local escaped_id
    escaped_id="$(printf '%s\n' "$version_id" | sed 's/[[\.*^$()+?{|]/\\&/g')"
    if ! grep -q "^| ${escaped_id} " "$COMMITS_FILE"; then
        echo "[LVC ERROR] No commit entry found for '${version_id}'." >&2
        exit 1
    fi

    # Replace the message field (4th column) while preserving version, timestamp, and tags
    python3 - "$COMMITS_FILE" "$version_id" "$new_message" <<'PYEOF'
import sys, re
commits_file, vid, new_msg = sys.argv[1], sys.argv[2], sys.argv[3]
with open(commits_file, 'r') as f:
    lines = f.readlines()
out = []
for line in lines:
    if line.startswith(f"| {vid} "):
        parts = line.split('|')
        # parts: ['', version, timestamp, message, tags, '\n']
        if len(parts) >= 5:
            parts[3] = f" {new_msg} "
        line = '|'.join(parts)
    out.append(line)
with open(commits_file, 'w') as f:
    f.writelines(out)
PYEOF

    echo "[LVC] Commit message for '${version_id}' updated."
}

# ============================================================
# MAIN — Command dispatch
# ============================================================
case "$COMMAND" in
    --new_version)
        fn_new_version "$@"
        ;;
    --load_version)
        fn_load_version "$@"
        ;;
    --rollback)
        fn_rollback
        ;;
    --status|--changes)
        fn_status
        ;;
    --list_versions)
        fn_list_versions
        ;;
    --structure)
        fn_structure "$@"
        ;;
    --compare_version)
        fn_compare_version "$@"
        ;;
    --show_file)
        fn_show_file "$@"
        ;;
    --delete_version)
        fn_delete_version "$@"
        ;;
    --clean)
        fn_clean
        ;;
    --tag)
        fn_tag "$@"
        ;;
    --update_commit)
        fn_update_commit "$@"
        ;;
    *)
        echo "[LVC ERROR] Unknown command: '$COMMAND'" >&2
        echo "Valid commands: --new_version | --load_version | --rollback | --status | --changes |" >&2
        echo "                --list_versions | --structure | --compare_version | --show_file |" >&2
        echo "                --delete_version | --clean | --tag | --update_commit" >&2
        exit 1
        ;;
esac
