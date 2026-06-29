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
const MAX_RUN := 6  # tiles in a horizontal row before the snake turns (looks tidy)

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

# The board layout is recomputed from the played sequence every turn (see
# _relayout). Each entry: {"tile", "pos", "size", "a", "b", "vertical"}.
var _placed: Array = []
var _opener_tile: Tile = null  # the spinner; the chain splits here (left↓, right↑)

# Route selection: when a clicked tile can go on either end, the player clicks an
# end of the board to choose. Null when nothing is mid-selection.
var _selected_tile: Tile = null
var _pending_moves: Array[Move] = []

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
	_clear_selection()
	_placed = []
	_last_played = null
	_pop_pending = false
	_opener_tile = null
	# The first-round opening double is a forced, choiceless move — play it.
	if _round.has_forced_opener():
		var op := _round.legal_moves()[0]
		_opener_tile = op.tile
		_mark_played(op.tile)
		_round.apply_move(op)
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
	_clear_selection()
	_render()
	while not _round.finished and _round.current == BOT:
		await get_tree().create_timer(BOT_DELAY).timeout
		var moves := _round.legal_moves()
		if moves.is_empty():
			if _variant == Round.Variant.DRAW and not _round.boneyard_empty():
				_round.draw_tile()
				_play("draw")
				_render()
				continue
			_round.pass_turn()
		else:
			var bot_move := _bot.choose_move(_round, BOT)
			if _round.board.is_empty():
				_opener_tile = bot_move.tile
			_mark_played(bot_move.tile)
			_round.apply_move(bot_move)
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


# ---------------------------------------------------------------- player input

func _on_hand_pressed(view: TileView) -> void:
	if _state != State.PLAYER_TURN:
		return
	# Clicking the already-selected tile cancels.
	if _selected_tile != null and view.tile_ref.equals(_selected_tile):
		_clear_selection()
		_render()
		return
	var moves := _moves_for(view.tile_ref)
	if moves.is_empty():
		return  # not playable
	if moves.size() == 1:
		_apply_player_move(moves[0])  # only one end -> play it
	else:
		# Plays on either end — light up both ends and let the player pick one.
		_selected_tile = view.tile_ref
		_pending_moves = moves
		_render()


func _on_end_clicked(_view: TileView, side: int) -> void:
	for m in _pending_moves:
		if m.side == side:
			_apply_player_move(m)
			return


func _apply_player_move(move: Move) -> void:
	_clear_selection()
	if _round.board.is_empty():
		_opener_tile = move.tile
	_mark_played(move.tile)
	_round.apply_move(move)
	_after_player_move()


func _clear_selection() -> void:
	_selected_tile = null
	_pending_moves = []


func _has_pending(side: int) -> bool:
	for m in _pending_moves:
		if m.side == side:
			return true
	return false


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
	if reserve.y > 0.0:
		sz.y += s
	elif reserve.y < 0.0:
		p.y -= s
		sz.y += s
	return p.x >= -0.5 and p.y >= -0.5 and p.x + sz.x <= inner.x + 0.5 and p.y + sz.y <= inner.y + 0.5


# Rebuild the whole board layout from the played sequence as a clean serpentine
# that always fits — recomputed every turn, so an end can never trap itself and
# tiles are always laid end-to-end (never crammed side-by-side).
func _relayout() -> void:
	_placed = []
	var layout: Array = _round.board.layout
	if layout.is_empty():
		return
	var s := tile_theme.half_size
	var c := _field_inner() * 0.5
	var oi := _opener_index(layout)
	var eo: Dictionary = layout[oi]
	var left_anchor: Dictionary
	var right_anchor: Dictionary
	if eo["is_double"]:
		_placed.append({"tile": eo["tile"], "pos": Vector2(c.x - s * 0.5, c.y - s), "size": Vector2(s, 2.0 * s), "a": eo["left_val"], "b": eo["left_val"], "vertical": true})
		left_anchor = {"pos": Vector2(c.x - s * 0.5, c.y), "facing": Vector2(-1, 0), "vertical": true, "h_dir": Vector2(-1, 0), "run": 0}
		right_anchor = {"pos": Vector2(c.x + s * 0.5, c.y), "facing": Vector2(1, 0), "vertical": true, "h_dir": Vector2(1, 0), "run": 0}
	else:
		_placed.append({"tile": eo["tile"], "pos": Vector2(c.x - s, c.y - s * 0.5), "size": Vector2(2.0 * s, s), "a": eo["left_val"], "b": eo["right_val"], "vertical": false})
		left_anchor = {"pos": Vector2(c.x - s, c.y), "facing": Vector2(-1, 0), "vertical": false, "h_dir": Vector2(-1, 0), "run": 0}
		right_anchor = {"pos": Vector2(c.x + s, c.y), "facing": Vector2(1, 0), "vertical": false, "h_dir": Vector2(1, 0), "run": 0}
	# Right of the opener wraps UPWARD; the connecting value is each tile's left.
	var anchor := right_anchor
	for i in range(oi + 1, layout.size()):
		anchor = _place_walk(layout[i], anchor, Vector2(0, -1), layout[i]["left_val"], layout[i]["right_val"])
	# Left of the opener wraps DOWNWARD; walking left, it connects on its right.
	anchor = left_anchor
	for i in range(oi - 1, -1, -1):
		anchor = _place_walk(layout[i], anchor, Vector2(0, 1), layout[i]["right_val"], layout[i]["left_val"])


# Place one tile of the walk and return the new anchor.
func _place_walk(entry: Dictionary, anchor: Dictionary, turn_dir: Vector2, connecting: int, exposed: int) -> Dictionary:
	var d := _layout_dir(anchor, entry["is_double"], turn_dir)
	var geo := _tile_geometry(anchor["pos"], anchor["facing"], d, connecting, exposed, entry["is_double"])
	# Starting a new row (a wrap off a turn): push it an extra half-tile away so the
	# crosswise doubles in either row have clear space and never look stacked.
	if anchor["facing"].y != 0.0 and d.y == 0.0:
		var shift: Vector2 = anchor["facing"] * (tile_theme.half_size * 0.7)
		geo["pos"] = geo["pos"] + shift
		geo["new_anchor"] = geo["new_anchor"] + shift
	_placed.append({"tile": entry["tile"], "pos": geo["pos"], "size": geo["size"], "a": geo["a"], "b": geo["b"], "vertical": geo["vertical"]})
	var new_h: Vector2 = d if d.y == 0.0 else anchor.get("h_dir", anchor["facing"])
	# Count tiles in the current horizontal row; a turn (vertical) starts a new row.
	var new_run := 0
	if d.y == 0.0:
		new_run = (anchor.get("run", 0) + 1) if anchor["facing"].y == 0.0 else 1
	return {"pos": geo["new_anchor"], "facing": geo["new_facing"], "vertical": geo["vertical"], "h_dir": new_h, "run": new_run}


# Where the opener (spinner) sits in the played sequence — the chain splits here.
func _opener_index(layout: Array) -> int:
	if _opener_tile != null:
		for i in range(layout.size()):
			if layout[i]["tile"].equals(_opener_tile):
				return i
	return 0


# Direction for the next tile in the auto-layout walk: continue straight if it
# fits, otherwise turn (toward turn_dir) into a new row; wrap when off a turn.
func _layout_dir(anchor: Dictionary, is_double: bool, turn_dir: Vector2) -> Vector2:
	var f: Vector2 = anchor["facing"]
	if is_double:
		return f
	var dirs: Array
	if f.y == 0.0:
		if anchor.get("vertical", false):
			dirs = [f]  # off a crosswise double, only continue straight
		elif anchor.get("run", 0) >= MAX_RUN:
			dirs = [turn_dir, -turn_dir]  # row is long enough — turn into a new row
		else:
			dirs = [f, turn_dir, -turn_dir]  # straight, preferred turn, then fallback
	else:
		var h: Vector2 = anchor.get("h_dir", Vector2(1, 0))
		dirs = [-h, h]  # wrap back the other way, or keep going
	for d in dirs:
		var geo := _tile_geometry(anchor["pos"], f, d, 0, 0, false)
		if _in_bounds(geo["pos"], geo["size"], d):
			return d
	return dirs[0]


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
	_clear_selection()
	_round.draw_tile()
	_play("draw")
	_render()


func _on_pass_pressed() -> void:
	if _state != State.PLAYER_TURN:
		return
	_clear_selection()
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

	# A hand tile is highlighted if it has a legal move (the auto-layout always fits).
	var playable := {}
	if _state == State.PLAYER_TURN and _round.current == HUMAN:
		for m in _round.legal_moves():
			playable[_tile_key(m.tile)] = true

	# Bot hand: face-down backs.
	_clear(_bot_hand_box)
	for t in _round.hands[BOT].tiles:
		_bot_hand_box.add_child(_make_back(t))

	# Board: re-flow the whole chain into a clean, always-fitting serpentine, then
	# scale + center it. While choosing an end, the two ends light up clickably.
	_relayout()
	_clear(_board_content)
	var choosing := _selected_tile != null
	for i in range(_placed.size()):
		var rec: Dictionary = _placed[i]
		var pick_side := -1
		if choosing and i == 0 and _has_pending(Board.Side.LEFT):
			pick_side = Board.Side.LEFT
		elif choosing and i == _placed.size() - 1 and _has_pending(Board.Side.RIGHT):
			pick_side = Board.Side.RIGHT
		var bview := TileView.new()
		bview.configure(tile_theme, rec["tile"], rec["a"], rec["b"], rec["vertical"], true, pick_side >= 0)
		bview.position = rec["pos"]
		bview.size = rec["size"]
		if pick_side >= 0:
			bview.set_highlighted(true)
			bview.clicked.connect(_on_end_clicked.bind(pick_side))
		_board_content.add_child(bview)
		if _last_played != null and rec["tile"].equals(_last_played):
			bview.set_recent(true)
			if _pop_pending:
				bview.pop_in()
	_pop_pending = false
	_autofit()

	# Player hand: click a highlighted tile to play it (then an end if it fits both).
	_clear(_player_hand_box)
	for t in _round.hands[HUMAN].tiles:
		var hl: bool = playable.has(_tile_key(t)) or (_selected_tile != null and t.equals(_selected_tile))
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
			if _selected_tile != null:
				line3 = "Click an end of the board to play it."
			elif _round.board.is_empty():
				line3 = "Your turn — click a tile to lead."
			elif _round.legal_moves().is_empty():
				line3 = "No legal move — draw a tile." if _draw_button_would_show() else "No legal move — you must pass."
			else:
				line3 = "Your turn — click a highlighted tile to play."
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
