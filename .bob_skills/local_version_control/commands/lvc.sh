#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

CONF_FILE="$SCRIPT_DIR/../project_name.conf"

if [ -f "$CONF_FILE" ]; then
    PROJECT_NAME=$(grep -E "^PROJECT_NAME=" "$CONF_FILE" | cut -d'=' -f2)
else
    echo "LVC Error: project_name.conf file not found!"
    echo "Please ensure the configuration exists in the .bob_skills/local_version_control directory."
    exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="unnamed_project"
fi

MAIN_ENGINE="$HOME/.local/share/local_version_control/bin/lvc.sh"

if [ ! -f "$MAIN_ENGINE" ]; then
    echo "LVC Error: Main system engine not found!"
    echo "Expected location: $MAIN_ENGINE"
    echo "Please run the install.sh script to complete the system deployment."
    exit 1
fi
bash "$MAIN_ENGINE" "$PROJECT_NAME" "$@"