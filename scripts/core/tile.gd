class_name Tile
extends RefCounted

## A single domino tile. Identity is the unordered pair of pip values, so
## [2|5] and [5|2] are the same tile. Orientation on the board (which end
## connects) is handled by the placement layer, not by the tile itself.

var low: int
var high: int


func _init(a: int, b: int) -> void:
	low = mini(a, b)
	high = maxi(a, b)


## True for tiles like [4|4] that have the same value on both ends.
func is_double() -> bool:
	return low == high


## Sum of both ends. Used for scoring leftover hands.
func pip_total() -> int:
	return low + high


## True if either end shows value n (i.e. the tile can connect to an open end of n).
func has_value(n: int) -> bool:
	return low == n or high == n


## Given the tile connects on value n, returns the value left exposed.
## Returns -1 if n is not on this tile.
func other_end(n: int) -> int:
	if low == n:
		return high
	if high == n:
		return low
	return -1


func equals(other: Tile) -> bool:
	return other != null and low == other.low and high == other.high


func _to_string() -> String:
	return "[%d|%d]" % [low, high]
