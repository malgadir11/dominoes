class_name BoardLayout
extends RefCounted

## Lays the played chain out as a real domino snake: tiles run horizontally,
## and when a run reaches the width bound a tile is placed VERTICALLY as a corner
## that turns the line down a row; the next run heads back the other way. Doubles
## are drawn crosswise (vertical, centered on the line). This matches how physical
## dominoes ring around a table. Pure geometry — no nodes — so it is testable and
## player-count agnostic (one shared line serves 2-4 players and 2v2).
##
## Each placement is a Dictionary:
##   {"tile": Tile, "a": int, "b": int, "vertical": bool, "pos": Vector2, "size": Vector2}
## (a, b) are the values shown in reading order (left→right, or top→bottom for
## vertical tiles); they are pre-oriented so equal numbers physically touch.

static func compute(layout: Array, theme: TileTheme, max_width: float) -> Dictionary:
	var s := theme.half_size
	var placements: Array = []
	if layout.is_empty():
		return {"placements": placements, "size": Vector2.ZERO}

	var gap := s * 0.16   # small space between tiles so the snake isn't cramped
	var pitch := 2.0 * s  # vertical distance between runs (clean L-corners, no double overlap)
	var dir := 1     # 1 = travelling right, -1 = travelling left
	var px := 0.0    # x of the open connection point of the chain so far
	var py := s      # y of the current run's center line
	var first := true

	for entry in layout:
		var is_double: bool = entry["is_double"]
		var lv: int = entry["left_val"]
		var rv: int = entry["right_val"]

		if first:
			first = false
			if is_double:
				placements.append(_p(entry, lv, rv, true, Vector2(px, py - s), Vector2(s, 2.0 * s)))
				px += s + gap
			else:
				placements.append(_p(entry, lv, rv, false, Vector2(px, py - s * 0.5), Vector2(2.0 * s, s)))
				px += 2.0 * s + gap
			continue

		# Turn the corner when the next horizontal tile would cross the bound.
		var turn := (dir == 1 and px + 2.0 * s > max_width) or (dir == -1 and px - 2.0 * s < 0.0)
		if turn:
			# A vertical tile bridging this run (top) to the next one (bottom).
			var corner_x := px if dir == 1 else px - s
			placements.append(_p(entry, lv, rv, true, Vector2(corner_x, py - s * 0.5), Vector2(s, 2.0 * s)))
			py += pitch
			dir = -dir
			continue

		if is_double:
			# Crosswise, centered on the line; advances by its short side.
			var dx := 0.0 if dir == 1 else s
			placements.append(_p(entry, lv, rv, true, Vector2(px - dx, py - s), Vector2(s, 2.0 * s)))
			px += (s + gap) * dir
		elif dir == 1:
			placements.append(_p(entry, lv, rv, false, Vector2(px, py - s * 0.5), Vector2(2.0 * s, s)))
			px += 2.0 * s + gap
		else:
			# Travelling left: the connecting value faces right, so swap a/b.
			placements.append(_p(entry, rv, lv, false, Vector2(px - 2.0 * s, py - s * 0.5), Vector2(2.0 * s, s)))
			px -= 2.0 * s + gap

	return _normalized(placements)


static func _p(entry: Dictionary, a: int, b: int, vertical: bool, pos: Vector2, size: Vector2) -> Dictionary:
	return {"tile": entry["tile"], "a": a, "b": b, "vertical": vertical, "pos": pos, "size": size}


# Shift everything so the top-left is (0, 0) and report the overall size.
static func _normalized(placements: Array) -> Dictionary:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for pl in placements:
		var p: Vector2 = pl["pos"]
		var sz: Vector2 = pl["size"]
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x + sz.x)
		max_y = maxf(max_y, p.y + sz.y)
	var shift := Vector2(-min_x, -min_y)
	for pl in placements:
		pl["pos"] = pl["pos"] + shift
	return {"placements": placements, "size": Vector2(max_x - min_x, max_y - min_y)}
