extends SceneTree
const PASS_MARKER := "ENTITY_VISUAL_ORACLE: PASS"
const FAIL_MARKER := "ENTITY_VISUAL_ORACLE: FAIL"
const EntityVisualLayerScript := preload("res://scripts/ui/EntityVisualLayer.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
var failures: Array = []
func _initialize() -> void:
	_run()
	_finish()
func _run() -> void:
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	registry.add_npc(NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 80.0, "y": 48.0}}))
	registry.add_item(ItemStateScript.from_dict({"id": "it_a", "position": {"x": 16.0, "y": 16.0}}))
	var layer = EntityVisualLayerScript.new()
	get_root().add_child(layer)
	layer.sync_from_registry(registry)
	_assert_true(layer.npc_visuals.has(StringName("npc_a")), "npc visual created")
	_assert_true(layer.item_visuals.has(StringName("it_a")), "item visual created")
	var nv = layer.npc_visuals[StringName("npc_a")]
	_assert_true(nv.position == Vector2(80, 48), "npc visual mirrors position, got %s" % str(nv.position))
	_assert_true(nv.get_node_or_null("HeldItemAnchor") != null, "has HeldItemAnchor")
	_assert_true(nv.get_node_or_null("SpeechBubble") != null, "has SpeechBubble")
	registry.npcs.erase(StringName("npc_a"))
	layer.sync_from_registry(registry)
	_assert_true(not layer.npc_visuals.has(StringName("npc_a")), "npc visual removed after registry delete")
	var reg2 = WorldEntityRegistryScript.new()
	reg2.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg2.add_npc(NPCStateScript.from_dict({"id": "npc_x", "position": {"x": 16.0, "y": 16.0}}))
	var layer2 = EntityVisualLayerScript.new()
	get_root().add_child(layer2)
	layer2.sync_from_registry(reg2)
	var nvx = layer2.npc_visuals[StringName("npc_x")]
	nvx.show_bubble("去看看可乐")
	var bubble = nvx.get_node("SpeechBubble")
	_assert_true(bubble.visible, "bubble visible after show_bubble")
	_assert_true(bubble.text == "去看看可乐", "bubble text set")
	var reg3 = WorldEntityRegistryScript.new()
	reg3.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg3.add_npc(NPCStateScript.from_dict({"id": "npc_h", "position": {"x": 48.0, "y": 48.0}}))
	reg3.add_item(ItemStateScript.from_dict({"id": "it_h", "position": {"x": 80.0, "y": 48.0}}))
	var layer3 = EntityVisualLayerScript.new()
	get_root().add_child(layer3)
	layer3.sync_from_registry(reg3)
	reg3.give_item_to_npc(StringName("it_h"), StringName("npc_h"))
	layer3.sync_from_registry(reg3)
	var iv = layer3.item_visuals[StringName("it_h")]
	var held_anchor = layer3.npc_visuals[StringName("npc_h")].get_node("HeldItemAnchor")
	_assert_true(iv.get_parent() == held_anchor, "held item visual reparented to HeldItemAnchor")
func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER); quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures: print("  - %s" % f)
		quit(1)
