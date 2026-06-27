extends Control

## The playable "Play vs Bots" screen: a setup panel, then a bordered field you
## play on. Click a tile to pick it up (it follows the cursor), then click a
## glowing spot to lock it. The left end extends left/down, the right end
## right/up; tiles connect full-face and can't be placed out of the field.
## This is the FILLER presentation layer — all art comes from `tile_theme`, all
## rules from the headless engine; the two are kept apart on purpose.

const TARGET_SCORE := 75
const HUMAN := 0
const BOT := 1
const BOT_DELAY := 0.55  # seconds, so the bot's moves are readable
const FIELD_SIZE := Vector2(1760, 660)  # the bordered play field (fits all 28 tiles)

enum State { SETUP, PLAYER_TURN, BOT_TURN, ROUND_OVER, MATCH_OVER }

## Assign a custom TileTheme here in the Inspector to reskin everything.
@export var tile_theme: TileTheme

var _state: int = State.SETUP
var _variant: int = Round.Variant.DRAW
var _bot: Bot
var _round: Round
var _scores := [0, 0]
var _opener := -1
var _status_extra := ""

# Player-placed board: each entry is the visual transform of a played tile,
#   {"tile": Tile, "pos": Vector2, "size": Vector2, "a": int, "b": int, "vertical": bool}
# and the two open ends are anchors the player drags new tiles onto.
var _placed: Array = []
var _anchors := {}  # {Board.Side: {"pos": Vector2, "facing": Vector2}}

# Click-to-place ("pick up") state: click a tile to hold it (it follows the
# cursor), then click a glowing spot to lock it there.
var _held_tile: Tile = null
var _held_candidates: Array = []  # [{"side": int, "dir": Vector2, "geo": Dictionary}]
var _held_index := -1
var _held_layer: Control = null
var _held_ghosts: Array = []
var _cursor_ghost: TileView = null

# Polish: the most recently played tile (highlighted + pop-animated once).
var _last_played: Tile = null
var _pop_pending := false
var _fit_tween: Tween  # smoothly slides/scales the board when it re-fits

# Placeholder sound effects (swappable filler in assets/audio/).
var _sfx := {}

# UI nodes (built in code).
var _setup_root: Control
var _difficulty_option: OptionButton
var _variant_option: OptionButton
var _game_root: Control
var _status_label: Label
var _bot_hand_box: HBoxContainer
var _board_area: Control
var _board_content: Control
var _player_hand_box: HBoxContainer
var _draw_button: Button
var _pass_button: Button
var _next_button: Button
var _banner: Control
var _banner_label: Label


func _ready() -> void:
	randomize()
	# Open maximized so the board has room — the editor keeps stripping window
	# size from project.godot, so set it in code. Skipped under headless (tests).
	if DisplayServer.get_name() != "headless":
		var win := get_window()
		win.min_size = Vector2i(900, 560)
		win.mode = Window.MODE_MAXIMIZED
	if tile_theme == null:
		tile_theme = TileTheme.new()
	_build_audio()
	_build_setup_ui()
	_build_game_ui()
	_show_setup()


# Load the placeholder sound effects, if present. Missing files are skipped so
# the game still runs without audio. Replace the files in assets/audio/ to reskin.
func _build_audio() -> void:
	for sound_name in ["place", "draw", "win"]:
		var path := "res://assets/audio/%s.wav" % sound_name
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			_sfx[sound_name] = player


func _play(sound_name: String) -> void:
	if _sfx.has(sound_name):
		_sfx[sound_name].play()


# ---------------------------------------------------------------- setup screen

func _build_setup_ui() -> void:
	_setup_root = CenterContainer.new()
	_setup_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_setup_root)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	_setup_root.add_child(panel)

	var title := Label.new()
	title.text = "Dominoes — Play vs Bots"
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	_difficulty_option = OptionButton.new()
	for label_name in ["Easy", "Medium", "Hard", "Expert"]:
		_difficulty_option.add_item(label_name)
	_difficulty_option.selected = Bot.Difficulty.MEDIUM
	panel.add_child(_labeled_row("Opponent", _difficulty_option))

	_variant_option = OptionButton.new()
	_variant_option.add_item("Draw")   # index 0 == Round.Variant.DRAW
	_variant_option.add_item("Block")  # index 1 == Round.Variant.BLOCK
	_variant_option.selected = Round.Variant.DRAW
	panel.add_child(_labeled_row("Rules", _variant_option))

	var start := Button.new()
	start.text = "Start match (first to %d)" % TARGET_SCORE
	start.pressed.connect(_on_start_pressed)
	panel.add_child(start)


func _labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	control.custom_minimum_size = Vector2(160, 0)
	row.add_child(control)
	return row


# ------------------------------------------------------------------ game board

func _build_game_ui() -> void:
	_game_root = Control.new()
	_game_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_game_root)

	var table := ColorRect.new()
	table.color = tile_theme.table_color
	table.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_root.add_child(table)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_game_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", tile_theme.text_color)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status_label)

	_bot_hand_box = _centered_hbox()
	col.add_child(_bot_hand_box)

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer_top)

	# The play field: a bordered table the snake lives inside (and, once drag
	# placement lands, can't be dragged out of). Centered, fixed size.
	var field := PanelContainer.new()
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(0, 0, 0, 0.12)  # faint inset over the table
	field_style.set_border_width_all(4)
	field_style.border_color = Color.BLACK
	field_style.set_corner_radius_all(10)
	for side in ["left", "right", "top", "bottom"]:
		field_style.set("content_margin_" + side, 18)
	field.add_theme_stylebox_override("panel", field_style)
	field.custom_minimum_size = FIELD_SIZE
	field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(field)
	# Board area: fills the field's inner area and clips to the border. Tiles live
	# in _board_content, which is auto-scaled and re-centered every turn so the
	# whole chain always fits neatly inside the field.
	_board_area = Control.new()
	_board_area.clip_contents = true
	field.add_child(_board_area)
	_board_content = Control.new()
	_board_area.add_child(_board_content)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer_bottom)

	_player_hand_box = _centered_hbox()
	col.add_child(_player_hand_box)

	var actions := _centered_hbox()
	col.add_child(actions)
	_draw_button = _big_button("Draw a tile")
	_draw_button.pressed.connect(_on_draw_pressed)
	actions.add_child(_draw_button)
	_pass_button = _big_button("Pass")
	_pass_button.pressed.connect(_on_pass_pressed)
	actions.add_child(_pass_button)
	_next_button = _big_button("")
	_next_button.pressed.connect(_on_next_pressed)
	actions.add_child(_next_button)

	# Win banner: a centered overlay shown on round/match end. Non-interactive so
	# it never blocks the buttons underneath.
	_banner = CenterContainer.new()
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_game_root.add_child(_banner)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 40)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_banner_label)


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 44)
	return b


func _centered_hbox() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	return box


# ------------------------------------------------------------------ flow / state

func _show_setup() -> void:
	_state = State.SETUP
	_setup_root.visible = true
	_game_root.visible = false


func _on_start_pressed() -> void:
	_variant = _variant_option.selected
	_bot = Bot.new(_difficulty_option.selected)
	_setup_root.visible = false
	_game_root.visible = true
	_start_match()


func _start_match() -> void:
	_scores = [0, 0]
	_opener = -1  # first round: highest double opens
	_start_round()


func _start_round() -> void:
	var deck := Deck.new()
	deck.shuffle_deck()
	_round = Round.deal(2, 7, _variant, deck, _opener)
	_status_extra = ""
	_cancel_held()
	_placed = []
	_anchors = {}
	_last_played = null
	_pop_pending = false
	# The first-round opening double is a forced, choiceless move — play it
	# automatically so the board always starts with a tile in the center.
	if _round.has_forced_opener():
		_place_opener(_round.legal_moves()[0])
	if _round.current == HUMAN:
		_state = State.PLAYER_TURN
		_render()
	else:
		_state = State.BOT_TURN
		_render()
		_run_bot()


func _run_bot() -> void:
	_state = State.BOT_TURN
	_status_extra = ""
	_cancel_held()
	_render()
	while not _round.finished and _round.current == BOT:
		await get_tree().create_timer(BOT_DELAY).timeout
		var moves := _round.legal_moves()
		var placeable: Array[Move] = []
		for m in moves:
			if _round.board.is_empty() or _move_placeable(m):
				placeable.append(m)
		if placeable.is_empty():
			# Nothing fits in bounds (no legal move, or the field is full here).
			if _variant == Round.Variant.DRAW and not _round.boneyard_empty():
				_round.draw_tile()
				_play("draw")
				_render()
				continue
			_round.pass_turn()
		else:
			var bot_move := _bot.choose_move(_round, BOT)
			if not (_round.board.is_empty() or _move_placeable(bot_move)):
				bot_move = placeable[0]  # the AI's pick doesn't fit; use one that does
			if _round.board.is_empty():
				_place_opener(bot_move)
			else:
				_place_directed(bot_move, _auto_dir(bot_move))
		_render()
	if _round.finished:
		_finish_round()
	else:
		_state = State.PLAYER_TURN
		_render()


func _mark_played(tile: Tile) -> void:
	_last_played = tile
	_pop_pending = true
	_play("place")


# ---------------------------------------------------------------- placement model

func _field_inner() -> Vector2:
	return FIELD_SIZE - Vector2(36, 36)  # minus the panel's content margins (18 each side)


# The first tile goes in the center and seeds both open-end anchors.
func _place_opener(move: Move) -> void:
	var s := tile_theme.half_size
	var c := _field_inner() * 0.5
	var t := move.tile
	if t.is_double():
		_placed.append({"tile": t, "pos": Vector2(c.x - s * 0.5, c.y - s), "size": Vector2(s, 2.0 * s), "a": t.low, "b": t.low, "vertical": true})
		_anchors[Board.Side.LEFT] = {"pos": Vector2(c.x - s * 0.5, c.y), "facing": Vector2(-1, 0), "vertical": true, "h_dir": Vector2(-1, 0)}
		_anchors[Board.Side.RIGHT] = {"pos": Vector2(c.x + s * 0.5, c.y), "facing": Vector2(1, 0), "vertical": true, "h_dir": Vector2(1, 0)}
	else:
		_placed.append({"tile": t, "pos": Vector2(c.x - s, c.y - s * 0.5), "size": Vector2(2.0 * s, s), "a": t.low, "b": t.high, "vertical": false})
		_anchors[Board.Side.LEFT] = {"pos": Vector2(c.x - s, c.y), "facing": Vector2(-1, 0), "vertical": false, "h_dir": Vector2(-1, 0)}
		_anchors[Board.Side.RIGHT] = {"pos": Vector2(c.x + s, c.y), "facing": Vector2(1, 0), "vertical": false, "h_dir": Vector2(1, 0)}
	_mark_played(t)
	_round.apply_move(move)


# Place a tile on one end, extending in a chosen direction.
func _place_directed(move: Move, dir: Vector2) -> void:
	var side := move.side
	var anchor: Dictionary = _anchors[side]
	var end_val: int = _round.board.left_end if side == Board.Side.LEFT else _round.board.right_end
	var geo := _tile_geometry(anchor["pos"], anchor["facing"], dir, end_val, move.tile.other_end(end_val), move.tile.is_double())
	_placed.append({"tile": move.tile, "pos": geo["pos"], "size": geo["size"], "a": geo["a"], "b": geo["b"], "vertical": geo["vertical"]})
	# Remember the last horizontal travel direction so a turn can wrap back.
	var new_h: Vector2 = dir if dir.y == 0.0 else anchor.get("h_dir", anchor["facing"])
	_anchors[side] = {"pos": geo["new_anchor"], "facing": geo["new_facing"], "vertical": geo["vertical"], "h_dir": new_h}
	_mark_played(move.tile)
	_round.apply_move(move)


# Directions a tile may extend at an end. The end snakes: it runs horizontally,
# turns into its corner (right end up, left end down) at the wall or by choice,
# then wraps back the other way on a new row — so it never runs out of room.
func _candidate_dirs(side: int, anchor: Dictionary, is_double: bool) -> Array:
	var f: Vector2 = anchor["facing"]
	if is_double:
		return [f]  # doubles always continue straight (laid crosswise)
	if f.y == 0.0:
		# Facing horizontal: continue straight; also turn into the corner, but only
		# off a horizontal tile (never off a vertical tile or a crosswise double).
		var turn := Vector2(0, -1) if side == Board.Side.RIGHT else Vector2(0, 1)
		if anchor.get("vertical", false):
			return [f]
		return [f, turn]
	# Facing vertical (just turned): wrap to the opposite horizontal direction.
	var h: Vector2 = anchor.get("h_dir", Vector2(1, 0) if side == Board.Side.RIGHT else Vector2(-1, 0))
	return [-h]


# Geometry of a tile attached at open-end edge-midpoint `m` (which faces `f`),
# extending in direction `d`. The connecting square sits flush OUTSIDE the anchor
# edge so faces meet fully and tiles never overlap the chain.
func _tile_geometry(m: Vector2, f: Vector2, d: Vector2, connecting: int, exposed: int, is_double: bool) -> Dictionary:
	var s := tile_theme.half_size
	if is_double:
		# Crosswise to the line, continuing straight (doubles don't turn the line).
		if f.x != 0.0:  # horizontal travel -> upright double
			var px := m.x if f.x > 0.0 else m.x - s
			return {"pos": Vector2(px, m.y - s), "size": Vector2(s, 2.0 * s), "a": connecting, "b": connecting, "vertical": true, "new_anchor": Vector2(m.x + s * f.x, m.y), "new_facing": f}
		var py := m.y if f.y > 0.0 else m.y - s
		return {"pos": Vector2(m.x - s, py), "size": Vector2(2.0 * s, s), "a": connecting, "b": connecting, "vertical": false, "new_anchor": Vector2(m.x, m.y + s * f.y), "new_facing": f}
	# Normal tile: connecting square flush at the edge, body extends along `d`.
	var connect_c := m + f * (s * 0.5)
	var far_c := connect_c + d * s
	var lo := Vector2(minf(connect_c.x, far_c.x), minf(connect_c.y, far_c.y)) - Vector2(s * 0.5, s * 0.5)
	var hi := Vector2(maxf(connect_c.x, far_c.x), maxf(connect_c.y, far_c.y)) + Vector2(s * 0.5, s * 0.5)
	var a := connecting
	var b := exposed
	if d.x < 0.0 or d.y < 0.0:  # left or up: the far (exposed) square reads first
		a = exposed
		b = connecting
	return {"pos": lo, "size": hi - lo, "a": a, "b": b, "vertical": d.y != 0.0, "new_anchor": far_c + d * (s * 0.5), "new_facing": d}


func _in_bounds(pos: Vector2, size: Vector2, reserve: Vector2 = Vector2.ZERO) -> bool:
	var inner := _field_inner()
	var s := tile_theme.half_size
	var p := pos
	var sz := size
	# Reserve a tile's room in the travel direction so the corner that will turn
	# the line still fits — this is why the snake turns before reaching the wall.
	if reserve.x > 0.0:
		sz.x += s
	elif reserve.x < 0.0:
		p.x -= s
		sz.x += s
	return p.x >= -0.5 and p.y >= -0.5 and p.x + sz.x <= inner.x + 0.5 and p.y + sz.y <= inner.y + 0.5


# Every in-bounds way to play `t`: each matching end, in its allowed directions.
func _candidates_for(t: Tile) -> Array:
	var res: Array = []
	for side in [Board.Side.LEFT, Board.Side.RIGHT]:
		if not _anchors.has(side):
			continue
		var end_val: int = _round.board.left_end if side == Board.Side.LEFT else _round.board.right_end
		if not t.has_value(end_val):
			continue
		var anchor: Dictionary = _anchors[side]
		var m: Vector2 = anchor["pos"]
		var f: Vector2 = anchor["facing"]
		for d in _candidate_dirs(side, anchor, t.is_double()):
			var geo := _tile_geometry(m, f, d, end_val, t.other_end(end_val), t.is_double())
			var reserve: Vector2 = d if d.y == 0.0 else Vector2.ZERO
			if _in_bounds(geo["pos"], geo["size"], reserve):
				res.append({"side": side, "dir": d, "geo": geo})
	return res


# The bot doesn't pick — take the first in-bounds direction (prefers straight).
func _auto_dir(move: Move) -> Vector2:
	for c in _candidates_for(move.tile):
		if c["side"] == move.side:
			return c["dir"]
	return _anchors[move.side]["facing"]


func _move_for_side(t: Tile, side: int) -> Move:
	for m in _round.legal_moves():
		if m.tile.equals(t) and m.side == side:
			return m
	return null


# A move is placeable only if it has an in-bounds spot — so nothing is ever put
# outside the field, by the player or the bot.
func _move_placeable(m: Move) -> bool:
	for c in _candidates_for(m.tile):
		if c["side"] == m.side:
			return true
	return false


func _tile_playable(t: Tile) -> bool:
	if _round.board.is_empty():
		return true  # any tile can lead; the opener goes at the center, always in bounds
	return not _candidates_for(t).is_empty()


func _player_has_placeable() -> bool:
	for t in _round.hands[HUMAN].tiles:
		if _tile_playable(t):
			return true
	return false


# ---------------------------------------------------------------- click to place

func _on_hand_pressed(view: TileView) -> void:
	if _state != State.PLAYER_TURN or _held_tile != null:
		return
	if _round.board.is_empty():
		# The opening tile has only one spot (center) — just place it.
		var moves := _moves_for(view.tile_ref)
		if not moves.is_empty():
			_place_opener(moves[0])
			_after_player_move()
		return
	if _moves_for(view.tile_ref).is_empty():
		return  # not playable
	_pick_up(view.tile_ref)


func _pick_up(t: Tile) -> void:
	_held_candidates = _candidates_for(t)
	if _held_candidates.is_empty():
		return  # no in-bounds spot to place it
	if _fit_tween != null and _fit_tween.is_valid():
		_fit_tween.kill()  # freeze the board so drag coordinates stay stable
	_held_tile = t
	_held_index = -1
	_build_held_layer()
	_update_held()


func _build_held_layer() -> void:
	var s := tile_theme.half_size
	_held_layer = Control.new()
	_held_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_content.add_child(_held_layer)  # shares the board's auto-fit scale
	_held_ghosts = []
	for c in _held_candidates:
		var geo: Dictionary = c["geo"]
		var g := TileView.new()
		g.configure(tile_theme, _held_tile, geo["a"], geo["b"], geo["vertical"], true, false)
		g.position = geo["pos"]
		g.size = geo["size"]
		g.modulate.a = 0.25
		_held_layer.add_child(g)
		_held_ghosts.append(g)
	# A translucent tile that follows the cursor.
	_cursor_ghost = TileView.new()
	_cursor_ghost.configure(tile_theme, _held_tile, _held_tile.low, _held_tile.high, false, false, false)
	_cursor_ghost.size = Vector2(2.0 * s, s)
	_cursor_ghost.modulate.a = 0.55
	_held_layer.add_child(_cursor_ghost)


func _input(event: InputEvent) -> void:
	if _held_tile == null:
		return
	if event is InputEventMouseMotion:
		_update_held()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_place()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_held()
		_render()


func _update_held() -> void:
	var s := tile_theme.half_size
	# Candidate positions are in board-content (layout) coords; the field rect is
	# in board-area coords. Use each for its own check so the auto-fit scale works.
	var content_mouse := _board_content.get_local_mouse_position()
	if _cursor_ghost != null:
		_cursor_ghost.position = content_mouse - Vector2(s, s * 0.5)
	var inside := Rect2(Vector2.ZERO, _field_inner()).has_point(_board_area.get_local_mouse_position())
	var best := -1
	if inside:
		var best_d := INF
		for i in range(_held_candidates.size()):
			var geo: Dictionary = _held_candidates[i]["geo"]
			var center: Vector2 = geo["pos"] + geo["size"] * 0.5
			var dist := content_mouse.distance_to(center)
			if dist < best_d:
				best_d = dist
				best = i
	_held_index = best
	for i in range(_held_ghosts.size()):
		_held_ghosts[i].modulate.a = 0.85 if i == best else 0.2


func _try_place() -> void:
	var mouse := _board_area.get_local_mouse_position()
	var inside := Rect2(Vector2.ZERO, _field_inner()).has_point(mouse)
	if not inside or _held_index < 0:
		_cancel_held()  # clicked off the field -> drop it back to hand
		_render()
		return
	var c: Dictionary = _held_candidates[_held_index]
	var t := _held_tile
	_cancel_held()
	var move := _move_for_side(t, c["side"])
	if move != null:
		_place_directed(move, c["dir"])
		_after_player_move()
	else:
		_render()


func _cancel_held() -> void:
	_held_tile = null
	_held_candidates = []
	_held_index = -1
	_cursor_ghost = null
	if _held_layer != null:
		_held_layer.queue_free()
		_held_layer = null
	_held_ghosts = []


func _after_player_move() -> void:
	if _round.finished:
		_finish_round()
	else:
		_run_bot()


# Scale and re-center the whole chain so it always fits neatly inside the field,
# no matter how far it has snaked — the board "smart-adjusts" as it grows.
func _autofit() -> void:
	if _placed.is_empty():
		_board_content.scale = Vector2.ONE
		_board_content.position = Vector2.ZERO
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rec in _placed:
		var p: Vector2 = rec["pos"]
		var sz: Vector2 = rec["size"]
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x + sz.x)
		hi.y = maxf(hi.y, p.y + sz.y)
	var bbox := hi - lo
	var field := _field_inner()
	var pad := 80.0
	var sc := minf((field.x - pad) / maxf(bbox.x, 1.0), (field.y - pad) / maxf(bbox.y, 1.0))
	sc = minf(sc, 1.15)  # don't over-zoom a tiny board
	var target_scale := Vector2(sc, sc)
	var target_pos := (field - bbox * sc) * 0.5 - lo * sc
	if _fit_tween != null and _fit_tween.is_valid():
		_fit_tween.kill()
	# Slide/scale smoothly into place, unless this is the first tile.
	if _board_content.get_child_count() <= 1 or _board_content.scale == Vector2.ONE and _board_content.position == Vector2.ZERO:
		_board_content.scale = target_scale
		_board_content.position = target_pos
	else:
		_fit_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_fit_tween.tween_property(_board_content, "scale", target_scale, 0.28)
		_fit_tween.tween_property(_board_content, "position", target_pos, 0.28)


func _show_banner(res: RoundResult) -> void:
	var win := res.winner == HUMAN
	var text := ""
	if _state == State.MATCH_OVER:
		text = "You win the match!" if win else "Bot wins the match"
	else:
		text = ("You won the round" if win else "Bot won the round") + "   +%d" % res.score
	_banner_label.text = text
	_banner.visible = true
	_banner.modulate.a = 0.0
	create_tween().tween_property(_banner, "modulate:a", 1.0, 0.25)


func _moves_for(t: Tile) -> Array[Move]:
	var res: Array[Move] = []
	for m in _round.legal_moves():
		if m.tile.equals(t):
			res.append(m)
	return res


func _on_draw_pressed() -> void:
	if _state != State.PLAYER_TURN:
		return
	_cancel_held()
	_round.draw_tile()
	_play("draw")
	_render()


func _on_pass_pressed() -> void:
	if _state != State.PLAYER_TURN:
		return
	_cancel_held()
	_round.pass_turn()
	if _round.finished:
		_finish_round()
	else:
		_run_bot()


func _finish_round() -> void:
	var res := _round.result
	_scores[res.winner] += res.score
	var who := "You" if res.winner == HUMAN else "Bot"
	var how := "going out" if res.win_type == Round.WinType.DOMINO else "the block"
	_status_extra = "%s won the round by %s, +%d." % [who, how, res.score]
	if _scores[res.winner] >= TARGET_SCORE:
		_state = State.MATCH_OVER
		_status_extra = ("You win the match!" if res.winner == HUMAN else "Bot wins the match.") + "  " + _status_extra
	else:
		_state = State.ROUND_OVER
		_opener = res.winner
	_play("win")
	_show_banner(res)
	_render()


func _on_next_pressed() -> void:
	if _state == State.MATCH_OVER:
		_show_setup()
	else:
		_start_round()


# ------------------------------------------------------------------ rendering

func _render() -> void:
	_status_label.text = _status_text()

	# A hand tile is highlighted only if it has an in-bounds spot to go.
	var playable := {}
	if _state == State.PLAYER_TURN and _round.current == HUMAN:
		for t in _round.hands[HUMAN].tiles:
			if _tile_playable(t):
				playable[_tile_key(t)] = true

	# Bot hand: face-down backs.
	_clear(_bot_hand_box)
	for t in _round.hands[BOT].tiles:
		_bot_hand_box.add_child(_make_back(t))

	# Board: the player-placed snake, drawn at each tile's stored transform inside
	# _board_content, which is then scaled and centered to fit the field.
	_clear(_board_content)
	for rec in _placed:
		var bview := TileView.new()
		bview.configure(tile_theme, rec["tile"], rec["a"], rec["b"], rec["vertical"], true, false)
		bview.position = rec["pos"]
		bview.size = rec["size"]
		_board_content.add_child(bview)
		if _last_played != null and rec["tile"].equals(_last_played):
			bview.set_recent(true)
			if _pop_pending:
				bview.pop_in()
	_pop_pending = false
	_autofit()

	# Player hand: drag playable (highlighted) tiles onto the board.
	_clear(_player_hand_box)
	for t in _round.hands[HUMAN].tiles:
		var hl: bool = playable.has(_tile_key(t))
		var view := _make_hand_tile(t, hl)
		view.clicked.connect(_on_hand_pressed)
		_player_hand_box.add_child(view)

	var stuck: bool = _state == State.PLAYER_TURN and _round.current == HUMAN and playable.is_empty()
	_draw_button.visible = stuck and _variant == Round.Variant.DRAW and not _round.boneyard_empty()
	_pass_button.visible = stuck and not _draw_button.visible
	var over: bool = _state == State.ROUND_OVER or _state == State.MATCH_OVER
	_next_button.visible = over
	_next_button.text = "New match" if _state == State.MATCH_OVER else "Next round"
	if not over:
		_banner.visible = false


func _status_text() -> String:
	var ends := _round.board.open_ends()
	var ends_str := "—" if ends.is_empty() else str(ends)
	var line1 := "You %d   ·   Bot %d   (first to %d)" % [_scores[HUMAN], _scores[BOT], TARGET_SCORE]
	var line2 := "Open ends: %s    Boneyard: %d" % [ends_str, _round.boneyard.size()]
	var line3 := ""
	match _state:
		State.PLAYER_TURN:
			if _held_tile != null:
				line3 = "Click a glowing spot to place it  (Esc to cancel)."
			elif _round.board.is_empty():
				line3 = "Your turn — click a tile to lead."
			elif not _player_has_placeable():
				line3 = "No move fits — draw a tile." if _draw_button_would_show() else "No move fits — you must pass."
			else:
				line3 = "Your turn — click a highlighted tile, then click a spot."
		State.BOT_TURN:
			line3 = "Bot is thinking…"
		_:
			line3 = _status_extra
	return "%s\n%s\n%s" % [line1, line2, line3]


func _draw_button_would_show() -> bool:
	return _variant == Round.Variant.DRAW and not _round.boneyard_empty()


func _player_legal_moves() -> Array[Move]:
	if _state == State.PLAYER_TURN and _round.current == HUMAN:
		return _round.legal_moves()
	var none: Array[Move] = []
	return none


func _make_hand_tile(t: Tile, highlighted: bool) -> TileView:
	var view := TileView.new()
	view.configure(tile_theme, t, t.low, t.high, false, true, true)
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.set_highlighted(highlighted)
	return view


func _make_back(t: Tile) -> TileView:
	var view := TileView.new()
	view.configure(tile_theme, t, 0, 0, false, false, false)
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return view


func _tile_key(t: Tile) -> int:
	return t.low * 7 + t.high


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
