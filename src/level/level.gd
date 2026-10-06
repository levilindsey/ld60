class_name Level
extends Node2D


const _GAME_OVER_RESTART_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2.ZERO


var player: Node2D

var has_started := false
var has_finished := false
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
	start_game()


func start_game() -> void:
	G.print("Starting level", ScaffolderLog.CATEGORY_GAME_STATE)

	has_started = true
	has_finished = false
	has_won = false

	spawn_player()


## Call when the player loses. Waits a beat, then reloads the level.
func game_over() -> void:
	if has_finished:
		return
	G.print("Game over", ScaffolderLog.CATEGORY_GAME_STATE)
	has_finished = true
	await get_tree().create_timer(_GAME_OVER_RESTART_DELAY_SEC).timeout
	if is_instance_valid(G.game_panel):
		G.game_panel.restart_level()


## Call when the player wins. Shows the credits overlay; pressing
## jump/ability there starts a fresh run.
func win() -> void:
	if has_won:
		return
	G.print("Game won", ScaffolderLog.CATEGORY_GAME_STATE)
	has_won = true
	has_finished = true
	G.state.transition(StateMain.State.CREDITS)


func _physics_process(delta: float) -> void:
	if is_instance_valid(player):
		%Camera2D.global_position = (
			player.global_position + _PLAYER_CAMERA_OFFSET
		)
	else:
		%Camera2D.global_position = (
			%PlayerSpawnPoint.global_position + _PLAYER_CAMERA_OFFSET
		)
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


func spawn_player() -> void:
	if G.settings.player_scene == null:
		# No player scene is wired up yet. The camera parks on
		# %PlayerSpawnPoint until one is assigned in settings.tres.
		return
	player = G.settings.player_scene.instantiate()
	%Players.add_child(player)
	var spawn_position: Vector2 = %PlayerSpawnPoint.global_position
	player.global_position = spawn_position
	player.call_deferred("set_global_position", spawn_position)
