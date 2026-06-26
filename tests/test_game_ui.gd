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

	print("\nPassed: %d   Failed: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)
