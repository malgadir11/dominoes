class_name Move
extends RefCounted

## A candidate play: a tile and which open end to attach it to. The round
## engine produces these as legal options; a human or the AI picks one.

var tile: Tile
var side: int  ## Board.Side


func _init(p_tile: Tile, p_side: int) -> void:
	tile = p_tile
	side = p_side


func _to_string() -> String:
	var side_name := "L" if side == Board.Side.LEFT else "R"
	return "%s@%s" % [tile, side_name]
