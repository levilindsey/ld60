class_name StrikablePoint
extends InteractionPoint
## A point the hammer strikes (docs/design/hammer.md).
##
## Each target sets a strength band. Below it a hit only tinks.
## Inside it the hit works. Above it the hit works and dents, and
## far above it dents more. Subclasses say what a working hit does.


## Charge where the band starts, from 0 to 1.
@export var band_min := 0.45
## Charge where the band ends, from 0 to 1.
@export var band_max := 0.75


## The hammer hit this point with this charge, from 0 to 1.
func on_struck(strength: float) -> void:
	if mode == Mode.FINISHED:
		return
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
		add_hammer_defect(get_over_defect(is_far))
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


## Records a defect on this point's item.
func add_hammer_defect(defect: RepairQuality.Defect) -> void:
	var item := get_item()
	if is_instance_valid(item):
		item.quality.add_defect(defect, global_position, self)
