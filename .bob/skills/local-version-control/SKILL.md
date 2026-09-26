---
name: local-version-control
description: Use when working in a project that contains a `.bob_skills/local_version_control/` folder. Activates the Local Version Control (LVC) system — a sandboxed, token-optimized version control interface for AI agents. Use for taking snapshots, restoring versions, comparing diffs, rolling back changes, and managing project history via the lvc.sh CLI facade.
---

# Local Version Control (LVC) — Agent Activation Guide

This project is equipped with a **Local Version Control System (LVC)**. All version control operations must go through the provided CLI facade. You must never use raw destructive shell commands or attempt to manage backups manually.

## Mandatory Reading

Before performing any version control operation, read these two files:

1. `.bob_skills/local_version_control/explanation.md` — full command reference and best-practice workflow guide
2. `.bob_skills/local_version_control/forbidden_actions.md` — strict operational boundaries you must not cross

## The One Rule for Every Operation

All LVC commands are invoked exclusively through this interface:

```bash
bash .bob_skills/local_version_control/commands/lvc.sh [COMMAND] [OPTIONS]
```

Never call the engine directly or modify any file inside `.bob_skills/`.

## Startup Checklist

When this skill activates, always complete these steps **in order** before touching any code:

### Step 0 — Verify project name (mandatory first step)

Run any LVC command. If it exits with `LVC Error: PROJECT_NAME is not set`, you **must** set it before proceeding:

1. Derive the name from the project's root directory name — lowercase, no spaces, hyphens or underscores only.
2. Write it with `execute_command`:
   ```bash
   sed -i 's/^PROJECT_NAME=.*/PROJECT_NAME=<derived-name>/' \
       .bob_skills/local_version_control/project_name.conf
   ```
3. Verify it took effect:
   ```bash
   grep PROJECT_NAME .bob_skills/local_version_control/project_name.conf
   ```

Do **not** open or manually edit `project_name.conf` — use only the `sed` command above.

### Step 1 — Check current state

Run `--status` to see the snapshot history and any uncommitted changes.

### Step 2 — Take a snapshot before major changes

Run `--new_version "descriptive message"` before any significant edit, refactor, or risky operation.

### Step 3 — Rollback safety net

Use `--rollback` if a restore goes wrong — never try to manually undo a `--load_version`.

## Quick Command Reference

| Goal | Command |
|------|---------|
| Check state & pending changes | `--status` or `--changes` |
| List all snapshots | `--list_versions` |
| View a snapshot's file tree | `--structure [vX]` |
| Save current work | `--new_version "message"` |
| Restore full project or one file | `--load_version [vX] [file_path]` |
| Undo the last restore | `--rollback` |
| Compare two snapshots (token-optimized) | `--compare_version [vX] [vY] [file]` |
| Read one file from a past snapshot | `--show_file [vX] [file_path]` |
| Tag a snapshot | `--tag [vX] [tag_name]` |
| Edit a commit message | `--update_commit [vX] "new message"` |
| Delete a snapshot | `--delete_version [vX]` |
| Purge oldest beyond storage limit | `--clean` |

## Workflow: Investigating a Regression

1. Run `--list_versions` to find the last known-good snapshot.
2. Run `--compare_version vX vY [file]` to isolate the breaking change — do **not** `cat` entire files.
3. If a full restore is needed, run `--load_version vX`. A rollback point (`v_temp`) is saved automatically.
4. If the restore breaks things further, run `--rollback` immediately.

See `explanation.md` for detailed examples of each command.
