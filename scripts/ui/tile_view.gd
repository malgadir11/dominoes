class_name TileView
extends Control

## Renders one domino tile, in a given orientation. This is the ONLY place tiles
## are drawn, and it reads all appearance from a TileTheme — replace the art by
## editing the theme (or its textures), not this file. It carries no game rules.
##
## A tile shows two values: `val_a` then `val_b`. When `vertical` is false they
## sit left|right; when true they sit top/bottom (used for doubles laid crosswise
## in the chain). Whatever value must touch a neighbour is passed on the touching
## side by the caller, so equal numbers always physically meet.

signal clicked(view: TileView)

var tile_ref: Tile
var val_a: int = 0
var val_b: int = 0
var vertical: bool = false
var face_up: bool = true
var interactive: bool = false
var highlighted: bool = false
var theme_data: TileTheme


## Configure and size the tile. `t` is the underlying tile (for click matching);
## `a`/`b` are the values to display in reading order (left→right or top→bottom).
func configure(td: TileTheme, t: Tile, a: int, b: int, p_vertical: bool, p_face_up: bool, p_interactive: bool) -> void:
	theme_data = td
	tile_ref = t
	val_a = a
	val_b = b
	vertical = p_vertical
	face_up = p_face_up
	interactive = p_interactive
	var s := td.half_size
	custom_minimum_size = Vector2(s, s * 2.0) if vertical else Vector2(s * 2.0, s)
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_highlighted(h: bool) -> void:
	highlighted = h
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _draw() -> void:
	var td := theme_data
	var s := td.half_size
	var full := Vector2(s, s * 2.0) if vertical else Vector2(s * 2.0, s)
	var rect := Rect2(Vector2.ZERO, full)

	# --- body ---
	if face_up and td.body_texture != null:
		draw_texture_rect(td.body_texture, rect, false)
	elif not face_up and td.back_texture != null:
		draw_texture_rect(td.back_texture, rect, false)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = td.body_color if face_up else td.back_color
		sb.set_corner_radius_all(int(td.corner_radius))
		sb.set_border_width_all(int(td.border_width))
		sb.border_color = td.highlight_color if highlighted else td.border_color
		draw_style_box(sb, rect)

	if not face_up:
		return

	# --- divider + the two halves ---
	if vertical:
		draw_line(Vector2(td.safe_margin, s), Vector2(s - td.safe_margin, s), td.border_color, td.divider_thickness)
		_draw_pips(val_a, Vector2.ZERO, s)
		_draw_pips(val_b, Vector2(0, s), s)
	else:
		draw_line(Vector2(s, td.safe_margin), Vector2(s, s - td.safe_margin), td.border_color, td.divider_thickness)
		_draw_pips(val_a, Vector2.ZERO, s)
		_draw_pips(val_b, Vector2(s, 0), s)


func _draw_pips(count: int, origin: Vector2, s: float) -> void:
	var td := theme_data
	var inset := td.safe_margin + td.pip_radius
	var span := s - 2.0 * inset
	for p in _pip_layout(count):
		var c := origin + Vector2(inset + p.x * span * 0.5, inset + p.y * span * 0.5)
		if td.pip_texture != null:
			var r := td.pip_radius
			draw_texture_rect(td.pip_texture, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
		else:
			draw_circle(c, td.pip_radius, td.pip_color)


## Standard dice arrangement on a 3x3 grid (coords in {0,1,2}).
func _pip_layout(n: int) -> Array:
	match n:
		1: return [Vector2(1, 1)]
		2: return [Vector2(0, 0), Vector2(2, 2)]
		3: return [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)]
		4: return [Vector2(0, 0), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)]
		5: return [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)]
		6: return [Vector2(0, 0), Vector2(2, 0), Vector2(0, 1), Vector2(2, 1), Vector2(0, 2), Vector2(2, 2)]
	return []
