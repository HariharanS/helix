#!/bin/bash
# Helix Workspace Setup Script (Legacy)
# Legacy helper for the pre-split combined layout.
# Reads workspace.yaml, clones/pulls repos, generates .code-workspace file
#
# Usage: ./setup-workspace.sh <workspace-name>
#
# Reads from: workspaces/<workspace-name>/workspace.yaml
# Expected YAML format:
#   name: order-feature
#   description: ...
#   status: created
#   repos:
#     - path: ../service-a
#       url: https://dev.azure.com/org/project/_git/service-a
#       branch: main
#       role: primary
#       onboarded: false

set -euo pipefail

WORKSPACE_NAME="${1:?Usage: setup-workspace.sh <workspace-name>}"
HELIX_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WS_DIR="${HELIX_ROOT}/workspaces/${WORKSPACE_NAME}"
WS_YAML="${WS_DIR}/workspace.yaml"

if [ ! -f "$WS_YAML" ]; then
  echo "Error: workspace.yaml not found at: $WS_YAML"
  exit 1
fi

echo "Setting up workspace: $WORKSPACE_NAME"
echo "Helix root: $HELIX_ROOT"
echo "Warning: setup-workspace.sh targets the legacy combined-layout workspace.yaml model. Prefer scripts/setup-workspace.ps1 for the meta-repo model."

# Parse repos from workspace.yaml (simple line-by-line parsing)
REPO_PATH=""
REPO_URL=""
REPO_BRANCH="main"
REPO_ONBOARDED=""
FOLDERS_JSON="[{\"name\": \"helix\", \"path\": \"../..\"}"

process_repo() {
  if [ -n "$REPO_PATH" ] && [ -n "$REPO_URL" ]; then
    FULL_PATH="${HELIX_ROOT}/${REPO_PATH}"
    REPO_NAME=$(basename "$REPO_PATH")

    if [ -d "$FULL_PATH" ]; then
      echo "  Fetching: $REPO_NAME"
      git -C "$FULL_PATH" fetch 2>/dev/null || echo "    Warning: fetch failed for $REPO_NAME"
      echo "    Status: $(git -C "$FULL_PATH" status -sb | head -1)"
    else
      echo "  Cloning: $REPO_NAME"
      # Detect URL type and use appropriate clone command
      if echo "$REPO_URL" | grep -q "dev.azure.com"; then
        az repos clone --repository "$REPO_NAME" --out "$FULL_PATH" 2>/dev/null || \
          git clone "$REPO_URL" "$FULL_PATH"
      elif echo "$REPO_URL" | grep -q "github.com"; then
        gh repo clone "$REPO_URL" "$FULL_PATH" 2>/dev/null || \
          git clone "$REPO_URL" "$FULL_PATH"
      else
        git clone "$REPO_URL" "$FULL_PATH"
      fi

      if [ -n "$REPO_BRANCH" ] && [ "$REPO_BRANCH" != "main" ]; then
        git -C "$FULL_PATH" checkout "$REPO_BRANCH" 2>/dev/null || true
      fi
    fi

    # Add to workspace folders
    RELATIVE_PATH="../../../${REPO_NAME}"
    FOLDERS_JSON="${FOLDERS_JSON}, {\"name\": \"${REPO_NAME}\", \"path\": \"${RELATIVE_PATH}\"}"
  fi
}

# Parse workspace.yaml
IN_REPO=false
while IFS= read -r line || [ -n "$line" ]; do
  # Detect new repo entry
  if echo "$line" | grep -q "^  - path:"; then
    # Process previous repo if any
    if [ "$IN_REPO" = true ]; then
      process_repo
    fi
    IN_REPO=true
    REPO_PATH=$(echo "$line" | sed 's/.*path:\s*//')
    REPO_URL=""
    REPO_BRANCH="main"
    REPO_ONBOARDED=""
  elif [ "$IN_REPO" = true ]; then
    if echo "$line" | grep -q "url:"; then
      REPO_URL=$(echo "$line" | sed 's/.*url:\s*//')
    elif echo "$line" | grep -q "branch:"; then
      REPO_BRANCH=$(echo "$line" | sed 's/.*branch:\s*//')
    elif echo "$line" | grep -q "onboarded:"; then
      REPO_ONBOARDED=$(echo "$line" | sed 's/.*onboarded:\s*//')
    fi
  fi
done < "$WS_YAML"

# Process last repo
if [ "$IN_REPO" = true ]; then
  process_repo
fi

FOLDERS_JSON="${FOLDERS_JSON}]"

# Generate .code-workspace file
WORKSPACE_FILE="${WS_DIR}/${WORKSPACE_NAME}.code-workspace"
echo ""
echo "Generating: $WORKSPACE_FILE"

cat > "$WORKSPACE_FILE" << EOF
{
  "folders": $(echo "$FOLDERS_JSON" | python3 -c "import sys,json; print(json.dumps(json.loads(sys.stdin.read()), indent=4))" 2>/dev/null || echo "$FOLDERS_JSON"),
  "settings": {}
}
EOF

# Update .claude/settings.json with additionalDirectories
CLAUDE_SETTINGS="${HELIX_ROOT}/.claude/settings.json"
echo "Updating: $CLAUDE_SETTINGS"

# Collect repo paths for additionalDirectories
ADDITIONAL_DIRS="[]"
while IFS= read -r line; do
  if echo "$line" | grep -q "^  - path:"; then
    RPATH=$(echo "$line" | sed 's/.*path:\s*//')
    if [ "$ADDITIONAL_DIRS" = "[]" ]; then
      ADDITIONAL_DIRS="[\"${RPATH}\""
    else
      ADDITIONAL_DIRS="${ADDITIONAL_DIRS}, \"${RPATH}\""
    fi
  fi
done < "$WS_YAML"
ADDITIONAL_DIRS="${ADDITIONAL_DIRS}]"

cat > "$CLAUDE_SETTINGS" << EOF
{
  "permissions": {
    "additionalDirectories": ${ADDITIONAL_DIRS}
  }
}
EOF

# Update active workspace pointer
ACTIVE_WS="${HELIX_ROOT}/.helix/active-workspace.yaml"
echo "Setting active workspace: $WORKSPACE_NAME"
cat > "$ACTIVE_WS" << EOF
# Active Workspace Pointer
# Set by: workspace-sync or "activate {workspace-name}" command
# Read by: helix orchestrator at session start
active: ${WORKSPACE_NAME}
EOF

echo ""
echo "Workspace setup complete!"
echo "  Open in VS Code: code ${WORKSPACE_FILE}"
echo "  Active workspace: ${WORKSPACE_NAME}"
