class_name Bot
extends RefCounted

## A computer opponent. All tiers share one evaluation function and differ only
## by feature weights and noise, so difficulty is competence, not cheating — the
## bot only ever looks at public information (its own hand, the board, the
## boneyard count, and the public move/pass/draw history).
##
## Build philosophy: HARD is the real brain. EASY/MEDIUM are HARD with weights
## detuned and noise cranked up. EXPERT is HARD plus two upgrades a strong human
## counter uses: full void inference (passes AND draws reveal what the opponent
## can't hold) and perfect endgame calculation (once the boneyard is dry in a
## 2-player draw game, the opponent's exact hand is deducible and the rest of
## the round is solved exactly — see Endgame).

enum Difficulty { EASY, MEDIUM, HARD, EXPERT }

# Feature weights.
var w_unload: float = 0.0    # dump heavy tiles (pips played)
var w_flex: float = 0.0     # keep my own future options open
var w_denial: float = 0.0   # leave ends the opponent probably can't answer
var w_endgame: float = 0.0  # when no more drawing, shed heavy tiles harder
var w_infer: float = 0.0    # steer ends to values the opponent has shown it lacks
var w_double: float = 0.0   # shed doubles early (only one suit can place them)
var w_noise: float = 0.0    # randomness; high = weak/erratic play
var use_solver: bool = false # exact endgame play when the position is fully known

var difficulty: int
var _rng: RandomNumberGenerator
var _solver := Endgame.new()

static var _full_set: Array[Tile] = []


func _init(p_difficulty: int, rng: RandomNumberGenerator = null) -> void:
	difficulty = p_difficulty
	if rng != null:
		_rng = rng  # tests pass a seeded rng for reproducibility
	else:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()  # real games vary run to run
	_apply_weights(p_difficulty)


func _apply_weights(d: int) -> void:
	match d:
		Difficulty.EASY:
			w_noise = 1.0  # EASY ignores features and plays at random
		Difficulty.MEDIUM:
			w_unload = 1.0
			w_flex = 0.5
			w_noise = 3.0
		Difficulty.HARD:
			w_unload = 1.0
			w_flex = 0.7
			w_denial = 0.6
			w_endgame = 1.5
			w_infer = 1.2
			w_double = 0.5
			w_noise = 0.2
		Difficulty.EXPERT:
			w_unload = 1.0
			w_flex = 0.8
			w_denial = 1.2
			w_endgame = 1.5
			w_infer = 6.0
			w_double = 0.6
			w_noise = 0.0
			use_solver = true


## Pick a move for `player` from the current legal options. Returns null only if
## there are no legal moves (the caller should draw or pass in that case).
func choose_move(r: Round, player: int) -> Move:
	var moves := r.legal_moves()
	if moves.is_empty():
		return null
	if difficulty == Difficulty.EASY:
		return moves[_rng.randi_range(0, moves.size() - 1)]
	var ranked := rank_moves(r, player)
	if w_noise > 0.0:
		var best: Dictionary = ranked[0]
		var best_score: float = best["score"] + _rng.randf() * w_noise
		for i in range(1, ranked.size()):
			var s: float = ranked[i]["score"] + _rng.randf() * w_noise
			if s > best_score:
				best_score = s
				best = ranked[i]
		return best["move"]
	return ranked[0]["move"]


## Evaluate every legal move for `player`, best first. Each entry:
##   {"move": Move, "score": float, "solved": bool, "why": String}
## `why` is a short human explanation of the strongest reasons — the coach mode
## renders it verbatim. Noise is never applied here; this is the honest ranking.
func rank_moves(r: Round, player: int) -> Array[Dictionary]:
	var moves := r.legal_moves()
	var out: Array[Dictionary] = []
	if moves.is_empty():
		return out

	var unseen := _unseen_tiles(r, player)
	var voids := _opponent_voids(r, player)
	var opp_size := 0
	if r.player_count == 2:
		opp_size = r.hands[1 - player].tiles.size()

	# Perfect endgame: 2P and every unseen tile is in the opponent's hand.
	if use_solver and r.player_count == 2 and not r.board.is_empty() \
			and unseen.size() == opp_size and opp_size > 0:
		var solved := _rank_solved(r, player, moves, unseen)
		if not solved.is_empty():
			return solved

	for m in moves:
		var e := _eval_move(m, r, player, unseen, voids, opp_size)
		out.append(e)
	out.sort_custom(func(x, y): return x["score"] > y["score"])
	return out


# ------------------------------------------------------------------ evaluation

func _eval_move(m: Move, r: Round, player: int, unseen: Array, voids: Dictionary, opp_size: int) -> Dictionary:
	var ends_after := _ends_after(m, r)
	var pips := float(m.tile.pip_total())
	var no_more_digging: bool = r.variant == Round.Variant.BLOCK or r.boneyard_empty()

	# Flexibility: how many of my OTHER tiles still play on the new ends.
	var my_rest: Array[Tile] = []
	for t in r.hands[player].tiles:
		if not t.equals(m.tile):
			my_rest.append(t)
	var flex := float(_count_matches(my_rest, ends_after))

	# Denial: EXPECTED number of opponent tiles answering the new ends. Unseen
	# tiles that touch a live void can't be in their hand; the rest are theirs
	# with probability hand_size / eligible_unseen (the boneyard soaks the rest).
	var eligible: Array = []
	for t in unseen:
		if not (voids.has(t.low) or voids.has(t.high)):
			eligible.append(t)
	var p_holds := 0.0
	if opp_size > 0 and not eligible.is_empty():
		p_holds = minf(1.0, float(opp_size) / float(eligible.size()))
	var expected_answers := float(_count_matches(eligible, ends_after)) * p_holds

	# Endgame: once nobody can dig for tiles, shedding heavy tiles matters more.
	var endgame := pips if no_more_digging else 0.0

	# Inference: reward steering ends onto values the opponent has proven it
	# lacks. Covering BOTH ends is worth extra — that's a forced pass (tempo).
	var infer := 0.0
	var void_hits: Array = []
	if not voids.is_empty():
		for e in ends_after:
			if voids.has(e):
				infer += 1.0
				if not void_hits.has(e):
					void_hits.append(e)
		if infer >= 2.0:
			infer += 1.5
		if not no_more_digging:
			infer *= 0.3  # they can still draw their way out

	var dbl := 1.0 if m.tile.is_double() else 0.0

	var score := w_unload * pips \
		+ w_flex * flex \
		- w_denial * expected_answers \
		+ w_endgame * endgame \
		+ w_infer * infer \
		+ w_double * dbl

	var why := _compose_why(pips, flex, expected_answers, infer, void_hits, dbl, no_more_digging)
	return {"move": m, "score": score, "solved": false, "why": why}


## Rank by exact search when the opponent's hand is fully deduced. Returns []
## if any solve aborts (position too big) so the caller falls back to heuristics.
func _rank_solved(r: Round, player: int, moves: Array[Move], opp_tiles: Array) -> Array[Dictionary]:
	var my_tiles: Array = []
	for t in r.hands[player].tiles:
		my_tiles.append(t)
	var out: Array[Dictionary] = []
	for m in moves:
		var v := _solver.value_of_move(my_tiles, opp_tiles, r.board.left_end, r.board.right_end, m.tile, m.side)
		if absf(v) == Endgame.ABORTED:
			return []
		out.append({"move": m, "score": v, "solved": true, "why": _solved_why(v)})
	out.sort_custom(func(x, y): return x["score"] > y["score"])
	return out


# ------------------------------------------------------------ coach explanations

func _compose_why(pips: float, flex: float, expected_answers: float, infer: float, void_hits: Array, dbl: float, no_more_digging: bool) -> String:
	# Collect candidate reasons with a salience score, keep the top two.
	var reasons: Array = []
	if infer >= 2.0:
		reasons.append([w_infer * infer + 5.0, "opponent can't answer either end — forced pass"])
	elif not void_hits.is_empty():
		var vals := ", ".join(void_hits.map(func(v): return str(v) + "s"))
		reasons.append([w_infer * infer + 2.0, "opponent has shown it can't play %s" % vals])
	if pips >= 8.0:
		reasons.append([w_unload * pips * (2.0 if no_more_digging else 1.0), "sheds %d pips" % int(pips)])
	if dbl > 0.0:
		reasons.append([w_double + pips * 0.1, "gets the double out early (doubles are hard to place later)"])
	if expected_answers <= 1.0:
		reasons.append([w_denial * (2.0 - expected_answers), "leaves ends with few matching tiles left"])
	if flex >= 2.0:
		reasons.append([w_flex * flex, "keeps %d of your other tiles playable" % int(flex)])
	if reasons.is_empty():
		return "the best of your options here"
	reasons.sort_custom(func(x, y): return x[0] > y[0])
	var parts: Array = [reasons[0][1]]
	if reasons.size() > 1:
		parts.append(reasons[1][1])
	return " · ".join(parts)


func _solved_why(v: float) -> String:
	if v > 0.0:
		return "endgame is fully readable now — this line wins the round by %d" % int(v)
	if v == 0.0:
		return "endgame is fully readable — this holds the round to a wash"
	return "no winning line exists — this limits the loss to %d" % int(-v)


# ----------------------------------------------------------------- information

## The two open ends after hypothetically playing m.
func _ends_after(m: Move, r: Round) -> Array:
	if r.board.is_empty():
		return [m.tile.low, m.tile.high]
	var le := r.board.left_end
	var re := r.board.right_end
	if m.side == Board.Side.LEFT:
		le = m.tile.other_end(le)
	else:
		re = m.tile.other_end(re)
	return [le, re]


func _count_matches(tiles: Array, ends: Array) -> int:
	var c := 0
	for t in tiles:
		for e in ends:
			if t.has_value(e):
				c += 1
				break
	return c


## Tiles the bot hasn't seen: the full set minus the board minus its own hand.
## These are split between opponents' hands and the boneyard.
func _unseen_tiles(r: Round, player: int) -> Array[Tile]:
	var seen := {}
	for t in r.board.chain:
		seen[_key(t)] = true
	for t in r.hands[player].tiles:
		seen[_key(t)] = true
	var res: Array[Tile] = []
	for t in _get_full_set():
		if not seen.has(_key(t)):
			res.append(t)
	return res


## Values the (single) opponent has revealed it cannot hold. Both passes and
## draws are proof: you only do either when neither open end is in your hand.
## Staleness: a later draw on ends NOT including v may have handed them a v, so
## a void only stays live while every subsequent draw re-proves it (drawing on
## ends that include v means the drawn-and-kept tiles lack v too).
func _opponent_voids(r: Round, player: int) -> Dictionary:
	var voids := {}
	if r.player_count != 2:
		return voids
	var opp := 1 - player
	for e in r.history:
		if e["player"] != opp:
			continue
		if e["type"] == "draw":
			# They acquired an unknown tile: any void not among these ends may
			# have just been filled. Voids ON these ends survive (they were
			# stuck on them — and if the drawn tile answered, it got played).
			var ends: Array = e["ends"]
			for v in voids.keys():
				if not ends.has(v):
					voids.erase(v)
			for v in ends:
				voids[v] = true
		elif e["type"] == "pass":
			# Passing acquires nothing, so it only ever ADDS proof.
			for v in e["ends"]:
				voids[v] = true
	return voids


func _key(t: Tile) -> int:
	return t.low * 7 + t.high


func _get_full_set() -> Array[Tile]:
	if _full_set.is_empty():
		_full_set = Deck.new().tiles
	return _full_set
