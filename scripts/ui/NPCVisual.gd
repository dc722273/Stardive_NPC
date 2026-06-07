extends Node2D
class_name NPCVisual
const ConstantsScript := preload("res://scripts/core/Constants.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")
var npc_id: StringName = &""
var label_text: String = ""
var color: Color = Color(0.34, 0.64, 0.95, 1.0)
var marker_texture: Texture2D = null
var selected: bool = false
var wellbeing_icon_text: String = ""
var wellbeing_effect: String = ""
var _bubble_timer: float = 0.0
const BUBBLE_DURATION := 8.0
const BUBBLE_FONT_SIZE := 28
func _init() -> void:
	_ensure_children()
func _ready() -> void:
	_ensure_children()
func _ensure_children() -> void:
	if get_node_or_null("HeldItemAnchor") == null:
		var anchor := Node2D.new()
		anchor.name = "HeldItemAnchor"
		anchor.position = HeldItemLayoutScript.anchor_offset()
		add_child(anchor)
	if get_node_or_null("SpeechBubble") == null:
		var bubble := Label.new()
		bubble.name = "SpeechBubble"
		bubble.position = Vector2(-40, -ConstantsScript.CELL_SIZE)
		bubble.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
		bubble.visible = false
		add_child(bubble)
	else:
		var bubble := get_node_or_null("SpeechBubble") as Label
		if bubble != null:
			bubble.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
func show_bubble(text: String) -> void:
	var bubble := get_node_or_null("SpeechBubble") as Label
	if bubble == null:
		return
	bubble.text = text
	bubble.visible = true
	_bubble_timer = BUBBLE_DURATION
func _process(delta: float) -> void:
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			var bubble := get_node_or_null("SpeechBubble") as Label
			if bubble != null:
				bubble.visible = false
func _draw() -> void:
	if marker_texture != null:
		var target_size := Vector2(ConstantsScript.CELL_SIZE * 1.9, ConstantsScript.CELL_SIZE * 1.9)
		draw_texture_rect(marker_texture, Rect2(-target_size * 0.5, target_size), false)
	else:
		draw_circle(Vector2.ZERO, ConstantsScript.CELL_SIZE * 0.68, color)
	if selected:
		draw_arc(Vector2.ZERO, ConstantsScript.CELL_SIZE * 0.96, 0, TAU, 32, Color(1.0, 0.84, 0.0, 1.0), 3.0)
	if not wellbeing_icon_text.is_empty():
		_draw_wellbeing_icon()
	if not label_text.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(-ConstantsScript.CELL_SIZE * 0.55, ConstantsScript.CELL_SIZE * 0.86), label_text, HORIZONTAL_ALIGNMENT_LEFT, ConstantsScript.CELL_SIZE * 1.4, 14, Color.WHITE)


func _draw_wellbeing_icon() -> void:
	var pos := Vector2(-ConstantsScript.CELL_SIZE * 0.20, -ConstantsScript.CELL_SIZE * 1.35)
	var radius := ConstantsScript.CELL_SIZE * 0.28
	var fill := Color(0.12, 0.11, 0.10, 0.86)
	var stroke := Color(1.0, 0.82, 0.18, 1.0)
	if wellbeing_effect == "dim":
		stroke = Color(0.72, 0.78, 0.88, 1.0)
	elif wellbeing_effect == "shake":
		stroke = Color(1.0, 0.36, 0.22, 1.0)
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0, TAU, 24, stroke, 2.0)
	draw_string(ThemeDB.fallback_font, pos + Vector2(-radius * 0.72, radius * 0.34), wellbeing_icon_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 1.45, 18, Color.WHITE)
