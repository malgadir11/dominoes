extends SceneTree

## Tests for the AI. The headline test is a bot-vs-bot tournament proving that
## stronger tiers actually win more often — measurable difficulty, not labels.
## Run with: godot --headless --script res://tests/test_ai.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_bot_returns_legal_move()
	_test_bot_prefers_known_void_end()
	_test_draw_void_inference()
	_test_expert_endgame_solver()
	_test_rank_moves_explanations()
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


func _test_expert_endgame_solver() -> void:
	# Boneyard empty, 2P: every unseen tile IS the opponent's hand, so EXPERT
	# calculates the rest of the round exactly. Position — board ends (1, 4);
	# me [1|2] + [4|6]; opponent [3|3] only. The opponent can never answer, so
	# with perfect play I go out and collect their 6 pips: the top-ranked move
	# must be a solved line with value +6, and choose_move must play it.
	var p0 := Hand.new()
	p0.add(Tile.new(1, 2))
	p0.add(Tile.new(4, 6))
	var p1 := Hand.new()
	p1.add(Tile.new(3, 3))
	var r := Round.from_state([p0, p1], Round.Variant.DRAW, Deck.new(-1), 0)
	r.board.play(Tile.new(1, 4), Board.Side.LEFT)  # ends (1, 4)
	# The solver only trusts its deduction when EVERY tile is accounted for
	# (hands + board + boneyard = 28, boneyard dry) — park the rest of the set
	# on the board chain so the test state honors the real-game invariant.
	var used := [Tile.new(1, 2), Tile.new(4, 6), Tile.new(3, 3), Tile.new(1, 4)]
	for t in Deck.new().tiles:
		var is_used := false
		for u in used:
			if t.equals(u):
				is_used = true
		if not is_used:
			r.board.chain.append(t)
	var bot := Bot.new(Bot.Difficulty.EXPERT, RandomNumberGenerator.new())
	var ranked := bot.rank_moves(r, 0)
	_check(not ranked.is_empty() and ranked[0]["solved"], "EXPERT switches to exact search once the boneyard is dry")
	_check(ranked[0]["score"] > 0.0, "solver finds the winning endgame line")
	var chosen := bot.choose_move(r, 0)
	_check(chosen.tile.equals(ranked[0]["move"].tile) and chosen.side == ranked[0]["move"].side, "choose_move plays the solver's best line")


func _test_draw_void_inference() -> void:
	# Drawing is proof of a void too: you only draw when neither open end is in
	# your hand. And a LATER draw on different ends stales old voids (the newly
	# drawn tile could be anything) while proving new ones.
	var p0 := Hand.new()
	p0.add(Tile.new(2, 1))
	var p1 := Hand.new()
	p1.add(Tile.new(6, 6))
	var r := Round.from_state([p0, p1], Round.Variant.DRAW, Deck.new(-1), 0)
	r.board.play(Tile.new(5, 1), Board.Side.LEFT)  # ends (5, 1)
	r.history.append({"type": "draw", "player": 1, "ends": [5, 1]})
	var bot := Bot.new(Bot.Difficulty.EXPERT, RandomNumberGenerator.new())
	var voids: Dictionary = bot._opponent_voids(r, 0)
	_check(voids.has(5) and voids.has(1), "a draw reveals voids on both faced ends")
	r.history.append({"type": "draw", "player": 1, "ends": [2, 6]})
	voids = bot._opponent_voids(r, 0)
	_check(voids.has(2) and voids.has(6) and not voids.has(5) and not voids.has(1), "a later draw on other ends stales old voids")


func _test_rank_moves_explanations() -> void:
	var deck := Deck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	deck.shuffle_deck(rng)
	var r := Round.deal(2, 7, Round.Variant.DRAW, deck)
	# Play out the forced opener so there are real choices to rank.
	r.apply_move(r.legal_moves()[0])
	var bot := Bot.new(Bot.Difficulty.EXPERT, rng)
	var ranked := bot.rank_moves(r, r.current)
	var ok := not ranked.is_empty()
	for i in range(ranked.size() - 1):
		if ranked[i]["score"] < ranked[i + 1]["score"]:
			ok = false
	var has_why := true
	for e in ranked:
		if String(e["why"]).is_empty():
			has_why = false
	_check(ok, "rank_moves returns moves sorted best-first")
	_check(has_why, "every ranked move carries a coach explanation")


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
	# The solver's home turf is DRAW (the boneyard actually drains there).
	var exp_vs_hard_draw := _winrate(Bot.Difficulty.EXPERT, Bot.Difficulty.HARD, 200, Round.Variant.DRAW)

	print("    match win rates over %d matches to 75 (block):" % matches)
	print("      HARD   vs EASY   = %.1f%%" % (hard_vs_easy * 100))
	print("      MEDIUM vs EASY   = %.1f%%" % (med_vs_easy * 100))
	print("      HARD   vs MEDIUM = %.1f%%" % (hard_vs_med * 100))
	print("      EXPERT vs HARD   = %.1f%%" % (exp_vs_hard * 100))
	print("      EXPERT vs HARD   = %.1f%%  (draw, 200 matches)" % (exp_vs_hard_draw * 100))

	_check(hard_vs_easy > 0.65, "HARD beats EASY decisively")
	_check(med_vs_easy > 0.55, "MEDIUM beats EASY")
	_check(hard_vs_med > 0.52, "HARD edges out MEDIUM")
	_check(exp_vs_hard >= 0.52, "EXPERT clearly beats HARD in block")
	_check(exp_vs_hard_draw >= 0.58, "EXPERT dominates HARD in draw (endgame solver)")
