class_name Toaster
extends Repairable
## A toaster on wheels, with a face nobody notices until it's fixed.
##
## One front wheel falls off as it arrives. Once that wheel is glued back
## on, the toaster won't sit still: it scoots left and right on the bench.
## A couple of hammer hits (`%Thump`) settle it down, and the last hit
## knocks the other front wheel off, to be glued on too. Grime to wipe
## off rounds it out. When it's finished, its face appears.


## How far one scoot moves the toaster, in pixels.
const _SCOOT_MIN_PX := 30.0
const _SCOOT_MAX_PX := 70.0
## How far the toaster may wander from where it started, in pixels.
const _WANDER_RANGE_PX := 110.0
const _SCOOT_SEC := 0.35
## How high a scoot hops, in pixels.
const _SCOOT_HOP_PX := 8.0
const _SCOOT_ROCK_RADIANS := 0.08
## The pause between scoots, in seconds.
const _SCOOT_WAIT_MIN_SEC := 0.8
const _SCOOT_WAIT_MAX_SEC := 2.0
## Where the knocked-off wheel lands, from the toaster's middle.
const _KNOCKED_WHEEL_OFFSET := Vector2(-170.0, 50.0)
const _FACE_POP_SEC := 0.35
## How high the toaster hops when its face appears, in pixels.
const _FACE_HOP_PX := 18.0


var _is_wandering := false
var _wander_home_x := 0.0
var _scoot_wait_sec := 0.0
var _scoot_tween: Tween


func _ready() -> void:
	super()
	%Thump.visible = false
	%Face.visible = false
	point_finished.connect(_on_point_finished)
	finished.connect(_show_face)


func _physics_process(delta: float) -> void:
	super(delta)
	if not _is_wandering or mode != Mode.UNDER_REPAIR:
		return
	if is_instance_valid(_scoot_tween) and _scoot_tween.is_running():
		return
	_scoot_wait_sec -= delta
	if _scoot_wait_sec <= 0.0:
		_scoot()


func _on_point_finished(point: InteractionPoint) -> void:
	if (
		point == %FirstWheelPoint
		and %Thump.mode != InteractionPoint.Mode.FINISHED
	):
		_start_wandering()
	elif point == %Thump:
		_stop_wandering()
		%SecondWheel.knock_off(global_position + _KNOCKED_WHEEL_OFFSET)


func _start_wandering() -> void:
	if _is_wandering:
		return
	_is_wandering = true
	_wander_home_x = global_position.x
	_scoot_wait_sec = _SCOOT_WAIT_MIN_SEC
	%Thump.visible = true


func _stop_wandering() -> void:
	_is_wandering = false
	if is_instance_valid(_scoot_tween):
		_scoot_tween.kill()
	rotation = 0.0


## One hop to the side, back toward the start once it strays too far.
func _scoot() -> void:
	_scoot_wait_sec = randf_range(_SCOOT_WAIT_MIN_SEC, _SCOOT_WAIT_MAX_SEC)
	var side := 1.0 if randf() < 0.5 else -1.0
	var away := global_position.x - _wander_home_x
	if absf(away) > _WANDER_RANGE_PX * 0.5:
		side = -signf(away)
	var from_x := global_position.x
	var to_x := clampf(
		from_x + side * randf_range(_SCOOT_MIN_PX, _SCOOT_MAX_PX),
		_wander_home_x - _WANDER_RANGE_PX,
		_wander_home_x + _WANDER_RANGE_PX,
	)
	var base_y := global_position.y
	G.audio.play_sound(&"skid", true)
	_scoot_tween = create_tween()
	_scoot_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_scoot_tween.tween_method(
		_set_scoot.bind(from_x, to_x, base_y, side),
		0.0,
		1.0,
		_SCOOT_SEC,
	)


func _set_scoot(
	progress: float,
	from_x: float,
	to_x: float,
	base_y: float,
	side: float,
) -> void:
	var eased := ease(progress, -2.0)
	global_position = Vector2(
		lerpf(from_x, to_x, eased),
		base_y - sin(progress * PI) * _SCOOT_HOP_PX,
	)
	rotation = side * sin(progress * PI) * _SCOOT_ROCK_RADIANS


## The payoff: the face pops onto the front panel with a little hop.
func _show_face() -> void:
	%Face.visible = true
	var face_scale: Vector2 = %Face.scale
	%Face.scale = face_scale * 1.3
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(%Face, "scale", face_scale, _FACE_POP_SEC)
	tween.parallel().tween_method(
		_set_face_hop,
		0.0,
		1.0,
		_FACE_POP_SEC,
	)


func _set_face_hop(progress: float) -> void:
	%Layers.position.y = -sin(progress * PI) * _FACE_HOP_PX
