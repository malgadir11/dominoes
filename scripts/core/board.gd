class_name Board
extends RefCounted

## The played chain of tiles. For the rules, only the two open ends matter, so
## those are tracked precisely. For rendering, `layout` records each tile in
## line order with the value facing left and the value facing right — so the
## display can guarantee matching numbers physically touch, and doubles can be
## drawn crosswise (perpendicular). `chain` keeps the raw tiles in the same order.

enum Side { LEFT, RIGHT }

var chain: Array[Tile] = []
## One Dictionary per tile, left-to-right:
##   {"tile": Tile, "left_val": int, "right_val": int, "is_double": bool}
## Invariant: layout[i].right_val == layout[i+1].left_val (the touching numbers).
var layout: Array[Dictionary] = []
var left_end: int = -1
var right_end: int = -1


func is_empty() -> bool:
	return chain.is_empty()


## The playable values. Empty board returns [] (anything goes). When both ends
## show the same value, returns a single entry.
func open_ends() -> Array:
	if is_empty():
		return []
	if left_end == right_end:
		return [left_end]
	return [left_end, right_end]


## Place a tile. The first tile sets both ends; later tiles must match the
## chosen side's open value, and are oriented so the matching numbers touch.
## Returns false if the placement is illegal.
func play(tile: Tile, side: int) -> bool:
	if is_empty():
		chain.append(tile)
		left_end = tile.low
		right_end = tile.high
		layout.append({"tile": tile, "left_val": tile.low, "right_val": tile.high, "is_double": tile.is_double()})
		return true
	if side == Side.LEFT:
		if not tile.has_value(left_end):
			return false
		var outward := tile.other_end(left_end)
		# The matching value faces the chain (right side of this new tile).
		layout.push_front({"tile": tile, "left_val": outward, "right_val": left_end, "is_double": tile.is_double()})
		chain.push_front(tile)
		left_end = outward
		return true
	if not tile.has_value(right_end):
		return false
	var outward := tile.other_end(right_end)
	# The matching value faces the chain (left side of this new tile).
	layout.push_back({"tile": tile, "left_val": right_end, "right_val": outward, "is_double": tile.is_double()})
	chain.append(tile)
	right_end = outward
	return true
