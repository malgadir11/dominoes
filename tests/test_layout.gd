extends SceneTree

## Tests for the corner-snaking board layout.
## Run with: godot --headless --script res://tests/test_layout.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_snakes_with_corners()
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


func _test_snakes_with_corners() -> void:
	var theme := TileTheme.new()
	var s := theme.half_size

	# A long straight chain (0-0 opener double, then a run of singles) that must
	# wrap several times within a narrow width.
	var b := Board.new()
	b.play(Tile.new(0, 0), Board.Side.LEFT)   # opening double
	for v in range(1, 7):
		b.play(Tile.new(0, v), Board.Side.RIGHT)  # 0-1, 0-2 ... extends the line
		b.play(Tile.new(v, 0), Board.Side.RIGHT)

	var max_width := s * 2.0 * 3.0 + 4.0  # room for ~3 horizontal tiles per row
	var info := BoardLayout.compute(b.layout, theme, max_width)
	var placements: Array = info["placements"]
	var size: Vector2 = info["size"]

	_check(placements.size() == b.layout.size(), "every tile gets a placement")
	_check(size.x > 0.0 and size.y > 0.0, "content has a positive size")

	# The opener double is drawn crosswise (vertical).
	_check(placements[0]["vertical"], "the opening double is laid crosswise")

	# It must wrap onto multiple rows...
	var rows := {}
	for pl in placements:
		rows[roundi(pl["pos"].y)] = true
	_check(rows.size() >= 3, "the chain wraps onto several rows")

	# ...and the turns are real vertical corner tiles (not just stacked rows).
	var corners := 0
	for i in range(placements.size()):
		var pl: Dictionary = placements[i]
		if pl["vertical"] and not b.layout[i]["is_double"]:
			corners += 1
	_check(corners >= 1, "non-double tiles are rotated at the corners")
