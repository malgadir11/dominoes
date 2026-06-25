class_name Bot
extends RefCounted

## A computer opponent. All tiers share one evaluation function and differ only
## by feature weights and noise, so difficulty is competence, not cheating — the
## bot only ever looks at public information (its own hand, the board, the
## boneyard count, and the public pass/move history).
##
## Build philosophy: HARD is the real brain. EASY/MEDIUM are HARD with weights
## detuned and noise cranked up. EXPERT is HARD plus the inference feature that
## exploits what opponents have revealed by passing.

enum Difficulty { EASY, MEDIUM, HARD, EXPERT }

# Feature weights.
var w_unload: float = 0.0    # dump heavy tiles (pips played)
var w_flex: float = 0.0      # keep my own future options open
var w_denial: float = 0.0    # leave ends few unseen tiles can answer
var w_endgame: float = 0.0   # when no more drawing, shed heavy tiles harder
var w_infer: float = 0.0     # steer ends to values a passed opponent can't hold
var w_noise: float = 0.0     # randomness; high = weak/erratic play

var difficulty: int
var _rng: RandomNumberGenerator

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
			w_denial = 0.45
			w_endgame = 1.5
			w_noise = 0.2
		Difficulty.EXPERT:
			w_unload = 1.0
			w_flex = 0.7
			w_denial = 0.5
			w_endgame = 1.5
			w_infer = 8.0
			w_noise = 0.0


## Pick a move for `player` from the current legal options. Returns null only if
## there are no legal moves (the caller should draw or pass in that case).
func choose_move(r: Round, player: int) -> Move:
	var moves := r.legal_moves()
	if moves.is_empty():
		return null
	if difficulty == Difficulty.EASY:
		return moves[_rng.randi_range(0, moves.size() - 1)]

	var unseen := _unseen_tiles(r, player)
	var voids := _opponent_voids(r, player)
	var boneyard_empty := r.boneyard_empty()

	var best: Move = null
	var best_score := -INF
	for m in moves:
		var s := _score_move(m, r, player, unseen, voids, boneyard_empty)
		s += _rng.randf() * w_noise
		if s > best_score:
			best_score = s
			best = m
	return best


func _score_move(m: Move, r: Round, player: int, unseen: Array, voids: Dictionary, boneyard_empty: bool) -> float:
	var ends_after := _ends_after(m, r)
	var pips := float(m.tile.pip_total())

	# Flexibility: how many of my OTHER tiles still play on the new ends.
	var my_rest: Array[Tile] = []
	for t in r.hands[player].tiles:
		if not t.equals(m.tile):
			my_rest.append(t)
	var flex := float(_count_matches(my_rest, ends_after))

	# Denial: fewer unseen tiles able to answer the new ends is better.
	var denial := -float(_count_matches(unseen, ends_after))

	# Endgame: once the boneyard is dry, shedding heavy tiles matters more.
	var endgame := pips if boneyard_empty else 0.0

	# Inference: reward ends a passed opponent is known to be void on. Worth more
	# when nobody can draw their way out of it.
	var infer := 0.0
	if r.player_count == 2 and not voids.is_empty():
		for e in ends_after:
			if voids.has(e):
				infer += 1.0
		if not boneyard_empty:
			infer *= 0.3

	return w_unload * pips \
		+ w_flex * flex \
		+ w_denial * denial \
		+ w_endgame * endgame \
		+ w_infer * infer


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


## Values the (single) opponent has revealed it cannot hold, by passing. In a
## 2-player game every pass means the opponent held neither open-end value.
func _opponent_voids(r: Round, player: int) -> Dictionary:
	var voids := {}
	if r.player_count != 2:
		return voids
	var opp := 1 - player
	for e in r.history:
		if e["type"] == "pass" and e["player"] == opp:
			for v in e["ends"]:
				voids[v] = true
	return voids


func _key(t: Tile) -> int:
	return t.low * 7 + t.high


func _get_full_set() -> Array[Tile]:
	if _full_set.is_empty():
		_full_set = Deck.new().tiles
	return _full_set
