extends SceneTree

## Headless tests for the round engine (Board, Move, Round, RoundResult).
## Run with: godot --headless --script res://tests/test_round.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_board_first_tile_sets_both_ends()
	_test_board_play_updates_end()
	_test_board_rejects_illegal()
	_test_board_layout_touches_and_flags_doubles()
	_test_deal_sizes_and_boneyard()
	_test_first_round_opener_is_forced_double()
	_test_domino_win_scoring()
	_test_block_win_scoring()
	_test_autoplay_finishes_and_conserves_tiles()

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


func _find_move(moves: Array, tile: Tile) -> Move:
	for m in moves:
		if m.tile.equals(tile):
			return m
	return null


func _test_board_first_tile_sets_both_ends() -> void:
	var b := Board.new()
	b.play(Tile.new(6, 4), Board.Side.LEFT)
	_check(b.left_end == 4 and b.right_end == 6, "first tile [6|4] sets ends to 4 and 6")
	var b2 := Board.new()
	b2.play(Tile.new(5, 5), Board.Side.LEFT)
	_check(b2.open_ends() == [5], "first double [5|5] yields a single open end of 5")


func _test_board_play_updates_end() -> void:
	var b := Board.new()
	b.play(Tile.new(6, 4), Board.Side.LEFT)  # ends 4 | 6
	b.play(Tile.new(6, 3), Board.Side.RIGHT)  # connect on 6, expose 3
	_check(b.right_end == 3, "playing [6|3] on the 6 end exposes 3")
	b.play(Tile.new(4, 0), Board.Side.LEFT)  # connect on 4, expose 0
	_check(b.left_end == 0, "playing [4|0] on the 4 end exposes 0")
	_check(b.chain.size() == 3, "chain has three tiles")


func _test_board_rejects_illegal() -> void:
	var b := Board.new()
	b.play(Tile.new(6, 4), Board.Side.LEFT)  # ends 4 | 6
	var ok := b.play(Tile.new(2, 1), Board.Side.LEFT)
	_check(not ok, "a tile matching neither end is rejected")


func _test_board_layout_touches_and_flags_doubles() -> void:
	var b := Board.new()
	b.play(Tile.new(6, 4), Board.Side.LEFT)   # ends 4 | 6
	b.play(Tile.new(6, 3), Board.Side.RIGHT)  # on the 6
	b.play(Tile.new(4, 0), Board.Side.LEFT)   # on the 4
	b.play(Tile.new(3, 3), Board.Side.RIGHT)  # a double on the 3

	var touching := true
	for i in range(b.layout.size() - 1):
		if b.layout[i]["right_val"] != b.layout[i + 1]["left_val"]:
			touching = false
	_check(touching, "every adjacent pair in the layout has matching numbers touching")

	var dbl: Dictionary = b.layout[b.layout.size() - 1]
	_check(dbl["is_double"] and dbl["left_val"] == 3 and dbl["right_val"] == 3,
		"the played double is flagged for crosswise layout with both halves equal")


func _test_deal_sizes_and_boneyard() -> void:
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.DRAW, deck)
	_check(r.hands[0].size() == 7 and r.hands[1].size() == 7, "two players each receive 7 tiles")
	_check(r.boneyard.size() == 14, "boneyard holds the remaining 14 tiles")


func _test_first_round_opener_is_forced_double() -> void:
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.DRAW, deck)
	var moves := r.legal_moves()
	_check(moves.size() == 1, "opener has exactly one forced opening move")
	_check(moves[0].tile.is_double(), "the forced opening tile is a double")
	_check(r.hands[r.current].tiles.has(moves[0].tile), "the forced tile is in the opener's hand")


func _test_domino_win_scoring() -> void:
	var p0 := Hand.new()
	p0.add(Tile.new(0, 1))
	var p1 := Hand.new()
	p1.add(Tile.new(5, 5))
	var r := Round.from_state([p0, p1], Round.Variant.BLOCK, Deck.new(-1), 0)
	var moves := r.legal_moves()
	r.apply_move(moves[0])  # P0 plays its only tile and goes out
	_check(r.finished and r.result.winner == 0, "going out wins the round")
	_check(r.result.win_type == Round.WinType.DOMINO, "win type is domino")
	_check(r.result.score == 10, "winner scores opponent's [5|5] = 10")


func _test_block_win_scoring() -> void:
	var p0 := Hand.new()
	p0.add(Tile.new(0, 0))
	p0.add(Tile.new(1, 1))
	var p1 := Hand.new()
	p1.add(Tile.new(2, 2))
	p1.add(Tile.new(3, 3))
	var r := Round.from_state([p0, p1], Round.Variant.BLOCK, Deck.new(-1), 0)

	# P0 leads with [0|0]; nobody can ever connect, so the round blocks out.
	var lead := _find_move(r.legal_moves(), Tile.new(0, 0))
	r.apply_move(lead)
	_check(r.legal_moves().is_empty(), "P1 has no legal reply")
	r.pass_turn()  # P1 passes
	_check(r.legal_moves().is_empty(), "P0 cannot play [1|1] either")
	r.pass_turn()  # P0 passes -> two passes in a row -> blocked

	_check(r.finished and r.result.win_type == Round.WinType.BLOCK, "round ends blocked")
	_check(r.result.winner == 0, "fewest pips (P0 holds 2) wins")
	# Opponents' pips (4 + 6 = 10) minus winner's own (2) = 8.
	_check(r.result.score == 8, "block score is opponents' pips minus winner's own (8)")


func _test_autoplay_finishes_and_conserves_tiles() -> void:
	var all_finished := true
	var tiles_conserved := true
	var valid_results := true
	var rng := RandomNumberGenerator.new()
	# Run many seeded games to shake out edge cases in both variants.
	for s in range(200):
		var variant: int = Round.Variant.DRAW if s % 2 == 0 else Round.Variant.BLOCK
		var deck := Deck.new()
		rng.seed = s
		deck.shuffle_deck(rng)
		var r := Round.deal(2, 7, variant, deck)
		var res := r.autoplay(rng)
		if not r.finished or res == null:
			all_finished = false
		if res != null and (res.winner < 0 or res.winner >= 2 or res.score < 0):
			valid_results = false
		var total := r.boneyard.size() + r.board.chain.size()
		for h in r.hands:
			total += h.size()
		if total != 28:
			tiles_conserved = false
	_check(all_finished, "200 random rounds all reach a result")
	_check(valid_results, "every result has a valid winner and non-negative score")
	_check(tiles_conserved, "all 28 tiles are always accounted for (hands + board + boneyard)")
