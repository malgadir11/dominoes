extends SceneTree

## Tests for the serpentine board layout geometry.
## Run with: godot --headless --script res://tests/test_layout.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_wraps_into_rows_and_orients_double()
	print("\n----------------------------------------")
	print("Passed: %d   Failed: %d" % [_passed, _failed])
	print("----------------------------------------")
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  ", label)
	else:
		_failed += 1
		print("  FAIL  ", label)


func _test_wraps_into_rows_and_orients_double() -> void:
	var theme := TileTheme.new()
	var s := theme.half_size  # tile is 2s wide, s tall; double is s wide, 2s tall

	# A 7-tile chain ending in a double.
	var b := Board.new()
	b.play(Tile.new(1, 2), Board.Side.LEFT)
	b.play(Tile.new(2, 3), Board.Side.RIGHT)
	b.play(Tile.new(3, 4), Board.Side.RIGHT)
	b.play(Tile.new(4, 5), Board.Side.RIGHT)
	b.play(Tile.new(5, 6), Board.Side.RIGHT)
	b.play(Tile.new(6, 0), Board.Side.RIGHT)
	b.play(Tile.new(0, 0), Board.Side.RIGHT)  # double on the open 0

	var max_width := s * 2.0 * 2.0 + 10.0  # room for ~2 full tiles per row
	var info := BoardLayout.compute(b.layout, theme, max_width)
	var placements: Array = info["placements"]
	var size: Vector2 = info["size"]

	_check(placements.size() == 7, "every tile gets a placement")
	_check(size.x <= max_width + 0.01, "content stays within the max width")
	_check(size.y > s * 2.0 + 0.01, "a long chain wraps onto more than one row")

	var first: Dictionary = placements[0]
	_check(not first["vertical"] and first["size"] == Vector2(s * 2.0, s) and first["pos"] == Vector2(0, s - s * 0.5),
		"first tile is horizontal at the row's start")

	var last: Dictionary = placements[6]
	_check(last["vertical"] and last["size"] == Vector2(s, s * 2.0),
		"the closing double is laid crosswise (vertical, half width)")
