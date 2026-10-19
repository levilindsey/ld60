extends "res://tests/probe_base.gd"
## Bread the bird. Boots the game, checks the bird stays hidden
## until enough repairables are through, then (standing in for
## the outbox) tells the controller the quota is met and the
## next item has landed: the smack plays, hides, and arms the
## peeks. One peek is then played directly to check its scene.
##
## Run it with `tests/run.ps1 -Name bird`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/bird/probe.tscn


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _controller: BirdController
var _smack: Node2D
var _peak: Node2D


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
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_controller = G.level.get_node("BirdController") as BirdController
	_smack = G.level.get_node(
		"Background/OutsideStuff/Scaler/BirdSmack"
	) as Node2D
	_peak = G.level.get_node(
		"Background/OutsideStuff/Scaler/BirdPeak"
	) as Node2D
	if not _expect(
		is_instance_valid(_controller)
		and is_instance_valid(_smack)
		and is_instance_valid(_peak),
		"the bird controller and both animations are in the level",
	):
		return
	_expect(
		not _smack.visible and not _peak.visible,
		"the bird starts hidden, before any repairable is through",
	)
	# Stand in for the outbox: the quota of repairables gets
	# through, then the next one lands. The smack follows a few
	# seconds into it.
	for repairable in BirdController.REPAIRABLES_BEFORE_SMACK:
		_controller._on_item_departed()
	_controller._on_item_landed()
	_expect(
		not _peak.visible,
		"the bird never peeks before the smack",
	)
	var smack_started := await _wait_until(
		func() -> bool: return _smack.visible,
		roundi(
			(BirdController.SMACK_DELAY_SEC + 3.0)
			* Engine.physics_ticks_per_second
		),
	)
	_expect(smack_started, "the smack plays into the next repairable")
	_expect(
		(_smack.get_node("AnimatedSprite2D") as AnimatedSprite2D)
		.is_playing(),
		"the smack animation is playing",
	)
	_expect(
		await _wait_until(
			func() -> bool: return not _smack.visible,
			roundi(6.0 * Engine.physics_ticks_per_second),
		),
		"the smack hides again when it finishes",
	)
	_expect(_controller._has_smacked, "the smack is marked as shown")
	# The peek loop is armed now; play one peek directly rather
	# than wait out the random interval.
	_controller._play_peak()
	_expect(
		_peak.visible
		and (_peak.get_node("AnimatedSprite2D") as AnimatedSprite2D)
		.is_playing(),
		"a peek plays after the smack",
	)
	_expect(
		await _wait_until(
			func() -> bool: return not _peak.visible,
			roundi(8.0 * Engine.physics_ticks_per_second),
		),
		"the peek hides again when it finishes",
	)


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false
