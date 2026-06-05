# AI NPC Emergence Sandbox

Godot 4.6 sandbox for testing a playable NPC/item/grid loop.

## Controls

- `WASD`: pan the camera. Moving the pointer to the screen edge also pans the camera.
- Left click: select an NPC, item, or map cell.
- Left drag and drop: move a selected NPC/item to a grid cell. Dropping an item on an empty-handed NPC gives that item to the NPC.
- Right click: discard the selected NPC held item to the nearest free cell.
- `F`: toggle `FencedArea` creation mode. Drag a 3x3 or larger rectangle, then enter name and description in the edit panel.
- `T`: generate a daily todo placeholder for sample NPCs.
- `Ctrl+S` / `Ctrl+L`: save and load the in-memory sandbox state.

## Verification

Run these from the repository root:

```powershell
python path\to\agentic-apr\scripts\fp-runner.py --phase post -- python apr\playable-ui\oracle\run_playable_ui_oracle.py
python tools\verify_project.py
.\tools\godot\run-tests.ps1
```
