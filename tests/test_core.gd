extends SceneTree

## Headless tests for the core data model (Tile, Deck, Hand).
## Run from the project folder with:
##   godot --headless --script res://tests/test_core.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_tile_normalizes()
	_test_tile_double_and_pips()
	_test_tile_other_end()
	_test_deck_has_28_unique_tiles()
	_test_deck_draw_shrinks()
	_test_seeded_shuffle_is_deterministic()
	_test_hand_pip_total()
	_test_hand_playable_tiles()
	_test_hand_empty_board_plays_anything()
	_test_hand_highest_double()

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


func _test_tile_normalizes() -> void:
	var t := Tile.new(5, 2)
	_check(t.low == 2 and t.high == 5, "tile normalizes [5,2] to low=2 high=5")


func _test_tile_double_and_pips() -> void:
	var d := Tile.new(4, 4)
	var n := Tile.new(6, 1)
	_check(d.is_double() and not n.is_double(), "is_double detects doubles")
	_check(d.pip_total() == 8 and n.pip_total() == 7, "pip_total sums both ends")


func _test_tile_other_end() -> void:
	var t := Tile.new(2, 6)
	_check(t.other_end(2) == 6, "other_end(2) on [2|6] is 6")
	_check(t.other_end(6) == 2, "other_end(6) on [2|6] is 2")
	_check(t.other_end(3) == -1, "other_end of a value not on the tile is -1")


func _test_deck_has_28_unique_tiles() -> void:
	var deck := Deck.new()
	_check(deck.size() == 28, "double-six deck has 28 tiles")
	var seen := {}
	for t in deck.tiles:
		seen[str(t)] = true
	_check(seen.size() == 28, "all 28 tiles are unique")


func _test_deck_draw_shrinks() -> void:
	var deck := Deck.new()
	var t := deck.draw()
	_check(t != null and deck.size() == 27, "draw returns a tile and shrinks the deck")


func _test_seeded_shuffle_is_deterministic() -> void:
	var a := Deck.new()
	var b := Deck.new()
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 12345
	rng_b.seed = 12345
	a.shuffle_deck(rng_a)
	b.shuffle_deck(rng_b)
	var same := true
	for i in range(a.size()):
		if not a.tiles[i].equals(b.tiles[i]):
			same = false
			break
	_check(same, "same seed produces the same shuffle")


func _test_hand_pip_total() -> void:
	var h := Hand.new()
	h.add(Tile.new(6, 6))
	h.add(Tile.new(3, 1))
	_check(h.pip_total() == 16, "hand pip_total sums all tiles (12 + 4)")


func _test_hand_playable_tiles() -> void:
	var h := Hand.new()
	h.add(Tile.new(6, 2))
	h.add(Tile.new(3, 3))
	h.add(Tile.new(0, 1))
	var playable := h.playable_tiles([2, 5])
	_check(playable.size() == 1 and playable[0].equals(Tile.new(6, 2)),
		"only the tile matching an open end is playable")
	_check(h.has_playable([2, 5]) and not h.has_playable([4, 5]),
		"has_playable reflects whether any tile matches")


func _test_hand_empty_board_plays_anything() -> void:
	var h := Hand.new()
	h.add(Tile.new(6, 2))
	h.add(Tile.new(3, 3))
	_check(h.playable_tiles([]).size() == 2, "empty board makes every tile playable")


func _test_hand_highest_double() -> void:
	var h := Hand.new()
	h.add(Tile.new(2, 2))
	h.add(Tile.new(5, 5))
	h.add(Tile.new(6, 1))
	var hd := h.highest_double()
	_check(hd != null and hd.equals(Tile.new(5, 5)), "highest_double finds [5|5]")
