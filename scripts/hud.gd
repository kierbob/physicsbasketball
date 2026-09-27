class_name Hud
extends CanvasLayer
## Score, popups, help text and the crosshair.

var _stats: Label
var _popup: Label
var _banner: Label
var _help: Label
var _overlay: Control

var _popup_time := 0.0
var _sight_visible := false
var _sight_pos := Vector2.ZERO


func _ready() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_stats = _label(26, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, 24)
	_popup = _label(40, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0)
	_popup.offset_bottom = -260
	_banner = _label(34, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0)
	_banner.offset_top = 220
	_help = _label(18, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM, 24)
	_help.modulate = Color(1, 1, 1, 0.8)
	_help.text = "\n".join([
		"WASD move  ·  Space jump  ·  Shift sprint",
		"Hold RMB: grab the bow, keep holding or you drop it. Mouse moves your bow arm",
		"Hold LMB: grab the string and pull  ·  let go to shoot",
		"No bow + hold LMB: flail your hand around",
		"R restart  ·  Esc free the mouse",
	])


## Full-screen label positioned purely by its text alignment.
func _label(size: int, h: HorizontalAlignment, v: VerticalAlignment, margin: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.horizontal_alignment = h
	label.vertical_alignment = v
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, margin)
	return label


func _process(delta: float) -> void:
	if _popup_time > 0.0:
		_popup_time -= delta
		_popup.modulate.a = clampf(_popup_time / 0.4, 0.0, 1.0)
	_overlay.queue_redraw()


func set_stats(score: int, arrows_left: int, best: int) -> void:
	_stats.text = "Score  %d\nArrows  %d\nBest  %d" % [score, arrows_left, best]


func flash(text: String, color := Color.WHITE) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", color)
	_popup_time = 1.6
	_popup.modulate.a = 1.0


func set_banner(text: String) -> void:
	_banner.text = text


## The bow's aim point on screen. The center crosshair hides while it shows.
func set_sight(visible_now: bool, pos: Vector2) -> void:
	_sight_visible = visible_now
	_sight_pos = pos


func _draw_overlay() -> void:
	if _sight_visible:
		_overlay.draw_circle(_sight_pos, 3.5, Color(1.0, 0.35, 0.25, 0.95))
		_overlay.draw_arc(_sight_pos, 7.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5), 1.5)
		return
	var center := _overlay.size * 0.5
	_overlay.draw_circle(center, 3.0, Color(1, 1, 1, 0.9))
	_overlay.draw_arc(center, 6.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5), 1.5)
