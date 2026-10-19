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
	await _press_at(glue.global_position)
	_expect(_hand.held == glue, "the hand holds the glue")
	var settle_frames := 0
	while settle_frames < 90 and (
		glue.follow_offset.length() > 0.5
		or (
			is_instance_valid(glue.rotation_tween)
			and glue.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
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
	glue.put_away()
	await _physics_frames(2)

	# Near aim: the nozzle lands beside the point, the way a
	# player sloppily covering the gap still glues it: the
	# bottle's area only has to cross the point's own area.
	point.reset_for_reglue()
	await _press_at(glue.global_position)
	_expect(_hand.held == glue, "the hand holds the glue again")
	var near_spot: Vector2 = (
		point.global_position + Vector2(80, 0) - nozzle_offset
	)
	await _press_down(near_spot)
	await _seconds(1.2)
	_expect(
		point.has_glue,
		"glue lands with the nozzle beside the point (near aim)",
	)
	print("DIAG near squeezing=", glue.get("_is_squeezing"), " has_glue=", point.has_glue, " nozzle dist=", glue.get_work_end_position().distance_to(point.global_position), " overlaps=", glue.interaction_area.get_overlapping_areas().size(), " glue shape world r=", (glue.get_interaction_shape().shape as CircleShape2D).radius * glue.get_interaction_shape().global_transform.get_scale().x)
	await _release_at(near_spot)
	glue.put_away()
	await _physics_frames(2)

	# A real hammer hit on the ray's body sets it off.
	var hammer := G.level.tools_by_type[Tool.Type.HAMMER] as Hammer
	await _grab_tool(hammer)
	_expect(_hand.held == hammer, "the hand holds the hammer")
	var art := ray.layers[0].art as Sprite2D
	var strike_spot: Vector2 = art.to_global(Vector2(0, -40))
	var hammer_settle := 0
	while hammer_settle < 90 and (
		hammer.follow_offset.length() > 0.5
		or (
			is_instance_valid(hammer.rotation_tween)
			and hammer.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		hammer_settle += 1
	var hammer_offset: Vector2 = hammer.get_work_end_position() - hammer.get_tip_position()
	await _move_to(strike_spot - hammer_offset)
	await _seconds(0.4)
	await _press_down(strike_spot - hammer_offset)
	await _seconds(0.3)
	print("DIAG face dist=", hammer.get_work_end_position().distance_to(strike_spot), " phase=", hammer.get("_phase"), " mode=", hammer.mode, " locked target=", hammer.get_locked_target(), " prop=", hammer.get_locked_prop(), " layer=", hammer.get_locked_layer(), " surface=", hammer.get_locked_surface())
	hammer.on_effect_pressed(strike_spot)
	print("DIAG direct: prop=", hammer.get_locked_prop(), " layer=", hammer.get_locked_layer(), " target=", hammer.get_locked_target())
	print("DIAG ray struck_at=", ray.is_struck_at(strike_spot), " active is ray=", G.level.active_repairable == ray, " active=", G.level.active_repairable, " ray mode=", ray.mode, " in shape=", ray.is_point_in_shape(strike_spot), " layer has_point=", ray.layers[0].has_point(strike_spot), " exposed=", ray.layers[0].is_exposed())
	await _release_at(strike_spot - hammer_offset)
	await _seconds(0.5)
	print("DIAG fired=", ray.has_fired, " jam hits=", (ray.get_node("Layers/Body/Jam") as StuckPart).hits_done if is_instance_valid(ray.get_node_or_null("Layers/Body/Jam")) else -1)
	_expect(
		ray.has_fired, "a hammer hit on the body sets the ray off"
	)
	_finish(0 if _failures.is_empty() else 1)
