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
## The speed the spew threw this clump at, in world pixels per
## second. It eases to nothing over the flight, and the clump
## settles wherever it stops.
var velocity := Vector2.ZERO
## True once the clump has come to rest. Only then is it a
## normal interaction point, at the spot where it settled.
var is_settled := true

var _was_blower_squeezed := false
var _launch_velocity := Vector2.ZERO
var _flight_total_sec := 0.0
var _flight_left_sec := 0.0


func _ready() -> void:
	super._ready()
	is_required = false


## Throws the clump at `p_velocity` for `flight_sec`. It
## slides that long, slowing evenly, and settles where it
## stops (the bench edge may stop it sooner).
func launch(p_velocity: Vector2, flight_sec: float) -> void:
	velocity = p_velocity
	_launch_velocity = p_velocity
	_flight_total_sec = maxf(flight_sec, 0.01)
	_flight_left_sec = _flight_total_sec
	is_settled = velocity.is_zero_approx()


## Bench dust has no layer over it, so a settled clump is
## always reachable. A flying clump is not a point yet, and
## only a cleaned clump stops counting as exposed.
func is_exposed() -> bool:
	return is_settled and mode != Mode.FINISHED


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_slide(delta)
	_poll_blower()


## Slides the flying clump across the bench, slowing evenly
## to a stop inside the bench. Where it stops is where the
## point lives from then on.
func _slide(delta: float) -> void:
	if is_settled or delta <= 0.0:
		return
	global_position += velocity * delta
	if is_instance_valid(G.level):
		global_position = G.level.clamp_to_bench(global_position)
	_flight_left_sec -= delta
	if _flight_left_sec <= 0.0:
		velocity = Vector2.ZERO
		is_settled = true
		return
	velocity = (
		_launch_velocity * (_flight_left_sec / _flight_total_sec)
	)


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
