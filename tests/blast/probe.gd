extends "res://tests/probe_base.gd"
## The shrink ray's first-hit blast: the ray pulses small then
## big, its broken crystal swells and flares blue, and a beat
## later the hammer bounces down to a quarter of its size and
## stays tiny (its hits already pitch up in Hammer._strike()).


func _ready() -> void:
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
	_start_timeout(60.0)
	_run.call_deferred()


func _run() -> void:
	var main := (
		(load("res://src/core/main.tscn") as PackedScene)
		.instantiate()
	)
	add_child(main)
	await _physics_frames(4)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_hand = G.level.hand
	var ray := (
		(load(
			"res://src/repairables/shrink_ray_repairable.tscn"
		) as PackedScene).instantiate() as ShrinkRay
	)
	G.level.add_child(ray)
	ray.mode = Repairable.Mode.UNDER_REPAIR
	ray.global_position = Vector2(0, 60)
	await _physics_frames(4)
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Hammer
	await _grab_tool(hammer)
	if not _expect(_hand.held == hammer, "the hand holds the hammer"):
		_finish(1)
		return
	var wrapper := hammer.find_child("Wrapper") as Node2D
	var wrapper_home: Vector2 = wrapper.scale
	var ray_home: Vector2 = ray.scale
	var crystal := ray.get_node(
		"Layers/Body/Crystal/BrokenPart/BustedCrystal"
	) as Sprite2D
	var crystal_home: Vector2 = crystal.scale
	ray.on_struck(0.5)
	_expect(ray.has_fired, "the first hit sets the ray off")
	await _seconds(0.12)
	_expect(
		ray.scale.x < ray_home.x * 0.99
		or crystal.modulate.b > 1.05,
		"the ray and its crystal pulse with the blast",
	)
	_expect(
		crystal.scale.x > crystal_home.x * 1.1,
		"the broken crystal swells with the blast",
	)
	_expect(
		wrapper.scale.is_equal_approx(wrapper_home),
		"the hammer has not shrunk yet in the first beat"
		+ " (got %s, home %s)" % [wrapper.scale, wrapper_home],
	)
	await _seconds(1.0)
	_expect(
		hammer.is_tiny
		and wrapper.scale.is_equal_approx(wrapper_home * 0.25),
		"the hammer bounces down to a quarter size and stays",
	)
	await _seconds(0.6)
	_expect(
		ray.scale.is_equal_approx(ray_home)
		and crystal.scale.is_equal_approx(crystal_home)
		and crystal.modulate.is_equal_approx(Color.WHITE),
		"the ray and crystal settle back after the blast",
	)
	_finish(0 if _failures.is_empty() else 1)
