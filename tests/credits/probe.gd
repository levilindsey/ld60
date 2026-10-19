extends "res://tests/probe_base.gd"
## The credits card. Boots the game and wins it outright (the
## item flow itself is other probes' job): the credits card
## floats down to the middle of the screen, the HUD credits
## overlay stays down, and presses on the bench and the rack do
## nothing at all.
##
## Run it with `tests/run.ps1 -Name credits`, or from the repo
## root (PowerShell):
##   godot --headless --path . res://tests/credits/probe.tscn


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 60.0


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	await get_tree().process_frame
	var main: Node = (load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _run()
	_finish(0 if _failures.is_empty() else 1)


func _run() -> void:
	await _seconds(0.3)
	# A second run of this probe (`--credits-at-start` in
	# tests/run.ps1) flips the settings flag instead: the
	# credits then show at the start, with no win called.
	var at_start := OS.get_cmdline_user_args().has("--credits-at-start")
	G.settings.show_credits_at_start = at_start
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	var card := G.level.get_node("CreditsCard") as CreditsCard
	if at_start:
		_expect(
			await _wait_until(
				func() -> bool:
					return (
						G.state.state == StateMain.State.CREDITS
						and card.visible
					),
				roundi(5.0 * Engine.physics_ticks_per_second),
			),
			"the credits show at the start with the flag on",
		)
	else:
		if not _expect(
			await _wait_for_landing(), "the first item lands"
		):
			return
		_expect(not card.visible, "the credits card starts hidden")
		G.level.win()
	_hand = G.level.hand
	_expect(
		G.state.state == StateMain.State.CREDITS,
		"winning enters the credits state",
	)
	_expect(
		await _wait_until(
			func() -> bool:
				return card.visible and card.position.length() < 4.0,
			roundi(5.0 * Engine.physics_ticks_per_second),
		),
		"the credits card floats down to the middle of the screen",
	)
	var overlay := G.hud.get_node("%CreditsOverlay") as Control
	_expect(
		overlay.modulate.a < 0.05,
		"the HUD credits overlay stays down",
	)
	_expect(
		(card.get_node("ThanksLabel") as Label).text
		== "Thanks for playing!",
		"the card carries the credits text",
	)
	# Nothing on the bench answers a press any more.
	await _press_at(Vector2(360.0, 60.0))
	var rack_tool := G.level.tools_by_type.values()[0] as Tool
	await _press_at(rack_tool.global_position)
	await _seconds(0.3)
	_expect(
		G.level.hand.is_empty(),
		"no press picks anything up behind the credits",
	)
	_expect(
		G.state.state == StateMain.State.CREDITS,
		"the game stays in the credits state",
	)
	_expect(
		card.visible and card.position.length() < 4.0,
		"the credits card stays in the middle",
	)


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false
