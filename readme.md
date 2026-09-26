# Agentic Local Version Control System (LVC)

A token-optimized, sandboxed local version control system designed specifically for Autonomous AI Agents (such as IBM Bob, Claude, or custom LLM wrappers). 

## Overview

When autonomous AI agents write code, granting them raw access to the terminal or standard version control tools (like Git) introduces significant risks and inefficiencies. Agents often consume excessive tokens reading entire file histories, exceed context window limits, or accidentally execute destructive commands (e.g., `rm -rf`).

The **Agentic Local VCS** solves these issues by introducing a "CLI Facade Pattern". It provides the AI agent with a safe, token-efficient, and restricted interface to manage code versions, review differences, and rollback errors without exposing the underlying system architecture or risking catastrophic data loss.

## Key Features

* **Token Optimization (Smart Diff):** Instead of dumping entire files into the agent's context, the `--compare_version` command uses minimal diff algorithms (ignoring whitespace and blank lines) to return only semantic changes.
* **Failsafe Rollback:** Before any old version is loaded, the system automatically captures the current workspace state into a `v_temp` directory. The agent can instantly recover from a flawed restoration using the `--rollback` command.
* **Centralized LLM Memory:** Prevents the agent from traversing directories to understand project history. A single, unified `commits.md` file serves as a highly token-efficient chronological memory log for the agent.
* **Strict Sandboxing (FHS Compliant):** The actual logic and storage backends are isolated in `~/.local/share/local_version_control/` and `~/Documents/.local_versions/`. The agent only interacts with a pass-through shim script, making privilege escalation or script manipulation impossible.

## Architecture: The CLI Facade Pattern

The system separates the agent's workspace from the actual operational logic:

1. **Unprivileged Zone (Project Workspace):** Contains only `.bob_skills/local_version_control/commands/lvc.sh` (a pass-through shim), configuration, and instruction files.
2. **Privileged Zone (System Directory):** Contains the actual executable logic (`~/.local/share/local_version_control/bin/lvc.sh`).
3. **Storage Zone (Document Directory):** Contains the isolated backups and `commits.md` file (`~/Documents/.local_versions/`).

---

## 1. System Installation (Perform Once)

First, you need to deploy the core system binaries to your local environment. Clone this repository and run the installation script.

```bash
git clone <your-repository-url>
cd agentic-local-vcs
chmod +x install.sh
./install.sh
```

The script copies `.local_version_control/` to `~/.local/share/local_version_control/` and creates the `~/Documents/.local_versions/` storage directory.

---

## 2. Project Setup (Perform Per Project)

Copy the `.bob_skills/` folder into the root of the project you want to version-control with an AI agent:

```bash
cp -r .bob_skills/ /path/to/your/project/
```

Then open `.bob_skills/local_version_control/project_name.conf` and set the project name:

```
PROJECT_NAME=my_project
```

Use a short, unique identifier with no spaces (underscores or hyphens are fine).

---

## 3. Agent Instructions

Point your AI agent to the skill files in `.bob_skills/local_version_control/`:

| File | Purpose |
|------|---------|
| `explanation.md` | Full command reference and best-practice guide for the agent |
| `forbidden_actions.md` | Hard operational boundaries the agent must not cross |
| `project_name.conf` | Project identifier consumed by the shim |
| `commands/lvc.sh` | The only interface the agent is permitted to execute |

The agent invokes every LVC operation through the pass-through shim:

```bash
bash .bob_skills/local_version_control/commands/lvc.sh [COMMAND] [OPTIONS]
```

---

## 4. Command Quick Reference

| Command | Description |
|---------|-------------|
| `--status` / `--changes` | Show snapshot history and pending file changes |
| `--list_versions` | List all snapshots with size and commit message |
| `--structure [vX]` | Display the file tree of a snapshot |
| `--new_version "message"` | Save a new snapshot with a commit message |
| `--load_version [vX] [file]` | Restore a full snapshot or a single file |
| `--rollback` | Undo the last `--load_version` operation |
| `--compare_version [vX] [vY] [file]` | Token-optimized diff between two snapshots |
| `--show_file [vX] [file]` | Print one file from a past snapshot |
| `--tag [vX] [tag_name]` | Apply a friendly tag to a snapshot |
| `--update_commit [vX] "message"` | Update the commit message of a snapshot |
| `--delete_version [vX]` | Permanently delete a single snapshot |
| `--clean` | Purge oldest snapshots beyond the storage limit |

---

## 5. Configuration

Storage behaviour is controlled by `.local_version_control/system_defaults.conf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_DIR` | `~/Documents/.local_versions` | Root directory for all project snapshots |
| `MAX_VERSIONS` | `10` | Maximum snapshots retained per project (oldest pruned on overflow) |
| `IGNORE_DIRS` | `node_modules/,__pycache__/,...` | Comma-separated rsync-style exclusion patterns |

---

## 6. Repository Structure

```
.
├── install.sh                            # One-time installation script
├── readme.md                             # This file
├── .local_version_control/               # Deployed to ~/.local/share/local_version_control/
│   ├── bin/
│   │   └── lvc.sh                        # Core engine (all command logic)
│   └── system_defaults.conf              # Tunable storage defaults
└── .bob_skills/
    └── local_version_control/
        ├── commands/
        │   └── lvc.sh                    # Pass-through shim (agent entry point)
        ├── explanation.md                # Agent instruction manual
        ├── forbidden_actions.md          # Agent operational boundaries
        └── project_name.conf            # Per-project name configuration
```

---

## License

