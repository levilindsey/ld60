class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO


var has_started := false
var has_won := false

## Linearly-decaying random-offset camera shake. New shake calls
## with a larger amplitude take over; smaller-amplitude calls during
## an active shake are ignored so a quiet event can't shorten a
## louder one.
var _shake_amplitude_px: float = 0.0
var _shake_initial_duration_sec: float = 0.0
var _shake_remaining_sec: float = 0.0


func _enter_tree() -> void:
	G.level = self


func _exit_tree() -> void:
	if G.level == self:
		G.level = null


func _ready() -> void:
	# Center the camera's anchor on its position. In Godot 4.5+ the
	# Camera2D default changed to FIXED_TOP_LEFT, which would make
	# the player render at the top-left of the screen given our
	# follow logic in _physics_process.
	%Camera2D.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


func _unhandled_input(event: InputEvent) -> void:
	pass


func start_game() -> void:
	G.print("Starting level", ScaffolderLog.CATEGORY_GAME_STATE)

	has_started = true
	has_won = false


## Call when the player wins. Shows the credits overlay; pressing
## jump/ability there starts a fresh run.
func win() -> void:
	if has_won:
		return
	G.print("Game won", ScaffolderLog.CATEGORY_GAME_STATE)
	has_won = true
	G.state.transition(StateMain.State.CREDITS)


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
