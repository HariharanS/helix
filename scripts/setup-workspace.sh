#!/bin/bash
# Helix Workspace Setup Script
# Clones/pulls all repos listed in a workspace config and generates a .code-workspace file
#
# Usage: ./setup-workspace.sh <workspace-config.json>
#
# Config format:
# {
#   "name": "sub-system-a",
#   "repos": [
#     { "name": "service-a", "url": "git@dev.azure.com:org/project/_git/service-a" },
#     { "name": "service-b", "url": "git@dev.azure.com:org/project/_git/service-b" }
#   ],
#   "basePath": "../"
# }

set -euo pipefail

CONFIG_FILE="${1:?Usage: setup-workspace.sh <workspace-config.json>}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

NAME=$(jq -r '.name' "$CONFIG_FILE")
BASE_PATH=$(jq -r '.basePath // "../"' "$CONFIG_FILE")
REPOS=$(jq -c '.repos[]' "$CONFIG_FILE")

echo "Setting up workspace: $NAME"
echo "Base path: $BASE_PATH"

# Clone or pull each repo
while IFS= read -r repo; do
  REPO_NAME=$(echo "$repo" | jq -r '.name')
  REPO_URL=$(echo "$repo" | jq -r '.url')
  REPO_PATH="${BASE_PATH}/${REPO_NAME}"

  if [ -d "$REPO_PATH" ]; then
    echo "Pulling: $REPO_NAME"
    git -C "$REPO_PATH" pull --ff-only 2>/dev/null || echo "  Warning: pull failed for $REPO_NAME, skipping"
  else
    echo "Cloning: $REPO_NAME"
    git clone "$REPO_URL" "$REPO_PATH"
  fi
done <<< "$REPOS"

# Generate .code-workspace file
WORKSPACE_FILE="workspaces/${NAME}.code-workspace"

echo "Generating workspace file: $WORKSPACE_FILE"

FOLDERS=$(jq -c '[.repos[] | { "path": ("../../" + .name) }]' "$CONFIG_FILE")

cat > "$WORKSPACE_FILE" << EOF
{
  "folders": [
    { "path": "." },
$(echo "$FOLDERS" | jq -r '.[] | "    { \"path\": \"" + .path + "\" },"' | sed '$ s/,$//')
  ],
  "settings": {
    "chat.agentFilesLocations": [
      { "source": "agents" }
    ],
    "chat.skillsLocations": [
      { "source": "skills" }
    ]
  }
}
EOF

echo "Workspace setup complete: $WORKSPACE_FILE"
echo "Open in VS Code: code $WORKSPACE_FILE"
