#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

CONF_FILE="$SCRIPT_DIR/../project_name.conf"

if [ -f "$CONF_FILE" ]; then
    PROJECT_NAME=$(grep -E "^PROJECT_NAME=" "$CONF_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
else
    echo "LVC Error: project_name.conf file not found!"
    echo "Please ensure the configuration exists in the .bob_skills/local_version_control directory."
    exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
    echo "LVC Error: PROJECT_NAME is not set in project_name.conf."
    echo ""
    echo "ACTION REQUIRED — you must assign a project name before using LVC:"
    echo "  1. Derive a short, unique name from the project's root directory name"
    echo "     (lowercase, no spaces — use underscores or hyphens)."
    echo "  2. Write it to the config file using the following command:"
    echo "     sed -i 's/^PROJECT_NAME=.*/PROJECT_NAME=<your_project_name>/' \\"
    echo "         .bob_skills/local_version_control/project_name.conf"
    echo "  3. Re-run your LVC command."
    echo ""
    echo "Example: if the project folder is 'my-web-app', run:"
    echo "     sed -i 's/^PROJECT_NAME=.*/PROJECT_NAME=my-web-app/' \\"
    echo "         .bob_skills/local_version_control/project_name.conf"
    exit 1
fi

MAIN_ENGINE="$HOME/.local/share/local_version_control/bin/lvc.sh"

if [ ! -f "$MAIN_ENGINE" ]; then
    echo "LVC Error: Main system engine not found!"
    echo "Expected location: $MAIN_ENGINE"
    echo "Please run the install.sh script to complete the system deployment."
    exit 1
fi
bash "$MAIN_ENGINE" "$PROJECT_NAME" "$@"