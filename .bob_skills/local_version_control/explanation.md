# LOCAL VERSION CONTROL SYSTEM (LVC) - AGENT INSTRUCTION MANUAL

System Prompt for Bob: In this project, you are equipped with a specialized "Local Version Control System (LVC)" designed to preserve your token limits, keep your context window clean, and ensure safe coding operations.

It is **STRICTLY FORBIDDEN** to manually create backup folders, execute system-wide destructive commands like `rm -rf`, or output entire files to the terminal just to review old code. You must perform all version control operations exclusively through the `lvc.sh` interface provided.

## BASIC EXECUTION RULE
You must execute all LVC commands from the project root directory using the following pass-through script:
`bash .bob_skills/local_version_control/commands/lvc.sh [PARAMETER]`

---

## PREREQUISITE: SET THE PROJECT NAME

**Before running any LVC command**, the project name must be configured. If it is missing, every command will exit immediately with:

```
LVC Error: PROJECT_NAME is not set in project_name.conf.
```

**How to set the project name (agent procedure):**

1. Derive a short identifier from the project's root directory name — lowercase, no spaces, hyphens or underscores only. Example: a folder named `MyWebApp` becomes `my-web-app`.
2. Write the name using `execute_command` — do **not** open the file for reading or editing:
   ```bash
   sed -i 's/^PROJECT_NAME=.*/PROJECT_NAME=<your_name>/' \
       .bob_skills/local_version_control/project_name.conf
   ```
3. Confirm the value was written:
   ```bash
   grep PROJECT_NAME .bob_skills/local_version_control/project_name.conf
   ```
4. Proceed with your LVC commands.

This step is required exactly once per project. Once the name is set, it persists across all future agent sessions.

---

## COMMAND REFERENCE GUIDE

### 1. Status and Memory Management
* **`--status` (or `--changes`)**: Checks for uncommitted modifications in the workspace since the last backup. Use this to assess the current state before writing code or taking a new backup.
* **`--list_versions`**: Do not read raw source files to understand the system's history. Use this command to instantly retrieve the chronological summary of past versions and commit messages (`commits.md`).
* **`--structure [vX]`**: Displays the file and directory tree of an older version without reading file contents.

### 2. Backup and Commit Operations
* **`--new_version "Detailed summary of your changes"`**: Safely copies the workspace modifications into a new version (e.g., v3) in the isolated storage area. *Mandatory Rule: Always execute this command after completing a significant feature or before initiating a risky refactoring process.*
* **`--tag [vX] [tag_name]`**: Applies a tag to critical versions (e.g., `--tag v3 stable`).
* **`--update_commit [vX] "new_message"`**: Updates the description of a previously recorded commit.

### 3. Smart Comparison (Token Optimization)
* **`--compare_version [vX] [vY] [file_path (optional)]`**: Compares versions. This command is highly token-optimized; it ignores whitespace changes and outputs only the modified lines with minimal context.
* **`--show_file [vX] [file_path]`**: Retrieves the contents of a single specific file from an older version. Use this instead of loading the entire project when you only need to inspect past logic.

### 4. Restore and Recovery (Critical)
* **`--load_version [vX] [file_path (optional)]`**: Replaces the current workspace with an older version. If a specific file path is provided, it restores only that file.
* **`--rollback`**: Failsafe mechanism. If you execute `--load_version` by mistake or the restoration breaks the system, the `--rollback` command will instantly revert the workspace to its exact state (`v_temp`) captured right before the load operation.

### 5. Cleanup Operations
* **`--delete_version [vX]`**: Deletes a single version that is faulty or obsolete.
* **`--clean`**: Automatically purges the oldest versions when the maximum storage limit defined in the system defaults is reached.

### 6. Help
* **`--help`**: Prints the full command reference including all options and configuration variables. Use this when unsure about a command's arguments.

### 7. Per-project Exclusions (.lvcignore)
You can exclude additional files and directories from snapshots on a per-project basis by creating a `.lvcignore` file in the project root. Its syntax is identical to `.gitignore`. Lines starting with `#` are comments.

Example `.lvcignore`:
```
# Exclude generated logs and temp files
logs/
*.log
tmp/
```

This supplements (does not replace) the global `IGNORE_DIRS` setting in `system_defaults.conf`. `.bob_skills/`, `.git/`, and `.local_version_control/` are always excluded regardless of any configuration.

---

## STRICT BEST PRACTICES FOR BOB
1. Always verify the current state with `--status` and secure it with `--new_version` prior to implementing major structural changes.
2. If a regression occurs, do not attempt to rewrite the entire file from scratch. Use `--compare_version` to isolate the specific error, or use `--load_version` to revert to a stable state.
3. Never manually alter or navigate into the backend storage directories (e.g., `~/Documents/.local_versions`). Rely entirely on the `lvc.sh` interface for all data retrieval and modification.