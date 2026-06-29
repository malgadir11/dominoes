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

	print("\nPassed: %d   Failed: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)
