extends SceneTree


var failures: Array[String] = []


func _initialize() -> void:
	_check_main_scene_loads()
	if failures.is_empty():
		print("PLAYABLE_UI_GODOT_ORACLE: PASS")
		quit(0)
		return

	print("PLAYABLE_UI_GODOT_ORACLE: FAIL")
	for failure in failures:
		push_error(failure)
	quit(1)


func _check_main_scene_loads() -> void:
	var packed_scene := load("res://scenes/main.tscn")
	# provenance: spec node tree requires scenes/main.tscn to be loadable as the playable GameRoot scene.
	_require(packed_scene != null, "scenes/main.tscn must load", "spec Godot node tree")
	if packed_scene == null:
		return

	var root = packed_scene.instantiate()
	# provenance: spec node tree top-level node is GameRoot.
	_require(root != null and root.name == "GameRoot", "main scene root must be GameRoot", "spec Godot node tree")
	if root == null:
		return

	# provenance: feature request says scenes/main.tscn attaches MainGame.
	var root_script = root.get_script()
	_require(
		root_script != null and str(root_script.resource_path).ends_with("scripts/MainGame.gd"),
		"GameRoot must attach scripts/MainGame.gd",
		"feature request scenes/main.tscn attaches MainGame"
	)

	# provenance: spec node tree requires these direct scene nodes.
	for node_path in ["WorldMap", "WorldState", "NPCSystem", "UI"]:
		_require(root.get_node_or_null(node_path) != null, "main scene must contain " + node_path, "spec Godot node tree")

	# provenance: spec node tree requires WorldMap display/input children.
	for node_path in ["WorldMap/GridSelectionOverlay", "WorldMap/FencedAreaOverlay"]:
		_require(root.get_node_or_null(node_path) != null, "main scene must contain " + node_path, "spec Godot node tree")

	# provenance: v2 P0 moves entity rendering out of MainGame._draw into a dedicated EntityVisualLayer node.
	_require(root.get_node_or_null("WorldMap/EntityVisualLayer") != null, "main scene must contain WorldMap/EntityVisualLayer", "v2 P0 EntityVisualLayer node")

	# provenance: spec node tree requires UI/FencedAreaEditPanel.
	_require(root.get_node_or_null("UI/FencedAreaEditPanel") != null, "main scene must contain UI/FencedAreaEditPanel", "spec Godot node tree")

	# provenance: v2 P3 collapsible controls hint (H to expand) requires UI/ControlsHint node.
	_require(root.get_node_or_null("UI/ControlsHint") != null, "main scene must contain UI/ControlsHint", "v2 P3 collapsible controls hint")

	# provenance: v2 P3 schedule sidebar shows selected NPC todo_list; requires UI/ScheduleSidebar node.
	_require(root.get_node_or_null("UI/ScheduleSidebar") != null, "main scene must contain UI/ScheduleSidebar", "v2 P3 schedule sidebar")

	# provenance: spec node tree requires WorldState service nodes.
	for node_path in [
		"WorldState/WorldPlaceRegistry",
		"WorldState/WorldEntityRegistry",
		"WorldState/BuildingPlacementService",
		"WorldState/InteractionEventLog",
	]:
		_require(root.get_node_or_null(node_path) != null, "main scene must contain " + node_path, "spec Godot node tree")

	root.free()


func _require(condition: bool, message: String, provenance: String) -> void:
	if not condition:
		failures.append(message + " | provenance: " + provenance)
