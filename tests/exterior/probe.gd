extends "res://tests/probe_base.gd"
## The exterior title screen. Boots the game to the title, checks
## the wall and door are showing with the old title message on
## the door's sign in Young Serif, then taps and checks the walk
## inside plays (door opens, no instant start) and lands in the
## game with a level running.
##
## Run it with `tests/run.ps1 -Name exterior`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/exterior/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	if _is_taking_screenshots:
		var blocker := _RealInputBlocker.new()
		blocker.probe = self
		add_child(blocker)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.5)
	if not _expect(
		G.state.state == StateMain.State.TITLE,
		"the game boots to the title",
	):
		return
	_expect(
		is_instance_valid(G.level) and not G.level.visible,
		"the level is built and hidden behind the title",
	)
	var exterior := (
		G.hud.get_node("TitleOverlay/Exterior") as Exterior
	)
	if not _expect(
		is_instance_valid(exterior), "the title shows the exterior"
	):
		return
	_expect(
		exterior.wall_texture.resource_path
		== "res://assets/images/repairables/exterior_wall.png",
		"the exterior shows the wall art",
	)
	var sign_title := exterior.get_node("SignViewport/SignTitle") as Label
	var sign_sub := exterior.get_node("SignViewport/SignSub") as Label
	_expect(
		sign_title.text == "Repair Shop"
		and sign_sub.text == "Come on in",
		"the sign carries the old title message",
	)
	var sign_font := sign_title.get_theme_font("font")
	_expect(
		is_instance_valid(sign_font)
		and sign_font.resource_path
		== "res://assets/fonts/young_serif/YoungSerif-Regular.ttf",
		"the sign is lettered in Young Serif",
	)
	var door := exterior.get_node("Zoom/Door") as ExteriorDoor
	_expect(
		is_instance_valid(door) and door.get_open_amount() == 0.0,
		"the door starts shut",
	)
	await _shot("title")

	# Tap the door: the walk inside plays instead of starting at
	# once, and the game follows once the door is open.
	await _tap_at(Vector2(640, 400))
	await _seconds(0.4)
	_expect(
		G.state.state == StateMain.State.TITLE
		and door.get_open_amount() > 0.05,
		"the tap opens the door before the game starts",
	)
	_expect(
		is_instance_valid(G.level) and G.level.visible,
		"the shop is already showing under the fade",
	)
	await _shot("door_opening")
	var waited_sec := 0.0
	while G.state.state != StateMain.State.GAME and waited_sec < 4.0:
		await _seconds(0.2)
		waited_sec += 0.2
	_expect(
		G.state.state == StateMain.State.GAME,
		"the walk inside lands in the game",
	)
	_expect(
		is_instance_valid(G.level), "the level is running inside"
	)


## A tap at a screen point, the way a player's arrives. (The
## title has no level yet, so the world-space press helpers do
## not apply.)
func _tap_at(screen_point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_point
	_is_pushing = true
	get_viewport().push_input(press, true)
	_is_pushing = false
	await _physics_frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen_point
	_is_pushing = true
	get_viewport().push_input(release, true)
	_is_pushing = false
	await _physics_frames(2)
