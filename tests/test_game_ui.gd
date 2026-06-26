extends SceneTree

## Smoke test for the presentation layer: instantiate the real game scene, put a
## tile on the board, render, and confirm a tile view actually appears. Guards
## against "the board shows nothing" regressions in the snaking layout.
## Run with: godot --headless --script res://tests/test_game_ui.gd

const STATE_PLAYER_TURN := 1  # game.gd: enum State { SETUP, PLAYER_TURN, ... }


func _initialize() -> void:
	var passed := 0
	var failed := 0

	var scene: Control = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene)
	# In a SceneTree's _initialize the main loop hasn't started, so _ready isn't
	# auto-fired yet; build the UI explicitly for the test.
	scene.call("_ready")

	# A round plus one player-placed tile transform.
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.BLOCK, deck, 0)
	r.board.play(Tile.new(6, 6), Board.Side.LEFT)

	scene.set("_round", r)
	scene.set("_placed", [{"tile": Tile.new(6, 6), "pos": Vector2(10, 10), "size": Vector2(128, 64), "a": 6, "b": 6, "vertical": false}])
	scene.set("_state", STATE_PLAYER_TURN)
	scene.call("_render")

	var board_area: Control = scene.get("_board_area")
	var rendered := board_area.get_child_count()
	if rendered == 1:
		passed += 1
		print("  PASS  the board renders the placed opening tile")
	else:
		failed += 1
		print("  FAIL  expected 1 board tile, got %d" % rendered)

	# No vertical-on-vertical: an end whose last tile is vertical (a turn tile or a
	# crosswise double) must offer only horizontal placements; a horizontal end may
	# also offer a vertical turn. (_round above has board ends [6, 6].)
	scene.set("_anchors", {
		Board.Side.RIGHT: {"pos": Vector2(500, 250), "facing": Vector2(1, 0), "vertical": true},
		Board.Side.LEFT: {"pos": Vector2(150, 250), "facing": Vector2(-1, 0), "vertical": false},
	})
	var cands: Array = scene.call("_candidates_for", Tile.new(6, 3))
	var right_has_vertical := false
	var left_has_vertical := false
	for c in cands:
		if c["dir"].y != 0.0:
			if c["side"] == Board.Side.RIGHT:
				right_has_vertical = true
			else:
				left_has_vertical = true
	if not right_has_vertical:
		passed += 1
		print("  PASS  no vertical placement off a vertical/double end")
	else:
		failed += 1
		print("  FAIL  vertical placement was offered off a vertical end")
	if left_has_vertical:
		passed += 1
		print("  PASS  vertical turn is allowed off a horizontal end")
	else:
		failed += 1
		print("  FAIL  expected a vertical turn option off a horizontal end")

	# Snake wrap: an end that just turned (faces vertical) must still offer a
	# horizontal placement so it never gets stuck against the border.
	scene.set("_anchors", {
		Board.Side.RIGHT: {"pos": Vector2(500, 250), "facing": Vector2(0, -1), "vertical": true, "h_dir": Vector2(1, 0)},
	})
	var wrap_cands: Array = scene.call("_candidates_for", Tile.new(6, 3))
	var has_horizontal := false
	for c in wrap_cands:
		if c["dir"].y == 0.0:
			has_horizontal = true
	if has_horizontal:
		passed += 1
		print("  PASS  a just-turned end offers a horizontal wrap (no border dead end)")
	else:
		failed += 1
		print("  FAIL  just-turned end had no placement (would get stuck at the border)")

	print("\nPassed: %d   Failed: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)
