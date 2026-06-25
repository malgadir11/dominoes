class_name RoundResult
extends RefCounted

## The outcome of a single round: who won, how, the points awarded, and every
## player's leftover pip count (for stats and the score screen).

var winner: int
var win_type: int  ## Round.WinType (DOMINO or BLOCK)
var score: int
var pip_totals: Array[int] = []


func _to_string() -> String:
	var type_name := "domino" if win_type == Round.WinType.DOMINO else "block"
	return "Player %d wins by %s for %d (pips: %s)" % [winner, type_name, score, pip_totals]
