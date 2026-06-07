#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="$0"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  if [[ "$LINK_TARGET" == /* ]]; then
    SCRIPT_PATH="$LINK_TARGET"
  else
    SCRIPT_PATH="$SCRIPT_DIR/$LINK_TARGET"
  fi
done

PROJECT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
GODOT_BIN="/Users/davidcai/Desktop/Godot.app/Contents/MacOS/Godot"

echo "AI NPC Emergence Sandbox launcher"
echo "Project: $PROJECT_DIR"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Cannot find Godot at: $GODOT_BIN"
  echo "Move Godot.app back to Desktop or edit GODOT_BIN in this launcher."
  read -k 1 "?Press any key to close..."
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
  echo "Cannot find project.godot in: $PROJECT_DIR"
  read -k 1 "?Press any key to close..."
  exit 1
fi

cd "$PROJECT_DIR"

echo "Refreshing Godot resource imports..."
"$GODOT_BIN" --path "$PROJECT_DIR" --import

echo "Launching Godot project..."
"$GODOT_BIN" --path "$PROJECT_DIR"
