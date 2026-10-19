class_name StrikablePoint
extends InteractionPoint
## A point the hammer strikes (docs/design/hammer.md).
##
## Each target sets a strength band. Below it a hit only tinks.
## Inside it the hit works. Above it the hit works and dents, and
## far above it dents more. Subclasses say what a working hit does.


## Visible size of the decal an over hard hit leaves, in pixels.
const _DENT_SMALL_SIZE_PX := 30.0
const _DENT_LARGE_SIZE_PX := 44.0
const _CRACK_SIZE_PX := 52.0

## Charge where the band starts, from 0 to 1.
@export var band_min := 0.45
## Charge where the band ends, from 0 to 1.
@export var band_max := 0.75


## The hammer hit this point with this charge, from 0 to 1.
func on_struck(strength: float) -> void:
	if mode == Mode.FINISHED:
		return
	# Every hit squishes the piece a bit, dent or not.
	var layer := get_layer()
	if is_instance_valid(layer):
		layer.squish(strength)
	if strength < band_min:
		G.audio.play_sound(&"click")
		pulse()
		return
	mode = Mode.ACTIVE
	var is_over := strength > band_max
	if is_over:
		var is_far := (
			strength > band_max + G.settings.hammer_far_margin
		)
		# The point picks the defect, unless the piece overrules
		# its set (a seating on a dent piece dents, not cracks).
		var defect := get_over_defect(is_far)
		if is_instance_valid(layer):
			defect = layer.get_hammer_defect(is_far, defect)
		add_hammer_defect(defect)
		G.level.shake_camera(7.0, 0.15)
	else:
		G.level.shake_camera(4.0, 0.15)
	G.audio.play_sound(&"thud", true)
	apply_hit(strength, is_over)


## What one working hit does. Subclasses override this.
func apply_hit(_strength: float, _is_over: bool) -> void:
	pass


## The defect an over hard hit costs. Subclasses may override.
func get_over_defect(is_far: bool) -> RepairQuality.Defect:
	return (
		RepairQuality.Defect.DENT_LARGE
		if is_far
		else RepairQuality.Defect.DENT_SMALL
	)


## Records a defect on this point's item, and leaves the matching
## fitted dent or crack decal on the layer's art.
func add_hammer_defect(defect: RepairQuality.Defect) -> void:
	var item := get_item()
	if is_instance_valid(item):
		item.quality.add_defect(defect, global_position, self)
	var layer := get_layer()
	if not is_instance_valid(layer):
		return
	match defect:
		RepairQuality.Defect.DENT_SMALL:
			layer.spawn_decal(
				DecalSpawner.Kind.DENT,
				global_position,
				_DENT_SMALL_SIZE_PX,
			)
		RepairQuality.Defect.DENT_LARGE:
			layer.spawn_decal(
				DecalSpawner.Kind.DENT,
				global_position,
				_DENT_LARGE_SIZE_PX,
			)
		RepairQuality.Defect.CRACK:
			layer.spawn_decal(
				DecalSpawner.Kind.CRACK, global_position, _CRACK_SIZE_PX
			)
		_:
			pass
