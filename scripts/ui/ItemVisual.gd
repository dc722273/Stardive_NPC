extends Node2D
class_name ItemVisual
const ConstantsScript := preload("res://scripts/core/Constants.gd")
var item_id: StringName = &""
var label_text: String = ""
var icon_text: String = ""
var held: bool = false


func _draw() -> void:
	var size := 40.0 if held else 64.0
	draw_rect(Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)), Color(0.92, 0.73, 0.24, 1.0), true)
	draw_rect(Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)), Color(0.18, 0.14, 0.08, 1.0), false, 1.0)
	var label := icon_text if not icon_text.is_empty() else str(item_id)
	draw_string(ThemeDB.fallback_font, Vector2(-size, -size * 0.8), label, HORIZONTAL_ALIGNMENT_CENTER, size * 2.0, 32, Color.WHITE)
