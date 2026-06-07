extends Node2D
class_name ItemVisual
const ConstantsScript := preload("res://scripts/core/Constants.gd")
var item_id: StringName = &""
var label_text: String = ""
var icon_text: String = ""
var held: bool = false
const GROUND_ICON_SIZE := 64.0
const HELD_ICON_SIZE := 80.0


func _draw() -> void:
	var size := HELD_ICON_SIZE if held else GROUND_ICON_SIZE
	_draw_icon_shape(size)
	var label := icon_text if not icon_text.is_empty() else str(item_id)
	draw_string(ThemeDB.fallback_font, Vector2(-size, -size * 0.17), label, HORIZONTAL_ALIGNMENT_CENTER, size * 2.0, int(size * 0.42), Color.WHITE)


func _draw_icon_shape(size: float) -> void:
	var key := icon_text.strip_edges()
	match key:
		"COKE":
			_draw_coke_icon(size)
		"枪":
			_draw_gun_icon(size)
		"杯":
			_draw_cup_icon(size)
		"账":
			_draw_ledger_icon(size)
		"$":
			_draw_cash_icon(size)
		"封":
			_draw_seal_icon(size)
		_:
			_draw_default_icon(size)


func _draw_default_icon(size: float) -> void:
	var rect := Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size))
	draw_rect(rect, Color(0.92, 0.73, 0.24, 1.0), true)
	draw_rect(rect, Color(0.18, 0.14, 0.08, 1.0), false, max(1.0, size * 0.04))


func _draw_coke_icon(size: float) -> void:
	var body := Rect2(Vector2(-size * 0.32, -size * 0.48), Vector2(size * 0.64, size * 0.96))
	draw_rect(body, Color(0.82, 0.08, 0.10, 1.0), true)
	draw_rect(body, Color(1.0, 0.86, 0.84, 1.0), false, max(1.0, size * 0.05))
	draw_line(Vector2(-size * 0.28, -size * 0.18), Vector2(size * 0.28, -size * 0.18), Color.WHITE, max(1.0, size * 0.04))
	draw_line(Vector2(-size * 0.28, size * 0.18), Vector2(size * 0.28, size * 0.18), Color.WHITE, max(1.0, size * 0.04))


func _draw_gun_icon(size: float) -> void:
	var dark := Color(0.10, 0.11, 0.12, 1.0)
	var metal := Color(0.62, 0.66, 0.68, 1.0)
	draw_rect(Rect2(Vector2(-size * 0.42, -size * 0.22), Vector2(size * 0.72, size * 0.22)), dark, true)
	draw_rect(Rect2(Vector2(size * 0.10, -size * 0.13), Vector2(size * 0.28, size * 0.12)), metal, true)
	draw_rect(Rect2(Vector2(-size * 0.05, -size * 0.02), Vector2(size * 0.20, size * 0.38)), dark, true)
	draw_line(Vector2(-size * 0.38, -size * 0.09), Vector2(size * 0.33, -size * 0.09), metal, max(1.0, size * 0.04))


func _draw_cup_icon(size: float) -> void:
	var gold := Color(0.94, 0.66, 0.16, 1.0)
	var rim := Color(1.0, 0.88, 0.38, 1.0)
	draw_rect(Rect2(Vector2(-size * 0.26, -size * 0.34), Vector2(size * 0.52, size * 0.56)), gold, true)
	draw_arc(Vector2(size * 0.30, -size * 0.12), size * 0.18, -PI * 0.5, PI * 0.5, 16, rim, max(1.0, size * 0.06))
	draw_line(Vector2(-size * 0.18, size * 0.24), Vector2(size * 0.18, size * 0.24), rim, max(1.0, size * 0.06))
	draw_line(Vector2(0, size * 0.20), Vector2(0, size * 0.38), rim, max(1.0, size * 0.06))
	draw_line(Vector2(-size * 0.24, size * 0.40), Vector2(size * 0.24, size * 0.40), rim, max(1.0, size * 0.06))


func _draw_ledger_icon(size: float) -> void:
	var cover := Rect2(Vector2(-size * 0.36, -size * 0.44), Vector2(size * 0.72, size * 0.88))
	draw_rect(cover, Color(0.16, 0.34, 0.30, 1.0), true)
	draw_rect(cover, Color(0.82, 0.74, 0.52, 1.0), false, max(1.0, size * 0.05))
	draw_line(Vector2(-size * 0.20, -size * 0.26), Vector2(size * 0.22, -size * 0.26), Color(0.82, 0.74, 0.52, 1.0), max(1.0, size * 0.035))
	draw_line(Vector2(-size * 0.20, -size * 0.08), Vector2(size * 0.22, -size * 0.08), Color(0.82, 0.74, 0.52, 1.0), max(1.0, size * 0.035))
	draw_line(Vector2(-size * 0.20, size * 0.10), Vector2(size * 0.10, size * 0.10), Color(0.82, 0.74, 0.52, 1.0), max(1.0, size * 0.035))


func _draw_cash_icon(size: float) -> void:
	for index in range(3):
		var offset := Vector2(size * 0.05 * float(index - 1), size * 0.05 * float(1 - index))
		var rect := Rect2(Vector2(-size * 0.40, -size * 0.26) + offset, Vector2(size * 0.80, size * 0.52))
		draw_rect(rect, Color(0.16, 0.58, 0.28, 1.0), true)
		draw_rect(rect, Color(0.78, 0.96, 0.76, 1.0), false, max(1.0, size * 0.035))
	draw_circle(Vector2.ZERO, size * 0.14, Color(0.78, 0.96, 0.76, 1.0))


func _draw_seal_icon(size: float) -> void:
	var rect := Rect2(Vector2(-size * 0.44, -size * 0.18), Vector2(size * 0.88, size * 0.36))
	draw_rect(rect, Color(0.98, 0.91, 0.60, 1.0), true)
	draw_rect(rect, Color(0.54, 0.10, 0.08, 1.0), false, max(1.0, size * 0.045))
	draw_line(Vector2(-size * 0.40, -size * 0.16), Vector2(size * 0.40, size * 0.16), Color(0.76, 0.04, 0.04, 1.0), max(1.0, size * 0.06))
	draw_line(Vector2(-size * 0.40, size * 0.16), Vector2(size * 0.40, -size * 0.16), Color(0.76, 0.04, 0.04, 1.0), max(1.0, size * 0.06))
