class_name Round
extends RefCounted

## Runs a single round of block/draw dominoes. Pure logic, no graphics.
##
## Driver contract (used by the UI, the AI, and tests alike):
##   while not round.finished:
##       var moves := round.legal_moves()
##       if moves.is_empty():
##           if round.variant == Round.Variant.DRAW and not round.boneyard_empty():
##               round.draw_tile()          # forced: keep drawing until playable
##           else:
##               round.pass_turn()
##       else:
##           round.apply_move(<one of moves>)   # the only real decision
##
## The single strategic choice each turn is which legal move to play; drawing is
## forced and passing only happens when no play is possible.

enum Variant { DRAW, BLOCK }
enum WinType { DOMINO, BLOCK }

var variant: int = Variant.DRAW
var player_count: int = 0
var hands: Array[Hand] = []
var board: Board
var boneyard: Deck
var current: int = 0
var finished: bool = false
var result: RoundResult = null

## Public event log of the round, in order. Each entry is a Dictionary:
##   {"type": "move", "player": int, "tile": Tile, "side": int}
##   {"type": "pass", "player": int, "ends": Array}   # open ends faced when passing
## Visible to everyone (no hidden info) — used by the AI's inference, the move
## history UI, and multiplayer sync.
var history: Array[Dictionary] = []

var _passes_in_row: int = 0
var _forced_opener: Tile = null  ## first-round opener must play this exact tile


func _init() -> void:
	board = Board.new()


## Standard setup: shuffle is the caller's responsibility (so tests can seed it).
## opener < 0 means "first round" — the highest double (or heaviest tile) opens.
## opener >= 0 means a later round opened by the previous winner with any tile.
static func deal(p_player_count: int, hand_size: int, p_variant: int, deck: Deck, opener: int = -1) -> Round:
	var r := Round.new()
	r.player_count = p_player_count
	r.variant = p_variant
	for i in range(p_player_count):
		r.hands.append(Hand.new())
	for n in range(hand_size):
		for i in range(p_player_count):
			r.hands[i].add(deck.draw())
	r.boneyard = deck
	if opener >= 0:
		r.current = opener
	else:
		r._determine_opener()
	return r


## Build a round from explicit hands — used by scenario tests. The board starts
## empty and `opener` plays first with any tile.
static func from_state(p_hands: Array, p_variant: int, p_boneyard: Deck, opener: int) -> Round:
	var r := Round.new()
	r.player_count = p_hands.size()
	r.variant = p_variant
	r.hands.assign(p_hands)
	r.boneyard = p_boneyard
	r.current = opener
	return r


## Legal plays for the current player. On an empty board the opener either has a
## single forced tile (first round) or may lead with any tile.
func legal_moves() -> Array[Move]:
	var moves: Array[Move] = []
	var hand := hands[current]
	if board.is_empty():
		if _forced_opener != null:
			moves.append(Move.new(_forced_opener, Board.Side.LEFT))
		else:
			for t in hand.tiles:
				moves.append(Move.new(t, Board.Side.LEFT))
		return moves
	for t in hand.tiles:
		if t.has_value(board.left_end):
			moves.append(Move.new(t, Board.Side.LEFT))
		# Skip the right side when both ends match — it would be a duplicate play.
		if board.right_end != board.left_end and t.has_value(board.right_end):
			moves.append(Move.new(t, Board.Side.RIGHT))
	return moves


func boneyard_empty() -> bool:
	return boneyard.is_empty()


## True while the first-round opener still owes the forced opening tile (the
## highest double). A choiceless move, so the UI can auto-play it.
func has_forced_opener() -> bool:
	return _forced_opener != null


## Forced draw for the current player (DRAW variant only). Returns the drawn
## tile so the UI can animate it, or null if the boneyard is empty.
func draw_tile() -> Tile:
	var t := boneyard.draw()
	if t != null:
		hands[current].add(t)
	return t


func apply_move(move: Move) -> void:
	if finished:
		return
	var hand := hands[current]
	if not board.play(move.tile, move.side):
		push_error("Round.apply_move: illegal move %s" % move)
		return
	hand.remove(move.tile)
	history.append({"type": "move", "player": current, "tile": move.tile, "side": move.side})
	_forced_opener = null
	_passes_in_row = 0
	if hand.is_empty():
		_finish(current, WinType.DOMINO)
		return
	_advance()


func pass_turn() -> void:
	if finished:
		return
	history.append({"type": "pass", "player": current, "ends": board.open_ends()})
	_passes_in_row += 1
	if _passes_in_row >= player_count:
		_finish_blocked()
		return
	_advance()


## Convenience: play the whole round with uniform random choices. Used by the
## AI-balancing simulator and the tests; not used by real gameplay.
func autoplay(rng: RandomNumberGenerator) -> RoundResult:
	while not finished:
		var moves := legal_moves()
		if moves.is_empty():
			if variant == Variant.DRAW and not boneyard_empty():
				draw_tile()
			else:
				pass_turn()
		else:
			apply_move(moves[rng.randi_range(0, moves.size() - 1)])
	return result


func _advance() -> void:
	current = (current + 1) % player_count


func _determine_opener() -> void:
	# Highest double across all hands opens with it.
	var best_player := -1
	var best_val := -1
	for i in range(player_count):
		var hd := hands[i].highest_double()
		if hd != null and hd.high > best_val:
			best_val = hd.high
			best_player = i
	if best_player != -1:
		current = best_player
		_forced_opener = hands[best_player].highest_double()
		return
	# No doubles were dealt: the single heaviest tile opens.
	var bp := 0
	var bv := -1
	var bt: Tile = null
	for i in range(player_count):
		for t in hands[i].tiles:
			if t.pip_total() > bv:
				bv = t.pip_total()
				bp = i
				bt = t
	current = bp
	_forced_opener = bt


func _finish_blocked() -> void:
	# Fewest pips wins; ties break to the lowest player index.
	var best := 0
	for i in range(1, player_count):
		if hands[i].pip_total() < hands[best].pip_total():
			best = i
	_finish(best, WinType.BLOCK)


func _finish(winner: int, type: int) -> void:
	finished = true
	result = RoundResult.new()
	result.winner = winner
	result.win_type = type
	result.pip_totals = []
	var others := 0
	for i in range(player_count):
		result.pip_totals.append(hands[i].pip_total())
		if i != winner:
			others += hands[i].pip_total()
	# Unified scoring: opponents' pips minus the winner's own (0 on a domino win).
	result.score = maxi(0, others - hands[winner].pip_total())
