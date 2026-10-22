extends "res://tests/probe_base.gd"
## Bread the bird. Boots the game, checks the bird stays hidden
## on the first repairable, then (standing in for the schedule)
## puts the bench at the smack's repairable index and lands an
## item there: the smack plays, falls to its marker, cleans
## itself up, and arms the peeks. One peek is then played
## directly to check its scene.
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
	# A second run of this probe (`--bird-at-start` in
	# tests/run.ps1) flips the settings flag instead: the slam
	# then plays at the start, on the first repairable.
	var at_start := OS.get_cmdline_user_args().has("--bird-at-start")
	G.settings.show_bird_slam_at_start = at_start
	G.state.transition(StateMain.State.GAME)
	await _seconds(0.8)
	if not _expect(is_instance_valid(G.level), "the level is running"):
		return
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_controller = G.level.get_node("BirdController") as BirdController
	_smack = G.level.get_node(
		"Background/OutsideStuff/BirdSmack"
	) as Node2D
	_peak = G.level.get_node(
		"Background/OutsideStuff/BirdPeak"
	) as Node2D
	if not _expect(
		is_instance_valid(_controller)
		and is_instance_valid(_smack)
		and is_instance_valid(_peak),
		"the bird controller and both animations are in the level",
	):
		return
	if at_start:
		# The flag plays the slam at the start: it lands on the
		# first repairable, with no schedule stand-in at all.
		var slam_started := await _wait_until(
			func() -> bool: return _smack.visible,
			roundi(
				(BirdController.SMACK_DELAY_SEC + 4.0)
				* Engine.physics_ticks_per_second
			),
		)
		_expect(slam_started, "the slam plays at the start")
		_expect(
			_controller._has_smacked,
			"the at-start slam is marked as shown",
		)
	else:
		_expect(
			not _smack.visible and not _peak.visible,
			"the bird starts hidden, before any repairable is through",
		)
		# The first item is before the smack's slot in the schedule:
		# landing it must not arm anything.
		_controller._on_item_landed()
		await _seconds(BirdController.SMACK_DELAY_SEC + 0.6)
		_expect(
			not _smack.visible and not _controller._has_smacked,
			"the smack stays away before its scheduled item",
		)
		# Stand in for the schedule: the bench is at the smack's
		# repairable (index 2, the third item) and it lands. The
		# smack follows a few seconds into it.
		G.level.next_item_index = BirdController.SMACK_ITEM_INDEX + 1
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
	var smack_sprite := _smack.get_node(
		"AnimatedSprite2D"
	) as AnimatedSprite2D
	_expect(
		await _wait_until(
			func() -> bool: return smack_sprite.position.length() > 20.0,
			roundi(8.0 * Engine.physics_ticks_per_second),
		),
		"the bird falls from the glass when the animation finishes",
	)
	_expect(
		await _wait_until(
			func() -> bool: return not _smack.visible,
			roundi(6.0 * Engine.physics_ticks_per_second),
		),
		"the smack hides again after the fall",
	)
	_expect(
		smack_sprite.position == Vector2.ZERO,
		"the bird-smack cleans itself up after the fall",
	)
	_expect(_controller._has_smacked, "the smack is marked as shown")
	# The bird only shows where `OutsideStuff`'s clip mask
	# lets it: its children are clipped to the window panes,
	# so a peek placed outside them plays invisibly (LX83).
	# The bird's spot in its 1754x1240 frames (head and bush,
	# around (1358, 280)) must land on an opaque mask texel.
	var peak_sprite := _peak.get_node(
		"AnimatedSprite2D"
	) as AnimatedSprite2D
	var blob_world: Vector2 = peak_sprite.global_transform * (
		Vector2(1358, 280) - Vector2(877, 620)
	)
	var outside := G.level.get_node(
		"Background/OutsideStuff"
	) as Sprite2D
	var mask_local: Vector2 = (
		outside.global_transform.affine_inverse() * blob_world
	)
	var mask_image := Image.load_from_file(
		"res://assets/images/room/window_clip_region.png"
	)
	var texel := Vector2i(
		(mask_local + Vector2(877, 620)).round()
	)
	_expect(
		mask_image.get_pixel(texel.x, texel.y).a > 0.5,
		"the peek bird sits inside the window clip mask",
	)
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
		"the peek fades out and hides when it finishes",
	)
	_expect(
		_peak.modulate.a < 0.05,
		"the peek ends the fade transparent",
	)
	_controller._play_peak()
	_expect(
		_peak.visible and _peak.modulate.a == 1.0,
		"the next peek starts fully opaque again",
	)
	_expect(
		await _wait_until(
			func() -> bool: return not _peak.visible,
			roundi(8.0 * Engine.physics_ticks_per_second),
		),
		"the second peek fades out and hides too",
	)


func _wait_until(
	condition: Callable, timeout_frames := 600
) -> bool:
	for frame in timeout_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false
