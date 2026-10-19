class_name Glue
extends Tool
## The glue bottle (docs/design/glue.md). Press and hold to
## squeeze, then trace a crack to cover it, or dab a broken
## point so its piece can be held back on. Flooding a crack
## leaves a blob. Squeezing anywhere else on a piece the
## hammer could dent (its surface, or the art of its exposed
## layer when it has no surface there) leaves a smear for
## the rag.


## How often an off-target squeeze smears, in seconds.
const _OFF_TARGET_BLOB_SEC := 0.5

## The bottle art. It squashes a little while squeezing.
@export var art: Node2D

var _is_squeezing := false
var _off_target_sec := 0.0


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _is_squeezing or delta <= 0.0:
		return
	# Glue leaves the working end, never the cursor marker or
	# the bottle's origin. A crack takes it where the working
	# end passes. A broken point takes it while the tool's
	# InteractionArea overlaps the point's own area.
	var nozzle := get_work_end_position()
	var amount := G.settings.glue_flow_rate * delta
	var hit := false
	if is_instance_valid(G.level) and is_instance_valid(
		G.level.active_repairable
	):
		for layer in G.level.active_repairable.layers:
			for point in layer.get_points():
				if not point.is_exposed():
					continue
				if not point.is_visible_in_tree():
					continue
				if point is Crack:
					if (point as Crack).on_glued(
						nozzle,
						G.settings.glue_radius_px,
						amount,
					):
						hit = true
	for area in interaction_area.get_overlapping_areas():
		var broken := area as BrokenPoint
		if not is_instance_valid(broken):
			continue
		if not broken.is_exposed() or not broken.is_visible_in_tree():
			continue
		if broken.on_glued(
			broken.global_position,
			G.settings.glue_radius_px,
			amount,
		):
			hit = true
	if hit:
		_off_target_sec = 0.0
		return
	_off_target_sec += delta
	if _off_target_sec >= _OFF_TARGET_BLOB_SEC:
		_off_target_sec = 0.0
		_smear_on_surface(nozzle)


func is_effect_tool() -> bool:
	return true


## A press starts the squeeze. The click itself already
## glues a broken point whose area the tool's InteractionArea
## overlaps, so a click on the nozzle counts at once. The
## shape query reads the working end where the press put it,
## where the physics overlaps have not caught up yet.
func on_effect_pressed(_global_point: Vector2) -> void:
	_is_squeezing = true
	_off_target_sec = 0.0
	art.scale = Vector2(1.0, 0.9)
	if is_instance_valid(G.level):
		G.level.hand.set_input_owner(self)
		var broken := _find_broken_point_at_work_end()
		if is_instance_valid(broken):
			broken.on_glued(
				broken.global_position,
				G.settings.glue_radius_px,
				1.0,
			)
	G.audio.play_sound(&"scrape")


## The broken point under the working end right now, by the
## InteractionArea's own shape, or null. Other points in the
## way do not hide it.
func _find_broken_point_at_work_end() -> BrokenPoint:
	var shape_node := get_interaction_shape()
	if not is_instance_valid(shape_node):
		return null
	if not is_instance_valid(shape_node.shape):
		return null
	var parameters := PhysicsShapeQueryParameters2D.new()
	parameters.shape = shape_node.shape
	parameters.transform = shape_node.global_transform
	parameters.collision_mask = (
		Settings.PhysicsLayer.INTERACTION_POINTS
	)
	parameters.collide_with_areas = true
	parameters.collide_with_bodies = false
	var space := get_world_2d().direct_space_state
	for result in space.intersect_shape(parameters, 32):
		var broken := result.collider as BrokenPoint
		if (
			is_instance_valid(broken)
			and broken.is_exposed()
			and broken.is_visible_in_tree()
		):
			return broken
	return null


func on_pointer_released(_global_point: Vector2) -> void:
	_stop_squeezing()


func put_away() -> void:
	_stop_squeezing()
	super.put_away()


func _stop_squeezing() -> void:
	_is_squeezing = false
	if is_instance_valid(art):
		art.scale = Vector2.ONE
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


## Glue where no point wanted it: a smear the rag can wipe
## off. It lands on the same sorts of places the hammer can
## dent: a surface, or, where a piece has no surface there,
## the art of its exposed layer (a strikable point's layer,
## say). It costs nothing while it can still be cleaned. An
## item that finishes with a smear on it pays for it then
## (see Repairable). A spot already smeared does not smear
## again.
func _smear_on_surface(at_position: Vector2) -> void:
	if not is_instance_valid(G.level):
		return
	if not is_instance_valid(G.settings.glue_smear_scene):
		return
	var layer := _find_smear_layer(at_position)
	if not is_instance_valid(layer) or not is_instance_valid(layer.art):
		return
	for point in layer.get_points():
		var smear := point as GlueSmear
		if not is_instance_valid(smear):
			continue
		if smear.mode == InteractionPoint.Mode.FINISHED:
			continue
		if smear.global_position.distance_to(at_position) < 30.0:
			return
	var smear := G.settings.glue_smear_scene.instantiate() as GlueSmear
	if not is_instance_valid(smear):
		return
	layer.add_child(smear)
	smear.global_position = at_position
	smear.rotation = randf() * TAU
	smear.reset_physics_interpolation()
	smear.setup_decal()


## The layer a smear lands on at a world position: the
## active surface's layer, or, where the exposed piece has
## no surface there, the exposed layer whose art is under
## the nozzle. The hammer dents both sorts of place.
func _find_smear_layer(at_position: Vector2) -> RepairLayer:
	var surface := G.level.hand.find_surface(at_position)
	if is_instance_valid(surface) and surface.is_active():
		return surface.get_layer()
	if not is_instance_valid(G.level.active_repairable):
		return null
	for layer in G.level.active_repairable.layers:
		if layer.is_exposed() and layer.has_point(at_position):
			return layer
	return null
