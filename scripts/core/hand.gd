class_name Hand
extends RefCounted

## The set of tiles a player is holding. Knows nothing about the board rules —
## it only answers questions about its own tiles. The round engine drives play.

var tiles: Array[Tile] = []


func add(tile: Tile) -> void:
	if tile != null:
		tiles.append(tile)


## Remove a specific tile instance. Returns false if it was not in the hand.
func remove(tile: Tile) -> bool:
	var idx := tiles.find(tile)
	if idx == -1:
		return false
	tiles.remove_at(idx)
	return true


func size() -> int:
	return tiles.size()


func is_empty() -> bool:
	return tiles.is_empty()


## Total pip count of all held tiles. This is what an opponent scores against
## you when you lose a round.
func pip_total() -> int:
	var total := 0
	for t in tiles:
		total += t.pip_total()
	return total


## Tiles that can legally be played given the current open ends.
## An empty `ends` array means the board is empty (round start) and anything goes.
func playable_tiles(ends: Array) -> Array[Tile]:
	if ends.is_empty():
		return tiles.duplicate()
	var result: Array[Tile] = []
	for t in tiles:
		for e in ends:
			if t.has_value(e):
				result.append(t)
				break
	return result


func has_playable(ends: Array) -> bool:
	return not playable_tiles(ends).is_empty()


## Highest double held (e.g. [6|6] over [3|3]), used to decide who opens the
## first round. Returns null if the hand holds no doubles.
func highest_double() -> Tile:
	var best: Tile = null
	for t in tiles:
		if t.is_double() and (best == null or t.high > best.high):
			best = t
	return best
