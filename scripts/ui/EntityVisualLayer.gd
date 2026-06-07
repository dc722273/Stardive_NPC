extends Node2D
class_name EntityVisualLayer
const NPCVisualScript := preload("res://scripts/ui/NPCVisual.gd")
const ItemVisualScript := preload("res://scripts/ui/ItemVisual.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")
var npc_visuals: Dictionary = {}
var item_visuals: Dictionary = {}
var _marker_texture_cache: Dictionary = {}
var wellbeing_config: Dictionary = {}


func configure_wellbeing(p_config: Dictionary) -> void:
	wellbeing_config = p_config.duplicate(true)


func sync_from_registry(entity_registry) -> void:
	if entity_registry == null:
		return
	_sync_npcs(entity_registry)
	_sync_items(entity_registry)
func _sync_npcs(entity_registry) -> void:
	for npc_id in entity_registry.npcs.keys():
		var npc = entity_registry.npcs[npc_id]
		var visual = npc_visuals.get(npc_id)
		if visual == null:
			visual = NPCVisualScript.new()
			visual.npc_id = npc_id
			add_child(visual)
			npc_visuals[npc_id] = visual
		visual.label_text = str(npc.name)
		visual.color = _color_for_npc(npc)
		visual.marker_texture = _marker_texture_for_npc(npc)
		_apply_wellbeing_visual(visual, npc)
		visual.position = npc.position
		visual.queue_redraw()
	for npc_id in npc_visuals.keys().duplicate():
		if not entity_registry.npcs.has(npc_id):
			npc_visuals[npc_id].queue_free()
			npc_visuals.erase(npc_id)
func _sync_items(entity_registry) -> void:
	var held_index_by_npc: Dictionary = {}
	for item_id in entity_registry.items.keys():
		var item = entity_registry.items[item_id]
		var visual = item_visuals.get(item_id)
		if visual == null:
			visual = ItemVisualScript.new()
			visual.item_id = item_id
			add_child(visual)
			item_visuals[item_id] = visual
		visual.label_text = str(item.name)
		visual.icon_text = _item_icon_text(item)
		visual.held = item.anchor_npc_id() != &""
		visual.queue_redraw()
		var anchor_npc_id: StringName = item.anchor_npc_id()
		if anchor_npc_id != &"" and npc_visuals.has(anchor_npc_id):
			var index := int(held_index_by_npc.get(anchor_npc_id, 0))
			held_index_by_npc[anchor_npc_id] = index + 1
			var anchor = npc_visuals[anchor_npc_id].get_node_or_null("HeldItemAnchor")
			if anchor != null and visual.get_parent() != anchor:
				visual.get_parent().remove_child(visual)
				anchor.add_child(visual)
			visual.position = _held_item_offset(index)
		else:
			if visual.get_parent() != self:
				visual.get_parent().remove_child(visual)
				add_child(visual)
			visual.position = item.position
	for item_id in item_visuals.keys().duplicate():
		if not entity_registry.items.has(item_id):
			item_visuals[item_id].queue_free()
			item_visuals.erase(item_id)


func _color_from_hex(hex: String) -> Color:
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() < 6:
		return Color(0.34, 0.64, 0.95, 1.0)
	return Color(
		float(hex.substr(0, 2).hex_to_int()) / 255.0,
		float(hex.substr(2, 2).hex_to_int()) / 255.0,
		float(hex.substr(4, 2).hex_to_int()) / 255.0,
		1.0
	)


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _marker_texture_for_npc(npc) -> Texture2D:
	if npc == null:
		return null
	var visual: Dictionary = npc.visual if npc != null and npc.get("visual") is Dictionary else {}
	var marker_path := str(visual.get("markerPath", ""))
	if marker_path.is_empty():
		return null
	if _marker_texture_cache.has(marker_path):
		return _marker_texture_cache[marker_path]
	var texture := _load_texture(marker_path)
	_marker_texture_cache[marker_path] = texture
	return texture


func _apply_wellbeing_visual(visual, npc) -> void:
	visual.wellbeing_icon_text = ""
	visual.wellbeing_effect = ""
	if npc == null or not (npc.wellbeing is Dictionary):
		return
	var wellbeing: Dictionary = npc.wellbeing
	if str(wellbeing.get("state", "normal")) != "down" and str(wellbeing.get("state", "normal")) != "worse":
		return
	if bool(wellbeing.get("resolved", false)):
		return
	var problem := str(wellbeing.get("problem", ""))
	var problem_cfg: Dictionary = wellbeing_config.get("problems", {}).get(problem, {})
	visual.wellbeing_icon_text = str(problem_cfg.get("iconText", ""))
	visual.wellbeing_effect = str(problem_cfg.get("effect", ""))


func _held_item_offset(index: int) -> Vector2:
	return HeldItemLayoutScript.item_offset(index)


func _color_for_npc(npc) -> Color:
	var traits: Dictionary = npc.traits if npc != null else {}
	var tell := float(traits.get("tell", 50.0)) / 100.0
	var play := float(traits.get("play", 50.0)) / 100.0
	var control := float(traits.get("control", 50.0)) / 100.0
	return Color(0.35 + control * 0.35, 0.42 + play * 0.25, 0.55 + tell * 0.25, 1.0)


func _item_icon_text(item) -> String:
	var visual: Dictionary = item.visual if item != null and item.visual is Dictionary else {}
	var icon_text := str(visual.get("iconText", ""))
	if not icon_text.is_empty():
		return icon_text
	var object_name := str(item.name)
	return object_name.left(2).to_upper()
