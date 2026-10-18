class_name DecalSpawner
extends Node
## Spawns runtime decals (skids, dents, cracks) on a part. A decal is a
## `Sprite2D` child of the part, so it moves with the part when its layer
## lifts off. Instance `decal_spawner.tscn` in the level as `%Decals`: it
## has the sets assigned, and a bare `DecalSpawner.new()` has none.
##
## `spawn(kind, part, global_position, size, direction)` is the whole API.
## The spawner turns on the part's clipping, so callers only pass the part.
##
## To add a kind:
## 1. Add an entry to `Kind`.
## 2. Add an export named after it below (DENT uses `dent_set`).
## 3. Make a `DecalSet` `.tres` for it and assign it in
##    `decal_spawner.tscn`.
## `_ready` stops the game with a message if a kind has no set.


enum Kind {
	SKID,
	GLUE_BLOB,
}

@export var skid_set: DecalSet
@export var glue_blob_set: DecalSet

## Picks the texture, rotation, scale and flips. A test can set its seed.
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.randomize()
	for kind_name: String in Kind.keys():
		G.check(
			get_set(Kind[kind_name]) != null,
			"No decal set for %s. Assign %s_set in decal_spawner.tscn." % [
				kind_name,
				kind_name.to_lower(),
			],
		)


## Returns the `DecalSet` for a kind, or null if none is assigned.
func get_set(kind: Kind) -> DecalSet:
	var kind_name: Variant = Kind.find_key(kind)
	if kind_name == null:
		return null
	return get("%s_set" % String(kind_name).to_lower()) as DecalSet


## Adds a decal of this kind to `part` and returns it (null if it can't).
##
## - `part` is a Control or a Node2D that is in the tree. It should be the
##   node that draws the art, such as a `ColorRect` or a `Sprite2D`: the
##   decal only shows where that node is opaque. Its clip applies to all of
##   its children. A part that draws nothing, such as a plain `Node2D`,
##   clips nothing, so its decals show in full.
## - `global_position` is where the decal's center goes, in world pixels.
##   It may be over the part's edge. The part clips what hangs over.
## - `size` is the length of the decal's longer side in world pixels,
##   whatever the part's scale or rotation. The set's `scale_range` varies
##   it a little.
## - `direction` is the world direction of the damage, such as the way a
##   screwdriver slipped. Only sets that align to the direction use it.
func spawn(
		kind: Kind,
		part: CanvasItem,
		global_position: Vector2,
		size: float,
		direction := Vector2.RIGHT,
) -> Sprite2D:
	var decal_set := get_set(kind)
	if not _is_spawn_valid(kind, decal_set, part, size):
		return null

	var texture: Texture2D = decal_set.textures[
		random.randi() % decal_set.textures.size()
	]
	var longer_side := maxf(texture.get_width(), texture.get_height())

	var decal := Sprite2D.new()
	decal.texture = texture
	decal.flip_h = decal_set.can_flip_horizontally and random.randf() < 0.5
	decal.flip_v = decal_set.can_flip_vertically and random.randf() < 0.5
	decal.modulate = decal_set.tint
	decal.material = decal_set.blend_material

	var world_rotation := random.randf() * TAU
	if decal_set.is_aligned_to_direction and not direction.is_zero_approx():
		world_rotation = direction.angle()
	var world_scale := (
		size
		* random.randf_range(decal_set.scale_range.x, decal_set.scale_range.y)
		/ longer_side
	)

	_set_up_clipping(part)
	part.add_child(decal)
	# Setting the global transform makes the decal's size, rotation and
	# position come out in world pixels. Godot works out the local transform
	# from the part's own scale, rotation and origin, so any part works.
	decal.global_transform = Transform2D(
		world_rotation,
		Vector2.ONE * world_scale,
		0.0,
		global_position,
	)
	# Physics interpolation is on, so don't slide in from the origin.
	decal.reset_physics_interpolation()
	return decal


func _is_spawn_valid(
		kind: Kind,
		decal_set: DecalSet,
		part: CanvasItem,
		size: float,
) -> bool:
	return (
		G.ensure(decal_set != null, "No decal set for kind %s." % kind)
		and G.ensure_valid(part, "Decal part is not a valid node.")
		and G.ensure(part.is_inside_tree(), "Decal part is not in the tree.")
		and G.ensure(size > 0.0, "Decal size must be positive.")
		and G.ensure(
			not decal_set.textures.is_empty(),
			"Decal set for kind %s has no textures." % kind,
		)
		and G.ensure(
			decal_set.textures.all(_is_texture_usable),
			"Decal set for kind %s has a missing or empty texture." % kind,
		)
	)


func _is_texture_usable(texture: Texture2D) -> bool:
	return (
		is_instance_valid(texture)
		and not texture.get_size().is_zero_approx()
	)


# Clips the part's children to the part's own drawn shape. A part that
# already clips (for example one set up as a mask) is left as it is.
func _set_up_clipping(part: CanvasItem) -> void:
	if part.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED:
		part.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
