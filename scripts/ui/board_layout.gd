class_name BoardLayout
extends RefCounted

## Turns the board's ordered tile sequence into screen placements that snake
## (boustrophedon) within a flexible max width: rows fill left-to-right, then the
## next row runs right-to-left under it, and so on — so the chain rings around
## instead of growing forever sideways. Pure geometry, no nodes, so it is easy to
## test and to retune (and it is player-count agnostic: 2, 3, 4 players and 2v2
## all share one line of play, so this serves every mode).
##
## Each placement is a Dictionary:
##   {"tile": Tile, "a": int, "b": int, "vertical": bool, "size": Vector2, "pos": Vector2}
## where (a, b) are the values to show in reading order (a then b). On right-to-
## left rows the values are pre-swapped so equal numbers still physically touch.
## Doubles are "vertical" (laid crosswise) and take half the width.

static func compute(layout: Array, theme: TileTheme, max_width: float) -> Dictionary:
	var s := theme.half_size
	var pitch := 2.0 * s  # vertical distance between row centers (fits crosswise doubles)

	# 1. Chunk the sequence into rows that fit within max_width.
	var rows: Array = []
	var cur: Array = []
	var cur_w := 0.0
	for entry in layout:
		var w := _entry_width(entry, s)
		if not cur.is_empty() and cur_w + w > max_width:
			rows.append(cur)
			cur = []
			cur_w = 0.0
		cur.append(entry)
		cur_w += w
	if not cur.is_empty():
		rows.append(cur)

	# 2. Position each row, alternating direction.
	var placements: Array = []
	var first_row_width := 0.0
	for ri in range(rows.size()):
		var row: Array = rows[ri]
		var ltr := ri % 2 == 0
		var y_center := s + ri * pitch
		if ri == 0:
			for entry in row:
				first_row_width += _entry_width(entry, s)
		if ltr:
			var x := 0.0
			for entry in row:
				placements.append(_place(entry, x, y_center, s, false))
				x += _entry_width(entry, s)
		else:
			# Right-to-left: anchor at the right edge so the turn lines up.
			var x := max_width
			for entry in row:
				var w := _entry_width(entry, s)
				x -= w
				placements.append(_place(entry, x, y_center, s, true))

	# A multi-row board uses the full width; a single row only as much as it needs.
	var content_w: float = max_width if rows.size() > 1 else first_row_width
	var height := rows.size() * pitch
	if layout.is_empty():
		content_w = 0.0
		height = 0.0
	return {"placements": placements, "size": Vector2(content_w, height)}


static func _entry_width(entry: Dictionary, s: float) -> float:
	return s if entry["is_double"] else 2.0 * s


static func _place(entry: Dictionary, x: float, y_center: float, s: float, reversed: bool) -> Dictionary:
	var is_double: bool = entry["is_double"]
	var a: int = entry["right_val"] if reversed else entry["left_val"]
	var b: int = entry["left_val"] if reversed else entry["right_val"]
	var size := Vector2(s, s * 2.0) if is_double else Vector2(s * 2.0, s)
	var top := y_center - (s if is_double else s * 0.5)
	return {"tile": entry["tile"], "a": a, "b": b, "vertical": is_double, "size": size, "pos": Vector2(x, top)}
