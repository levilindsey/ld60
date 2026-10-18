extends "res://tests/probe_base.gd"
## The effect tools (LX14, LX18, LX20). Boots the game, takes the
## rag, the air blower and the hammer off the rack, and works test
## points spawned onto the test item's cover with pushed input.
##
## Run it with `tests/run.ps1 -Name tools`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/tools/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _GRIME_SCENE_PATH := "res://src/interaction_points/grime_spot.tscn"
const _DUST_SCENE_PATH := "res://src/interaction_points/dust_clump.tscn"
const _FAN_SCENE_PATH := "res://src/interaction_points/fan.tscn"
const _STUCK_SCENE_PATH := "res://src/interaction_points/stuck_part.tscn"
const _BENT_SCENE_PATH := "res://src/interaction_points/bent_part.tscn"
const _SEAT_SCENE_PATH := "res://src/interaction_points/seat_part.tscn"
const _TIMEOUT_SEC := 120.0

var _item: Repairable
var _cover: RepairLayer


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
	await _seconds(0.3)
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		return
	_item = G.level.active_repairable
	_cover = _item.layers[_item.layers.size() - 1]
	_hand = G.level.hand

	_expect(
		G.level.tools_by_type.has(Tool.Type.RAG)
		and G.level.tools_by_type.has(Tool.Type.AIR_BLOWER)
		and G.level.tools_by_type.has(Tool.Type.HAMMER),
		"rag, air blower and hammer are on the rack",
	)
	await _check_rag()
	await _check_air_blower()
	await _check_hammer()


## Takes a tool off the rack by pressing its holder.
func _grab(type: Tool.Type) -> Tool:
	await _press_at(G.level.get_tool_holder_position(type))
	return G.level.tools_by_type[type]


func _spawn_point(
	scene_path: String, at_position: Vector2
) -> InteractionPoint:
	var scene := load(scene_path) as PackedScene
	var point := scene.instantiate() as InteractionPoint
	_cover.add_child(point)
	point.position = at_position
	return point


func _check_rag() -> void:
	var grime := _spawn_point(
		_GRIME_SCENE_PATH, Vector2(-30, -25)
	) as GrimeSpot
	await _physics_frames(2)
	var rag_tool := await _grab(Tool.Type.RAG)
	var rag := rag_tool as Rag
	_expect(_hand.held == rag, "the hand holds the rag")
	_expect(
		rag.held_sprite.visible and not rag.hanging_sprite.visible,
		"held rag shows the bunched sprite",
	)
	var spot_position := grime.global_position
	await _press_down(spot_position)
	for swing in 8:
		await _move_to(spot_position + Vector2(28, 0))
		await _move_to(spot_position + Vector2(-28, 0))
	await _release_at(spot_position)
	_expect(
		grime.mode == InteractionPoint.Mode.FINISHED,
		"dragging the rag cleans the grime",
	)

	# A sensitive surface smears in stages when wiped.
	var surface := Surface.new()
	surface.collision_layer = Settings.PhysicsLayer.SURFACES
	surface.type = Surface.Type.PAPER_LABEL
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(70, 40)
	shape_node.shape = rectangle
	surface.add_child(shape_node)
	_cover.add_child(surface)
	surface.position = Vector2(0, 32)
	await _physics_frames(2)
	var points_before := _item.quality.get_defect_points_total()
	var surface_position := surface.global_position
	await _press_down(surface_position)
	for swing in 8:
		await _move_to(surface_position + Vector2(30, 0))
		await _move_to(surface_position + Vector2(-30, 0))
	await _release_at(surface_position)
	_expect(
		_item.quality.get_defect_points_total() == points_before + 10,
		"wiping a paper label costs a ruined smear",
	)
	await _press_at(G.level.get_tool_holder_position(Tool.Type.RAG))
	_expect(
		rag.mode == Tool.Mode.STORED and rag.hanging_sprite.visible,
		"stored rag shows the hanging sprite",
	)


func _check_air_blower() -> void:
	var dust := _spawn_point(
		_DUST_SCENE_PATH, Vector2(30, -25)
	) as DustClump
	var fan := _spawn_point(_FAN_SCENE_PATH, Vector2(-30, 25)) as Fan
	await _physics_frames(2)
	var blower_tool := await _grab(Tool.Type.AIR_BLOWER)
	var blower := blower_tool as AirBlower
	_expect(_hand.held == blower, "the hand holds the air blower")
	_expect(blower.plump_sprite.visible, "the bulb starts plump")
	# Let the held turn settle, so the aim uses the final direction.
	await _seconds(0.5)
	var aim := dust.global_position - blower.get_nozzle_direction() * 60.0
	await _press_down(aim)
	_expect(blower.squeezed_sprite.visible, "a tap squeezes the bulb")
	await _release_at(aim)
	for puff in 4:
		await _seconds(0.25)
		await _press_at(aim)
	await _seconds(0.6)
	_expect(
		dust.mode == InteractionPoint.Mode.FINISHED,
		"puffs blow the dust away",
	)
	var fan_aim := fan.global_position - blower.get_nozzle_direction() * 60.0
	for puff in 3:
		await _press_at(fan_aim)
		await _seconds(0.25)
	await _seconds(0.3)
	_expect(
		not is_zero_approx(fan.art.rotation),
		"puffs spin the fan",
	)
	# Gliding onto its holder puts a held tool away on its own.
	# Pressing there would only take it again.
	await _move_to(
		G.level.get_tool_holder_position(Tool.Type.AIR_BLOWER)
	)
	for frame in 60:
		if blower.mode == Tool.Mode.STORED:
			break
		await get_tree().physics_frame
	_expect(
		blower.mode == Tool.Mode.STORED,
		"the air blower goes back on the rack",
	)


func _check_hammer() -> void:
	var stuck := _spawn_point(
		_STUCK_SCENE_PATH, Vector2(12, 30)
	) as StuckPart
	stuck.hits_needed = 2
	var bent := _spawn_point(_BENT_SCENE_PATH, Vector2(0, -32)) as BentPart
	var seat := _spawn_point(_SEAT_SCENE_PATH, Vector2(-15, -5)) as SeatPart
	await _physics_frames(2)
	var hammer_tool := await _grab(Tool.Type.HAMMER)
	var hammer := hammer_tool as Hammer
	_expect(_hand.held == hammer, "the hand holds the hammer")

	# A tap is too weak to jog the stuck part.
	await _strike(hammer, stuck.global_position, 0.05)
	_expect(stuck.hits_done == 0, "a tap below the band does nothing")
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(stuck.hits_done == 1, "a hit in the band jogs the part")
	await _strike(hammer, stuck.global_position, 0.6)
	_expect(
		stuck.mode == InteractionPoint.Mode.FINISHED,
		"enough hits free the stuck part",
	)

	var error_before := bent.current_error_deg
	await _strike(hammer, bent.global_position, 0.6)
	_expect(
		bent.current_error_deg < error_before
		and bent.mode != InteractionPoint.Mode.FINISHED,
		"a hit in the band bends the part back a share",
	)
	var defects_before := _item.quality.get_defect_count()
	await _strike(hammer, bent.global_position, 1.3)
	_expect(
		bent.current_error_deg < 0.0,
		"a hit over the band flips the bend",
	)
	_expect(
		_item.quality.get_defect_count() > defects_before,
		"a hit over the band costs a dent",
	)

	await _strike(hammer, seat.global_position, 0.6)
	_expect(
		is_equal_approx(seat.seat_progress, 0.5),
		"a hit in the band seats the part halfway",
	)
	await _strike(hammer, seat.global_position, 1.3)
	_expect(
		seat.mode == InteractionPoint.Mode.FINISHED,
		"a hard hit seats the part and finishes it",
	)


## Holds a swing for `hold_sec` at a point, then lets it go and
## waits out the swing, the hit stop and the recoil.
func _strike(_hammer: Hammer, at_position: Vector2, hold_sec: float) -> void:
	await _press_down(at_position)
	await _seconds(hold_sec)
	await _release_at(at_position)
	await _seconds(0.5)
