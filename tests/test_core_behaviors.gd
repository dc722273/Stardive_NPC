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
const NPCPerformanceDirectorScript := preload("res://scripts/npc/NPCPerformanceDirector.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const InteractionDeltaRulesScript := preload("res://scripts/world/InteractionDeltaRules.gd")
const WellbeingRulesScript := preload("res://scripts/world/WellbeingRules.gd")
const MainGameScript := preload("res://scripts/MainGame.gd")
const EntityVisualLayerScript := preload("res://scripts/ui/EntityVisualLayer.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")
const NPCChatPanelScript := preload("res://scripts/ui/NPCChatPanel.gd")
const NPCVisualScript := preload("res://scripts/ui/NPCVisual.gd")
const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")


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
	_test_chat_reported_item_transfer_updates_world_and_memory(failures)
	_test_repeated_rejected_item_is_auto_dropped_by_npc(failures)
	_test_feedback_pause_blocks_npc_movement_and_new_decisions(failures)
	_test_speech_bubble_duration_and_font_size(failures)
	_test_art_assets_load_from_config_paths(failures)
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
	_test_feedback_builder_chat_events_have_fallbacks(failures)
	_test_todo_executor_blocks_and_adds_fallback(failures)
	_test_npc_chat_panel_preloads(failures)
	_test_main_game_feedback_adds_final_lines_to_chat_history(failures)
	_test_main_game_records_npc_visible_memory(failures)
	_test_npc_mover_replans_when_path_is_invalidated(failures)
	_test_position_is_source_of_truth(failures)
	_test_mvp_object_pool_has_six_social_pressure_items(failures)
	_test_wellbeing_rules_use_existing_events_and_item_social(failures)
	_test_wellbeing_rules_cover_mvp_object_pool_interventions(failures)
	_test_performance_director_sanitizes_to_catalog_ids(failures)
	_test_training_gun_to_shiye_creates_preemptive_body_gag(failures)
	_test_gold_cup_to_shiye_turns_liking_into_relation_debt(failures)
	_test_coke_ping_pong_between_trump_and_jiu_tong_creates_relation_gag(failures)
	_test_gift_stance_handles_player_ground_gift_without_npc_relation(failures)
	_test_gift_relation_requires_npc_attribution(failures)
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
			"classification": {"category": "drink", "subtype": "soda", "material": "aluminum"},
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
	_assert_equal(item.classification["subtype"], "soda", "ItemState resolves type classification subtype", failures)
	_assert_equal(item.social["status"], 80, "ItemState applies default social", failures)
	_assert_equal(item.social.has("power"), true, "ItemState includes power social axis", failures)
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
	_assert_equal(str(recent[0].payload.get("source", "")), "player_remove_object_from_npc", "Discard payload exposes player removal source", failures)
	_assert_equal(recent[0].payload.has("object_social"), true, "Discard payload carries object social data for wellbeing rules", failures)


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


func _test_chat_reported_item_transfer_updates_world_and_memory(failures: Array) -> void:
	var context := _make_main_game_drag_context()
	var game = context["game"]
	var registry = game.entity_registry
	registry.npcs[&"npc_alpha"].name = "九筒"
	registry.npcs[&"npc_alpha"].aliases = ["九筒"]
	registry.npcs[&"npc_beta"].name = "川普"
	registry.npcs[&"npc_beta"].aliases = ["川普"]
	registry.items[&"item_cola"].name = "一瓶可乐"
	registry.items[&"item_cola"].type_id = &"cola"
	registry.items[&"item_cola"].owner_id = &"npc_alpha"
	registry.object_types[&"cola"] = {"name": "可乐", "aliases": ["一瓶可乐", "可乐"]}

	var transfer: Dictionary = game._parse_chat_transfer(&"npc_beta", "九筒送给他一瓶可乐")
	_assert_equal(transfer.get("ok", false), true, "Chat transfer parser accepts pronoun recipient", failures)
	var event = game._apply_chat_transfer_event(&"npc_beta", "九筒送给他一瓶可乐", transfer)

	_assert_equal(registry.items[&"item_cola"].anchor_npc_id(), &"npc_beta", "Chat reported transfer moves item to target NPC", failures)
	_assert_equal(event.type, &"player_chat_reported_item_transfer", "Chat reported transfer records a world event", failures)
	_assert_equal(event.payload.get("source", ""), "player_chat_reported_transfer", "Chat transfer payload keeps source", failures)
	_assert_equal(event.payload.get("interaction_trace", {}).get("countInWindow", 0), 1, "Chat transfer advances item interaction trace", failures)
	_assert_equal(event.payload.get("performance_plan", {}).has("pattern"), true, "Chat transfer includes performance plan for NPC reaction", failures)
	_assert_equal(str(event.payload.get("scene_seed", {}).get("visible_topic", "")).find("已按这句话") >= 0, true, "Chat transfer tells feedback builder the world state changed", failures)
	game.free()


func _test_repeated_rejected_item_is_auto_dropped_by_npc(failures: Array) -> void:
	var game = MainGameScript.new()
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var object_types := {
		"sealed_brief": {
			"name": "Sealed Brief",
			"category": "document",
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
	var sealed_brief = ItemStateScript.from_dict({
		"id": "sealed_brief",
		"typeId": "sealed_brief",
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
	registry.add_item(sealed_brief)
	registry.add_item(briefcase)
	game.entity_registry = registry
	game.gameplay_config = _gameplay_config()

	var cautious_auto_drop := {}
	for i in range(2):
		_assert_equal(registry.give_item_to_npc(&"sealed_brief", &"jiu_tong"), true, "Repeated rejected item can be attached before auto rule", failures)
		var payload: Dictionary = game._item_event_payload(&"sealed_brief", &"jiu_tong", &"trump")
		var auto_drop: Dictionary = game._maybe_auto_drop_rejected_item(&"sealed_brief", &"jiu_tong", payload)
		if i == 0:
			_assert_equal(auto_drop.is_empty(), true, "First rejected attach is not auto-dropped for cautious NPC", failures)
		if i == 1:
			cautious_auto_drop = auto_drop
	_assert_equal(cautious_auto_drop.is_empty(), false, "Cautious responsibility-avoidant NPC auto-drops on second rejected attach", failures)
	_assert_equal(cautious_auto_drop.get("threshold", 0), 2, "Cautious NPC/object threshold is computed as 2", failures)
	_assert_equal(cautious_auto_drop.get("thresholdFactors", []).has("high_caution"), true, "Auto-drop threshold records high_caution factor", failures)
	_assert_equal(cautious_auto_drop.get("thresholdFactors", []).has("avoid_responsibility"), true, "Auto-drop threshold records avoid_responsibility factor", failures)
	_assert_equal(sealed_brief.anchor_type(), "ground", "Auto-dropped rejected item ends on ground", failures)
	_assert_equal(sealed_brief.custody_state, "rejected", "Auto-dropped rejected item records rejected custody", failures)
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


func _test_art_assets_load_from_config_paths(failures: Array) -> void:
	var game = MainGameScript.new()
	var gameplay_config := ConfigLoaderScript.load_gameplay_config()
	var bg_texture = game._load_png_texture(str(gameplay_config.get("world", {}).get("backgroundPath", "")))
	_assert_equal(bg_texture != null, true, "World background loads from gameplay config path", failures)
	if bg_texture != null:
		_assert_equal(bg_texture.get_width() > 0, true, "World background has width", failures)
		_assert_equal(bg_texture.get_height() > 0, true, "World background has height", failures)

	var layer = EntityVisualLayerScript.new()
	var npc_bundle := ConfigLoaderScript.load_npc_configs()
	for npc_cfg in npc_bundle.get("configs", []):
		if not (npc_cfg is Dictionary):
			continue
		var npc = NPCStateScript.from_dict(npc_cfg)
		var marker_texture = layer._marker_texture_for_npc(npc)
		_assert_equal(marker_texture != null, true, "%s marker loads from config path" % npc.name, failures)
		if marker_texture != null:
			_assert_equal(marker_texture.get_width() > 0, true, "%s marker has width" % npc.name, failures)
			_assert_equal(marker_texture.get_height() > 0, true, "%s marker has height" % npc.name, failures)
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


func _test_feedback_builder_chat_events_have_fallbacks(failures: Array) -> void:
	var builder = NPCFeedbackBuilderScript.new()
	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha"})
	var chat_event = InteractionEventScript.from_dict({
		"type": "player_chat_to_npc",
		"actor_id": "player",
		"primary_entity_id": "npc_alpha",
		"target_entity_id": "npc_alpha",
		"target_type": "npc",
		"payload": {"player_message": "九筒送给你一瓶可乐"},
	})
	var chat_feedback: Dictionary = builder.build_feedback(chat_event, npc, {})
	_assert_equal(str(chat_feedback.get("text", "")).find("九筒送给你一瓶可乐") >= 0, true, "Chat fallback includes player message", failures)

	var transfer_event = InteractionEventScript.from_dict({
		"type": "player_chat_reported_item_transfer",
		"actor_id": "player",
		"primary_entity_id": "diet_coke",
		"target_entity_id": "npc_alpha",
		"target_type": "npc",
		"payload": {"item_name": "健怡可乐", "previousAnchorNpcName": "九筒"},
	})
	var transfer_feedback: Dictionary = builder.build_feedback(transfer_event, npc, {})
	_assert_equal(str(transfer_feedback.get("text", "")).find("健怡可乐") >= 0, true, "Reported transfer fallback includes item", failures)


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


func _test_npc_chat_panel_preloads(failures: Array) -> void:
	var panel = NPCChatPanelScript.new()
	_assert_equal(panel != null, true, "NPCChatPanel preloads", failures)
	_assert_equal(panel.has_signal("message_submitted"), true, "NPCChatPanel exposes submit signal", failures)
	panel._build_controls_if_needed()
	for index in range(12):
		panel.add_line("NPC", "line %d" % index)
	_assert_equal(panel._history.size(), 10, "NPCChatPanel keeps latest ten lines", failures)
	_assert_equal(panel._history[0].contains("line 2"), true, "NPCChatPanel drops oldest lines first", failures)
	_assert_equal(panel._history[9].contains("line 11"), true, "NPCChatPanel keeps newest line visible in history", failures)
	var controls_margin := panel.history_label.get_parent().get_child(1) as MarginContainer
	_assert_equal(controls_margin.get_theme_constant("margin_top"), 10, "NPCChatPanel input row is lowered by configured offset", failures)
	panel.free()


func _test_main_game_feedback_adds_final_lines_to_chat_history(failures: Array) -> void:
	var registry = _make_registry()
	registry.add_npc(NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha", "current_cell": {"x": 1, "y": 1}}))
	var WorldPlaceRegistryScript = load("res://scripts/world/WorldPlaceRegistry.gd")
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	var event_log = InteractionEventLogScript.new()
	var game = MainGameScript.new()
	var panel = NPCChatPanelScript.new()
	panel._build_controls_if_needed()
	game.entity_registry = registry
	game.place_registry = place_registry
	game.event_log = event_log
	game.npc_feedback_builder = NPCFeedbackBuilderScript.new()
	game.npc_feedback_builder.configure(registry, place_registry, pathfinder, event_log)
	game.npc_chat_panel = panel
	var event = event_log.record(&"player_drop_item_on_npc", &"diet_coke", &"npc_alpha", &"npc", Vector2i(1, 1), {"item_name": "健怡可乐"})
	game._emit_npc_feedback(event, &"npc_alpha")
	_assert_equal(panel._history.size(), 1, "NPC feedback writes final text into chat history", failures)
	_assert_equal(panel._history[0].contains("npc_alpha"), true, "NPC feedback chat line includes speaker", failures)
	for index in range(12):
		game._add_npc_chat_line(&"npc_alpha", "extra %d" % index)
	_assert_equal(panel._history.size(), 10, "Main game chat history still keeps latest ten lines", failures)
	_assert_equal(panel._history[9].contains("extra 11"), true, "Main game chat history follows newest line", failures)
	panel.free()
	game.free()


func _test_main_game_records_npc_visible_memory(failures: Array) -> void:
	var game = MainGameScript.new()
	var registry = _make_registry()
	registry.add_npc(NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha", "current_cell": {"x": 1, "y": 1}}))
	var event_log = InteractionEventLogScript.new()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(registry, null, null, event_log)
	game.entity_registry = registry
	game.event_log = event_log
	game.npc_feedback_builder = builder
	game.tick = 42
	var event = game._record_direct_chat_event(&"npc_alpha", "你还记得刚才吗？")
	game._emit_npc_chat_feedback(event, &"npc_alpha")
	var memories: Array = registry.npcs[&"npc_alpha"].recent_events
	_assert_equal(memories.size() >= 2, true, "Chat target remembers player message and NPC reply", failures)
	_assert_equal(StringName(memories[0].type), &"player_chat_to_npc", "NPC memory stores the player chat event", failures)
	_assert_equal(StringName(memories[memories.size() - 1].type), &"npc_feedback_line", "NPC memory stores its own latest reply", failures)
	game.free()


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


func _test_mvp_object_pool_has_six_social_pressure_items(failures: Array) -> void:
	var bundle: Dictionary = ConfigLoaderScript.load_item_bundle()
	var types: Dictionary = bundle.get("objectTypes", {})
	var expected_ids := [&"diet_coke", &"jiu_tong_gun", &"gold_cup", &"shiye_ledger", &"dollars_stack", &"seal_strip"]
	_assert_equal(types.size(), expected_ids.size(), "MVP object pool contains exactly six configured object types", failures)
	for object_id in expected_ids:
		_assert_equal(types.has(str(object_id)), true, "MVP object type exists: %s" % str(object_id), failures)
	var ledger: Dictionary = types.get("shiye_ledger", {})
	_assert_equal(ledger.get("classification", {}).get("subtype", ""), "ledger", "Ledger subtype is stored without category prefix", failures)
	_assert_equal(ledger.get("defaultAffordance", {}).get("discardable", true), false, "Shiye ledger is not casually discardable", failures)
	var gun: Dictionary = types.get("jiu_tong_gun", {})
	_assert_equal(int(gun.get("defaultSocial", {}).get("danger", 0)) >= 90, true, "Jiu Tong gun carries high danger pressure", failures)
	var objects: Array = bundle.get("objects", [])
	var object_by_id := {}
	for raw_object in objects:
		if raw_object is Dictionary:
			object_by_id[StringName(raw_object.get("id", ""))] = raw_object
	_assert_equal(object_by_id.get(&"diet_coke", {}).get("ownerId", ""), "trump", "Diet coke has social owner instead of hardcoded reaction owner", failures)
	_assert_equal(object_by_id.get(&"jiu_tong_gun", {}).get("ownerId", ""), "jiu_tong", "Gun owner remains Jiu Tong", failures)
	_assert_equal(object_by_id.get(&"shiye_ledger", {}).get("ownerId", ""), "shi_ye", "Ledger owner is Shiye", failures)
	var ground_cells := {}
	for object_id in expected_ids:
		var raw_object: Dictionary = object_by_id.get(object_id, {})
		var anchor: Dictionary = raw_object.get("currentAnchor", {})
		if str(anchor.get("type", "ground")) == "npc":
			_assert_equal(str(anchor.get("npcId", "")) != "", true, "Held MVP object has NPC anchor: %s" % str(object_id), failures)
			continue
		_assert_equal(raw_object.has("current_cell") or raw_object.has("position"), true, "Ground MVP object has visible initial placement: %s" % str(object_id), failures)
		var item = ItemStateScript.from_dict(raw_object, types)
		_assert_equal(item.current_cell != Vector2i.ZERO, true, "Ground MVP object is not hidden at default origin: %s" % str(object_id), failures)
		_assert_equal(ground_cells.has(item.current_cell), false, "Ground MVP object does not overlap another MVP object: %s" % str(object_id), failures)
		ground_cells[item.current_cell] = object_id


func _test_wellbeing_rules_use_existing_events_and_item_social(failures: Array) -> void:
	var config: Dictionary = ConfigLoaderScript.load_wellbeing_config()
	var registry = _make_registry()
	var npc = NPCStateScript.from_dict({"id": "shi_ye", "name": "师爷", "current_cell": {"x": 2, "y": 2}, "runtime": {"wellbeing": {"state": "down", "problem": "stressed"}}})
	var item = ItemStateScript.from_dict({"id": "jiu_tong_gun", "name": "九筒的枪", "social": {"danger": 95, "status": 70, "utility": 10, "debt": 20, "awkward": 85, "joke": 70}, "currentAnchor": {"type": "npc", "npcId": "shi_ye"}})
	registry.add_npc(npc)
	registry.add_item(item)
	var event_log = InteractionEventLogScript.new()
	var event = event_log.record(&"player_drop_item_on_npc", &"jiu_tong_gun", &"shi_ye", &"npc", Vector2i(2, 2), {"object_social": item.social.duplicate(true)})
	var judgement: Dictionary = WellbeingRulesScript.evaluate_event(event, npc, item, config)
	_assert_equal(judgement.get("result", ""), "harm", "Stressed NPC receiving danger object is judged as harm", failures)
	_assert_equal(judgement.get("reason", ""), "danger_added", "Wellbeing judgement records configured harm reason", failures)
	_assert_equal(npc.wellbeing.get("state", ""), "worse", "Wellbeing updates NPC runtime state", failures)
	var round = NPCStateScript.from_dict(npc.to_dict())
	_assert_equal(round.wellbeing.get("problem", ""), "stressed", "NPC wellbeing round-trips through runtime serialization", failures)


func _test_wellbeing_rules_cover_mvp_object_pool_interventions(failures: Array) -> void:
	var config: Dictionary = ConfigLoaderScript.load_wellbeing_config()
	var object_types := _core_validation_object_types()
	var registry = _make_registry()
	var event_log = InteractionEventLogScript.new()

	var stressed = NPCStateScript.from_dict({"id": "shi_ye", "runtime": {"wellbeing": {"state": "down", "problem": "stressed"}}})
	var ledger = ItemStateScript.from_dict({"id": "shiye_ledger", "typeId": "shiye_ledger", "ownerId": "shi_ye", "currentAnchor": {"type": "npc", "npcId": "shi_ye"}}, object_types)
	var ledger_event = event_log.record(&"player_drop_item_on_npc", &"shiye_ledger", &"shi_ye", &"npc", Vector2i(2, 2), {"object_social": ledger.social.duplicate(true), "object_classification": ledger.classification.duplicate(true)})
	var ledger_judgement: Dictionary = WellbeingRulesScript.evaluate_event(ledger_event, stressed, ledger, config)
	_assert_equal(ledger_judgement.get("result", ""), "help", "Ledger-like order object helps stressed NPC", failures)

	var afraid_owner = NPCStateScript.from_dict({"id": "jiu_tong", "runtime": {"wellbeing": {"state": "down", "problem": "afraid"}}})
	var gun = ItemStateScript.from_dict({"id": "jiu_tong_gun", "typeId": "jiu_tong_gun", "ownerId": "jiu_tong", "currentAnchor": {"type": "npc", "npcId": "jiu_tong"}}, object_types)
	var gun_home_event = event_log.record(&"player_drop_item_on_npc", &"jiu_tong_gun", &"jiu_tong", &"npc", Vector2i(2, 2), {"object_social": gun.social.duplicate(true), "object_classification": gun.classification.duplicate(true)})
	var gun_home_judgement: Dictionary = WellbeingRulesScript.evaluate_event(gun_home_event, afraid_owner, gun, config)
	_assert_equal(gun_home_judgement.get("result", ""), "help", "Danger item returning to owner can reduce fear", failures)
	_assert_equal(gun_home_judgement.get("reason", ""), "danger_removed", "Owner-safe danger item uses danger_removed reason", failures)

	var lost_face = NPCStateScript.from_dict({"id": "trump", "runtime": {"wellbeing": {"state": "down", "problem": "lost_face"}}})
	var dangerous_status_event = event_log.record(&"player_drop_item_on_npc", &"jiu_tong_gun", &"trump", &"npc", Vector2i(2, 2), {"object_social": gun.social.duplicate(true), "object_classification": gun.classification.duplicate(true)})
	var dangerous_status_judgement: Dictionary = WellbeingRulesScript.evaluate_event(dangerous_status_event, lost_face, gun, config)
	_assert_equal(dangerous_status_judgement.get("result", ""), "harm", "High-status danger object does not restore lost face", failures)

	var bored = NPCStateScript.from_dict({"id": "jiu_tong", "runtime": {"wellbeing": {"state": "down", "problem": "bored"}}})
	var seal = ItemStateScript.from_dict({"id": "seal_strip", "typeId": "seal_strip", "currentAnchor": {"type": "ground"}}, object_types)
	var seal_event = event_log.record(&"player_drop_item_on_npc", &"seal_strip", &"jiu_tong", &"npc", Vector2i(2, 2), {"object_social": seal.social.duplicate(true), "object_classification": seal.classification.duplicate(true)})
	var seal_judgement: Dictionary = WellbeingRulesScript.evaluate_event(seal_event, bored, seal, config)
	_assert_equal(seal_judgement.get("result", ""), "help", "High joke seal can relieve boredom through gag potential", failures)


func _test_performance_director_sanitizes_to_catalog_ids(failures: Array) -> void:
	var config: Dictionary = ConfigLoaderScript.load_wellbeing_config()
	var director = NPCPerformanceDirectorScript.new()
	director.configure(config)
	var judgement := {"result": "harm", "reason": "danger_added", "resultLabel": "添乱"}
	var plan := {
		"pattern": "negative_reaction",
		"steps": [
			{"channel": "body", "actionId": "hold_up_hands", "delayMs": 0},
			{"channel": "face", "expressionId": "defensive", "delayMs": 10},
			{"channel": "face", "expressionId": "not_in_catalog", "delayMs": 20},
			{"channel": "speech", "line": "小人没碰。", "delayMs": 20},
		],
	}
	var sanitized: Dictionary = director.sanitize_plan(plan, judgement)
	_assert_equal(sanitized.get("steps", []).size(), 3, "Performance director drops ids outside catalog", failures)
	_assert_equal(sanitized["steps"][0].get("actionId", ""), "hold_up_hands", "Performance director keeps valid action id", failures)
	var rendered := director.render_plan(sanitized, judgement)
	_assert_equal(rendered.contains("[添乱]"), true, "Rendered performance includes rule-owned result tag", failures)
	_assert_equal(rendered.contains("[举手撇清]"), true, "Rendered performance uses catalog label for valid action", failures)
	_assert_equal(rendered.contains("[防御]"), true, "Rendered performance uses catalog label for valid expression", failures)


func _test_training_gun_to_shiye_creates_preemptive_body_gag(failures: Array) -> void:
	var game = MainGameScript.new()
	var registry = _make_registry()
	registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()
	var object_types := _core_validation_object_types()
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("jiu_tong")))
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("shi_ye")))
	var gun = ItemStateScript.from_dict({"id": "jiu_tong_gun", "typeId": "jiu_tong_gun", "ownerId": "jiu_tong", "currentAnchor": {"type": "npc", "npcId": "jiu_tong"}}, object_types)
	registry.add_item(gun)
	game.entity_registry = registry
	game.event_log = event_log
	game.gameplay_config = _gameplay_config()

	var first: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(gun, &"shi_ye", &"jiu_tong", [&"jiu_tong", &"shi_ye"], registry, _gameplay_config(), 1)
	_assert_equal(first["giftStance"].get("gagTag", ""), "小人没碰", "First gun attach chooses Shiye's readable body gag", failures)
	_assert_equal(_plan_has_expression(first.get("performancePlan", {}), "nervous"), true, "Gift performance plan includes catalog expression from stance reason", failures)
	_assert_equal(first["objectMemoryUpdates"].is_empty(), true, "First gun attach is only reaction, not learned gag yet", failures)
	var second: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(gun, &"shi_ye", &"jiu_tong", [&"jiu_tong", &"shi_ye"], registry, _gameplay_config(), 2)
	_assert_equal(second["objectMemoryUpdates"].is_empty(), false, "Second gun attach promotes recognition memory", failures)
	_assert_equal(gun.memory["topLinks"][0]["stage"], "repeated", "Second gun attach reaches recognition stage", failures)
	_assert_equal(gun.memory["topLinks"][0]["gagTag"], "小人没碰", "Gun memory stores task-readable gag tag", failures)
	var distance_before_preemptive: float = registry.npcs[&"shi_ye"].position.distance_to(game._item_world_position(&"jiu_tong_gun"))
	var preemptive := game._emit_preemptive_item_gag(&"jiu_tong_gun")
	_assert_equal(preemptive.is_empty(), false, "Third interaction can fire when player merely drags the trained gun", failures)
	_assert_equal(preemptive.get("gagTag", ""), "小人没碰", "Preemptive gun gag uses trained body tag", failures)
	_assert_equal(str(preemptive.get("event_text", "")).find("预判") >= 0, true, "Preemptive gun gag is visibly predictive", failures)
	_assert_equal(preemptive.get("body_reaction", {}).get("type", ""), "retreat", "Preemptive avoidant body gag moves NPC away", failures)
	_assert_equal(registry.npcs[&"shi_ye"].position.distance_to(game._item_world_position(&"jiu_tong_gun")) > distance_before_preemptive, true, "Shiye physically retreats from trained gun gag", failures)
	_assert_equal(gun.memory["topLinks"][0]["stage"], "noticed", "Preemptive drag upgrades body gag to task-ready noticed stage", failures)
	_assert_equal(event_log.recent_events(1)[0].type, &"player_drag_started_trained_item", "Dragging trained item records preemptive gag event", failures)
	game.free()


func _test_gold_cup_to_shiye_turns_liking_into_relation_debt(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := _core_validation_object_types()
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("trump")))
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("shi_ye")))
	var cup = ItemStateScript.from_dict({"id": "gold_cup", "typeId": "gold_cup", "currentAnchor": {"type": "npc", "npcId": "trump"}}, object_types)
	registry.add_item(cup)

	var result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(cup, &"shi_ye", &"trump", [&"trump", &"shi_ye"], registry, _gameplay_config(), 10, {
		"operator": "player_drag",
		"giverNpcId": &"trump",
		"receiverNpcId": &"shi_ye",
		"fromAnchor": {"type": "npc", "npcId": "trump"},
		"toAnchor": {"type": "npc", "npcId": "shi_ye"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})
	var stance: Dictionary = result["giftStance"]
	var relation: Dictionary = registry.relation_memory(&"shi_ye", &"trump")
	_assert_equal(["ambivalent", "like"].has(str(stance.get("result", ""))), true, "Gold cup creates want/cover tension instead of simple rejection", failures)
	_assert_equal(int(stance.get("like", 0)) > int(stance.get("reject", 0)) - 12, true, "Gold cup remains attractive enough for Shiye to hesitate", failures)
	_assert_equal(int(relation.get("attention", 0)) > 0, true, "Gold cup makes Shiye pay attention to giver", failures)
	_assert_equal(int(relation.get("warmth", 0)) > 0, true, "Gold cup liking converts into warmth toward giver", failures)
	_assert_equal(int(relation.get("debt", 0)) > 0, true, "Gold cup pressure converts into relationship debt", failures)
	_assert_equal(int(relation.get("awkward", 0)) > 0, true, "Gold cup debt also leaves awkwardness", failures)


func _test_coke_ping_pong_between_trump_and_jiu_tong_creates_relation_gag(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := _core_validation_object_types()
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("trump")))
	registry.add_npc(NPCStateScript.from_dict(_core_validation_npc("jiu_tong")))
	var coke = ItemStateScript.from_dict({"id": "diet_coke", "typeId": "diet_coke", "currentAnchor": {"type": "ground"}}, object_types)
	registry.add_item(coke)

	var to_trump: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(coke, &"trump", &"jiu_tong", [&"jiu_tong", &"trump"], registry, _gameplay_config(), 20, {
		"operator": "player_drag",
		"giverNpcId": &"jiu_tong",
		"receiverNpcId": &"trump",
		"fromAnchor": {"type": "npc", "npcId": "jiu_tong"},
		"toAnchor": {"type": "npc", "npcId": "trump"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})
	var to_jiu_tong: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(coke, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, _gameplay_config(), 21, {
		"operator": "player_drag",
		"giverNpcId": &"trump",
		"receiverNpcId": &"jiu_tong",
		"fromAnchor": {"type": "npc", "npcId": "trump"},
		"toAnchor": {"type": "npc", "npcId": "jiu_tong"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})
	var to_trump_again: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(coke, &"trump", &"jiu_tong", [&"jiu_tong", &"trump"], registry, _gameplay_config(), 22, {
		"operator": "player_drag",
		"giverNpcId": &"jiu_tong",
		"receiverNpcId": &"trump",
		"fromAnchor": {"type": "npc", "npcId": "jiu_tong"},
		"toAnchor": {"type": "npc", "npcId": "trump"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})
	var to_jiu_tong_again: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(coke, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, _gameplay_config(), 23, {
		"operator": "player_drag",
		"giverNpcId": &"trump",
		"receiverNpcId": &"jiu_tong",
		"fromAnchor": {"type": "npc", "npcId": "trump"},
		"toAnchor": {"type": "npc", "npcId": "jiu_tong"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})

	_assert_equal(to_trump["giftTrace"].get("eventType", ""), "gift:npc:jiu_tong", "Coke to Trump is attributed to Jiu Tong", failures)
	_assert_equal(to_jiu_tong["giftTrace"].get("eventType", ""), "gift:npc:trump", "Coke back to Jiu Tong is attributed to Trump", failures)
	_assert_equal(to_trump_again["interactionTrace"].get("stage", ""), "repeated", "Coke returning to Trump becomes recognizable", failures)
	_assert_equal(to_jiu_tong_again["interactionTrace"].get("stage", ""), "repeated", "Coke returning to Jiu Tong becomes recognizable", failures)
	_assert_equal(coke.memory["topLinks"].size() >= 2, true, "Coke memory keeps both sides of the ping-pong", failures)
	_assert_equal(registry.relation_memory(&"trump", &"jiu_tong").is_empty(), false, "Trump relation to Jiu Tong changes through coke", failures)
	_assert_equal(registry.relation_memory(&"jiu_tong", &"trump").is_empty(), false, "Jiu Tong relation to Trump changes through coke", failures)


func _test_interaction_delta_updates_object_and_relation_memory(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := {
		"sealed_brief": {
			"name": "Sealed Brief",
			"category": "document",
			"defaultSocial": {"status": 80, "utility": 50, "debt": 60, "awkward": 90, "joke": 95, "danger": 5},
		}
	}
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict({"id": "trump"}))
	registry.add_npc(NPCStateScript.from_dict({"id": "jiu_tong"}))
	var item = ItemStateScript.from_dict({
		"id": "sealed_brief",
		"typeId": "sealed_brief",
		"ownerId": "trump",
		"accessRule": {"allowedNpcIds": ["trump"], "publicKnown": true, "exclusivity": 95},
		"currentAnchor": {"type": "npc", "npcId": "jiu_tong"},
	}, object_types)
	registry.add_item(item)

	var first_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, _gameplay_config(), 12)

	_assert_equal(first_result["giftStance"].has("pressure"), true, "Gift stance exposes pressure", failures)
	_assert_equal(first_result["giftStance"].has("fatigue"), true, "Gift stance exposes fatigue", failures)
	_assert_equal(first_result["giftStance"]["legacyResult"], "reject", "Forbidden private item maps to legacy reject stance", failures)
	_assert_equal(int(first_result["giftStance"]["reject"]) > int(first_result["giftStance"]["want"]), true, "Forbidden private item reject score exceeds like score", failures)
	_assert_equal(first_result["giftStance"]["dominantReason"], "forbidden", "Forbidden private item dominant reason is stable", failures)
	_assert_equal(int(first_result["heatDelta"]) > 0, true, "Forbidden private item produces positive heat delta", failures)
	_assert_equal(first_result["interactionTrace"]["countInWindow"], 1, "First attach records short-lived interaction trace", failures)
	_assert_equal(int(first_result["interactionTrace"]["heat"]) > 0, true, "First attach trace heat is positive", failures)
	_assert_equal(first_result["giftTrace"]["eventType"], "gift:npc:trump", "NPC-attributed gift records giver-scoped fatigue trace", failures)
	_assert_equal(item.memory["topLinks"].is_empty(), true, "First attach does not promote trace into formal object memory", failures)
	_assert_equal(registry.relation_memory(&"jiu_tong", &"trump").is_empty(), false, "Relation memory records transfer pressure", failures)
	_assert_equal(registry.relation_memory(&"trump", &"jiu_tong").is_empty(), true, "Gift relation does not update giver back to receiver automatically", failures)
	_assert_equal(registry.npcs[&"jiu_tong"].stance_to_object["objectId"], "sealed_brief", "NPC runtime records stance to object", failures)
	_assert_equal(item.owner_id, &"trump", "Attach does not rewrite ownerId", failures)
	_assert_equal(item.custody_state, "unclaimed", "Attach keeps custody as unclaimed instead of duplicating stance", failures)

	var second_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, _gameplay_config(), 13)
	_assert_equal(second_result["interactionTrace"]["countInWindow"], 2, "Second attach advances trace count", failures)
	_assert_equal(int(second_result["giftStance"]["fatigue"]) > int(first_result["giftStance"]["fatigue"]), true, "Repeated gift raises fatigue", failures)
	_assert_equal(second_result["performancePlan"]["pattern"], "leak_cover", "Repeated attach switches to leak_cover pattern", failures)
	_assert_equal(item.memory["topLinks"].is_empty(), false, "Repeated attach promotes trace into object memory", failures)
	_assert_equal(item.memory["topLinks"][0]["npcId"], "jiu_tong", "Object memory stores only the direct target NPC link", failures)
	_assert_equal(item.memory["topLinks"][0].has("stage"), true, "Object memory stores stage", failures)
	_assert_equal(int(item.memory["topLinks"][0]["heat"]) > 0, true, "Second attach starts formal object memory heat", failures)
	_assert_equal(item.memory["topLinks"][0]["stage"], "repeated", "Second attach promotes object memory to repeated", failures)
	var third_result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"jiu_tong", &"trump", [&"trump", &"jiu_tong"], registry, _gameplay_config(), 14)
	_assert_equal(int(third_result["interactionTrace"]["heat"]) > int(second_result["interactionTrace"]["heat"]), true, "Third attach increases trace heat", failures)
	_assert_equal(third_result["interactionTrace"]["stage"], "noticed", "Third attach marks trace as noticed", failures)
	_assert_equal(third_result["performancePlan"]["pattern"], "preemptive_gag", "Third attach switches to preemptive_gag pattern", failures)
	_assert_equal(int(item.memory["topLinks"][0]["heat"]) > 0, true, "Third attach updates formal object memory heat", failures)
	_assert_equal(item.memory["topLinks"][0]["stage"], "noticed", "Third attach promotes object memory to noticed", failures)
	var relation_after_third: Dictionary = registry.relation_memory(&"jiu_tong", &"trump")
	_assert_equal(int(relation_after_third["attention"]) > 0, true, "Third attach relation attention accumulates", failures)
	_assert_equal(int(relation_after_third["awkward"]) > 0 or int(relation_after_third["suspicion"]) > 0, true, "Third attach relation records social pressure", failures)
	var saved: Dictionary = registry.to_dict()
	_assert_equal(saved.has("interaction_traces"), true, "Registry serializes interaction traces separately from items", failures)
	var loaded = WorldEntityRegistryScript.new()
	loaded.load_from_dict(saved)
	_assert_equal(loaded.interaction_trace(&"sealed_brief", &"jiu_tong")["countInWindow"], 3, "Registry restores interaction trace by canonical key", failures)


func _test_gift_stance_handles_player_ground_gift_without_npc_relation(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := {
		"diet_coke": {
			"name": "Diet Coke",
			"category": "drink",
			"classification": {"category": "drink", "subtype": "soda", "material": "aluminum"},
			"defaultSocial": {"status": 40, "power": 0, "utility": 55, "debt": 15, "awkward": 10, "joke": 20, "danger": 0},
		}
	}
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict({
		"id": "trump",
		"traits": {"tell": 78, "face": 86, "control": 88, "caution": 44, "play": 72},
		"preference": {"classificationAffinity": {"drink.soda": 30}, "tolerance": {"repetition": 70}},
	}))
	registry.add_npc(NPCStateScript.from_dict({"id": "jiu_tong"}))
	var item = ItemStateScript.from_dict({"id": "diet_coke", "typeId": "diet_coke", "currentAnchor": {"type": "ground"}}, object_types)
	registry.add_item(item)

	var result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"trump", &"", [&"trump"], registry, _gameplay_config(), 20, {
		"operator": "player_drag",
		"receiverNpcId": &"trump",
		"fromAnchor": {"type": "ground"},
		"toAnchor": {"type": "npc", "npcId": "trump"},
		"attributionTarget": "player",
		"attributionConfidence": 1.0,
	})
	_assert_equal(result["giftStance"]["result"], "like", "Player can directly gift unowned liked object from ground", failures)
	_assert_equal(result["giftTrace"]["eventType"], "gift:player", "Player-origin gift records player fatigue trace", failures)
	_assert_equal(registry.relation_memory(&"trump", &"jiu_tong").is_empty(), true, "Player-origin unowned gift does not create NPC relation", failures)
	_assert_equal(InteractionDeltaRulesScript._classification_keys(item).has("drink.soda"), true, "Subtype is stored short and composed into category subtype key", failures)


func _test_gift_relation_requires_npc_attribution(failures: Array) -> void:
	var registry = _make_registry()
	var object_types := {
		"sealed_brief": {
			"name": "Sealed Brief",
			"category": "document",
			"classification": {"category": "document", "subtype": "sealed", "material": "paper"},
			"defaultSocial": {"status": 20, "power": 10, "utility": 10, "debt": 90, "awkward": 95, "joke": 10, "danger": 0},
		}
	}
	registry.set_object_types(object_types)
	registry.add_npc(NPCStateScript.from_dict({"id": "giver"}))
	registry.add_npc(NPCStateScript.from_dict({
		"id": "receiver",
		"traits": {"caution": 88, "face": 90, "control": 72, "play": 20, "tell": 40},
		"preference": {"classificationAffinity": {"document.sealed": -20}, "tolerance": {"debt": 10, "awkward": 20, "repetition": 15}},
	}))
	var item = ItemStateScript.from_dict({"id": "sealed_brief", "typeId": "sealed_brief", "currentAnchor": {"type": "npc", "npcId": "giver"}}, object_types)
	registry.add_item(item)

	var result: Dictionary = InteractionDeltaRulesScript.apply_attach_object_to_npc(item, &"receiver", &"giver", [&"giver", &"receiver"], registry, _gameplay_config(), 30, {
		"operator": "player_drag",
		"giverNpcId": &"giver",
		"receiverNpcId": &"receiver",
		"fromAnchor": {"type": "npc", "npcId": "giver"},
		"toAnchor": {"type": "npc", "npcId": "receiver"},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	})
	var relation: Dictionary = registry.relation_memory(&"receiver", &"giver")
	_assert_equal(relation.is_empty(), false, "NPC-attributed gift changes receiver relation to giver", failures)
	_assert_equal(registry.relation_memory(&"giver", &"receiver").is_empty(), true, "Gift relation is not automatically symmetric", failures)
	_assert_equal(["reject", "accept_then_discard"].has(str(result["giftStance"]["result"])), true, "Disliked gift can reject or accept then discard by persona", failures)


func _plan_has_expression(plan: Dictionary, expression_id: String) -> bool:
	for step in plan.get("steps", []):
		if step is Dictionary and str(step.get("expressionId", "")) == expression_id:
			return true
	return false


func _make_registry():
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 4, 4))
	return registry


func _core_validation_object_types() -> Dictionary:
	return ConfigLoaderScript.load_item_bundle().get("objectTypes", {})


func _gameplay_config() -> Dictionary:
	return ConfigLoaderScript.load_gameplay_config()


func _core_validation_npc(npc_id: String) -> Dictionary:
	return ConfigLoaderScript.load_npc_configs().get("by_id", {}).get(npc_id, {"id": npc_id})


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
