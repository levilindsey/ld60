extends "res://tests/probe_base.gd"
## Wiggling a socket's broken part out by tapping. Boots the
## game and spawns a part socket on the test box cover. The
## yank arrows show while its part can be tugged. Each tap is
## one swing to alternating sides, and enough taps pop the
## part out and hide the arrows. Dragging back and forth
## still works it loose the usual way.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _SOCKET_SCENE_PATH := "res://src/interaction_points/part_socket.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable
var _cover: RepairLayer
var _socket: PartSocket


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = "--screenshots" in OS.get_cmdline_args()
	var main := (
		(load(_MAIN_SCENE_PATH) as PackedScene).instantiate()
		as Main
	)
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _seconds(0.3)
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(await _wait_for_landing(), "the first item lands"):
		_finish(1)
		return
	_item = G.level.active_repairable
	_hand = G.level.hand
	_cover = _item.layers[_item.layers.size() - 1]
	_socket = (
		(load(_SOCKET_SCENE_PATH) as PackedScene).instantiate()
		as PartSocket
	)
	_cover.add_child(_socket)
	_socket.position = Vector2(12, 30)
	_socket.swings_needed = 4
	await _physics_frames(2)
	if not _expect(
		is_instance_valid(_socket), "the socket is on the cover"
	):
		_finish(1)
		return
	_expect(
		not _socket.is_yank_indicator_visible(),
		"the yank arrows stay hidden before the part is tugged",
	)
	await _press_down(_socket.global_position)
	_expect(
		_socket.is_yank_indicator_visible(),
		"the yank arrows show while the part is being tugged",
	)
	await _physics_frames(2)
	_expect(
		_socket._yank_indicator.global_position.y
		< _socket.global_position.y - 120.0,
		"the yank arrows float clear of the tugging finger",
	)
	await _release_at(_socket.global_position)
	_expect(
		_socket._wiggle.swings == 1,
		"one tap is one wiggle swing",
	)
	var first_rock := _socket._wiggle.rock_angle_rad
	_expect(
		not is_zero_approx(first_rock),
		"the tap rocks the part to one side",
	)
	await _press_at(_socket.global_position)
	_expect(
		_socket._wiggle.swings == 2
		and signf(_socket._wiggle.rock_angle_rad) == -signf(first_rock),
		"a second tap swings it to the other side",
	)
	await _press_at(_socket.global_position)
	await _press_at(_socket.global_position)
	_expect(
		not _socket.has_broken_part,
		"enough taps pop the part out",
	)
	_expect(
		not _socket.is_yank_indicator_visible(),
		"the yank arrows hide once the part is out",
	)

	# A hard yank (one long drag, not swings) pulls a part
	# out too, and costs nothing: no defect, full score.
	var yank_socket := (
		(load(_SOCKET_SCENE_PATH) as PackedScene).instantiate()
		as PartSocket
	)
	_cover.add_child(yank_socket)
	yank_socket.position = Vector2(-80, 30)
	await _physics_frames(2)
	await _press_down(yank_socket.global_position)
	await _move_to(
		yank_socket.global_position + Vector2(-400.0, 0.0)
	)
	_expect(
		not yank_socket.has_broken_part,
		"one long drag yanks the part out",
	)
	await _release_at(
		yank_socket.global_position + Vector2(-400.0, 0.0)
	)
	_expect(
		_item.quality.get_defect_points_total() == 0
		and _item.quality.get_summary().is_empty(),
		"a hard yank charges no defect",
	)
	_finish(0 if _failures.is_empty() else 1)
