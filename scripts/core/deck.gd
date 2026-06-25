class_name Deck
extends RefCounted

## The full domino set, also serving as the boneyard (draw pile) once a round
## starts. max_pips controls the set size: 6 = double-six (28 tiles), and the
## same code yields double-nine or double-twelve if we expand later.

const DOUBLE_SIX := 6

var tiles: Array[Tile] = []


func _init(max_pips: int = DOUBLE_SIX) -> void:
	_build(max_pips)


func _build(max_pips: int) -> void:
	tiles.clear()
	for a in range(max_pips + 1):
		for b in range(a, max_pips + 1):
			tiles.append(Tile.new(a, b))


func size() -> int:
	return tiles.size()


func is_empty() -> bool:
	return tiles.is_empty()


## Shuffle in place. Pass a seeded RandomNumberGenerator for reproducible
## games (used by the test/simulation harness); omit it for a real shuffle.
func shuffle_deck(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		tiles.shuffle()
		return
	# Deterministic Fisher-Yates so a given seed always produces the same deal.
	for i in range(tiles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp


## Remove and return the top tile, or null if the deck is empty.
func draw() -> Tile:
	if tiles.is_empty():
		return null
	return tiles.pop_back()
