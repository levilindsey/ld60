class_name DirtSpot
extends InteractionPoint
## Shared base for the placed dirt points: dust, grime and rust.
##
## The art is one texture picked at random from a `DecalSet`. Which
## set is a per-point configuration: `texture_set` picks the first or
## the second set, so one scene covers both dusts and both grimes.
## The color is a configuration too: the set's `tint` (and its blend
## material) gives the default look, and `tint` on the point multiplies
## it, so a scene can wear its dirt warmer, darker or paler without a
## new set. The art is white, so the tints do all the coloring.
##
## Subclasses own the cleaning: they fade the art by calling
## `_set_art_alpha()` with the share of dirt left.


## Which of the point's two sets the art comes from.
enum TextureSet {
	FIRST,
	SECOND,
}

## The dirt art. It fades as the point cleans.
@export var art: Sprite2D
## The set `TextureSet.FIRST` wears.
@export var first_set: DecalSet
## The set `TextureSet.SECOND` wears. Null wears the first set.
@export var second_set: DecalSet
## Which set this point wears.
@export var texture_set := TextureSet.FIRST
## A color laid over the set's own tint. White keeps the set's look.
@export var tint := Color.WHITE
## The visible art's longer side, in pixels.
@export var art_size_px := 40.0

## The scale the art rests at, from `art_size_px` and the texture.
var _art_home_scale := Vector2.ONE
## The turn the art rests at. The wobble swings around it.
var _art_home_rotation := 0.0
## The alpha the configured colors give the art before any fading.
var _base_alpha := 1.0


## The set this point wears.
func get_active_set() -> DecalSet:
	if texture_set == TextureSet.SECOND and is_instance_valid(second_set):
		return second_set
	return first_set


## Picks the art's texture, size, turn and color from the active set.
## Subclasses call it in `_ready()` before their first fade update.
func _set_up_art() -> void:
	G.check(is_instance_valid(art))
	var decal_set := get_active_set()
	if not G.check(
		is_instance_valid(decal_set) and not decal_set.textures.is_empty()
	):
		return
	var texture := decal_set.textures.pick_random() as Texture2D
	art.texture = texture
	var visible_rect := DecalSpawner.get_visible_rect(texture)
	if visible_rect.size.x > 0.0 and visible_rect.size.y > 0.0:
		art.region_enabled = true
		art.region_rect = visible_rect
	var longer_side := maxf(visible_rect.size.x, visible_rect.size.y)
	var scale_factor := 1.0
	if longer_side > 0.0:
		scale_factor = art_size_px / longer_side
	scale_factor *= randf_range(
		decal_set.scale_range.x, decal_set.scale_range.y
	)
	_art_home_scale = Vector2.ONE * scale_factor
	art.scale = _art_home_scale
	_art_home_rotation = randf() * TAU
	art.rotation = _art_home_rotation
	art.material = decal_set.blend_material
	var color: Color = decal_set.tint * tint
	_base_alpha = color.a
	art.modulate = color


## Fades the art to `share` of its configured alpha (1 is full dirt).
func _set_art_alpha(share: float) -> void:
	if is_instance_valid(art):
		art.modulate.a = _base_alpha * clampf(share, 0.0, 1.0)
