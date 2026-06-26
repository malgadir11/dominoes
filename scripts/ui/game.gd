extends Control

## The playable "Play vs Bots" screen: a setup panel, then a board you play on
## by clicking tiles. This is the FILLER presentation layer — placeholder layout
## built in code so it is easy to replace later with a designed scene. All tile
## art comes from `tile_theme`; all rules come from the headless engine. The two
## are kept apart on purpose.
##
## TODO (later polish): choosing which open end to attach a tile to (currently
## auto-picks the first legal side), a snaking/wrapping board layout, drag option,
## animations, and wiring the other main-menu screens.

const TARGET_SCORE := 75
const HUMAN := 0
const BOT := 1
const BOT_DELAY := 0.55  # seconds, so the bot's moves are readable

enum State { SETUP, PLAYER_TURN, BOT_TURN, ROUND_OVER, MATCH_OVER }

## Assign a custom TileTheme here in the Inspector to reskin everything.
@export var tile_theme: TileTheme
## The board snakes to stay within this width (flexible; also capped to the
## window). Raise it for a wider table, lower it for a tighter ring.
@export var board_max_width: float = 880.0

var _state: int = State.SETUP
var _variant: int = Round.Variant.DRAW
var _bot: Bot
var _round: Round
var _scores := [0, 0]
var _opener := -1
var _status_extra := ""

# Placement selection: when a clicked tile can go on either end, the player picks
# the route. Null when nothing is mid-placement.
var _selected_tile: Tile = null
var _pending_moves: Array[Move] = []

# Polish: the most recently played tile (highlighted + pop-animated once).
var _last_played: Tile = null
var _pop_pending := false

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
var _player_hand_box: HBoxContainer
var _draw_button: Button
var _pass_button: Button
var _next_button: Button
var _left_end_button: Button
var _right_end_button: Button
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

	# Board: a centered area we position tiles into absolutely, so the chain can
	# snake within a flexible width instead of growing sideways forever.
	var board_center := CenterContainer.new()
	col.add_child(board_center)
	_board_area = Control.new()
	board_center.add_child(_board_area)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer_bottom)

	_player_hand_box = _centered_hbox()
	col.add_child(_player_hand_box)

	var actions := _centered_hbox()
	col.add_child(actions)
	_left_end_button = _big_button("")
	_left_end_button.pressed.connect(_on_zone_pressed.bind(Board.Side.LEFT))
	actions.add_child(_left_end_button)
	_right_end_button = _big_button("")
	_right_end_button.pressed.connect(_on_zone_pressed.bind(Board.Side.RIGHT))
	actions.add_child(_right_end_button)
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
	_last_played = null
	_pop_pending = false
	# The first-round opening double is a forced, choiceless move — play it
	# automatically so the board always starts with a tile in the center.
	if _round.has_forced_opener():
		var opening := _round.legal_moves()[0]
		_mark_played(opening.tile)
		_round.apply_move(opening)
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
			_mark_played(bot_move.tile)
			_round.apply_move(bot_move)
		_render()
	if _round.finished:
		_finish_round()
	else:
		_state = State.PLAYER_TURN
		_render()


func _on_player_tile_clicked(view: TileView) -> void:
	if _state != State.PLAYER_TURN:
		return
	# Clicking the already-selected tile cancels the route choice.
	if _selected_tile != null and view.tile_ref.equals(_selected_tile):
		_clear_selection()
		_render()
		return
	var moves := _moves_for(view.tile_ref)
	if moves.is_empty():
		return  # not playable
	if moves.size() == 1:
		_apply_player_move(moves[0])  # only one spot -> place immediately
	else:
		# Two routes (both ends): let the player click a board end to choose.
		_selected_tile = view.tile_ref
		_pending_moves = moves
		_render()


func _on_zone_pressed(side: int) -> void:
	if _selected_tile == null:
		return
	for m in _pending_moves:
		if m.side == side:
			_apply_player_move(m)
			return


func _apply_player_move(move: Move) -> void:
	_clear_selection()
	_mark_played(move.tile)
	_round.apply_move(move)
	if _round.finished:
		_finish_round()
	else:
		_run_bot()


func _mark_played(tile: Tile) -> void:
	_last_played = tile
	_pop_pending = true
	_play("place")


func _clear_selection() -> void:
	_selected_tile = null
	_pending_moves = []


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

	var legal := _player_legal_moves()
	var playable := {}
	for m in legal:
		playable[_tile_key(m.tile)] = true

	# Bot hand: face-down backs.
	_clear(_bot_hand_box)
	for t in _round.hands[BOT].tiles:
		_bot_hand_box.add_child(_make_back(t))

	# Board: snakes within a flexible width; matching numbers touch; doubles laid
	# crosswise. While choosing a route, the relevant end tile is clickable/lit.
	_clear(_board_area)
	var choosing := _selected_tile != null
	var info := BoardLayout.compute(_round.board.layout, tile_theme, _resolved_board_width())
	var placements: Array = info["placements"]
	_board_area.custom_minimum_size = info["size"]
	for i in range(placements.size()):
		var is_left_end := i == 0
		var is_right_end := i == placements.size() - 1
		var pick_side := -1
		if choosing and is_left_end and _has_pending_side(Board.Side.LEFT):
			pick_side = Board.Side.LEFT
		elif choosing and is_right_end and _has_pending_side(Board.Side.RIGHT):
			pick_side = Board.Side.RIGHT
		var view := _make_board_view(placements[i], pick_side)
		_board_area.add_child(view)
		# Highlight the most recently played tile; pop it once when freshly placed.
		if _last_played != null and view.tile_ref.equals(_last_played):
			view.set_recent(true)
			if _pop_pending:
				view.pop_in()
	_pop_pending = false

	# Player hand: playable tiles highlighted, the selected one too.
	_clear(_player_hand_box)
	for t in _round.hands[HUMAN].tiles:
		var hl: bool = playable.has(_tile_key(t)) or (_selected_tile != null and t.equals(_selected_tile))
		var view := _make_hand_tile(t, hl)
		view.clicked.connect(_on_player_tile_clicked)
		_player_hand_box.add_child(view)

	var stuck: bool = _state == State.PLAYER_TURN and legal.is_empty()
	_draw_button.visible = stuck and _variant == Round.Variant.DRAW and not _round.boneyard_empty()
	_pass_button.visible = stuck and not _draw_button.visible
	var over: bool = _state == State.ROUND_OVER or _state == State.MATCH_OVER
	_next_button.visible = over
	_next_button.text = "New match" if _state == State.MATCH_OVER else "Next round"
	if not over:
		_banner.visible = false

	# Route-choice buttons (in addition to clicking the lit end tile on the board).
	_left_end_button.visible = choosing and _has_pending_side(Board.Side.LEFT)
	_left_end_button.text = "◂ play on %d" % _round.board.left_end
	_right_end_button.visible = choosing and _has_pending_side(Board.Side.RIGHT)
	_right_end_button.text = "play on %d ▸" % _round.board.right_end


func _has_pending_side(side: int) -> bool:
	for m in _pending_moves:
		if m.side == side:
			return true
	return false


func _status_text() -> String:
	var ends := _round.board.open_ends()
	var ends_str := "—" if ends.is_empty() else str(ends)
	var line1 := "You %d   ·   Bot %d   (first to %d)" % [_scores[HUMAN], _scores[BOT], TARGET_SCORE]
	var line2 := "Open ends: %s    Boneyard: %d" % [ends_str, _round.boneyard.size()]
	var line3 := ""
	match _state:
		State.PLAYER_TURN:
			if _selected_tile != null:
				line3 = "Click an end of the board to place your tile."
			elif _player_legal_moves().is_empty():
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


## Build one absolutely-positioned board tile from a layout placement. If
## pick_side >= 0 this tile is a selectable chain end: it lights up and clicking
## it places the held tile there.
func _make_board_view(p: Dictionary, pick_side: int) -> TileView:
	var view := TileView.new()
	view.configure(tile_theme, p["tile"], p["a"], p["b"], p["vertical"], true, pick_side >= 0)
	view.position = p["pos"]
	view.size = p["size"]
	if pick_side >= 0:
		view.set_highlighted(true)
		view.clicked.connect(_on_board_end_clicked.bind(pick_side))
	return view


func _on_board_end_clicked(_view: TileView, side: int) -> void:
	_on_zone_pressed(side)


func _resolved_board_width() -> float:
	var vp_w := get_viewport_rect().size.x
	var available := (vp_w - 160.0) if vp_w > 0.0 else board_max_width
	return clampf(minf(board_max_width, available), 320.0, 4000.0)


func _tile_key(t: Tile) -> int:
	return t.low * 7 + t.high


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
