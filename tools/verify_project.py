from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


STATE_EXPECTATIONS = {
    "scripts/state/NPCState.gd": {
        "class_name": "NPCState",
        "fields": [
            "id",
            "name",
            "traits",
            "tags",
            "style",
            "anim_set_id",
            "performance_state",
            "emotional_state",
            "stance_to_object",
            "current_gag",
            "cooldowns",
            "current_cell",
            "position",
            "todo_list",
            "recent_events",
        ],
        "serialized_fields": [
            "id",
            "name",
            "traits",
            "tags",
            "style",
            "animSetId",
            "runtime",
            "current_cell",
            "position",
            "todo_list",
            "recent_events",
        ],
    },
    "scripts/state/ItemState.gd": {
        "class_name": "ItemState",
        "fields": [
            "id",
            "type_id",
            "name",
            "category",
            "owner_id",
            "access_rule",
            "current_anchor",
            "custody_state",
            "affordance",
            "social",
            "social_override",
            "state",
            "memory",
            "current_cell",
            "position",
        ],
        "serialized_fields": [
            "id",
            "typeId",
            "ownerId",
            "accessRule",
            "currentAnchor",
            "custodyState",
            "state",
            "memory",
            "current_cell",
            "position",
            "social",
        ],
    },
    "scripts/state/TodoItem.gd": {
        "class_name": "TodoItem",
        "fields": [
            "id",
            "intent",
            "target_place_id",
            "target_npc_id",
            "target_item_id",
            "reason",
            "priority",
            "status",
        ],
    },
    "scripts/state/InteractionEvent.gd": {
        "class_name": "InteractionEvent",
        "fields": [
            "id",
            "type",
            "actor_id",
            "primary_entity_id",
            "target_entity_id",
            "target_type",
            "cell",
            "tick",
            "payload",
        ],
    },
    "scripts/state/FencedAreaPlace.gd": {
        "class_name": "FencedAreaPlace",
        "fields": [
            "id",
            "name",
            "description",
            "created_by",
            "updated_at_tick",
            "emoji",
            "footprint",
            "door_cell",
            "fence_cells",
            "interior_cells",
        ],
    },
}

WORLD_EXPECTATIONS = {
    "scripts/world/WorldEntityRegistry.gd": {
        "class_name": "WorldEntityRegistry",
        "fields": [
            "npcs",
            "items",
            "object_types",
            "relation_memories",
            "interaction_traces",
            "map_bounds",
            "blocked_cells",
            "repair_warnings",
        ],
        "methods": [
            "add_npc",
            "add_item",
            "set_map_bounds",
            "set_blocked_cell",
            "validate_forced_drop",
            "move_entity_to_cell",
            "set_entity_position",
            "give_item_to_npc",
            "drop_anchored_items",
            "repair_inventory_links",
            "update_interaction_trace",
            "interaction_trace",
            "decay_interaction_memories",
            "to_dict",
            "load_from_dict",
        ],
    },
    "scripts/world/InteractionEventLog.gd": {
        "class_name": "InteractionEventLog",
        "fields": [
            "events",
            "next_event_number",
        ],
        "methods": [
            "append_event",
            "record",
            "recent_events",
            "to_dict",
            "load_from_dict",
        ],
    },
    "scripts/world/WorldPlaceRegistry.gd": {
        "class_name": "WorldPlaceRegistry",
        "fields": [
            "places",
            "next_place_number",
        ],
        "methods": [
            "create_place",
            "update_text",
            "remove_place",
            "get_place_at_cell",
            "get_places_near_cell",
            "get_random_cell_in_place",
            "to_dict",
            "load_from_dict",
        ],
    },
    "scripts/world/GridPathfinder.gd": {
        "class_name": "GridPathfinder",
        "fields": [
            "map_bounds",
            "solid_cells",
        ],
        "methods": [
            "set_map_bounds",
            "set_solid_cell",
            "set_solid_cells",
            "is_walkable",
            "find_path",
            "to_dict",
            "load_from_dict",
        ],
    },
    "scripts/world/BuildingPlacementService.gd": {
        "class_name": "BuildingPlacementService",
        "fields": [
            "entity_registry",
            "place_registry",
            "pathfinder",
            "event_log",
            "movers",
        ],
        "methods": [
            "configure",
            "register_mover",
            "choose_door_cell_from_drag",
            "can_place_fenced_area",
            "place_fenced_area",
            "get_door_cell",
            "get_fence_cells",
            "get_interior_cells",
            "get_npcs_occupying_cells",
            "get_npcs_with_paths_intersecting",
        ],
    },
}

NPC_EXPECTATIONS = {
    "scripts/npc/LLMClient.gd": {
        "class_name": "LLMClient",
        "fields": [
            "current_generations",
            "current_operation_ids",
            "operations",
            "next_operation_number",
        ],
        "methods": [
            "start_operation",
            "append_stream_chunk",
            "complete_operation",
            "cancel_operation",
        ],
    },
    "scripts/npc/DailyTodoPlanner.gd": {
        "class_name": "DailyTodoPlanner",
        "fields": [
            "entity_registry",
            "place_registry",
            "default_max_count",
        ],
        "methods": [
            "configure",
            "validate_todos",
            "validate_daily_todos",
            "sanitize_todos",
        ],
    },
    "scripts/npc/NPCFeedbackBuilder.gd": {
        "class_name": "NPCFeedbackBuilder",
        "fields": [
            "entity_registry",
            "place_registry",
            "event_log",
            "llm_client",
        ],
        "methods": [
            "configure",
            "build_feedback",
            "begin_feedback_stream",
        ],
    },
    "scripts/npc/NPCActionScheduler.gd": {
        "class_name": "NPCActionScheduler",
        "fields": [
            "active_lanes",
        ],
        "methods": [
            "start_action",
            "try_start_action",
            "finish_action",
            "interrupt_action",
        ],
    },
    "scripts/npc/TodoExecutor.gd": {
        "class_name": "TodoExecutor",
        "fields": [
            "entity_registry",
            "place_registry",
            "pathfinder",
            "event_log",
            "mover",
        ],
        "methods": [
            "configure",
            "execute_todo",
            "start_todo",
            "handle_replan_failed",
            "mark_todo_blocked",
        ],
    },
    "scripts/npc/NPCMover.gd": {
        "class_name": "NPCMover",
        "fields": [
            "entity_registry",
            "place_registry",
            "pathfinder",
            "event_log",
            "planned_path",
            "target_cell",
        ],
        "methods": [
            "configure",
            "plan_path",
            "move_to_cell",
            "get_path_cells",
            "request_replan",
        ],
    },
}

REQUIRED_FILES = [
    "project.godot",
    "scenes/main.tscn",
    "scripts/core/Constants.gd",
    "tests/run_tests.gd",
    "tests/test_core_behaviors.gd",
    *STATE_EXPECTATIONS.keys(),
    *WORLD_EXPECTATIONS.keys(),
    *NPC_EXPECTATIONS.keys(),
]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def has_field(source: str, field_name: str) -> bool:
    pattern = rf"(?m)^(?:@export\s+)?var\s+{re.escape(field_name)}\b"
    return re.search(pattern, source) is not None


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def verify_required_files(failures: list[str]) -> None:
    for relative_path in REQUIRED_FILES:
        require((ROOT / relative_path).is_file(), f"missing required file: {relative_path}", failures)


def verify_project_config(failures: list[str]) -> None:
    project_path = ROOT / "project.godot"
    if not project_path.is_file():
        return

    source = read_text("project.godot")
    require('config/name="AI NPC Emergence Sandbox"' in source, "project.godot must define the project name", failures)
    require('run/main_scene="res://scenes/main.tscn"' in source, "project.godot must point to scenes/main.tscn", failures)
    require('config/features=PackedStringArray("4.6")' in source, "project.godot must target Godot 4.6", failures)


def verify_constants(failures: list[str]) -> None:
    constants_path = ROOT / "scripts/core/Constants.gd"
    if not constants_path.is_file():
        return

    source = read_text("scripts/core/Constants.gd")
    require("class_name Constants" in source, "Constants.gd must expose class_name Constants", failures)
    require("INVALID_CELL" in source, "Constants.gd must define INVALID_CELL", failures)
    require("Vector2i(-1, -1)" in source, "INVALID_CELL must be outside the legal map range", failures)


def verify_state_file(relative_path: str, expectation: dict[str, object], failures: list[str]) -> None:
    path = ROOT / relative_path
    if not path.is_file():
        return

    source = read_text(relative_path)
    class_name = str(expectation["class_name"])
    require(f"class_name {class_name}" in source, f"{relative_path} must expose class_name {class_name}", failures)
    require("static func from_dict" in source, f"{relative_path} must expose static from_dict", failures)
    require("func to_dict" in source, f"{relative_path} must expose to_dict", failures)

    for field_name in expectation["fields"]:
        require(has_field(source, str(field_name)), f"{relative_path} missing field: {field_name}", failures)

    for field_name in expectation.get("serialized_fields", expectation["fields"]):
        require(f'"{field_name}"' in source, f"{relative_path} must serialize field: {field_name}", failures)


def verify_state_files(failures: list[str]) -> None:
    for relative_path, expectation in STATE_EXPECTATIONS.items():
        verify_state_file(relative_path, expectation, failures)

    fenced_path = ROOT / "scripts/state/FencedAreaPlace.gd"
    if fenced_path.is_file():
        source = read_text("scripts/state/FencedAreaPlace.gd")
        require("rect_cells" not in source, "FencedAreaPlace must not define or serialize rect_cells", failures)


def verify_world_file(relative_path: str, expectation: dict[str, object], failures: list[str]) -> None:
    path = ROOT / relative_path
    if not path.is_file():
        return

    source = read_text(relative_path)
    class_name = str(expectation["class_name"])
    require(f"class_name {class_name}" in source, f"{relative_path} must expose class_name {class_name}", failures)

    for field_name in expectation["fields"]:
        require(has_field(source, str(field_name)), f"{relative_path} missing field: {field_name}", failures)

    for method_name in expectation["methods"]:
        require(f"func {method_name}" in source, f"{relative_path} missing method: {method_name}", failures)


def verify_world_files(failures: list[str]) -> None:
    for relative_path, expectation in WORLD_EXPECTATIONS.items():
        verify_world_file(relative_path, expectation, failures)


def verify_npc_files(failures: list[str]) -> None:
    for relative_path, expectation in NPC_EXPECTATIONS.items():
        verify_world_file(relative_path, expectation, failures)


def verify_test_placeholders(failures: list[str]) -> None:
    for relative_path in ("tests/run_tests.gd", "tests/test_core_behaviors.gd"):
        path = ROOT / relative_path
        if not path.is_file():
            continue
        source = read_text(relative_path)
        require("extends SceneTree" in source or "extends RefCounted" in source, f"{relative_path} must be a Godot script placeholder", failures)


def main() -> int:
    failures: list[str] = []

    verify_required_files(failures)
    verify_project_config(failures)
    verify_constants(failures)
    verify_state_files(failures)
    verify_world_files(failures)
    verify_npc_files(failures)
    verify_test_placeholders(failures)

    if failures:
        print("VERIFY_PROJECT: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("VERIFY_PROJECT: PASS")
    print(f"- checked {len(REQUIRED_FILES)} required files")
    print(f"- checked {len(STATE_EXPECTATIONS)} state classes with from_dict/to_dict")
    print(f"- checked {len(WORLD_EXPECTATIONS)} world classes with required APIs")
    print(f"- checked {len(NPC_EXPECTATIONS)} NPC backend classes with required APIs")
    print("- confirmed FencedAreaPlace uses footprint without rect_cells")
    return 0


if __name__ == "__main__":
    sys.exit(main())
