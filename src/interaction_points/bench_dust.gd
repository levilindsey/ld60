class_name BenchDust
extends DustClump
## Dust spewed onto the bench itself, not onto an item. A hard
## knock (a hammer whack on the TV) calls
## `Level.spawn_bench_dust()` and the clumps live under the
## level until the air blower cleans them or the item finishes
## and pays for what is left.
##
## The blower only scans the item's layers, so a bench clump
## cannot wait to be called the way an item clump is. It watches
## the blower instead: when a puff starts, it runs the same cone
## test the blower runs and sprays itself when it sits inside.
## The blower itself needs no changes.


## True once the leftover charge has taken this clump. It keeps
## a second charge from costing the same dust twice.
var is_charged := false

var _was_blower_squeezed := false


func _ready() -> void:
	super._ready()
	is_required = false


## Bench dust has no layer over it, so it is always reachable.
## Only a cleaned clump stops counting as exposed.
func is_exposed() -> bool:
	return mode != Mode.FINISHED


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_poll_blower()


## Sprays this clump when a fresh puff covers it. The test is
## the blower's own: inside the cone's length and half angle,
## full strength at the nozzle falling to a third at the far
## end, and one tap's worth of spray.
func _poll_blower() -> void:
	if mode == Mode.FINISHED or not is_visible_in_tree():
		_was_blower_squeezed = false
		return
	if not is_instance_valid(G.level):
		return
	var blower := G.level.tools_by_type.get(
		Tool.Type.AIR_BLOWER
	) as AirBlower
	if not is_instance_valid(blower):
		return
	var is_squeezed := (
		is_instance_valid(blower.cone_visual)
		and blower.cone_visual.visible
	)
	var is_fresh_puff := is_squeezed and not _was_blower_squeezed
	_was_blower_squeezed = is_squeezed
	if not is_fresh_puff:
		return
	var nozzle := blower.get_nozzle_position()
	var direction := blower.get_nozzle_direction()
	var offset := global_position - nozzle
	var distance := offset.length()
	var length := G.settings.air_cone_length_px
	if distance > length:
		return
	var strength := 1.0
	if distance > 1.0:
		var half_angle := deg_to_rad(
			G.settings.air_cone_half_angle_deg
		)
		if absf(offset.angle_to(direction)) > half_angle:
			return
		strength = lerpf(1.0, 1.0 / 3.0, distance / length)
	on_sprayed(strength, direction, G.settings.air_puff_sec)
