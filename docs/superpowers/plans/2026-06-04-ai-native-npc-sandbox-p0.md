# AI-native NPC Sandbox P0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first playable Godot prototype for AI-native NPC world fact authoring: drag/drop NPCs and items, create fenced places, generate guarded daily todos, and persist the world state.

**Architecture:** Keep gameplay truth in small GDScript runtime services under `scripts/`, with UI nodes only reading or calling service APIs. `WorldEntityRegistry`, `WorldPlaceRegistry`, `BuildingPlacementService`, `InteractionEventLog`, and NPC planner/executor modules own structured state; draw/input scripts are display and interaction layers only.

**Tech Stack:** Godot 4.6-compatible project files, GDScript, Godot headless script tests, plus a Python static verifier because this workspace currently has no Godot executable on PATH.

---

## Current Workspace Constraints

- The workspace is not a git repository, so tasks must not claim commits. Replace commit steps with "record files changed and verification output".
- Godot is not currently available on PATH. Add Godot-native tests, but use `python tools/verify_project.py` as the runnable verification command in this environment.
- The project starts from docs only. All runtime files are new.

## File Structure

- Create `project.godot`: Godot project metadata and main scene.
- Create `scenes/main.tscn`: Root scene for the playable prototype.
- Create `scripts/core/Constants.gd`: Shared sentinels and event/type constants.
- Create `scripts/state/NPCState.gd`, `scripts/state/ItemState.gd`, `scripts/state/TodoItem.gd`, `scripts/state/InteractionEvent.gd`, `scripts/state/FencedAreaPlace.gd`: Small state objects with serialization helpers.
- Create `scripts/world/WorldEntityRegistry.gd`: NPC/item position, occupancy, forced drop, inventory transactions, save/load repair.
- Create `scripts/world/WorldPlaceRegistry.gd`: FencedAreaPlace source of truth and place queries.
- Create `scripts/world/InteractionEventLog.gd`: Append-only structured event store.
- Create `scripts/world/GridPathfinder.gd`: Grid walkability and simple BFS pathfinding.
- Create `scripts/world/BuildingPlacementService.gd`: FencedArea validation, door/fence/interior geometry, atomic placement, path impact notification.
- Create `scripts/npc/LLMClient.gd`: Mock/sync LLM backend plus operation/generation guard.
- Create `scripts/npc/DailyTodoPlanner.gd`: Todo schema validation and fallback.
- Create `scripts/npc/NPCFeedbackBuilder.gd`: Event-bound deterministic feedback with streaming-ready operation shape.
- Create `scripts/npc/NPCActionScheduler.gd`, `scripts/npc/TodoExecutor.gd`, `scripts/npc/NPCMover.gd`: Lane scheduling, todo execution, replan/block behavior.
- Create `scripts/ui/GridSelectionOverlay.gd`, `scripts/ui/FencedAreaOverlay.gd`, `scripts/ui/FencedAreaEditPanel.gd`: Input preview, fenced area rendering, name/description confirmation UI.
- Create `scripts/MainGame.gd`: Wires services, sample NPC/item data, camera movement, drag/drop, right-click discard, fenced area mode, save/load hotkeys.
- Create `tests/run_tests.gd`, `tests/test_core_behaviors.gd`: Godot headless tests for registries, building placement, todo validation, save/load.
- Create `tools/verify_project.py`: Static source verifier runnable without Godot.
- Create `README.md`: Run controls and verification commands.

---

### Task 1: Godot Project Skeleton And State Types

**Files:**
- Create: `project.godot`
- Create: `scenes/main.tscn`
- Create: `scripts/core/Constants.gd`
- Create: `scripts/state/NPCState.gd`
- Create: `scripts/state/ItemState.gd`
- Create: `scripts/state/TodoItem.gd`
- Create: `scripts/state/InteractionEvent.gd`
- Create: `scripts/state/FencedAreaPlace.gd`
- Create: `tests/run_tests.gd`
- Create: `tests/test_core_behaviors.gd`
- Create: `tools/verify_project.py`

- [ ] **Step 1: Write verifier expectations first**

Add `tools/verify_project.py` with checks that the Godot project, state classes, required `class_name`s, serialization methods, `INVALID_CELL`, and initial Godot test files exist.

- [ ] **Step 2: Run verifier and confirm RED**

Run: `python tools/verify_project.py`
Expected: non-zero exit because runtime files are missing.

- [ ] **Step 3: Create project and state files**

Create the files listed above. Each state file must expose `from_dict` and `to_dict`; `FencedAreaPlace` must use `footprint` as the only rectangle source of truth and must not define `rect_cells`.

- [ ] **Step 4: Run verifier and confirm GREEN for skeleton**

Run: `python tools/verify_project.py`
Expected: skeleton/state checks pass; later task checks may remain marked as not yet required only if verifier stages are explicit.

---

### Task 2: World Entity Registry And Interaction Events

**Files:**
- Create: `scripts/world/WorldEntityRegistry.gd`
- Create: `scripts/world/InteractionEventLog.gd`
- Modify: `tests/test_core_behaviors.gd`
- Modify: `tools/verify_project.py`

- [ ] **Step 1: Add failing behavior tests**

Add Godot tests for:
- item drop to empty cell updates `current_cell` and occupancy;
- item drop onto empty-handed NPC sets `item.held_by_npc_id`, `item.current_cell = Constants.INVALID_CELL`, and `npc.held_item_id`;
- second item on a holding NPC is rejected and state is unchanged;
- right-click discard places held item on nearest valid cell and records `player_forced_drop_item`;
- save/load repair prefers NPC inventory when inventory links disagree.

- [ ] **Step 2: Run static verifier RED**

Run: `python tools/verify_project.py`
Expected: failure for missing registry/event methods.

- [ ] **Step 3: Implement registry and event log**

Implement `validate_forced_drop`, `move_entity_to_cell`, `give_item_to_npc`, `drop_held_item`, `find_nearest_free_cell`, `repair_inventory_links`, `to_dict`, and `load_from_dict`. All inventory changes must be transaction-like and maintain the bidirectional invariant.

- [ ] **Step 4: Run static verifier GREEN for entity APIs**

Run: `python tools/verify_project.py`
Expected: entity/event API checks pass.

---

### Task 3: FencedArea Place Registry, Placement, And Path Semantics

**Files:**
- Create: `scripts/world/WorldPlaceRegistry.gd`
- Create: `scripts/world/GridPathfinder.gd`
- Create: `scripts/world/BuildingPlacementService.gd`
- Modify: `tests/test_core_behaviors.gd`
- Modify: `tools/verify_project.py`

- [ ] **Step 1: Add failing behavior tests**

Add Godot tests for:
- `3x3` footprint produces non-corner `door_cell`, boundary `fence_cells` excluding the door, and inner `interior_cells`;
- `1xN`, `2xN`, `Nx1`, and `Nx2` footprints are rejected with a reason;
- placement rejects footprint covering an NPC current cell;
- overlapping FencedAreas and doors covered by new fence are rejected;
- pathfinder blocks fence cells, keeps door/interior walkable, and path into interior goes through door;
- placement on an NPC future path triggers replan; failed replan marks current todo `BLOCKED` and records `npc_todo_blocked_by_building`.

- [ ] **Step 2: Run static verifier RED**

Run: `python tools/verify_project.py`
Expected: failure for missing place/building/path APIs.

- [ ] **Step 3: Implement place registry, pathfinder, placement service**

Implement `create_fenced_area_place`, `get_place_at_cell`, `get_places_near_cell`, `get_random_cell_in_place`, `choose_door_cell_from_drag`, `can_place_fenced_area`, `place_fenced_area`, `get_fence_cells`, `get_interior_cells`, `is_walkable`, and BFS pathfinding. `place_fenced_area` must be the only geometry write entry and must roll back registry/path/event changes if later steps fail.

- [ ] **Step 4: Run static verifier GREEN for place/building APIs**

Run: `python tools/verify_project.py`
Expected: place/building/path API checks pass.

---

### Task 4: NPC Todo, Feedback, Operation Guard, And Execution Lanes

**Files:**
- Create: `scripts/npc/LLMClient.gd`
- Create: `scripts/npc/DailyTodoPlanner.gd`
- Create: `scripts/npc/NPCFeedbackBuilder.gd`
- Create: `scripts/npc/NPCActionScheduler.gd`
- Create: `scripts/npc/TodoExecutor.gd`
- Create: `scripts/npc/NPCMover.gd`
- Modify: `tests/test_core_behaviors.gd`
- Modify: `tools/verify_project.py`

- [ ] **Step 1: Add failing behavior tests**

Add Godot tests for:
- todo validator accepts only `visit_place`, `talk_to_npc`, `inspect_item`, `wander`, and `rest`;
- invalid targets are discarded and empty output falls back to `wander`;
- generation mismatch or operation id mismatch discards late LLM results;
- daily todo partial streaming buffers never commit until final JSON validates;
- same NPC cannot run two movement actions or two speech streams, but can move and speak at the same time;
- interrupted actions record `npc_action_interrupted`.

- [ ] **Step 2: Run static verifier RED**

Run: `python tools/verify_project.py`
Expected: failure for missing NPC modules and method names.

- [ ] **Step 3: Implement NPC modules**

Implement deterministic mock LLM responses, generation tracking per `(npc_id, kind)`, todo validation/fallback, event-bound feedback strings, lane locks, movement path execution, and todo blocked/fallback behavior.

- [ ] **Step 4: Run static verifier GREEN for NPC APIs**

Run: `python tools/verify_project.py`
Expected: NPC API checks pass.

---

### Task 5: Playable Scene, Drag/Drop UI, FencedArea Editing, And Persistence

**Files:**
- Create: `scripts/ui/GridSelectionOverlay.gd`
- Create: `scripts/ui/FencedAreaOverlay.gd`
- Create: `scripts/ui/FencedAreaEditPanel.gd`
- Create: `scripts/MainGame.gd`
- Modify: `scenes/main.tscn`
- Modify: `tools/verify_project.py`
- Create: `README.md`

- [ ] **Step 1: Add static UI expectations**

Extend `tools/verify_project.py` to check controls and script responsibilities:
- `WASD` and edge camera movement exist in `MainGame.gd`;
- left click select/drag/drop and right click discard handlers exist;
- drag preview/hover is separate from drop commit;
- FencedArea mode uses grid rectangle drag and confirmation panel;
- overlay reads from `WorldPlaceRegistry` rather than storing source-of-truth places;
- save/load calls registry serialization and inventory repair.

- [ ] **Step 2: Run static verifier RED**

Run: `python tools/verify_project.py`
Expected: failure for missing UI/runtime wiring.

- [ ] **Step 3: Implement playable scene**

Implement a dense prototype view with grid cells, emoji/text labels for NPCs/items/places, drag/drop interactions, right-click discard, FencedArea creation mode, feedback text, daily todo hotkey, and save/load hotkeys. Use Godot basic drawing and controls only; no external art assets.

- [ ] **Step 4: Document run controls**

Document controls, run commands, and test commands in `README.md`.

- [ ] **Step 5: Run static verifier GREEN for full P0 source**

Run: `python tools/verify_project.py`
Expected: all static source checks pass.

---

### Task 6: Final Verification And Review

**Files:**
- Modify only if verification finds issues.

- [ ] **Step 1: Run available verification**

Run: `python tools/verify_project.py`
Expected: `All static Godot prototype checks passed.`

- [ ] **Step 2: Record unavailable Godot verification**

Run: `where.exe godot`
Expected in this workspace: non-zero/no output. Record that Godot headless tests are present but not executed locally because Godot is not installed.

- [ ] **Step 3: Spec compliance review**

Review P0 acceptance criteria from `docs/superpowers/specs/2026-06-04-ai-native-npc-sandbox-core-design.md` against the created files. List gaps explicitly.

- [ ] **Step 4: Code quality review**

Review responsibilities, file size, source-of-truth boundaries, transaction behavior, and test coverage. Fix important issues before final report.
