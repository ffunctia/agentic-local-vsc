#!/bin/bash

SYSTEM_DEST="$HOME/.local/share/local_version_control"
STORAGE_DEST="$HOME/Documents/.local_versions"

echo "Initializing installation sequence..."

mkdir -p "$SYSTEM_DEST"
mkdir -p "$STORAGE_DEST"

if [ -d "./.local_version_control" ]; then
    cp -r ./.local_version_control/* "$SYSTEM_DEST/"
    echo "SUCCESS: System binaries deployed to $SYSTEM_DEST."
else
    echo "ERROR: Source directory './.local_version_control' not found."
    exit 1
fi

chmod +x "$SYSTEM_DEST/bin/lvc.sh" 2>/dev/null

echo ""
echo "Installation successfully completed."
echo "Usage: Copy the '.bob_skills' folder into the root directory of your target project."