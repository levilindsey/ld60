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
## The visible art's longer side, in world pixels. Items are
## authored at texture scale (a Game n Watch at 0.13), so the
## art and the hit circle are scaled back up by the item's
## scale at ready; otherwise a scaled-down item shrinks its
## dirt to a few invisible pixels (the drop shadow learned
## the same lesson).
@export var art_size_px := 40.0

## The scale the art rests at, from `art_size_px` and the texture.
var _art_home_scale := Vector2.ONE
## The turn the art rests at. The wobble swings around it.
var _art_home_rotation := 0.0
## The alpha the configured colors give the art before any fading.
var _base_alpha := 1.0
## 1 over this point's global scale, captured at ready.
var _scale_compensation := 1.0
## The decal sprites this spot renders: the art plus any
## extras from `_add_extra_decals()`. They fade together.
var _decal_sprites: Array[Sprite2D] = []
## The alpha share the decals were last faded to, so extras
## added later match the rest.
var _decal_alpha_share := 1.0
## Multiplier on the configured decal size. Dust renders at
## twice its configured size; other dirt at the size itself.
var _decal_size_scale := 1.0


## How far, in world pixels, a grime or dust spot past the
## first on its layer may sit from where it was authored.
const _EXTRA_SPOT_OFFSET_PX := 18.0


func _ready() -> void:
	super._ready()
	_scale_compensation = _get_scale_compensation()
	_compensate_hit_shapes()
	_nudge_extra_spot()


## Spots past the first grime or dust spot on a layer sit a
## little off their authored spot, at random within
## `_EXTRA_SPOT_OFFSET_PX`, so repeated dirt does not land in
## a pattern. The first spot keeps its authored place (the
## grime on a screw stays centred on it). Bench dust is a
## dust clump too, but the level places it after ready, so
## the nudge never shows there.
func _nudge_extra_spot() -> void:
	if not (self is GrimeSpot or self is DustClump):
		return
	if not is_instance_valid(get_parent()):
		return
	var spots_before := 0
	for sibling in get_parent().get_children():
		if sibling == self:
			break
		if sibling is GrimeSpot or sibling is DustClump:
			spots_before += 1
	if spots_before == 0:
		return
	var world_offset := (
		Vector2.from_angle(randf() * TAU)
		* sqrt(randf())
		* _EXTRA_SPOT_OFFSET_PX
	)
	position += world_offset * _scale_compensation


## The factor that turns this point's local sizes back into
## world sizes on a scaled item.
func _get_scale_compensation() -> float:
	var global_scale := absf(global_transform.get_scale().x)
	if global_scale <= 0.0001:
		return 1.0
	return 1.0 / global_scale


## Scales this point's own hit shapes up by the compensation,
## so the authored circle keeps its world size on a scaled
## item. Shape resources are shared between points; the
## shape nodes are not.
func _compensate_hit_shapes() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).scale *= (
				_scale_compensation
			)


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
		scale_factor = (
			art_size_px
			* _decal_size_scale
			* _scale_compensation
			/ longer_side
		)
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
	_decal_sprites = [art]


## Renders `total_count` decals for this spot in all (the art
## is the first). Each extra gets its own texture, turn and a
## small offset around the spot, so a bigger patch reads as
## more dirt, not a bigger blob. Subclasses call this from
## `_ready()` after `_set_up_art()`.
func _add_extra_decals(total_count: int) -> void:
	var decal_set := get_active_set()
	if not is_instance_valid(decal_set):
		return
	if decal_set.textures.is_empty():
		return
	for index in range(1, maxi(total_count, 1)):
		var decal := Sprite2D.new()
		add_child(decal)
		_configure_decal(decal, decal_set)
		decal.position = (
			Vector2.from_angle(randf() * TAU)
			* sqrt(randf())
			* art_size_px
			* 0.5
			* _scale_compensation
		)
		_decal_sprites.append(decal)


## Gives one decal sprite its texture, size, turn and color
## from a set, the way `_set_up_art()` gives the art's.
func _configure_decal(decal: Sprite2D, decal_set: DecalSet) -> void:
	var texture := decal_set.textures.pick_random() as Texture2D
	decal.texture = texture
	var visible_rect := DecalSpawner.get_visible_rect(texture)
	if visible_rect.size.x > 0.0 and visible_rect.size.y > 0.0:
		decal.region_enabled = true
		decal.region_rect = visible_rect
	var longer_side := maxf(visible_rect.size.x, visible_rect.size.y)
	var scale_factor := 1.0
	if longer_side > 0.0:
		scale_factor = (
			art_size_px
			* _decal_size_scale
			* _scale_compensation
			/ longer_side
		)
	scale_factor *= randf_range(
		decal_set.scale_range.x, decal_set.scale_range.y
	)
	decal.scale = Vector2.ONE * scale_factor
	decal.rotation = randf() * TAU
	decal.material = decal_set.blend_material
	decal.modulate = decal_set.tint * tint
	decal.modulate.a = _base_alpha * _decal_alpha_share


## Fades the decals to `share` of their configured alpha
## (1 is full dirt).
func _set_art_alpha(share: float) -> void:
	_decal_alpha_share = clampf(share, 0.0, 1.0)
	for decal in _decal_sprites:
		if is_instance_valid(decal):
			decal.modulate.a = _base_alpha * _decal_alpha_share
	if (
		_decal_sprites.is_empty() and is_instance_valid(art)
	):
		art.modulate.a = _base_alpha * _decal_alpha_share
