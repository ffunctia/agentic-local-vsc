#!/bin/bash
set -euo pipefail

SYSTEM_DEST="$HOME/.local/share/local_version_control"
STORAGE_DEST="$HOME/Documents/.local_versions"

echo "Initializing installation sequence..."

# ── 1. Create directories ─────────────────────────────────────
mkdir -p "$SYSTEM_DEST"
mkdir -p "$STORAGE_DEST"

# ── 2. Deploy engine to system directory ──────────────────────
if [ -d "./.local_version_control" ]; then
    cp -r ./.local_version_control/* "$SYSTEM_DEST/"
    echo "SUCCESS: System binaries deployed to $SYSTEM_DEST."
else
    echo "ERROR: Source directory './.local_version_control' not found."
    exit 1
fi

# ── 3. Engine permissions (system directory) ──────────────────
# The engine and its config live outside the project workspace.
# Owner can read/write/execute; group and others have no access,
# preventing any unprivileged process from reading engine internals.
chmod 700 "$SYSTEM_DEST"
chmod 700 "$SYSTEM_DEST/bin"
chmod 750 "$SYSTEM_DEST/bin/lvc.sh"       # owner: rwx  group: r-x  others: ---
chmod 640 "$SYSTEM_DEST/system_defaults.conf" 2>/dev/null || true  # owner: rw-  group: r--

# ── 4. Project-side .bob_skills/ permissions ──────────────────
# Applied here so users who clone and run install.sh immediately
# get the correct access contract without any manual chmod step.
# These permissions express the *intended* agent access policy:
#
#   File / Dir                    Mode    Rationale
#   ─────────────────────────────────────────────────────────────
#   .bob_skills/local_version_control/    r-x   traversable, not writable
#   commands/                     r-x     traversable, not writable
#   commands/lvc.sh               r-x     read+execute, no write; policy forbids agent from reading .sh
#   explanation.md                r--     read-only; no write
#   forbidden_actions.md          r--     read-only; no write
#   project_name.conf             rw-     agent writes project name via sed -i

BOB_SKILLS_LVC=".bob_skills/local_version_control"

if [ -d "$BOB_SKILLS_LVC" ]; then
    # Directories: owner rwx, group r-x, others r-x (traversable)
    chmod 755 "$BOB_SKILLS_LVC"
    chmod 755 "$BOB_SKILLS_LVC/commands"

    # Shim script: read+execute for everyone, no write access.
    # This prevents any process from modifying the shim while keeping it
    # runnable via `bash lvc.sh`. The agent is additionally prohibited
    # from reading shell script contents by the forbidden_actions.md policy.
    chmod 555 "$BOB_SKILLS_LVC/commands/lvc.sh"

    # Markdown instruction files: read-only for everyone
    chmod 444 "$BOB_SKILLS_LVC/explanation.md"      2>/dev/null || true
    chmod 444 "$BOB_SKILLS_LVC/forbidden_actions.md" 2>/dev/null || true

    # Project name config: owner read+write, others read-only
    # (sed -i used by the agent runs as the same user, so owner write is sufficient)
    chmod 644 "$BOB_SKILLS_LVC/project_name.conf"

    echo "SUCCESS: .bob_skills/ permissions configured."
else
    echo "NOTE: .bob_skills/ not found in current directory — skipping project permission setup."
    echo "      Run this script from the project root after copying .bob_skills/ there."
fi

echo ""
echo "Installation successfully completed."
echo "Usage: Copy the '.bob_skills' folder into the root directory of your target project,"
echo "       then re-run install.sh (or run: bash install.sh) from that project root to"
echo "       apply the correct file permissions."