#!/usr/bin/env python3
"""Frozen APR oracle for the playable UI scene loop.

This oracle is evaluator-owned. Generator agents must treat it as read-only.
Exit code contract for fp-runner:
  0 = PASS
  1 = FAIL, acceptance assertions did not hold
  2 = INCONCLUSIVE, oracle infrastructure could not evaluate
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ORACLE_GD = ROOT / "apr" / "playable-ui" / "oracle" / "playable_ui_oracle.gd"


class Oracle:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.inconclusive: list[str] = []

    def require(self, condition: bool, message: str, provenance: str) -> None:
        # provenance: agentic-apr requires every frozen assertion to state why it is correct.
        if not condition:
            self.failures.append(f"{message} | provenance: {provenance}")

    def inconclusive_if(self, condition: bool, message: str) -> None:
        if condition:
            self.inconclusive.append(message)


def file_text(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def gd_functions(source: str) -> set[str]:
    return set(re.findall(r"(?m)^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", source))


def has_func_matching(functions: set[str], *patterns: str) -> bool:
    for function_name in functions:
        for pattern in patterns:
            if re.search(pattern, function_name, re.IGNORECASE):
                return True
    return False


def contains_any(source: str, tokens: list[str]) -> bool:
    lowered = source.lower()
    return any(token.lower() in lowered for token in tokens)


def check_required_files_and_classes(oracle: Oracle) -> None:
    required = {
        "scripts/MainGame.gd": "MainGame",
        "scripts/ui/GridSelectionOverlay.gd": "GridSelectionOverlay",
        "scripts/ui/FencedAreaEditPanel.gd": "FencedAreaEditPanel",
        "scripts/ui/FencedAreaOverlay.gd": "FencedAreaOverlay",
    }
    for relative_path, class_name in required.items():
        path = ROOT / relative_path
        # provenance: spec "Godot nodes and module boundaries" lists these scripts/nodes as the playable UI surface.
        oracle.require(path.exists(), f"{relative_path} must exist", "spec Godot nodes and module boundaries")
        source = file_text(relative_path)
        oracle.require(
            f"class_name {class_name}" in source,
            f"{relative_path} must expose class_name {class_name}",
            "spec Godot nodes and module boundaries",
        )


def check_main_game_contract(oracle: Oracle) -> None:
    source = file_text("scripts/MainGame.gd")
    funcs = gd_functions(source)

    # provenance: spec P0 #1 says WASD or screen-edge camera movement must exist.
    oracle.require(
        "KEY_W" in source and "KEY_A" in source and "KEY_S" in source and "KEY_D" in source
        and has_func_matching(funcs, r"camera", r"edge.*move", r"move.*camera"),
        "MainGame must expose camera movement logic for WASD/edge panning",
        "spec player basic operations and P0 #1",
    )
    # provenance: spec P0 #2 says left-click selection must be playable.
    oracle.require(
        has_func_matching(funcs, r"select", r"pick.*entity", r"resolve.*target"),
        "MainGame must expose a callable selection handler",
        "spec player basic operations and P0 #2",
    )
    # provenance: spec P0 #2-4 says drag/drop drives NPC/item placement and item-to-NPC interaction.
    oracle.require(
        has_func_matching(funcs, r"drag", r"start.*grab", r"update.*grab"),
        "MainGame must expose a callable drag handler",
        "spec player basic operations and P0 #2-4",
    )
    # provenance: spec P0 #4-5 says left-button release/drop triggers formal interactions.
    oracle.require(
        has_func_matching(funcs, r"drop", r"release", r"place.*entity"),
        "MainGame must expose a callable drop/release handler",
        "spec player basic operations and P0 #4-5",
    )
    # provenance: spec P0 #6 says right-click discard clears held item and places it nearby.
    oracle.require(
        has_func_matching(funcs, r"discard", r"right.*click", r"drop.*held"),
        "MainGame must expose a callable right-click discard handler",
        "spec right-click discard and P0 #6",
    )
    # provenance: spec P0 #7-8 says FencedArea creation mode confirms a grid rectangle into a place.
    oracle.require(
        has_func_matching(funcs, r"fenced.*mode", r"confirm.*fenced", r"create.*fenced", r"area.*confirm"),
        "MainGame must expose FencedArea mode/confirmation handlers",
        "spec map place editing and P0 #7-8",
    )
    # provenance: spec NPC feedback section says player interventions produce feedback text.
    oracle.require(
        has_func_matching(funcs, r"feedback", r"reaction"),
        "MainGame must expose feedback text update/generation handling",
        "spec NPC feedback and player intervention feedback",
    )
    # provenance: feature request includes daily todo hotkey; spec P0 #10 requires daily todo generation.
    oracle.require(
        has_func_matching(funcs, r"todo", r"daily"),
        "MainGame must expose a daily todo hotkey/action handler",
        "spec P0 #10 and feature request daily todo hotkey",
    )
    # provenance: spec P0 #12 says save/load keeps places, held items, and item positions stable.
    oracle.require(
        has_func_matching(funcs, r"save") and has_func_matching(funcs, r"load"),
        "MainGame must expose save and load handlers",
        "spec save/load invariant and P0 #12",
    )
    # provenance: spec requires runtime services to own world state, with MainGame wiring services and sample NPC/item data.
    oracle.require(
        contains_any(source, ["WorldEntityRegistry", "WorldPlaceRegistry", "BuildingPlacementService", "InteractionEventLog"]),
        "MainGame must wire core world services",
        "feature request MainGame wires services and spec module boundaries",
    )


def check_grid_selection_overlay(oracle: Oracle) -> None:
    source = file_text("scripts/ui/GridSelectionOverlay.gd")
    funcs = gd_functions(source)
    # provenance: spec GridSelectionOverlay says it handles mouse down/drag/release.
    oracle.require(
        has_func_matching(funcs, r"mouse", r"input") and contains_any(source, ["MOUSE_BUTTON_LEFT", "InputEventMouseButton", "InputEventMouseMotion"]),
        "GridSelectionOverlay must handle mouse down/drag/release input",
        "spec GridSelectionOverlay section",
    )
    # provenance: spec GridSelectionOverlay says it converts screen/world position to grid cell.
    oracle.require(
        has_func_matching(funcs, r"screen.*grid", r"world.*grid", r"position.*grid", r"to.*grid")
        and contains_any(source, ["Vector2i", "local_to_map", "world_to_map", "floor"]),
        "GridSelectionOverlay must convert screen/world positions into grid cells",
        "spec GridSelectionOverlay section",
    )
    # provenance: spec GridSelectionOverlay says it generates a Rect2i preview while dragging.
    oracle.require(
        "Rect2i" in source and contains_any(source, ["preview", "selection_rect", "rectangle", "drag_rect", "queue_redraw", "_draw"]),
        "GridSelectionOverlay must emit or record a rectangle preview",
        "spec GridSelectionOverlay section",
    )
    # provenance: spec GridSelectionOverlay says it does not save Place.
    forbidden = ["WorldPlaceRegistry", "create_fenced_area_place", "place_fenced_area", "FencedAreaPlace", "to_dict", "load_from_dict"]
    oracle.require(
        not contains_any(source, forbidden),
        "GridSelectionOverlay must not save Place or call placement/registry write APIs",
        "spec GridSelectionOverlay section: does not save Place",
    )


def check_fenced_area_edit_panel(oracle: Oracle) -> None:
    source = file_text("scripts/ui/FencedAreaEditPanel.gd")
    # provenance: spec FencedAreaEditPanel says it edits name + description.
    oracle.require(
        contains_any(source, ["name", "description"]) and contains_any(source, ["LineEdit", "TextEdit", "description_text"]),
        "FencedAreaEditPanel must edit name and description",
        "spec FencedAreaEditPanel section",
    )
    # provenance: spec FencedAreaEditPanel says confirm calls BuildingPlacementService.place_fenced_area.
    oracle.require(
        "BuildingPlacementService" in source and ".place_fenced_area" in source,
        "FencedAreaEditPanel must call BuildingPlacementService.place_fenced_area on confirm",
        "spec FencedAreaEditPanel section",
    )
    # provenance: spec FencedAreaEditPanel should not bypass placement invariants by writing registry directly.
    oracle.require(
        "WorldPlaceRegistry" not in source and "create_fenced_area_place" not in source,
        "FencedAreaEditPanel must not directly write WorldPlaceRegistry",
        "spec FencedAreaEditPanel section and BuildingPlacementService unique write entry",
    )


def check_fenced_area_overlay(oracle: Oracle) -> None:
    source = file_text("scripts/ui/FencedAreaOverlay.gd")
    # provenance: spec FencedAreaOverlay says it reads data from WorldPlaceRegistry.
    oracle.require(
        "WorldPlaceRegistry" in source and contains_any(source, ["get_all", "get_places", "places", "get_place"]),
        "FencedAreaOverlay must read FencedArea data from WorldPlaceRegistry",
        "spec FencedAreaOverlay section",
    )
    # provenance: spec FencedAreaOverlay says it displays range, door, fence boundary, and label/name.
    oracle.require(
        contains_any(source, ["footprint", "door_cell", "fence_cells", "name"]) and contains_any(source, ["_draw", "draw_rect", "draw_string", "Label"]),
        "FencedAreaOverlay must draw footprint/range, door, fence boundary, and label",
        "spec FencedAreaOverlay section",
    )
    # provenance: spec FencedAreaOverlay says it is display only, not source of truth.
    forbidden = ["create_fenced_area_place", ".place_fenced_area", "load_from_dict", "to_dict", "var places", "var fenced_areas"]
    oracle.require(
        not contains_any(source, forbidden),
        "FencedAreaOverlay must not keep or write source-of-truth place data",
        "spec FencedAreaOverlay section: not source of truth",
    )


def check_readme(oracle: Oracle) -> None:
    readme = file_text("README.md")
    # provenance: feature request requires README controls and verification commands.
    required_groups = {
        "WASD camera controls": ["WASD", "camera", "摄像"],
        "left drag/drop controls": ["left", "drag", "drop", "左键", "拖拽", "放置"],
        "right-click discard control": ["right", "discard", "右键", "丢弃"],
        "FencedArea creation": ["FencedArea", "fenced area", "围栏", "地点"],
        "save/load controls": ["save", "load", "保存", "读取"],
        "verification commands": ["verify", "test", "godot", "验证", "测试"],
    }
    for label, tokens in required_groups.items():
        oracle.require(
            contains_any(readme, tokens),
            f"README.md must document {label}",
            "feature request README controls and verification commands",
        )


def run_godot_scene_smoke(oracle: Oracle) -> None:
    command = [
        str(ROOT / "tools" / "godot" / "godot.cmd"),
        "--headless",
        "--script",
        str(ORACLE_GD),
    ]
    try:
        proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=60)
    except FileNotFoundError as exc:
        oracle.inconclusive.append(f"Godot wrapper missing: {exc}")
        return
    except subprocess.TimeoutExpired as exc:
        oracle.inconclusive.append(f"Godot scene smoke timed out: {exc}")
        return
    output = (proc.stdout or "") + (proc.stderr or "")
    # provenance: spec node tree says main scene must load headlessly with GameRoot/WorldMap/WorldState/NPCSystem/UI nodes.
    oracle.require(
        proc.returncode == 0,
        "Godot playable_ui_oracle.gd scene load smoke must pass\n" + output[-2000:],
        "spec Godot node tree and feature request headless load/smoke",
    )


def main() -> int:
    os.chdir(ROOT)
    oracle = Oracle()
    oracle.inconclusive_if(not ORACLE_GD.exists(), f"missing oracle GDScript: {ORACLE_GD}")

    check_required_files_and_classes(oracle)
    check_main_game_contract(oracle)
    check_grid_selection_overlay(oracle)
    check_fenced_area_edit_panel(oracle)
    check_fenced_area_overlay(oracle)
    check_readme(oracle)
    if ORACLE_GD.exists():
        run_godot_scene_smoke(oracle)

    if oracle.failures:
        print("PLAYABLE_UI_ORACLE: FAIL")
        for failure in oracle.failures:
            print(f"- {failure}")
        if oracle.inconclusive:
            print("PLAYABLE_UI_ORACLE: infra notes")
            for note in oracle.inconclusive:
                print(f"- {note}")
        return 1

    if oracle.inconclusive:
        print("PLAYABLE_UI_ORACLE: INCONCLUSIVE")
        for note in oracle.inconclusive:
            print(f"- {note}")
        return 2

    print("PLAYABLE_UI_ORACLE: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # Never let an oracle bug masquerade as a feature failure.
        print(f"PLAYABLE_UI_ORACLE: INCONCLUSIVE: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(2)
