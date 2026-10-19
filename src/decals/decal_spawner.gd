class_name DecalSpawner
extends Node
## Spawns runtime decals (skids, dents, cracks) on a part. A decal is a
## `Sprite2D` child of the part, so it moves with the part when its layer
## lifts off. Instance `decal_spawner.tscn` in the level as `%Decals`: it
## has the sets assigned, and a bare `DecalSpawner.new()` has none.
##
## `spawn(kind, part, global_position, size, direction)` is the whole API.
## The spawner clips the decal (to the part's layer's Shape
## where it has one, else to the part's own art), so callers
## only pass the part.
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
	DENT,
	CRACK,
	SCRATCH,
	RUST,
	DUST,
	DUST_2,
	GRIME,
	GRIME_2,
}

## The longest side a fitted decal may span, as a share of the part's
## longest side. See `fit_size()`.
const _MAX_PART_SHARE := 0.95
## A fitted decal's center stays this share of its size inside the
## part's edge. See `fit_position()`.
const _FIT_INSET_SHARE := 0.35

@export var skid_set: DecalSet
@export var glue_blob_set: DecalSet
@export var dent_set: DecalSet
@export var crack_set: DecalSet
@export var scratch_set: DecalSet
@export var rust_set: DecalSet
@export var dust_set: DecalSet
@export var dust_2_set: DecalSet
@export var grime_set: DecalSet
@export var grime_2_set: DecalSet

static var _visible_rects: Dictionary = {}

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
## - `size` is the length of the visible art's longer side in world
##   pixels, whatever the part's scale or rotation. The set's
##   `scale_range` varies it a little.
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
	# The textures carry a wide transparent margin, so `size` is the
	# longer side of the visible art, not of the whole picture.
	var visible_rect := get_visible_rect(texture)
	var longer_side := maxf(visible_rect.size.x, visible_rect.size.y)

	var decal := Sprite2D.new()
	decal.texture = texture
	if visible_rect.size.x > 0.0 and visible_rect.size.y > 0.0:
		decal.region_enabled = true
		decal.region_rect = visible_rect
	decal.flip_h = decal_set.can_flip_horizontally and random.randf() < 0.5
	decal.flip_v = decal_set.can_flip_vertically and random.randf() < 0.5
	decal.modulate = decal_set.tint
	decal.material = decal_set.blend_material

	var world_rotation := part.get_global_transform().get_rotation()
	if decal_set.is_aligned_to_direction and not direction.is_zero_approx():
		world_rotation = direction.angle()
	elif decal_set.has_random_rotation:
		world_rotation = random.randf() * TAU
	var world_scale := (
		size
		* random.randf_range(decal_set.scale_range.x, decal_set.scale_range.y)
		/ longer_side
	)

	_get_decal_parent(part).add_child(decal)
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


## The rect of a texture's visible art, in texture pixels. The decal
## textures are drawn small in the middle of a big transparent
## picture, so this is much smaller than the texture. A texture whose
## image cannot be read gives its full rect.
static func get_visible_rect(texture: Texture2D) -> Rect2:
	if _visible_rects.has(texture):
		return _visible_rects[texture]
	var rect := Rect2(Vector2.ZERO, texture.get_size())
	var image := texture.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = Rect2(used)
	_visible_rects[texture] = rect
	return rect


## The rect a part draws in, in the part's own pixels: a `Control`'s
## size, a `Sprite2D`'s rect, or the bounds of a `Polygon2D`'s points.
## Anything else gives an empty rect, and the fit helpers below then
## leave their input alone.
static func get_part_rect(part: CanvasItem) -> Rect2:
	if part is Control:
		return Rect2(Vector2.ZERO, (part as Control).size)
	if part is Sprite2D:
		return (part as Sprite2D).get_rect()
	if part is Polygon2D:
		var polygon := (part as Polygon2D).polygon
		if polygon.is_empty():
			return Rect2()
		var rect := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			rect = rect.expand(point)
		return rect
	return Rect2()


## Shrinks `size` so a decal of that visible size fits on `part`: at
## most `_MAX_PART_SHARE` of the part's longest side.
static func fit_size(part: CanvasItem, size: float) -> float:
	var rect := get_part_rect(part)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return size
	return minf(size, maxf(rect.size.x, rect.size.y) * _MAX_PART_SHARE)


## Nudges a world position so a decal of `size` centered there stays
## inside `part`'s rect, with a margin. A part too small for the
## margin centers the decal instead. The spawner's clipping is still
## the safety net for a spun decal's corners.
static func fit_position(
	part: CanvasItem, world_position: Vector2, size: float
) -> Vector2:
	var rect := get_part_rect(part)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return world_position
	var transform := part.get_global_transform()
	var local := transform.affine_inverse() * world_position
	var inset := size * _FIT_INSET_SHARE
	local.x = _fit_axis(local.x, rect.position.x, rect.end.x, inset)
	local.y = _fit_axis(local.y, rect.position.y, rect.end.y, inset)
	return transform * local


static func _fit_axis(
	value: float, low: float, high: float, inset: float
) -> float:
	if low + inset > high - inset:
		return (low + high) * 0.5
	return clampf(value, low + inset, high - inset)


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


## The name of the per-part mask node `_get_decal_parent()`
## makes, reused by every later decal on the same part.
const _SHAPE_MASK_NAME := "DecalShapeMask"


## Where a fresh decal goes under `part`: inside a mask shaped
## like the part's layer's authored Shape, when that layer has
## a polygon Shape, so the decal only shows within the Shape
## region. Godot clips canvas children to a parent's drawn
## alpha, and a filled `Polygon2D` set to CLIP_CHILDREN_ONLY
## draws nothing itself but clips its children to its fill, so
## the Shape's polygon becomes the mask. The polygon is taken
## in the part's own points at spawn time, so it moves with the
## part (and its layer) afterwards. Without a usable Shape, the
## part's own clipping (its texture alpha) does the job, as
## before.
func _get_decal_parent(part: CanvasItem) -> CanvasItem:
	var layer := _find_layer(part)
	if is_instance_valid(layer):
		var world_polygon := layer.get_shape_world_polygon()
		if world_polygon.size() >= 3:
			var mask := (
				part.get_node_or_null(_SHAPE_MASK_NAME) as Polygon2D
			)
			if not is_instance_valid(mask):
				mask = Polygon2D.new()
				mask.name = _SHAPE_MASK_NAME
				mask.color = Color.WHITE
				mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
				part.add_child(mask)
			mask.polygon = OutlineHint.world_polygon_to_local(
				part, world_polygon
			)
			return mask
	_set_up_clipping(part)
	return part


## The repair layer `part` belongs to, or null.
func _find_layer(part: CanvasItem) -> RepairLayer:
	var node: Node = part
	while is_instance_valid(node):
		if node is RepairLayer:
			return node as RepairLayer
		node = node.get_parent()
	return null


# Clips the part's children to the part's own drawn shape. A part that
# already clips (for example one set up as a mask) is left as it is.
func _set_up_clipping(part: CanvasItem) -> void:
	if part.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED:
		part.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
