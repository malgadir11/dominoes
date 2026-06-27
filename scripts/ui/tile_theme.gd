class_name TileTheme
extends Resource

## Every visual parameter for the dominoes art, in one swappable resource.
## Gameplay code never reads this — it is purely cosmetic — so a future artist
## can reskin the ENTIRE game without touching any logic:
##
##   Option A (recolor / resize): edit the values below in the Inspector.
##   Option B (real artwork): assign body_texture / pip_texture / back_texture
##            and the renderer uses the images instead of the placeholders.
##
## To use a custom look, make a new .tres from this script, tweak it, and assign
## it to the Game node's `tile_theme` slot. Nothing else changes.
##
## FILLER: the defaults below are programmer-art placeholders, not final art.

@export_group("Dimensions")
@export var half_size: float = 50.0       ## one square half of a tile, in px
@export var corner_radius: float = 7.0
@export var border_width: float = 2.0
@export var divider_thickness: float = 2.0
@export var pip_radius: float = 5.0
@export var safe_margin: float = 9.0      ## inset where pips are allowed to sit

@export_group("Colors")
@export var body_color: Color = Color("f4f4f2")     ## face-up tile body
@export var border_color: Color = Color("c9c9c4")
@export var pip_color: Color = Color("2b2b2b")
@export var back_color: Color = Color("3a6ea5")     ## face-down tile back
@export var table_color: Color = Color("23433a")    ## play surface
@export var highlight_color: Color = Color("4caf7d") ## a playable / selected tile
@export var recent_color: Color = Color("e0a23b")    ## the most recently played tile
@export var text_color: Color = Color("f4f4f2")

@export_group("Optional artwork (overrides the procedural placeholders)")
@export var body_texture: Texture2D
@export var pip_texture: Texture2D
@export var back_texture: Texture2D


## Convenience: the full size of a horizontal tile (two squares wide).
func tile_size() -> Vector2:
	return Vector2(half_size * 2.0, half_size)
