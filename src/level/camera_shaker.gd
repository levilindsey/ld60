class_name CameraShaker
extends Node


## Linearly-decaying random-offset camera shake. New shake calls
## with a larger amplitude take over; smaller-amplitude calls during
## an active shake are ignored so a quiet event can't shorten a
## louder one.
var _shake_amplitude_px: float = 0.0
var _shake_initial_duration_sec: float = 0.0
var _shake_remaining_sec: float = 0.0

@export var camera: Camera2D


func _physics_process(delta: float) -> void:
	_tick_camera_shake(delta)


func shake_camera(amplitude_px: float, duration_sec: float) -> void:
	if amplitude_px <= 0.0 or duration_sec <= 0.0:
		return
	if amplitude_px < _shake_amplitude_px and _shake_remaining_sec > 0.0:
		return
	_shake_amplitude_px = amplitude_px
	_shake_initial_duration_sec = duration_sec
	_shake_remaining_sec = duration_sec


func _tick_camera_shake(delta: float) -> void:
	if _shake_remaining_sec <= 0.0:
		if %Camera2D.offset != Vector2.ZERO:
			%Camera2D.offset = Vector2.ZERO
		return
	_shake_remaining_sec -= delta
	if _shake_remaining_sec <= 0.0:
		_shake_amplitude_px = 0.0
		%Camera2D.offset = Vector2.ZERO
		return
	var t: float = (
		_shake_remaining_sec
		/ maxf(_shake_initial_duration_sec, 0.001)
	)
	var amp: float = _shake_amplitude_px * t
	%Camera2D.offset = Vector2(
			randf_range(-amp, amp),
			randf_range(-amp, amp))
