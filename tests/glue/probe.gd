extends "res://tests/probe_base.gd"
## The glue bottle and crack (LX22). Boots the game, spawns a
## crack on the test item's cover, floods one spot, then traces
## the crack and lets it dry.
##
## Run it with `tests/run.ps1 -Name glue`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/glue/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _CRACK_SCENE_PATH := "res://src/interaction_points/crack.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable
var _crack: Crack
## Pointer minus sample, so the nozzle follows the crack.
var _nozzle_offset := Vector2.ZERO


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
	_hand = G.level.hand
	_item = G.level.active_repairable
	_expect(
		G.level.tools_by_type.has(Tool.Type.GLUE),
		"the glue bottle is on the rack",
	)
	var cover := _item.layers[_item.layers.size() - 1]
	_crack = (load(_CRACK_SCENE_PATH) as PackedScene).instantiate() as Crack
	cover.add_child(_crack)
	_crack.position = Vector2(-55, -15)
	await _physics_frames(2)
	_expect(_crack.get_sample_count() > 10, "the crack has samples")

	var glue_tool := G.level.tools_by_type[Tool.Type.GLUE]
	await _press_at(glue_tool.global_position)
	_expect(
		_hand.held == glue_tool,
		"the hand holds the glue bottle",
	)
	_nozzle_offset = await _get_nozzle_offset(glue_tool)

	# Flooding one spot blobs it.
	var samples := _crack.get_samples()
	var middle: Vector2 = _crack.to_global(
		samples[samples.size() / 2]
	)
	var defects_before := _item.quality.get_defect_count()
	await _press_down(middle - _nozzle_offset)
	await _seconds(1.2)
	await _release_at(middle - _nozzle_offset)
	_expect(
		_item.quality.get_defect_count() > defects_before,
		"flooding one spot costs a glue blob",
	)

	# Tracing the whole crack covers it.
	await _trace_crack()
	await _trace_crack()
	_expect(
		_crack.is_drying or _crack.get_min_coverage() >= 1.0,
		"tracing covers the whole crack",
	)
	await _seconds(G.settings.glue_dry_sec + 0.7)
	_expect(
		_crack.mode == InteractionPoint.Mode.FINISHED,
		"the covered crack dries into a seam",
	)


## The working end's offset from the pointer, once the held
## bottle has settled into the hand.
func _get_nozzle_offset(tool: Tool) -> Vector2:
	var settle_frames := 0
	while settle_frames < 90 and (
		tool.follow_offset.length() > 0.5
		or (
			is_instance_valid(tool.rotation_tween)
			and tool.rotation_tween.is_running()
		)
	):
		await _physics_frames(1)
		settle_frames += 1
	return (
		tool.get_work_end_position() - tool.get_tip_position()
	)


## Presses with the nozzle at the first sample and drags it
## along the crack and back, pausing a few frames per sample.
func _trace_crack() -> void:
	var samples := _crack.get_samples()
	var start: Vector2 = _crack.to_global(samples[0])
	await _press_down(start - _nozzle_offset)
	for sample in samples:
		await _move_to(_crack.to_global(sample) - _nozzle_offset)
		await _physics_frames(4)
	for index in range(samples.size() - 1, -1, -1):
		await _move_to(
			_crack.to_global(samples[index]) - _nozzle_offset
		)
		await _physics_frames(4)
	await _release_at(start - _nozzle_offset)
