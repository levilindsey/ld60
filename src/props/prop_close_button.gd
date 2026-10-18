class_name PropCloseButton
extends Node2D
## The close button that floats beside a lifted prop. It pops in with a
## slight overshoot and a half spin, and plays the reverse to pop out.


const _POP_DURATION_SEC := 0.3
## How far the button overshoots its size as it pops in.
const _OVERSHOOT := 1.7
## How far the button is spun while fully shrunk.
const _SPIN_RADIANS := -PI


## Size of the tap target, centered on the button.
@export var hit_size := Vector2(48, 48)


func _ready() -> void:
	visible = false


func pop_in() -> void:
	visible = true
	_set_appearance(0.0)
	%Sprite.reset_physics_interpolation()
	_tween_appearance(0.0, 1.0, _set_appearance.bind(1.0))


func pop_out() -> void:
	_tween_appearance(1.0, 0.0, hide)


## Whether a press lands on the button while it's showing.
func is_pressed_by(event: InputEventMouse) -> bool:
	if not visible:
		return false
	var point := (make_input_local(event) as InputEventMouse).position
	return Rect2(-hit_size / 2.0, hit_size).has_point(point)


func _tween_appearance(
	from_appearance: float,
	to_appearance: float,
	on_completed: Callable,
) -> void:
	G.time.tween_method(
		self,
		"_set_appearance",
		from_appearance,
		to_appearance,
		_POP_DURATION_SEC,
		"linear",
		0.0,
		TimeType.APP_PHYSICS,
		on_completed,
	)


## 0 is fully shrunk and spun away; 1 is at rest. Scale follows a "back"
## curve, so it overshoots slightly on the way in and winds up slightly
## before shrinking on the way out.
func _set_appearance(appearance: float) -> void:
	var t := appearance - 1.0
	var back_scale := (
		1.0
		+ (_OVERSHOOT + 1.0) * t * t * t
		+ _OVERSHOOT * t * t
	)
	%Sprite.scale = Vector2.ONE * maxf(back_scale, 0.0)
	%Sprite.rotation = _SPIN_RADIANS * t * t
