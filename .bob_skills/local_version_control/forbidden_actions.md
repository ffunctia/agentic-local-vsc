# STRICT OPERATIONAL RULES AND FORBIDDEN ACTIONS

As an autonomous AI agent, you must strictly adhere to the following security protocols. Violating these boundaries will compromise the integrity of the sandbox environment and may result in catastrophic data loss.

## 1. Directory and File Modification Bans
* **DO NOT** edit, delete, rename, or move any file or folder located within the `.bob_skills/` directory. These are critical, read-only configuration and instruction files. The **only** permitted write operation inside `.bob_skills/` is using `sed -i` to set `PROJECT_NAME` in `project_name.conf`.
* **DO NOT** manually navigate to, modify, or delete contents within the backend storage and system directories (`~/Documents/.local_versions/` and `~/.local/share/local_version_control/`).

## 2. Destructive Terminal Commands
* **DO NOT** execute destructive standard terminal commands such as `rm -rf`, `rm -r`, or equivalent recursive deletion tools in the project root or any of its subdirectories to manage file states.
* **DO NOT** use wildcard characters (`*`) in combination with any deletion commands to clean up the workspace.

## 3. Version Control Limitations
* **DO NOT** attempt to manually create backup folders, zip files, or tarballs to save your progress.
* **DO NOT** write custom shell scripts to manage backups, rollbacks, or file comparisons.
* You must rely entirely and exclusively on the provided `bash .bob_skills/local_version_control/commands/lvc.sh` interface for all version control, restoration, and diff operations.

## 4. Shell Script Reading Ban
* **DO NOT** read, print, or inspect the contents of any `.sh` file within this project — including `.bob_skills/local_version_control/commands/lvc.sh` and any scripts in `~/.local/share/local_version_control/`. These files are opaque by design.
* You are permitted to **execute** `bash .bob_skills/local_version_control/commands/lvc.sh` but never to open, `cat`, or display its source code.
* Readable files are limited to: `.md` documentation files and `project_name.conf`.

Failure to comply with these boundaries is a direct violation of your operational parameters. If you are unsure how to proceed with a file operation, refer to `explanation.md` or execute the status command via the LVC interface.