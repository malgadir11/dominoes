extends SceneTree

## Tests for the AI. The headline test is a bot-vs-bot tournament proving that
## stronger tiers actually win more often — measurable difficulty, not labels.
## Run with: godot --headless --script res://tests/test_ai.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_bot_returns_legal_move()
	_test_bot_prefers_known_void_end()
	_test_tiers_separate_by_winrate()

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


# Drive one full round between two bots; return the winning player index.
func _play_round(bots: Array, variant: int, game_seed: int) -> int:
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, variant, deck)
	var guard := 0
	while not r.finished and guard < 2000:
		guard += 1
		var moves := r.legal_moves()
		if moves.is_empty():
			if variant == Round.Variant.DRAW and not r.boneyard_empty():
				r.draw_tile()
			else:
				r.pass_turn()
		else:
			r.apply_move(bots[r.current].choose_move(r, r.current))
	return r.result.winner if r.result != null else -1


# Play a match to `target` points between two bots. Winner of each round opens
# the next; the first round opener is forced (highest double). Returns the
# winning seat. This mirrors the real match layer (step 4) we'll build next.
func _play_match(bots: Array, variant: int, target: int, rng: RandomNumberGenerator) -> int:
	var scores := [0, 0]
	var opener := -1  # first round: highest double opens
	while scores[0] < target and scores[1] < target:
		var deck := Deck.new()
		deck.shuffle_deck(rng)
		var r := Round.deal(2, 7, variant, deck, opener)
		var guard := 0
		while not r.finished and guard < 2000:
			guard += 1
			var moves := r.legal_moves()
			if moves.is_empty():
				if variant == Round.Variant.DRAW and not r.boneyard_empty():
					r.draw_tile()
				else:
					r.pass_turn()
			else:
				r.apply_move(bots[r.current].choose_move(r, r.current))
		scores[r.result.winner] += r.result.score
		opener = r.result.winner
	return 0 if scores[0] >= target else 1


# Match win rate of bot A over many matches; seat rotates to cancel any edge.
func _winrate(diff_a: int, diff_b: int, matches: int, variant: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a_wins := 0
	for g in range(matches):
		var a_seat := g % 2
		var bots := [null, null]
		bots[a_seat] = Bot.new(diff_a, rng)
		bots[1 - a_seat] = Bot.new(diff_b, rng)
		if _play_match(bots, variant, 75, rng) == a_seat:
			a_wins += 1
	return float(a_wins) / float(matches)


func _test_bot_returns_legal_move() -> void:
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.BLOCK, deck)
	var bot := Bot.new(Bot.Difficulty.HARD, rng)
	var m := bot.choose_move(r, r.current)
	var legal := r.legal_moves()
	var found := false
	for lm in legal:
		if lm.tile.equals(m.tile) and lm.side == m.side:
			found = true
	_check(found, "HARD bot returns a move that is in the legal set")


func _test_bot_prefers_known_void_end() -> void:
	# Opponent (P1) passed facing ends [3,3], so it holds no 3s. The expert,
	# choosing between exposing a 3 (opponent can't answer) or a 5, should pick
	# the 3 to keep the board locked against P1.
	var p0 := Hand.new()
	p0.add(Tile.new(2, 3))  # played on the open 2 -> exposes a 3 (opponent void)
	p0.add(Tile.new(2, 5))  # played on the open 2 -> exposes a 5
	var p1 := Hand.new()
	p1.add(Tile.new(6, 6))
	var r := Round.from_state([p0, p1], Round.Variant.BLOCK, Deck.new(-1), 0)
	# Seed the board with a [2|2] lead and a recorded P1 pass against ends [3,3].
	r.board.play(Tile.new(2, 2), Board.Side.LEFT)
	r.history.append({"type": "pass", "player": 1, "ends": [3, 3]})

	var bot := Bot.new(Bot.Difficulty.EXPERT, RandomNumberGenerator.new())
	var m := bot.choose_move(r, 0)
	_check(m.tile.equals(Tile.new(2, 3)), "EXPERT exposes the value the opponent can't play")


func _test_tiers_separate_by_winrate() -> void:
	var matches := 300
	var v := Round.Variant.BLOCK  # block expresses skill more cleanly than draw

	var hard_vs_easy := _winrate(Bot.Difficulty.HARD, Bot.Difficulty.EASY, matches, v)
	var med_vs_easy := _winrate(Bot.Difficulty.MEDIUM, Bot.Difficulty.EASY, matches, v)
	var hard_vs_med := _winrate(Bot.Difficulty.HARD, Bot.Difficulty.MEDIUM, matches, v)
	var exp_vs_hard := _winrate(Bot.Difficulty.EXPERT, Bot.Difficulty.HARD, matches, v)

	print("    match win rates over %d matches to 75 (block):" % matches)
	print("      HARD   vs EASY   = %.1f%%" % (hard_vs_easy * 100))
	print("      MEDIUM vs EASY   = %.1f%%" % (med_vs_easy * 100))
	print("      HARD   vs MEDIUM = %.1f%%" % (hard_vs_med * 100))
	print("      EXPERT vs HARD   = %.1f%%" % (exp_vs_hard * 100))

	_check(hard_vs_easy > 0.65, "HARD beats EASY decisively")
	_check(med_vs_easy > 0.55, "MEDIUM beats EASY")
	_check(hard_vs_med > 0.52, "HARD edges out MEDIUM")
	_check(exp_vs_hard >= 0.50, "EXPERT is at least as strong as HARD")
