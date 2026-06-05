extends SceneTree

# Frozen oracle for main Task 3 spec conformance.
#
# Covers two observable spec violations found in review:
#   A. WorldPlaceRegistry.get_random_cell_in_place() must only return door_cell
#      or a walkable interior cell — never a fence cell (spec:370).
#   B. BuildingPlacementService.place_fenced_area() must keep door_cell walkable
#      in the pathfinding grid even if that cell was solid beforehand, by
#      explicitly setting fence solid + door/interior walkable (spec:274-280,
#      326-338). Blocking only fence and relying on an implicit walkable default
#      is a spec deviation.
#
# Both assertions FAIL on the pre-fix implementation and PASS after the fix,
# using the SAME assertions (RAIL: F->P, oracle read-only).

const PASS_MARKER := "PLACE_REGISTRY_WALKABLE_ORACLE: PASS"

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const BuildingPlacementServiceScript := preload("res://scripts/world/BuildingPlacementService.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_a_random_cell_never_returns_fence()
	_test_b_door_stays_walkable_when_pre_solid()
	_finish()


# --- A: get_random_cell_in_place output domain ---------------------------------
func _test_a_random_cell_never_returns_fence() -> void:
	var registry = WorldPlaceRegistryScript.new()

	# A normal 3x3 place: interior is the only non-boundary cell (2,2);
	# door is a non-corner boundary cell (2,1); fence is the rest of the boundary.
	var footprint := Rect2i(1, 1, 3, 3)
	var door_cell := Vector2i(2, 1)
	var fence_cells := [
		Vector2i(1, 1), Vector2i(3, 1),
		Vector2i(1, 2), Vector2i(3, 2),
		Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	]
	var interior_cells := [Vector2i(2, 2)]
	registry.create_place(&"place_normal", "Garden", "", footprint, door_cell, fence_cells, interior_cells)

	var normal_pick: Vector2i = registry.get_random_cell_in_place(&"place_normal")
	# Provenance: spec:370 — get_random_cell_in_place may only return door_cell or
	# a walkable interior cell, never a fence cell.
	_assert_true(not fence_cells.has(normal_pick),
		"A1 normal place: random cell is not a fence cell (got %s)" % str(normal_pick))
	# Provenance: spec:370 — the returned cell must be in {door_cell} ∪ interior_cells.
	_assert_true(normal_pick == door_cell or interior_cells.has(normal_pick),
		"A2 normal place: random cell is door or interior (got %s)" % str(normal_pick))

	# A degenerate place with NO interior cells but real fence cells. The registry
	# must NOT fall back to a fence cell; spec:370 forbids returning fence. The
	# only legal non-fence cell available is door_cell.
	var degen_footprint := Rect2i(5, 5, 3, 3)
	var degen_door := Vector2i(6, 5)
	var degen_fence := [
		Vector2i(5, 5), Vector2i(7, 5),
		Vector2i(5, 6), Vector2i(7, 6),
		Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7),
	]
	registry.create_place(&"place_degen", "Edge", "", degen_footprint, degen_door, degen_fence, [])

	var degen_pick: Vector2i = registry.get_random_cell_in_place(&"place_degen")
	# Provenance: spec:370 — even with no interior, the result must never be a fence cell.
	_assert_true(not degen_fence.has(degen_pick),
		"A3 degenerate place (empty interior): result is not a fence cell (got %s)" % str(degen_pick))
	# Provenance: spec:370 — with empty interior the only legal cell is door_cell
	# (or INVALID_CELL if no legal cell exists); never a fence cell.
	_assert_true(degen_pick == degen_door or degen_pick == ConstantsScript.INVALID_CELL,
		"A4 degenerate place: result is door_cell or INVALID_CELL (got %s)" % str(degen_pick))


# --- B: door stays walkable after placement, even if pre-solid -----------------
func _test_b_door_stays_walkable_when_pre_solid() -> void:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, -2, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(entity_registry.map_bounds)
	var event_log = InteractionEventLogScript.new()
	var service = BuildingPlacementServiceScript.new()
	service.configure(entity_registry, place_registry, pathfinder, event_log)

	# Footprint (1,1,3,4): interior = {(2,2),(2,3)}. With drag end above at (2,0)
	# the chosen door is the top-edge non-corner cell (2,1), whose inside-neighbor
	# is (2,2). We pre-mark solid ONLY door (2,1) and interior (2,3):
	#   - (2,2) is left walkable so the door's walkable-connection check passes and
	#     (2,1) can be selected as the door.
	#   - door (2,1) is never part of fence_cells, so can_place's solid-fence check
	#     does not reject it; placement must still succeed.
	#   - (2,3) is a real interior cell that does NOT participate in door
	#     connectivity, so pre-blocking it does not affect placement, but the
	#     service must explicitly clear its solid state on placement.
	# This pins both fix lines: explicit door-unblock AND explicit interior-unblock.
	var footprint := Rect2i(1, 1, 3, 4)
	var expected_door := Vector2i(2, 1)
	var interior_cell := Vector2i(2, 3)
	pathfinder.set_solid_cell(expected_door, true)
	pathfinder.set_solid_cell(interior_cell, true)

	var result: Dictionary = service.place_fenced_area(&"place_b", "Yard", "", footprint, Vector2i(2, 0))

	# Provenance: placement of a 3x3 footprint with a clear drag target is legal
	# (can_place must succeed); door is not part of fence cells.
	_assert_true(result.get("ok", false),
		"B0 placement succeeds (reason=%s)" % str(result.get("reason", "")))
	var placed_door: Vector2i = result["place"].door_cell if result.has("place") and result["place"] != null else ConstantsScript.INVALID_CELL
	_assert_equal(placed_door, expected_door, "B0b chosen door is the expected top-edge cell")

	# Provenance: spec:276,332-336 — door_cell must be walkable in the pathfinding
	# grid after placement; the service must explicitly clear its solid state.
	_assert_equal(pathfinder.is_walkable(expected_door), true,
		"B1 door cell is walkable after placement even though it was pre-solid")
	# Provenance: spec:277,334-336 — interior cells must be walkable after placement.
	_assert_equal(pathfinder.is_walkable(interior_cell), true,
		"B2 interior cell is walkable after placement even though it was pre-solid")
	# Provenance: spec:275,329-330 — fence cells must be solid (blocked) after placement.
	_assert_equal(pathfinder.is_walkable(Vector2i(1, 1)), false,
		"B3 fence corner cell is blocked after placement")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
		return

	print("PLACE_REGISTRY_WALKABLE_ORACLE: FAIL")
	for failure in failures:
		push_error(failure)
	quit(1)
