extends "res://tests/probe_base.gd"
## Socket parts take presses over the item body. On the
## keyboard the spacebar's art is a few world pixels tall, so
## a press that lands a little above or below it used to grab
## the whole keyboard and drag it instead of tugging the bar.
## A press within the loose parts' grab margin of a socket's
## part must take the part; a press well clear of every part
## still drags the item.
##
## Run it with `tests/run.ps1 -Name partgrab`.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable
var _socket: PartSocket


func _ready() -> void:
	_start_timeout(_TIMEOUT_SEC)
	_is_taking_screenshots = OS.get_cmdline_user_args().has(
		"--screenshots"
	)
	await get_tree().process_frame
	var main: Node = (
		load(_MAIN_SCENE_PATH) as PackedScene
	).instantiate()
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
	var probe_queue: Array[Repairable.Type] = [
		Repairable.Type.KEYBOARD,
	]
	G.settings.item_queue = probe_queue
	G.state.transition(StateMain.State.GAME)
	if not _expect(
		await _wait_for_landing(), "the keyboard lands"
	):
		return
	_hand = G.level.hand
	_item = G.level.active_repairable
	for layer in _item.layers:
		for point in layer.get_points():
			if point is PartSocket and point.name == "Spacebar":
				_socket = point as PartSocket
	if not _expect(
		is_instance_valid(_socket), "the keyboard has a spacebar"
	):
		return
	var centre := _socket.global_position
	# The bar's footprint is a few world pixels tall: a press
	# just below it misses the art but stays in the margin.
	var near := centre + Vector2(0, 12)
	_expect(
		not _socket.is_point_on_part(near),
		"the near press starts off the bar's art",
	)
	await _press_down(near)
	_expect(
		_socket.is_tugging(),
		"a press just off the spacebar tugs the spacebar",
	)
	_expect(
		_hand.held != _item,
		"the same press does not grab the keyboard",
	)
	await _release_at(near)
	await _physics_frames(4)
	# On the art itself, the same preference holds.
	await _press_down(centre)
	_expect(
		_socket.is_tugging(),
		"a press on the spacebar tugs the spacebar",
	)
	await _release_at(centre)
	await _physics_frames(4)
	# Well clear of every part, the body still drags. The
	# spot is found by scan: on the item, on no point, and
	# farther than the grab margin from every socket.
	var body_spot := Vector2.ZERO
	var found_spot := false
	for x_step in range(-100, 101, 10):
		if found_spot:
			break
		for y_step in range(-70, 71, 10):
			var spot := (
				_item.global_position
				+ Vector2(float(x_step), float(y_step))
			)
			if not _item.has_point(spot):
				continue
			if is_instance_valid(_hand.find_point(spot)):
				continue
			var clear := true
			for layer in _item.layers:
				for point in layer.get_points():
					var other := point as PartSocket
					if (
						is_instance_valid(other)
						and other.get_part_distance(spot)
						<= G.settings.part_grab_margin_px
					):
						clear = false
			if clear:
				body_spot = spot
				found_spot = true
				break
	if not _expect(
		found_spot, "a body spot clear of the parts exists"
	):
		return
	await _press_down(body_spot)
	_expect(
		_hand.held == _item,
		"a press clear of the parts drags the keyboard",
	)
	await _release_at(body_spot)
	await _physics_frames(4)
