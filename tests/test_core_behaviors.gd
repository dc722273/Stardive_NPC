extends RefCounted
class_name TestCoreBehaviors

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const FencedAreaPlaceScript := preload("res://scripts/state/FencedAreaPlace.gd")
const InteractionEventScript := preload("res://scripts/state/InteractionEvent.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const DailyTodoPlannerScript := preload("res://scripts/npc/DailyTodoPlanner.gd")
const LLMClientScript := preload("res://scripts/npc/LLMClient.gd")
const NPCActionSchedulerScript := preload("res://scripts/npc/NPCActionScheduler.gd")
const NPCFeedbackBuilderScript := preload("res://scripts/npc/NPCFeedbackBuilder.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const InteractionDeltaRulesScript := preload("res://scripts/world/InteractionDeltaRules.gd")
const MainGameScript := preload("res://scripts/MainGame.gd")
const EntityVisualLayerScript := preload("res://scripts/ui/EntityVisualLayer.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")
const NPCVisualScript := preload("res://scripts/ui/NPCVisual.gd")


func run() -> Array:
	var failures: Array = []
	_test_constants(failures)
	_test_movement_constants(failures)
	_test_world_cell_conversions(failures)
	_test_todo_round_trip(failures)
	_test_interaction_event_round_trip(failures)
	_test_item_round_trip_and_held_sentinel(failures)
	_test_item_type_defaults_and_social_override(failures)
	_test_npc_nested_round_trip(failures)
	_test_fenced_area_round_trip(failures)
	_test_item_drop_updates_position(failures)
	_test_item_drop_on_npc_sets_current_anchor(failures)
	_test_second_item_on_holding_npc_is_allowed_like_stardive(failures)
	_test_right_click_discard_drops_all_held_items_and_records_events(failures)
	_test_drag_hit_prefers_visible_held_item(failures)
	_test_release_held_item_to_other_npc_records_transfer_event(failures)
	_test_repeated_rejected_item_is_auto_dropped_by_npc(failures)
	_test_feedback_pause_blocks_npc_movement_and_new_decisions(failures)
	_test_speech_bubble_duration_and_font_size(failures)
	_test_art_assets_load_by_picture_name(failures)
	_test_save_load_repair_uses_item_holder_as_authority(failures)
	_test_append_event_advances_generated_id_counter(failures)
	_test_fenced_area_geometry_for_3x3_footprint(failures)
	_test_world_place_registry_round_trip_and_queries(failures)
	_test_fenced_area_rejects_thin_footprints(failures)
	_test_placement_rejects_npc_current_occupancy(failures)
	_test_placement_rejects_overlaps_and_door_covered_by_fence(failures)
	_test_pathfinder_blocks_fence_but_routes_through_door(failures)
	_test_placement_path_impact_replans_or_blocks_todo(failures)
	_test_daily_todo_planner_validation_and_fallback(failures)
	_test_llm_client_generation_guard_and_cancel(failures)
	_test_action_scheduler_lane_locks(failures)
	_test_feedback_builder_binds_event_context(failures)
	_test_todo_executor_blocks_and_adds_fallback(failures)
	_test_npc_mover_replans_when_path_is_invalidated(failures)
	_test_position_is_source_of_truth(failures)
	_test_interaction_delta_updates_object_and_relation_memory(failures)
	return failures


func _test_constants(failures: Array) -> void:
	_assert_equal(ConstantsScript.INVALID_CELL, Vector2i(-1, -1), "INVALID_CELL sentinel changed", failures)


func _test_movement_constants(failures: Array) -> void:
	_assert_equal(ConstantsScript.NPC_SPEED, 44.0, "NPC_SPEED matches Stardive free-roam speed", failures)
	_assert_equal(ConstantsScript.INTERACT_RADIUS, 40.0, "INTERACT_RADIUS is 40 px", failures)


func _test_world_cell_conversions(failures: Array) -> void:
	_assert_equal(ConstantsScript.CELL_SIZE, 64, "CELL_SIZE matches Stardive tile size", failures)
	_assert_equal(ConstantsScript.world_to_cell(Vector2(0, 0)), Vector2i(0, 0), "world_to_cell origin", failures)
	_assert_equal(ConstantsScript.world_to_cell(Vector2(80, 144)), Vector2i(1, 2), "world_to_cell mid-cell", failures)
	_assert_equal(ConstantsScript.world_to_cell(Vector2(128, 128)), Vector2i(2, 2), "world_to_cell on boundary", failures)
	_assert_equal(ConstantsScript.cell_to_world_center(Vector2i(0, 0)), Vector2(32, 32), "cell center origin", failures)
	_assert_equal(ConstantsScript.cell_to_world_center(Vector2i(2, 1)), Vector2(160, 96), "cell center 2,1", failures)


func _test_todo_round_trip(failures: Array) -> void:
	var todo = TodoItemScript.from_dict({
		"id": "todo_visit",
		"intent": "visit_place",
		"target_place_id": "place_hospital",
		"reason": "check in",
		"priority": 80,
		"status": "pending",
	})
	_assert_equal(todo.to_dict()["intent"], &"visit_place", "TodoItem keeps intent", failures)
	_assert_equal(todo.to_dict()["target_place_id"], &"place_hospital", "TodoItem keeps target place", failures)


func _test_interaction_event_round_trip(failures: Array) -> void:
	var event = InteractionEventScript.from_dict({
		"id": "event_1",
		"type": "player_drop_item_on_npc",
		"actor_id": "player",
		"primary_entity_id": "item_cola",
		"target_entity_id": "npc_jiutong",
		"target_type": "npc",
		"cell": {"x": 3, "y": 4},
		"tick": 12,
		"payload": {"note": "hello"},
	})
	_assert_equal(event.to_dict()["cell"], {"x": 3, "y": 4}, "InteractionEvent keeps cell", failures)
	_assert_equal(event.to_dict()["payload"], {"note": "hello"}, "InteractionEvent keeps payload", failures)
	var malformed = InteractionEventScript.from_dict({"payload": "not a dictionary"})
	_assert_equal(malformed.payload, {}, "InteractionEvent ignores malformed payload", failures)


func _test_item_round_trip_and_held_sentinel(failures: Array) -> void:
	var grid_item = ItemStateScript.from_dict({
		"id": "item_cola",
		"name": "Cola",
		"category": "drink",
		"current_cell": {"x": 5, "y": 6},
	})
	_assert_equal(grid_item.to_dict()["current_cell"], {"x": 5, "y": 6}, "ItemState keeps grid cell", failures)
	var held_item = ItemStateScript.from_dict({
		"id": "item_cola",
		"currentAnchor": {"type": "npc", "npcId": "npc_jiutong"},
	})
	_assert_equal(held_item.current_cell, ConstantsScript.INVALID_CELL, "Anchored ItemState uses INVALID_CELL", failures)
	_assert_equal(held_item.anchor_npc_id(), &"npc_jiutong", "ItemState reads currentAnchor npcId", failures)


func _test_item_type_defaults_and_social_override(failures: Array) -> void:
	var object_types := {
		"diet_coke": {
			"name": "Diet Coke",
			"category": "drink",
			"defaultSocial": {"status": 80, "utility": 50, "joke": 95},
			"defaultAffordance": {"draggable": true, "openable": true, "consumable": true},
		}
	}
	var item = ItemStateScript.from_dict({
		"id": "diet_coke_001",
		"typeId": "diet_coke",
		"social": {"danger": 7},
	}, object_types)
	_assert_equal(item.name, "Diet Coke", "ItemState resolves type name", failures)
	_assert_equal(item.category, "drink", "ItemState resolves type category", failures)
	_assert_equal(item.social["status"], 80, "ItemState applies default social", failures)
	_assert_equal(item.social["danger"], 7, "ItemState applies instance social override", failures)
	_assert_equal(item.affordance["openable"], true, "ItemState applies default affordance", failures)
	_assert_equal(item.to_dict().has("name"), false, "SocialObject instance does not duplicate type name", failures)
	_assert_equal(item.to_dict()["typeId"], &"diet_coke", "SocialObject serializes typeId", failures)


func _test_npc_nested_round_trip(failures: Array) -> void:
	var npc = NPCStateScript.from_dict({
		"id": "npc_jiutong",
		"name": "Jiu Tong",
		"traits": {"tell": 40, "face": 50, "control": 60, "caution": 70, "play": 30},
		"style": {"lineMode": "strategic_observer"},
		"current_cell": {"x": 1, "y": 2},
		"todo_list": [{"id": "todo_1", "intent": "wander"}],
		"recent_events": [{"id": "event_1", "type": "player_drop_item_on_npc"}],
	})
	_assert_equal(npc.to_dict()["current_cell"], {"x": 1, "y": 2}, "NPCState keeps current cell", failures)
	_assert_equal(npc.to_dict()["name"], "Jiu Tong", "NPCState serializes profile name", failures)
	_assert_equal(npc.todo_list.size(), 1, "NPCState loads nested todos", failures)
	_assert_equal(npc.recent_events.size(), 1, "NPCState loads nested events", failures)
	var malformed = NPCStateScript.from_dict({"todo_list": null, "recent_events": "bad"})
	_assert_equal(malformed.todo_list.size(), 0, "NPCState ignores malformed todo list", failures)
	_assert_equal(malformed.recent_events.size(), 0, "NPCState ignores malformed recent events", failures)


func _test_fenced_area_round_trip(failures: Array) -> void:
	_assert_equal(FencedAreaPlaceScript.new().to_dict().has("footprint"), true, "FencedAreaPlace serializes footprint", failures)
	_assert_equal(FencedAreaPlaceScript.new().to_dict().has("rect_cells"), false, "FencedAreaPlace must not serialize rect_cells", failures)
	var place = FencedAreaPlaceScript.from_dict({
		"footprint": {"position": {"x": 1, "y": 2}, "size": {"x": 3, "y": 4}},
		"door_cell": {"x": 2, "y": 2},
		"fence_cells": [{"x": 1, "y": 2}],
		"interior_cells": [{"x": 2, "y": 3}],
	})
	_assert_equal(place.footprint, Rect2i(1, 2, 3, 4), "FencedAreaPlace deserializes footprint", failures)
	_assert_equal(place.door_cell, Vector2i(2, 2), "FencedAreaPlace deserializes door", failures)
	_assert_equal(place.fence_cells, [Vector2i(1, 2)], "FencedAreaPlace deserializes fence cells", failures)
	_assert_equal(place.interior_cells, [Vector2i(2, 3)], "FencedAreaPlace deserializes interior cells", failures)


func _test_item_drop_updates_position(failures: Array) -> void:
	var reg = WorldEntityRegistryScript.new()
	reg.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg.add_item(ItemStateScript.from_dict({"id": "it", "position": {"x": 16.0, "y": 16.0}}))
	var ok = reg.set_entity_position(StringName("it"), Vector2(80, 80))
	_assert_equal(ok, true, "set item position ok", failures)
	_assert_equal(reg.items[StringName("it")].position, Vector2(80, 80), "item position updated", failures)


func _test_item_drop_on_npc_sets_current_anchor(failures: Array) -> void:
	var registry = _make_registry()
	var npc = NPCStateScript.from_dict({"id": "npc_jiutong", "current_cell": {"x": 2, "y": 2}})
	var item = ItemStateScript.from_dict({"id": "item_cola", "current_cell": {"x": 1, "y": 1}})
	registry.add_npc(npc)
	registry.add_item(item)

	_assert_equal(registry.give_item_to_npc(&"item_cola", &"npc_jiutong"), true, "NPC accepts object anchor", failures)
	_assert_equal(item.anchor_npc_id(), &"npc_jiutong", "Item records currentAnchor npcId", failures)
	_assert_equal(item.current_cell, ConstantsScript.INVALID_CELL, "Anchored item leaves grid", failures)
	_assert_equal(item.custody_state, "unclaimed", "Attach defaults to unclaimed custody", failures)
	_assert_equal(registry.get_item_at_cell(Vector2i(1, 1)), &"", "Anchored item is removed from item occupancy", failures)


func _test_second_item_on_holding_npc_is_allowed_like_stardive(failures: Array) -> void:
	var registry = _make_registry()
	var npc = NPCStateScript.from_dict({"id": "npc_jiutong", "current_cell": {"x": 2, "y": 2}})
	var first_item = ItemStateScript.from_dict({"id": "item_cola", "currentAnchor": {"type": "npc", "npcId": "npc_jiutong"}})
	var second_item = ItemStateScript.from_dict({"id": "item_chip", "current_cell": {"x": 1, "y": 1}})
	registry.add_npc(npc)
	registry.add_item(first_item)
	registry.add_item(second_item)

	_assert_equal(registry.give_item_to_npc(&"item_chip", &"npc_jiutong"), true, "Stardive-style NPC accepts a second item", failures)
	_assert_equal(first_item.anchor_npc_id(), &"npc_jiutong", "First item remains anchored", failures)
	_assert_equal(second_item.anchor_npc_id(), &"npc_jiutong", "Second item records same anchor", failures)
	_assert_equal(second_item.current_cell, ConstantsScript.INVALID_CELL, "Second anchored item leaves grid", failures)
	_assert_equal(registry.items_anchored_to_npc(&"npc_jiutong").size(), 2, "Registry lists both anchored items", failures)


func _test_right_click_discard_drops_all_held_items_and_records_events(failures: Array) -> void:
	var registry = _make_registry()
	var event_log = InteractionEventLogScript.new()
	var npc = NPCStateScript.from_dict({"id": "npc_jiutong", "current_cell": {"x": 2, "y": 2}})
	var item = ItemStateScript.from_dict({"id": "item_cola", "currentAnchor": {"type": "npc", "npcId": "npc_jiutong"}})
	var item_two = ItemStateScript.from_dict({"id": "item_chip", "currentAnchor": {"type": "npc", "npcId": "npc_jiutong"}})
	registry.add_npc(npc)
	registry.add_item(item)
	registry.add_item(item_two)

	_assert_equal(registry.drop_anchored_items(&"npc_jiutong", event_log), true, "Right-click discard drops anchored items", failures)
	_assert_equal(item.anchor_type(), "ground", "Discard clears item anchor", failures)
	_assert_equal(item_two.anchor_type(), "ground", "Discard clears second item anchor", failures)
	_assert_equal(item.position.x > npc.position.x, true, "Discard lands item near holder", failures)
	var recent = event_log.recent_events(2)
	_assert_equal(recent.size(), 2, "Discard records one event per dropped item", failures)
	_assert_equal(recent[0].type, &"player_forced_drop_item", "Discard event type is player_forced_drop_item", failures)
	var dropped_ids := [recent[0].primary_entity_id, recent[1].primary_entity_id]
	_assert_equal(dropped_ids.has(&"item_cola"), true, "Discard event records cola id", failures)
	_assert_equal(dropped_ids.has(&"item_chip"), true, "Discard event records chip id", failures)
	_assert_equal(recent[0].target_entity_id, &"npc_jiutong", "Discard event records NPC id", failures)


func _test_drag_hit_prefers_visible_held_item(failures: Array) -> void:
	var context := _make_main_game_drag_context()
	var game = context["game"]
	var holder = context["holder"]
	var visual_item_pos: Vector2 = holder.position + HeldItemLayoutScript.anchor_offset() + HeldItemLayoutScript.item_offset(0)

	_assert_equal(game._item_world_position(&"item_cola"), visual_item_pos, "Held item logical hit position matches visual anchor", failures)
	_assert_equal(game._hit_test_entity(holder.position), &"npc_alpha", "Clicking NPC center still selects NPC", failures)
	_assert_equal(game._hit_test_entity(visual_item_pos + Vector2(-24.0, 0.0)), &"item_cola", "Clicking visible held item selects item even near holder", failures)
	game.free()


func _test_release_held_item_to_other_npc_records_transfer_event(failures: Array) -> void:
	var context := _make_main_game_drag_context()
	var game = context["game"]
	var target = context["target"]
	game.dragged_item_previous_anchor_npc_id = &"npc_alpha"

	var handled: bool = game._handle_item_release(&"item_cola", target.position)

	_assert_equal(handled, true, "Dropping held item on another NPC is handled", failures)
	_assert_equal(game.entity_registry.items[&"item_cola"].anchor_npc_id(), &"npc_beta", "Held item transfers to target NPC", failures)
	var recent = game.event_log.recent_events(1)
	_assert_equal(recent.size(), 1, "Transfer writes one interaction event", failures)
	if not recent.is_empty():
		_assert_equal(recent[0].type, &"player_transfer_item_between_npcs", "Transfer event type drives NPC dialogue feedback", failures)
		_assert_equal(recent[0].payload.get("item_transfer_interaction", false), true, "Transfer payload is marked as item transfer", failures)
		_assert_equal(recent[0].payload.get("npc_ids", []).has(&"npc_alpha"), true, "Transfer payload includes previous holder", failures)
		_assert_equal(recent[0].payload.get("npc_ids", []).has(&"npc_beta"), true, "Transfer payload includes target holder", failures)
	game.free()


func _test_repeated_rejected_item_is_auto_dropped_by_npc(failures: Array) -> void:
	var game = MainGameScript.new()
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var object_types := {
		"diet_coke": {
			"name": "Diet Coke",
			"category": "drink",
			"defaultSocial": {"status": 80, "utility": 50, "debt": 60, "awkward": 90, "joke": 95, "danger": 5},
		},
		"status_briefcase": {
			"name": "Status Briefcase",
			"category": "prop",
			"defaultSocial": {"status": 90, "utility": 80, "debt": 20, "awkward": 80, "joke": 10, "danger": 0},
		}
	}
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict({"id": "trump", "name": "Trump", "position": {"x": 64.0, "y": 64.0}}))
	registry.add_npc(NPCStateScript.from_dict({
		"id": "jiu_tong",
		"name": "Jiu Tong",
		"position": {"x": 160.0, "y": 160.0},
		"traits": {"caution": 82, "face": 65, "control": 52, "play": 36, "tell": 42},
		"tags": ["avoid_responsibility"],
	}))
	registry.add_npc(NPCStateScript.from_dict({
		"id": "status_keeper",
		"name": "Status Keeper",
		"position": {"x": 224.0, "y": 160.0},
		"traits": {"caution": 20, "face": 90, "control": 60, "play": 40, "tell": 50},
		"tags": [],
	}))
	var coke = ItemStateScript.from_dict({
		"id": "diet_coke",
		"typeId": "diet_coke",
		"ownerId": "trump",
		"accessRule": {"allowedNpcIds": ["trump"], "publicKnown": true, "exclusivity": 95},
		"currentAnchor": {"type": "ground"},
		"position": {"x": 96.0, "y": 96.0},
		"memory": {"topLinks": []},
	}, object_types)
	var briefcase = ItemStateScript.from_dict({
		"id": "status_briefcase",
		"typeId": "status_briefcase",
		"ownerId": "trump",
		"accessRule": {"allowedNpcIds": ["trump"], "publicKnown": true, "exclusivity": 95},
		"currentAnchor": {"type": "ground"},
		"position": {"x": 128.0, "y": 96.0},
		"memory": {"topLinks": []},
	}, object_types)
	registry.add_item(coke)
	registry.add_item(briefcase)
	game.entity_registry = registry
	game.gameplay_config = {}

	var cautious_auto_drop := {}
	for i in range(2):
		_assert_equal(registry.give_item_to_npc(&"diet_coke", &"jiu_tong"), true, "Repeated rejected item can be attached before auto rule", failures)
		var payload: Dictionary = game._item_event_payload(&"diet_coke", &"jiu_tong", &"trump")
		var auto_drop: Dictionary = game._maybe_auto_drop_rejected_item(&"diet_coke", &"jiu_tong", payload)
		if i == 0:
			_assert_equal(auto_drop.is_empty(), true, "First rejected attach is not auto-dropped for cautious NPC", failures)
		if i == 1:
			cautious_auto_drop = auto_drop
	_assert_equal(cautious_auto_drop.is_empty(), false, "Cautious responsibility-avoidant NPC auto-drops on second rejected attach", failures)
	_assert_equal(cautious_auto_drop.get("threshold", 0), 2, "Cautious NPC/object threshold is computed as 2", failures)
	_assert_equal(cautious_auto_drop.get("thresholdFactors", []).has("high_caution"), true, "Auto-drop threshold records high_caution factor", failures)
	_assert_equal(cautious_auto_drop.get("thresholdFactors", []).has("avoid_responsibility"), true, "Auto-drop threshold records avoid_responsibility factor", failures)
	_assert_equal(coke.anchor_type(), "ground", "Auto-dropped rejected item ends on ground", failures)
	_assert_equal(coke.custody_state, "rejected", "Auto-dropped rejected item records rejected custody", failures)
	_assert_equal(cautious_auto_drop.get("countInWindow", 0), 2, "Auto drop reports dynamic repeated interaction count", failures)

	var high_face_auto_drop := {}
	for i in range(4):
		_assert_equal(registry.give_item_to_npc(&"status_briefcase", &"status_keeper"), true, "High-face NPC can hold status object before auto rule", failures)
		var payload: Dictionary = game._item_event_payload(&"status_briefcase", &"status_keeper", &"trump")
		var auto_drop: Dictionary = game._maybe_auto_drop_rejected_item(&"status_briefcase", &"status_keeper", payload)
		if i < 3:
			_assert_equal(auto_drop.is_empty(), true, "High-face NPC delays auto-drop before computed threshold", failures)
		else:
			high_face_auto_drop = auto_drop
	_assert_equal(high_face_auto_drop.is_empty(), false, "High-face NPC eventually auto-drops at later threshold", failures)
	_assert_equal(high_face_auto_drop.get("threshold", 0), 4, "High-face/value object threshold is computed as 4", failures)
	_assert_equal(high_face_auto_drop.get("thresholdFactors", []).has("high_face"), true, "Auto-drop threshold records high_face factor", failures)
	_assert_equal(high_face_auto_drop.get("thresholdFactors", []).has("valuable_object"), true, "Auto-drop threshold records valuable_object factor", failures)
	_assert_equal(briefcase.anchor_type(), "ground", "Late auto-dropped item ends on ground", failures)
	game.free()


func _test_feedback_pause_blocks_npc_movement_and_new_decisions(failures: Array) -> void:
	var game = MainGameScript.new()
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha", "position": {"x": 64.0, "y": 64.0}})
	registry.add_npc(npc)
	game.entity_registry = registry
	game.npc_feedback_pause_until_ms = {}

	game._pause_npc_for_feedback(&"npc_alpha", 8.0)
	game._decide_one_npc(npc)
	_assert_equal(game.npc_movers.has(&"npc_alpha"), false, "Paused NPC does not start new movement decisions", failures)

	var mover := SpeechPauseMover.new()
	game.npc_movers[&"npc_alpha"] = mover
	game.advance_npc_movement(1.0)
	_assert_equal(mover.advance_calls, 0, "Paused NPC active mover does not advance", failures)

	game.npc_feedback_pause_until_ms[&"npc_alpha"] = 0
	game.advance_npc_movement(1.0)
	_assert_equal(mover.advance_calls, 1, "NPC movement resumes after feedback pause expires", failures)
	game.free()


func _test_speech_bubble_duration_and_font_size(failures: Array) -> void:
	var visual = NPCVisualScript.new()
	visual.show_bubble("hello")
	var bubble := visual.get_node_or_null("SpeechBubble") as Label
	_assert_equal(NPCVisualScript.BUBBLE_DURATION, 8.0, "Speech bubble duration is 8 seconds", failures)
	_assert_equal(NPCVisualScript.BUBBLE_FONT_SIZE, 28, "Speech bubble font size is doubled", failures)
	_assert_equal(bubble != null and bubble.visible, true, "Speech bubble becomes visible", failures)
	if bubble != null:
		_assert_equal(bubble.get_theme_font_size("font_size"), 28, "Speech bubble label applies doubled font size", failures)
	visual.free()


func _test_art_assets_load_by_picture_name(failures: Array) -> void:
	var game = MainGameScript.new()
	var bg_texture = game._load_png_texture("res://assets/bg/鹅城地图.png")
	_assert_equal(bg_texture != null, true, "Goose city background loads from picture name", failures)
	if bg_texture != null:
		_assert_equal(bg_texture.get_width() > 0, true, "Goose city background has width", failures)
		_assert_equal(bg_texture.get_height() > 0, true, "Goose city background has height", failures)

	var layer = EntityVisualLayerScript.new()
	for npc_name in ["九筒", "师爷", "特朗普"]:
		var npc = NPCStateScript.from_dict({"id": npc_name, "name": npc_name})
		var marker_texture = layer._marker_texture_for_npc(npc)
		_assert_equal(marker_texture != null, true, "%s marker loads from picture name" % npc_name, failures)
		if marker_texture != null:
			_assert_equal(marker_texture.get_width() > 0, true, "%s marker has width" % npc_name, failures)
			_assert_equal(marker_texture.get_height() > 0, true, "%s marker has height" % npc_name, failures)
	layer.free()
	game.free()


func _test_save_load_repair_uses_item_holder_as_authority(failures: Array) -> void:
	var registry = _make_registry()
	registry.load_from_dict({
		"map_bounds": {"position": {"x": 0, "y": 0}, "size": {"x": 4, "y": 4}},
		"blocked_cells": [],
		"npcs": [
			{"id": "npc_jiutong", "current_cell": {"x": 2, "y": 2}},
		],
		"items": [
			{"id": "item_cola", "currentAnchor": {"type": "npc", "npcId": "npc_jiutong"}},
			{"id": "item_chip", "currentAnchor": {"type": "npc", "npcId": "npc_jiutong"}},
		],
	})

	var item = registry.items[&"item_cola"]
	_assert_equal(item.anchor_npc_id(), &"npc_jiutong", "Repair keeps item currentAnchor", failures)
	_assert_equal(item.current_cell, ConstantsScript.INVALID_CELL, "Repair removes NPC-anchored item from grid", failures)
	_assert_equal(registry.items_anchored_to_npc(&"npc_jiutong").size(), 2, "Repair keeps multiple item anchors", failures)
	_assert_equal(registry.repair_warnings.size(), 0, "Repair does not warn when anchors are valid", failures)
	_assert_equal(registry.to_dict()["items"][0]["currentAnchor"]["npcId"], "npc_jiutong", "Round-trip serializes repaired currentAnchor", failures)


func _test_append_event_advances_generated_id_counter(failures: Array) -> void:
	var event_log = InteractionEventLogScript.new()
	var existing_event = InteractionEventScript.from_dict({
		"id": "event_0001",
		"type": "loaded_event",
	})
	event_log.append_event(existing_event)
	var generated_event = event_log.record(&"player_forced_drop_item")

	_assert_equal(generated_event.id, &"event_0002", "append_event advances generated id counter past explicit event id", failures)


func _test_fenced_area_geometry_for_3x3_footprint(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	var footprint := Rect2i(1, 1, 3, 3)

	var door_cell: Vector2i = service.choose_door_cell_from_drag(footprint, Vector2i(2, 0))
	var fence_cells: Array = service.get_fence_cells(footprint, door_cell)
	var interior_cells: Array = service.get_interior_cells(footprint)

	_assert_equal(door_cell, Vector2i(2, 1), "3x3 footprint chooses nearest non-corner door", failures)
	_assert_equal(fence_cells.has(Vector2i(1, 1)), true, "3x3 fence includes top-left corner", failures)
	_assert_equal(fence_cells.has(Vector2i(3, 3)), true, "3x3 fence includes bottom-right corner", failures)
	_assert_equal(fence_cells.has(door_cell), false, "3x3 fence excludes door cell", failures)
	_assert_equal(fence_cells.size(), 7, "3x3 boundary fence excludes exactly one door", failures)
	_assert_equal(interior_cells, [Vector2i(2, 2)], "3x3 interior is strict non-boundary cell", failures)

	var inside_drag_door: Vector2i = service.choose_door_cell_from_drag(footprint, Vector2i(2, 2))
	_assert_equal(inside_drag_door, Vector2i(2, 1), "Inside drag projects to nearest legal edge door", failures)


func _test_world_place_registry_round_trip_and_queries(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	var registry = context["place_registry"]
	var placed: Dictionary = service.place_fenced_area(&"place_registry", "Garden", "quiet", Rect2i(1, 1, 3, 3), Vector2i(2, 0))
	_assert_equal(placed.get("ok", false), true, "Registry test places fenced area", failures)

	_assert_equal(registry.get_place_at_cell(Vector2i(2, 2)).id, &"place_registry", "Registry finds place by interior cell", failures)
	_assert_equal(registry.get_places_near_cell(Vector2i(4, 4), 1).size(), 1, "Registry finds nearby place", failures)
	_assert_equal(registry.get_random_cell_in_place(&"place_registry"), Vector2i(2, 2), "Registry returns deterministic interior cell without rng", failures)
	_assert_equal(registry.update_text(&"place_registry", "Renamed", "updated", "G", 7), true, "Registry updates place text", failures)

	var WorldPlaceRegistryScript = load("res://scripts/world/WorldPlaceRegistry.gd")
	var loaded_registry = WorldPlaceRegistryScript.new()
	loaded_registry.load_from_dict(registry.to_dict())
	_assert_equal(loaded_registry.get_place_at_cell(Vector2i(2, 2)).name, "Renamed", "Registry persists updated text", failures)
	_assert_equal(loaded_registry.remove_place(&"place_registry"), true, "Registry removes place", failures)
	_assert_equal(loaded_registry.get_place_at_cell(Vector2i(2, 2)), null, "Registry no longer finds removed place", failures)


func _test_fenced_area_rejects_thin_footprints(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	for footprint in [Rect2i(1, 1, 1, 4), Rect2i(1, 1, 2, 4), Rect2i(1, 1, 4, 1), Rect2i(1, 1, 4, 2)]:
		var result: Dictionary = service.can_place_fenced_area(footprint, Vector2i(2, 0))
		_assert_equal(result.get("ok", true), false, "Thin footprint is rejected: %s" % str(footprint), failures)
		_assert_equal(str(result.get("reason", "")).is_empty(), false, "Thin footprint rejection includes reason", failures)


func _test_placement_rejects_npc_current_occupancy(failures: Array) -> void:
	var context = _make_placement_context()
	var registry = context["entity_registry"]
	var service = context["service"]
	registry.add_npc(NPCStateScript.from_dict({"id": "npc_inside", "current_cell": {"x": 2, "y": 2}}))

	var result: Dictionary = service.can_place_fenced_area(Rect2i(1, 1, 3, 3), Vector2i(2, 0))

	_assert_equal(result.get("ok", true), false, "Placement rejects footprint covering NPC current cell", failures)
	_assert_equal(result.get("reason", ""), "npc_occupies_footprint", "NPC occupancy rejection reason is stable", failures)


func _test_placement_rejects_overlaps_and_door_covered_by_fence(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	var first_result: Dictionary = service.place_fenced_area(&"place_first", "Garden", "", Rect2i(1, 1, 3, 3), Vector2i(2, 0))
	_assert_equal(first_result.get("ok", false), true, "Initial fenced area places successfully", failures)

	var overlapping_result: Dictionary = service.can_place_fenced_area(Rect2i(3, 1, 3, 3), Vector2i(4, 0))
	_assert_equal(overlapping_result.get("ok", true), false, "Placement rejects overlapping fenced areas", failures)
	_assert_equal(overlapping_result.get("reason", ""), "overlaps_fenced_area", "Overlap rejection reason is stable", failures)

	var door_covered_result: Dictionary = service.can_place_fenced_area(Rect2i(1, -1, 3, 3), Vector2i(1, 0))
	_assert_equal(door_covered_result.get("ok", true), false, "Placement rejects new fence covering existing door", failures)
	_assert_equal(door_covered_result.get("reason", ""), "door_covered_by_new_fence", "Door-covered rejection reason is stable", failures)


func _test_pathfinder_blocks_fence_but_routes_through_door(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	var pathfinder = context["pathfinder"]
	var placement: Dictionary = service.place_fenced_area(&"place_path", "Garden", "", Rect2i(1, 1, 3, 3), Vector2i(2, 0))
	_assert_equal(placement.get("ok", false), true, "Path test places fenced area", failures)

	_assert_equal(pathfinder.is_walkable(Vector2i(1, 1)), false, "Pathfinder blocks fence cell", failures)
	_assert_equal(pathfinder.is_walkable(Vector2i(2, 1)), true, "Pathfinder keeps door walkable", failures)
	_assert_equal(pathfinder.is_walkable(Vector2i(2, 2)), true, "Pathfinder keeps interior walkable", failures)
	var path: Array = pathfinder.find_path(Vector2i(2, 0), Vector2i(2, 2))
	_assert_equal(path.is_empty(), false, "Pathfinder finds route into fenced interior", failures)
	_assert_equal(path.has(Vector2i(2, 1)), true, "Path into interior goes through door", failures)


func _test_placement_path_impact_replans_or_blocks_todo(failures: Array) -> void:
	var context = _make_placement_context()
	var service = context["service"]
	var event_log = context["event_log"]
	var todo = TodoItemScript.from_dict({"id": "todo_visit", "status": "pending"})
	var mover = StubMover.new(&"npc_path", [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], false, todo)
	service.register_mover(&"npc_path", mover)

	var placement: Dictionary = service.place_fenced_area(&"place_blocking_path", "Garden", "", Rect2i(1, 1, 3, 3), Vector2i(2, 0))

	_assert_equal(placement.get("ok", false), true, "Path impact does not reject placement", failures)
	_assert_equal(mover.replan_requests, 1, "Placement notifies mover whose future path intersects new fence", failures)
	_assert_equal(todo.status, &"BLOCKED", "Failed replan marks current todo BLOCKED", failures)
	var recent = event_log.recent_events(2)
	_assert_equal(recent.size(), 2, "Placement and blocked todo write events", failures)
	_assert_equal(recent[0].type, &"player_placed_building", "Placement records player_placed_building event", failures)
	_assert_equal(recent[1].type, &"npc_todo_blocked_by_building", "Failed replan records blocked todo event", failures)


func _test_daily_todo_planner_validation_and_fallback(failures: Array) -> void:
	var world := _make_npc_loop_world()
	var planner = DailyTodoPlannerScript.new()
	planner.configure(world["entity_registry"], world["place_registry"])
	var npc = world["npc"]
	var todos: Array = planner.validate_todos([
		{"intent": "visit_place", "target_place_id": "place_clinic", "priority": 90},
		{"intent": "teleport", "target_place_id": "place_clinic", "priority": 80},
		{"intent": "inspect_item", "target_item_id": "item_missing", "priority": 70},
		{"intent": "rest", "priority": 60},
	], npc, world["entity_registry"], world["place_registry"], 2)

	_assert_equal(todos.size(), 2, "DailyTodoPlanner caps valid todos", failures)
	_assert_equal(todos[0].intent, &"visit_place", "DailyTodoPlanner keeps valid target todo", failures)
	_assert_equal(todos[1].intent, &"rest", "DailyTodoPlanner keeps valid non-target todo", failures)

	var fallback: Array = planner.validate_todos([{"intent": "visit_place", "target_place_id": "missing"}], npc, world["entity_registry"], world["place_registry"], 4)
	_assert_equal(fallback.size(), 1, "DailyTodoPlanner creates fallback for empty valid output", failures)
	_assert_equal(fallback[0].intent, &"wander", "DailyTodoPlanner fallback is wander", failures)


func _test_llm_client_generation_guard_and_cancel(failures: Array) -> void:
	var client = LLMClientScript.new()
	var old_op: Dictionary = client.start_operation(&"npc_alpha", &"daily_todo")
	var current_op: Dictionary = client.start_operation(&"npc_alpha", &"daily_todo")
	client.append_stream_chunk(old_op["operation_id"], "[{\"intent\":\"rest\"}]")
	var late_result: Dictionary = client.complete_operation(old_op["operation_id"], "[{\"intent\":\"rest\"}]")
	client.append_stream_chunk(current_op["operation_id"], "[{\"intent\":\"wander\"}]")
	var current_result: Dictionary = client.complete_operation(current_op["operation_id"], "[{\"intent\":\"wander\"}]")

	_assert_equal(current_op["generation"] > old_op["generation"], true, "LLMClient increments generation per npc/kind", failures)
	_assert_equal(late_result["committed"], false, "LLMClient discards late generation", failures)
	_assert_equal(current_result["committed"], true, "LLMClient commits current generation", failures)

	var cancel_op: Dictionary = client.start_operation(&"npc_alpha", &"feedback")
	_assert_equal(client.cancel_operation(cancel_op["operation_id"]), true, "LLMClient cancels operation", failures)
	var cancelled_result: Dictionary = client.complete_operation(cancel_op["operation_id"], "hello")
	_assert_equal(cancelled_result["committed"], false, "LLMClient does not commit cancelled operation", failures)


func _test_action_scheduler_lane_locks(failures: Array) -> void:
	var scheduler = NPCActionSchedulerScript.new()
	var move_first: Dictionary = scheduler.start_action({"id": &"move_1", "npc_id": &"npc_alpha", "lane": &"movement"})
	var speech_first: Dictionary = scheduler.start_action({"id": &"speech_1", "npc_id": &"npc_alpha", "lane": &"speech"})
	var move_second: Dictionary = scheduler.start_action({"id": &"move_2", "npc_id": &"npc_alpha", "lane": &"movement"})

	_assert_equal(move_first["accepted"], true, "Scheduler accepts first movement action", failures)
	_assert_equal(speech_first["accepted"], true, "Scheduler accepts speech in parallel with movement", failures)
	_assert_equal(move_second["accepted"], false, "Scheduler rejects duplicate movement lane", failures)
	_assert_equal(scheduler.finish_action(&"npc_alpha", &"movement"), true, "Scheduler releases finished lane", failures)
	_assert_equal(scheduler.start_action({"id": &"move_3", "npc_id": &"npc_alpha", "lane": &"movement"})["accepted"], true, "Scheduler accepts movement after release", failures)


func _test_feedback_builder_binds_event_context(failures: Array) -> void:
	var world := _make_npc_loop_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var event = world["event_log"].record(&"player_forced_drop_item", &"item_cola", &"npc_alpha", &"npc", Vector2i(5, 5))
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)

	_assert_equal(feedback["ok"], true, "FeedbackBuilder returns ok feedback for event", failures)
	_assert_equal(feedback["event_id"], event.id, "FeedbackBuilder binds feedback to source event", failures)
	_assert_equal(feedback["npc_id"], &"npc_alpha", "FeedbackBuilder binds feedback to NPC", failures)
	_assert_equal(feedback["context"]["place_id"], &"place_clinic", "FeedbackBuilder includes local place context", failures)


func _test_todo_executor_blocks_and_adds_fallback(failures: Array) -> void:
	var world := _make_npc_loop_world()
	var npc = world["npc"]
	var todo = TodoItemScript.from_dict({"id": "todo_missing", "intent": "visit_place", "target_place_id": "missing", "status": "pending"})
	npc.todo_list = [todo]
	var executor = TodoExecutorScript.new()
	executor.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var result: Dictionary = executor.execute_todo(npc, todo, world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])

	_assert_equal(result["status"], &"BLOCKED", "TodoExecutor marks missing target todo blocked", failures)
	_assert_equal(todo.status, &"BLOCKED", "TodoExecutor mutates todo status to BLOCKED", failures)
	_assert_equal(npc.todo_list.size(), 2, "TodoExecutor appends fallback todo", failures)
	_assert_equal(npc.todo_list[1].intent, &"wander", "TodoExecutor fallback todo is wander", failures)


func _test_npc_mover_replans_when_path_is_invalidated(failures: Array) -> void:
	var world := _make_npc_loop_world()
	var mover = NPCMoverScript.new()
	mover.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var plan: Dictionary = mover.plan_path(world["npc"], Vector2i(3, 0))
	_assert_equal(plan["ok"], true, "NPCMover plans initial path", failures)
	world["pathfinder"].set_solid_cell(Vector2i(1, 0), true)
	world["pathfinder"].set_solid_cell(Vector2i(0, 1), true)
	_assert_equal(mover.request_replan(null, [Vector2i(1, 0)]), false, "NPCMover reports failed replan when path becomes invalid", failures)


func _test_position_is_source_of_truth(failures: Array) -> void:
	var npc = NPCStateScript.from_dict({"id": "npc_a", "name": "A", "position": {"x": 160.0, "y": 96.0}})
	_assert_equal(npc.position, Vector2(160, 96), "npc position from dict", failures)
	_assert_equal(npc.current_cell, Vector2i(2, 1), "npc current_cell derived from position", failures)
	var round = NPCStateScript.from_dict(npc.to_dict())
	_assert_equal(round.position, Vector2(160, 96), "npc position round-trips", failures)
	var legacy = NPCStateScript.from_dict({"id": "npc_b", "current_cell": {"x": 4, "y": 4}})
	_assert_equal(legacy.position, Vector2(288, 288), "legacy npc position from cell center", failures)
	var item = ItemStateScript.from_dict({"id": "it_a", "position": {"x": 32.0, "y": 32.0}})
	_assert_equal(item.position, Vector2(32, 32), "item position from dict", failures)
	_assert_equal(item.current_cell, Vector2i(0, 0), "item current_cell derived", failures)


func _test_interaction_delta_updates_object_and_relation_memory(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := {
		"diet_coke": {
			"name": "Diet Coke",
			"category": "drink",
			"defaultSocial": {"status": 80, "utility": 50, "debt": 60, "awkward": 90, "joke": 95, "danger": 5},
		}
	}
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict({"id": "trump"}))
	registry.add_npc(NPCStateScript.from_dict({"id": "jiu_tong"}))
	var item = ItemStateScript.from_dict({
		"id": "diet_coke",
		"typeId": "diet_coke",
		"ownerId": "trump",
		"accessRule": {"allowedNpcIds": ["trump"], "publicKnown": true, "exclusivity": 95},
		"currentAnchor": {"type": "npc", "npcId": "jiu_tong"},
	}, object_types)
	registry.add_item(item)

	var first_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, {}, 12)

	_assert_equal(first_result["objectStance"]["result"], "reject", "Forbidden coke creates reject stance", failures)
	_assert_equal(first_result["objectStance"]["want"], 50, "Forbidden coke want score is stable", failures)
	_assert_equal(first_result["objectStance"]["reject"], 78, "Forbidden coke reject score is stable", failures)
	_assert_equal(first_result["objectStance"]["dominantReason"], "forbidden", "Forbidden coke dominant reason is stable", failures)
	_assert_equal(first_result["heatDelta"], 57, "Forbidden coke heat delta is stable", failures)
	_assert_equal(first_result["interactionTrace"]["countInWindow"], 1, "First attach records short-lived interaction trace", failures)
	_assert_equal(first_result["interactionTrace"]["heat"], 57, "First attach trace heat is stable", failures)
	_assert_equal(item.memory["topLinks"].is_empty(), true, "First attach does not promote trace into formal object memory", failures)
	_assert_equal(registry.relation_memory(&"jiu_tong", &"trump").is_empty(), false, "Relation memory records transfer pressure", failures)
	_assert_equal(registry.npcs[&"jiu_tong"].stance_to_object["objectId"], "diet_coke", "NPC runtime records stance to object", failures)
	_assert_equal(item.owner_id, &"trump", "Attach does not rewrite ownerId", failures)
	_assert_equal(item.custody_state, "unclaimed", "Attach keeps custody as unclaimed instead of duplicating stance", failures)

	var second_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, {}, 13)
	_assert_equal(second_result["interactionTrace"]["countInWindow"], 2, "Second attach advances trace count", failures)
	_assert_equal(second_result["interactionTrace"]["heat"], 103, "Second attach trace heat decays then adds", failures)
	_assert_equal(second_result["performancePlan"]["pattern"], "leak_cover", "Repeated attach switches to leak_cover pattern", failures)
	_assert_equal(item.memory["topLinks"].is_empty(), false, "Repeated attach promotes trace into object memory", failures)
	_assert_equal(item.memory["topLinks"][0]["npcId"], "jiu_tong", "Object memory stores only the direct target NPC link", failures)
	_assert_equal(item.memory["topLinks"][0].has("stage"), true, "Object memory stores stage", failures)
	_assert_equal(item.memory["topLinks"][0]["heat"], 57, "Second attach starts formal object memory heat", failures)
	_assert_equal(item.memory["topLinks"][0]["stage"], "repeated", "Second attach promotes object memory to repeated", failures)
	var third_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, {}, 14)
	_assert_equal(third_result["interactionTrace"]["heat"], 139, "Third attach trace heat remains stable", failures)
	_assert_equal(third_result["interactionTrace"]["stage"], "noticed", "Third attach marks trace as noticed", failures)
	_assert_equal(third_result["performancePlan"]["pattern"], "preemptive_gag", "Third attach switches to preemptive_gag pattern", failures)
	_assert_equal(item.memory["topLinks"][0]["heat"], 102, "Third attach updates formal object memory heat", failures)
	_assert_equal(item.memory["topLinks"][0]["stage"], "noticed", "Third attach promotes object memory to noticed", failures)
	var relation_after_third: Dictionary = registry.relation_memory(&"jiu_tong", &"trump")
	_assert_equal(relation_after_third["attention"], 9, "Third attach relation attention accumulates", failures)
	_assert_equal(relation_after_third["awkward"], 15, "Third attach relation awkward accumulates", failures)
	_assert_equal(relation_after_third["suspicion"], 3, "Third attach relation suspicion accumulates", failures)
	_assert_equal(relation_after_third["debt"], 3, "Third attach relation debt accumulates", failures)
	_assert_equal(relation_after_third["fun"], 6, "Third attach relation fun accumulates", failures)
	var saved: Dictionary = registry.to_dict()
	_assert_equal(saved.has("interaction_traces"), true, "Registry serializes interaction traces separately from items", failures)
	var loaded = WorldEntityRegistryScript.new()
	loaded.load_from_dict(saved)
	_assert_equal(loaded.interaction_trace(&"diet_coke", &"jiu_tong")["countInWindow"], 3, "Registry restores interaction trace by canonical key", failures)


func _make_registry():
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 4, 4))
	return registry


func _make_placement_context() -> Dictionary:
	var WorldPlaceRegistryScript = load("res://scripts/world/WorldPlaceRegistry.gd")
	var GridPathfinderScript = load("res://scripts/world/GridPathfinder.gd")
	var BuildingPlacementServiceScript = load("res://scripts/world/BuildingPlacementService.gd")
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, -2, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(entity_registry.map_bounds)
	var event_log = InteractionEventLogScript.new()
	var service = BuildingPlacementServiceScript.new()
	service.configure(entity_registry, place_registry, pathfinder, event_log)
	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"service": service,
	}


func _make_npc_loop_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var WorldPlaceRegistryScript = load("res://scripts/world/WorldPlaceRegistry.gd")
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()
	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "current_cell": {"x": 0, "y": 0}})
	var target_npc = NPCStateScript.from_dict({"id": "npc_beta", "current_cell": {"x": 6, "y": 6}})
	var item = ItemStateScript.from_dict({"id": "item_cola", "current_cell": {"x": 1, "y": 0}})
	entity_registry.add_npc(npc)
	entity_registry.add_npc(target_npc)
	entity_registry.add_item(item)
	place_registry.create_place(&"place_clinic", "Clinic", "known valid target place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])
	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"npc": npc,
	}


func _make_main_game_drag_context() -> Dictionary:
	var game = MainGameScript.new()
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()
	var holder = NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha", "position": {"x": 160.0, "y": 160.0}})
	var target = NPCStateScript.from_dict({"id": "npc_beta", "name": "Beta", "position": {"x": 260.0, "y": 160.0}})
	var item = ItemStateScript.from_dict({
		"id": "item_cola",
		"name": "可乐",
		"currentAnchor": {"type": "npc", "npcId": "npc_alpha"},
	})
	registry.add_npc(holder)
	registry.add_npc(target)
	registry.add_item(item)
	game.entity_registry = registry
	game.event_log = event_log
	game.gameplay_config = {"free_roam": {"item_involvement_radius_meters": 2.0, "item_transfer_distance_meters": 1.5}}
	return {
		"game": game,
		"holder": holder,
		"target": target,
	}


func _assert_equal(actual: Variant, expected: Variant, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


class StubMover:
	extends RefCounted

	var npc_id: StringName = &""
	var current_path: Array = []
	var replan_result: bool = true
	var current_todo = null
	var replan_requests: int = 0

	func _init(p_npc_id: StringName, p_current_path: Array, p_replan_result: bool, p_current_todo = null) -> void:
		npc_id = p_npc_id
		current_path = p_current_path.duplicate()
		replan_result = p_replan_result
		current_todo = p_current_todo

	func get_path_cells() -> Array:
		return current_path.duplicate()

	func request_replan(_place, _blocked_cells: Array) -> bool:
		replan_requests += 1
		return replan_result


class SpeechPauseMover:
	extends RefCounted

	var advance_calls: int = 0

	func is_idle() -> bool:
		return false

	func advance(_npc, _delta: float) -> Dictionary:
		advance_calls += 1
		return {"done": false}
