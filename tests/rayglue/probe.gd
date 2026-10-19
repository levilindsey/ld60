extends "res://tests/probe_base.gd"


func _ready() -> void:
	_is_taking_screenshots = OS.get_cmdline_user_args().has("--screenshots")
	_start_timeout(90.0)
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://src/core/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _physics_frames(4)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_hand = G.level.hand
	var ray := (load("res://src/repairables/shrink_ray_repairable.tscn") as PackedScene).instantiate() as Repairable
	G.level.add_child(ray)
	ray.mode = Repairable.Mode.UNDER_REPAIR
	ray.global_position = Vector2(0, 60)
	G.level.active_repairable = ray
	await _physics_frames(4)
	var point: BrokenPoint = null
	for layer in ray.layers:
		for p in layer.get_points():
			if p is BrokenPoint:
				point = p as BrokenPoint
	if not _expect(is_instance_valid(point), "the shrink ray has a broken point"):
		_finish(1)
		return
	print("DIAG point global=", point.global_position, " exposed=", point.is_exposed(), " visible=", point.is_visible_in_tree(), " piece=", is_instance_valid(point.piece))
	if is_instance_valid(point.piece):
		point.piece.detach_for_fall(ray.global_position + point.piece.fall_target_offset)
		await _physics_frames(30)
	var glue := G.level.tools_by_type[Tool.Type.GLUE] as Tool
	await _grab_tool(glue)
	_expect(_hand.held == glue, "the hand holds the glue")
	var nozzle_offset: Vector2 = glue.get_work_end_position() - glue.get_tip_position()
	print("DIAG nozzle offset=", nozzle_offset, " squeezing before=", glue.get("_is_squeezing"))
	await _press_down(point.global_position - nozzle_offset)
	await _seconds(1.2)
	print("DIAG squeezing=", glue.get("_is_squeezing"), " has_glue=", point.has_glue, " mode=", point.mode)
	await _shot("ray_glue_squeeze")
	await _release_at(point.global_position - nozzle_offset)
	await _physics_frames(4)
	_expect(point.has_glue, "glue lands on the trigger point from the bottle")
	var decal: Sprite2D = point.glue_decal
	_expect(is_instance_valid(decal) and decal.is_visible_in_tree(), "the trigger glue dab shows")
	if is_instance_valid(decal):
		print("DIAG decal pos=", decal.global_position, " alpha=", decal.modulate.a, " parent=", decal.get_parent().name)
	await _shot("ray_glued")
	_finish(0 if _failures.is_empty() else 1)
