class_name Endgame
extends RefCounted

## Perfect-information endgame solver for 2-player rounds.
##
## In the DRAW variant, once the boneyard is empty the set of unseen tiles IS the
## opponent's hand (unseen = opponents + boneyard, and the boneyard is dry). From
## that moment the round is a perfect-information game, small enough to solve
## exactly with alpha-beta. This is fair play, not cheating: any human counter
## could make the same deduction at a real table.
##
## Values are net round points for side A (A's winnings minus B's), matching
## Round's scoring: a domino win earns the loser's remaining pips; a blocked
## round earns the pip difference to whoever holds fewer (a tie scores 0).

const ABORTED := 1.0e18  # sentinel: search exceeded the node budget

var _nodes := 0
var _budget := 0


## Best guaranteed net score for side A. Side A moves next when turn == 0.
## Returns ABORTED if the position was too big for `budget` nodes.
func solve(a_tiles: Array, b_tiles: Array, le: int, re: int, turn: int, budget: int = 400000) -> float:
	_nodes = 0
	_budget = budget
	return _search(a_tiles.duplicate(), b_tiles.duplicate(), le, re, turn, 0, -INF, INF)


## The value (for the mover) of playing `tile` on `side` from this position,
## assuming both sides play the rest of the round perfectly.
func value_of_move(my: Array, opp: Array, le: int, re: int, tile: Tile, side: int, budget: int = 400000) -> float:
	var rest: Array = []
	for t in my:
		if not t.equals(tile):
			rest.append(t)
	if rest.is_empty():
		return float(_pips(opp))  # playing it goes out: domino win, collect their pips
	var nle := le
	var nre := re
	if side == Board.Side.LEFT:
		nle = tile.other_end(le)
	else:
		nre = tile.other_end(re)
	_nodes = 0
	_budget = budget
	return _search(rest, opp.duplicate(), nle, nre, 1, 0, -INF, INF)


func _search(a: Array, b: Array, le: int, re: int, turn: int, passes: int, alpha: float, beta: float) -> float:
	_nodes += 1
	if _nodes > _budget:
		return ABORTED
	if passes >= 2:  # blocked: fewer pips wins the difference (a tie scores 0)
		return float(_pips(b) - _pips(a))  # positive when A holds fewer

	var mover: Array = a if turn == 0 else b
	var moves := _legal(mover, le, re)
	if moves.is_empty():
		return _search(a, b, le, re, 1 - turn, passes + 1, alpha, beta)

	var best := -INF if turn == 0 else INF
	for mv in moves:
		var t: Tile = mv[0]
		var rest: Array = []
		for x in mover:
			if not x.equals(t):
				rest.append(x)
		var v: float
		if rest.is_empty():
			# Mover dominoes and collects the other side's remaining pips.
			v = float(_pips(b)) if turn == 0 else -float(_pips(a))
		elif turn == 0:
			v = _search(rest, b, mv[1], mv[2], 1, 0, alpha, beta)
		else:
			v = _search(a, rest, mv[1], mv[2], 0, 0, alpha, beta)
		if absf(v) == ABORTED:
			return ABORTED
		if turn == 0:
			best = maxf(best, v)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, v)
			beta = minf(beta, best)
		if beta <= alpha:
			break
	return best


## Legal placements as [tile, new_left, new_right]; skips the duplicate when both
## ends show the same value (same rule as Round.legal_moves).
func _legal(tiles: Array, le: int, re: int) -> Array:
	var res: Array = []
	for t in tiles:
		if t.has_value(le):
			res.append([t, t.other_end(le), re])
		if re != le and t.has_value(re):
			res.append([t, le, t.other_end(re)])
	return res


func _pips(tiles: Array) -> int:
	var s := 0
	for t in tiles:
		s += t.pip_total()
	return s
