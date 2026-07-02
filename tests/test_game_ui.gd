extends SceneTree

## Tests for the presentation layer: that the board renders, and that the
## auto-layout (_relayout / _layout_dir) keeps a full 28-tile chain inside the
## field even when it all stacks on one end.
## Run with: godot --headless --script res://tests/test_game_ui.gd

const STATE_PLAYER_TURN := 1  # game.gd: enum State { SETUP, PLAYER_TURN, ... }


func _initialize() -> void:
	var passed := 0
	var failed := 0

	var scene: Control = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene)
	scene.call("_ready")  # main loop hasn't started, so fire _ready explicitly

	# Render: a round with one tile on the board should re-flow into one tile view.
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.BLOCK, deck, 0)
	r.board.play(Tile.new(6, 6), Board.Side.LEFT)
	scene.set("_round", r)
	scene.set("_state", STATE_PLAYER_TURN)
	scene.call("_render")

	var content: Control = scene.get("_board_content")
	if content.get_child_count() == 1:
		passed += 1
		print("  PASS  the board re-flows and renders the played tile")
	else:
		failed += 1
		print("  FAIL  expected 1 board tile, got %d" % content.get_child_count())

	# Capacity: walk the auto-layout greedily for a full 28-tile chain on one end
	# and confirm every tile stays in bounds (the field never overflows).
	var theme: TileTheme = scene.get("tile_theme")
	var bs: float = theme.half_size
	var cen: Vector2 = scene.call("_field_inner") * 0.5
	var anchor := {"pos": Vector2(cen.x + bs, cen.y), "facing": Vector2(1, 0), "vertical": false, "h_dir": Vector2(1, 0), "run": 0}
	var placed := 1  # the opener
	for i in range(27):
		var d: Vector2 = scene.call("_layout_dir", anchor, false, Vector2(0, -1))  # right side wraps up
		var geo: Dictionary = scene.call("_tile_geometry", anchor["pos"], anchor["facing"], d, 0, 0, false)
		if not scene.call("_in_bounds", geo["pos"], geo["size"], d):
			break  # no in-bounds room left
		placed += 1
		var nh: Vector2 = d if d.y == 0.0 else anchor["h_dir"]
		var nr := 0
		if d.y == 0.0:
			nr = (int(anchor["run"]) + 1) if anchor["facing"].y == 0.0 else 1
		anchor = {"pos": geo["new_anchor"], "facing": geo["new_facing"], "vertical": geo["vertical"], "h_dir": nh, "run": nr}
	if placed >= 28:
		passed += 1
		print("  PASS  all 28 tiles fit in the field even piled on one end")
	else:
		failed += 1
		print("  FAIL  only %d tiles fit before running out of room" % placed)

	# End mapping: the highlighted clickable ends must be the PHYSICAL ends of the
	# chain. _placed is ordered [opener, right-walk…, left-walk…], so the ends are
	# not index 0 / size-1 — _relayout tracks _left_end_idx / _right_end_idx. With
	# an opener in the middle of the chain, those must point at layout[0] (left) and
	# layout[last] (right). Regression for the "can't play on the right end" bug.
	var r2 := Round.deal(2, 7, Round.Variant.BLOCK, deck, 0)
	var b: Board = r2.board
	b.play(Tile.new(3, 3), Board.Side.LEFT)   # opener (board empty)
	b.play(Tile.new(3, 5), Board.Side.RIGHT)
	b.play(Tile.new(3, 2), Board.Side.LEFT)
	b.play(Tile.new(5, 6), Board.Side.RIGHT)  # layout: [2|3][3|3][3|5][5|6]
	scene.set("_round", r2)
	scene.set("_opener_tile", Tile.new(3, 3))  # opener sits in the middle
	scene.call("_relayout")
	var pl: Array = scene.get("_placed")
	var li: int = scene.get("_left_end_idx")
	var ri: int = scene.get("_right_end_idx")
	var lay: Array = b.layout
	var left_ok: bool = pl[li]["tile"].equals(lay[0]["tile"])
	var right_ok: bool = pl[ri]["tile"].equals(lay[lay.size() - 1]["tile"])
	if left_ok and right_ok and li != ri:
		passed += 1
		print("  PASS  highlighted ends map to the physical left/right chain ends")
	else:
		failed += 1
		print("  FAIL  end mapping wrong (left_ok=%s right_ok=%s li=%d ri=%d)" % [left_ok, right_ok, li, ri])

	# Physical connection: every consecutive pair in the chain must be laid flush
	# edge-to-edge in the RENDERED layout — no gaps, no overlaps — no matter how far
	# the snake wraps. Regression for "pieces stop connecting after a while" (the
	# corner gaps that accumulated once the chain turned several times).
	var deck3 := Deck.new()
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 7
	deck3.shuffle_deck(rng3)
	var r3 := Round.deal(2, 7, Round.Variant.DRAW, deck3, 0)
	var opener3: Tile = null
	if r3.has_forced_opener():
		var op3: Move = r3.legal_moves()[0]
		opener3 = op3.tile
		r3.apply_move(op3)
	for _i in range(200):
		if r3.finished:
			break
		var mv := r3.legal_moves()
		if mv.is_empty():
			if not r3.boneyard_empty():
				r3.draw_tile()
			else:
				r3.pass_turn()
			continue
		r3.apply_move(mv[0])
	scene.set("_round", r3)
	scene.set("_opener_tile", opener3)
	scene.call("_relayout")
	var pl3: Array = scene.get("_placed")
	var lay3: Array = r3.board.layout
	var by_key := {}
	for rec in pl3:
		by_key[rec["tile"].low * 7 + rec["tile"].high] = rec
	var disconnects := 0
	var worst := 0.0
	for k in range(lay3.size() - 1):
		var ta: Tile = lay3[k]["tile"]
		var tb: Tile = lay3[k + 1]["tile"]
		var ra: Dictionary = by_key[ta.low * 7 + ta.high]
		var rb: Dictionary = by_key[tb.low * 7 + tb.high]
		var gap: float = _edge_gap(ra["pos"], ra["size"], rb["pos"], rb["size"])
		if gap > 0.6:  # more than ~1px of separation (or overlap) = not flush
			disconnects += 1
			worst = maxf(worst, gap)
	if disconnects == 0:
		passed += 1
		print("  PASS  all %d chain joints are flush across %d wraps" % [lay3.size() - 1, lay3.size()])
	else:
		failed += 1
		print("  FAIL  %d of %d joints not flush (worst gap/overlap %.1fpx)" % [disconnects, lay3.size() - 1, worst])

	# Coach mode: with coaching on and a playable hand, the recommended tile is
	# marked and the explanation line is filled in.
	var cp0 := Hand.new()
	cp0.add(Tile.new(6, 2))
	cp0.add(Tile.new(3, 4))
	var cp1 := Hand.new()
	cp1.add(Tile.new(5, 5))
	var cr := Round.from_state([cp0, cp1], Round.Variant.DRAW, Deck.new(-1), 0)
	cr.board.play(Tile.new(6, 6), Board.Side.LEFT)
	scene.set("_round", cr)
	scene.set("_opener_tile", Tile.new(6, 6))
	scene.set("_state", STATE_PLAYER_TURN)
	scene.set("_coach_enabled", true)
	scene.set("_coach_bot", Bot.new(Bot.Difficulty.EXPERT))
	scene.call("_render")
	var coach_label: Label = scene.get("_coach_label")
	var marked := false
	for v in scene.get("_player_hand_box").get_children():
		if v.coach and v.tile_ref.equals(Tile.new(6, 2)):
			marked = true
	if marked and not coach_label.text.is_empty():
		passed += 1
		print("  PASS  coach marks the recommended tile and explains the choice")
	else:
		failed += 1
		print("  FAIL  coach hint missing (marked=%s text='%s')" % [marked, coach_label.text])

	# Leave game: mid-match, the temp top-left button returns to the setup screen.
	scene.call("_on_leave_pressed")
	var setup_visible: bool = scene.get("_setup_root").visible
	var game_hidden: bool = not scene.get("_game_root").visible
	if setup_visible and game_hidden and int(scene.get("_state")) == 0:  # State.SETUP
		passed += 1
		print("  PASS  leave game returns to the setup screen")
	else:
		failed += 1
		print("  FAIL  leave game didn't reach setup (setup=%s game_hidden=%s state=%s)" % [setup_visible, game_hidden, scene.get("_state")])

	print("\nPassed: %d   Failed: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)


# Distance two tile rectangles are from being laid flush edge-to-edge: 0 when they
# share an edge exactly, positive for a gap between them OR an interior overlap.
func _edge_gap(ap: Vector2, asz: Vector2, bp: Vector2, bsz: Vector2) -> float:
	var ox: float = minf(ap.x + asz.x, bp.x + bsz.x) - maxf(ap.x, bp.x)  # >0 overlap, <0 gap
	var oy: float = minf(ap.y + asz.y, bp.y + bsz.y) - maxf(ap.y, bp.y)
	if ox > 0.0 and oy > 0.0:
		return minf(ox, oy)  # rectangles overlap in 2D — penetration depth
	return maxf(-ox, -oy)    # otherwise the separation (0 when flush)
