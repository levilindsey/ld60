class_name HintTracker
extends Node
## Watches the current repair step and lights its target after
## the player has gone a while without a correct interaction.
##
## The steps come from the item's `RepairSequence`, which is
## derived from the item as authored. Nothing here knows an
## item's layout. Every physics frame the tracker asks the
## sequence what can be acted on now, picks one candidate among
## the best steps, and times how long the bench goes without
## progress on it. Progress is a candidate turning ACTIVE or
## FINISHED, a broken part popping out, a drawer opening for a
## fetch, a dragged layer, screw or part of the right kind, or
## any of the other state changes in `_build_fingerprint()`.
## Progress and step changes both restart the count and clear
## any hint already showing.
##
## After `Settings.hint_delay_sec` the target lights: a point,
## a layer, a loose part, every drawer for a fetch, or the
## outbox the finished item already outlines. After the longer
## `Settings.hint_tool_delay_sec` the stored tool the lit point
## needs lights too. A fitting step with no tool lights its
## socket instead. The tracker never lights a tool first.


var _item: Repairable
var _sequence: RepairSequence
var _current_steps: Array[RepairStep] = []
var _current_signature := ""
var _idle_sec := 0.0
var _hint_level := 0
var _fingerprint := ""
var _has_fingerprint := false

var _candidate_points: Array[InteractionPoint] = []
var _candidate_sockets: Array[PartSocket] = []
var _target_point: InteractionPoint
var _target_layer: RepairLayer
var _target_part: Part
var _target_is_drawers := false
var _target_is_outbox := false
var _secondary_point: InteractionPoint

var _lit_points: Array[InteractionPoint] = []
var _lit_layers: Array[RepairLayer] = []
var _lit_parts: Array[Part] = []
var _lit_drawers: Array[Drawer] = []
var _lit_tools: Array[Tool] = []


func _physics_process(delta: float) -> void:
	var level := G.level
	if not is_instance_valid(level):
		return
	var item := level.active_repairable
	if item != _item:
		_item = item
		_sequence = (
			item.get_repair_sequence() if is_instance_valid(item) else null
		)
		_current_signature = ""
		_reset_idle()
	if (
		not is_instance_valid(item)
		or not is_instance_valid(_sequence)
		or item.mode != Repairable.Mode.UNDER_REPAIR
	):
		_current_steps.clear()
		_current_signature = ""
		_clear_hints()
		_idle_sec = 0.0
		return
	var steps := _sequence.get_current_steps(level)
	_current_steps = steps
	var signature := _get_steps_signature(steps)
	var is_new_step := signature != _current_signature
	if is_new_step:
		_current_signature = signature
		_clear_hints()
		_idle_sec = 0.0
		_has_fingerprint = false
	# The target is picked fresh each frame. Inside one step it
	# still moves, from every drawer to the part in an open one.
	_pick_target(level, steps)
	if steps.is_empty():
		return
	var is_working := _is_working_on_current(level)
	var fingerprint := _build_fingerprint(level)
	var has_progressed := (
		_has_fingerprint and fingerprint != _fingerprint
	)
	_fingerprint = fingerprint
	_has_fingerprint = true
	if is_working or (has_progressed and not is_new_step):
		_idle_sec = 0.0
		if _hint_level > 0:
			_clear_hints()
		return
	if is_new_step:
		return
	_idle_sec += delta
	_apply_desired_hints(level)


## The step the player should be on, or null between items.
func get_current_step() -> RepairStep:
	if _current_steps.is_empty():
		return null
	return _current_steps[0]


## Every step that can be acted on in the current tier.
func get_current_steps() -> Array[RepairStep]:
	return _current_steps.duplicate()


## The derived sequence of the item on the bench, or null.
func get_sequence() -> RepairSequence:
	return _sequence


## Seconds since the last correct interaction on this step.
func get_idle_sec() -> float:
	return _idle_sec


## 0 for no hint, 1 for the target hint, 2 once the tool or the
## fitting socket joins it.
func get_hint_level() -> int:
	return _hint_level


## True once the first delay has lit a target.
func is_hint_shown() -> bool:
	return _hint_level >= 1


## True once the longer delay has lit the tool or socket too.
func is_tool_hint_shown() -> bool:
	return _hint_level >= 2


## The point the target hint lights, or null.
func get_target_point() -> InteractionPoint:
	return _target_point


## The layer the target hint lights, or null.
func get_target_layer() -> RepairLayer:
	return _target_layer


## The loose part the target hint lights, or null.
func get_target_part() -> Part:
	return _target_part


## True while the target hint lights every drawer.
func is_targeting_drawers() -> bool:
	return _target_is_drawers


## True while the finished item waits to be shipped.
func is_targeting_outbox() -> bool:
	return _target_is_outbox


## Restarts the delay and clears any hint. Hand and point code
## may call it on a correct interaction the fingerprint cannot
## see. The tracker also finds most progress on its own.
func note_correct_interaction() -> void:
	_reset_idle()


func _reset_idle() -> void:
	_idle_sec = 0.0
	_has_fingerprint = false
	_clear_hints()


func _get_steps_signature(steps: Array[RepairStep]) -> String:
	var signatures: Array[String] = []
	for step in steps:
		signatures.append(step.get_signature())
	return "|".join(signatures)


## Picks one target among the current steps, first step first and
## authored order inside a step. Other candidates stay unlit, as
## the request asked for one of the available interactions.
func _pick_target(level: Level, steps: Array[RepairStep]) -> void:
	_candidate_points.clear()
	_candidate_sockets.clear()
	_target_point = null
	_target_layer = null
	_target_part = null
	_target_is_drawers = false
	_target_is_outbox = false
	_secondary_point = null
	for step in steps:
		match step.kind:
			RepairStep.Kind.SHIP:
				_target_is_outbox = true
				return
			RepairStep.Kind.UNSCREW, RepairStep.Kind.SCREW_IN:
				_add_point_candidates(step)
			RepairStep.Kind.REPAIR, RepairStep.Kind.EXTRACT_PART:
				_add_point_candidates(step)
			RepairStep.Kind.RETURN_SCREW:
				for screw in step.get_returnable_screws():
					_candidate_points.append(screw)
					if not is_instance_valid(_target_point):
						_target_point = screw
			RepairStep.Kind.REMOVE_LAYER, RepairStep.Kind.REPLACE_LAYER:
				if is_instance_valid(step.layer):
					if (
						not is_instance_valid(_target_point)
						and not is_instance_valid(_target_layer)
						and not is_instance_valid(_target_part)
						and not _target_is_drawers
					):
						_target_layer = step.layer
			RepairStep.Kind.FETCH_PART, RepairStep.Kind.INSTALL_PART:
				_pick_socket_target(level, step)
	for point in _candidate_points:
		var part_socket := point as PartSocket
		if is_instance_valid(part_socket):
			_candidate_sockets.append(part_socket)


func _add_point_candidates(step: RepairStep) -> void:
	for point in step.get_candidate_points():
		_candidate_points.append(point)
		if not is_instance_valid(_target_point):
			_target_point = point


func _pick_socket_target(level: Level, step: RepairStep) -> void:
	var part_socket := step.socket
	if not is_instance_valid(part_socket):
		return
	_candidate_sockets.append(part_socket)
	var has_target := (
		is_instance_valid(_target_point)
		or is_instance_valid(_target_layer)
		or is_instance_valid(_target_part)
		or _target_is_drawers
	)
	if step.kind == RepairStep.Kind.INSTALL_PART:
		var loose := level.get_loose_part_of_type(
			part_socket.accepted_part,
		)
		if is_instance_valid(loose) and not has_target:
			_target_part = loose
			_secondary_point = part_socket
		return
	# Fetch: a shut bench lights every drawer. An open drawer
	# lights the part inside it when this drawer holds the kind.
	if level.are_drawers_busy():
		return
	var open_drawer := level.get_open_drawer()
	if is_instance_valid(open_drawer):
		var stored := level.get_part_of_type_in_drawer(
			open_drawer, part_socket.accepted_part,
		)
		if is_instance_valid(stored) and not has_target:
			_target_part = stored
		return
	if not has_target:
		_target_is_drawers = true


## True while the player is hands on with a candidate: a point
## mid microgame, a socket being wiggled, the right loose piece
## being dragged, or the finished item in the hand.
func _is_working_on_current(level: Level) -> bool:
	for point in _candidate_points:
		if not is_instance_valid(point):
			continue
		if point.mode == InteractionPoint.Mode.ACTIVE:
			return true
		var part_socket := point as PartSocket
		if is_instance_valid(part_socket) and part_socket.is_tugging():
			return true
	var hand := level.hand
	if not is_instance_valid(hand):
		return false
	var owner: Object = hand.input_owner
	if is_instance_valid(owner):
		if _candidate_points.has(owner as InteractionPoint):
			return true
		if _candidate_sockets.has(owner as PartSocket):
			return true
		var owner_tool := owner as Tool
		if is_instance_valid(owner_tool) and is_instance_valid(
			_target_point,
		):
			if _target_point.accepted_tools.has(owner_tool.type):
				return true
	if is_instance_valid(_target_layer):
		if hand.get_loose_layer() == _target_layer:
			return true
	if is_instance_valid(hand.get_loose_screw()):
		if _candidate_points.has(hand.get_loose_screw()):
			return true
	var loose_part := hand.get_loose_part()
	if is_instance_valid(loose_part):
		for part_socket in _candidate_sockets:
			if loose_part.type == part_socket.accepted_part:
				return true
	var broken_piece := hand.get_loose_broken_piece()
	if is_instance_valid(broken_piece):
		if _candidate_points.has(broken_piece.target_point):
			return true
	if _target_is_outbox and hand.held == _item:
		return true
	return false


## A string of every state a correct interaction on the current
## steps can change. A new fingerprint means progress happened.
## State from steps the player is not on is left out, so opening
## a drawer during a screw step does not restart that count.
func _build_fingerprint(level: Level) -> String:
	var fields: Array[String] = [_current_signature]
	for point in _candidate_points:
		if is_instance_valid(point):
			fields.append(_get_point_fingerprint(point))
	for part_socket in _candidate_sockets:
		if _candidate_points.has(part_socket):
			continue
		fields.append(_get_point_fingerprint(part_socket))
	for step in _current_steps:
		if is_instance_valid(step.layer):
			var layer := step.layer
			fields.append(
				"%d:%d:%d:%d" % [
					layer.get_instance_id(),
					int(layer.is_on),
					int(layer.is_moving),
					int(layer.has_been_removed),
				]
			)
	if not _candidate_sockets.is_empty():
		for drawer in level.get_drawers():
			fields.append(
				"%d:%d" % [drawer.get_instance_id(), drawer.state]
			)
		for part_socket in _candidate_sockets:
			for part in level.get_drawer_parts():
				if part.type != part_socket.accepted_part:
					continue
				fields.append(
					"%d:%d:%d:%d" % [
						part.get_instance_id(),
						int(part.is_stored),
						int(part.is_installed),
						int(part.is_returning),
					]
				)
	if is_instance_valid(_item):
		fields.append(
			"%d:%d" % [int(_item.has_finished), _item.mode]
		)
	return "|".join(fields)


func _get_point_fingerprint(point: InteractionPoint) -> String:
	var fields := "%d:%d" % [point.get_instance_id(), point.mode]
	var part_socket := point as PartSocket
	if is_instance_valid(part_socket):
		fields += ":%d" % int(part_socket.has_broken_part)
	var screw := point as Screw
	if is_instance_valid(screw):
		fields += ":%d:%d:%d" % [
			screw.travel,
			roundi(screw.slide * 20.0),
			screw.health,
		]
	if point is DustClump:
		fields += ":%d" % roundi(
			(point as DustClump).hit_points_left * 20.0,
		)
	elif point is GrimeSpot:
		fields += ":%d" % roundi(
			(point as GrimeSpot).hit_points_left * 20.0,
		)
	elif point is Crack:
		fields += ":%d" % roundi(
			(point as Crack).get_min_coverage() * 20.0,
		)
	elif point is StuckPart:
		fields += ":%d" % (point as StuckPart).hits_done
	elif point is BentPart:
		fields += ":%d" % roundi(
			(point as BentPart).current_error_deg,
		)
	elif point is SeatPart:
		fields += ":%d" % roundi(
			(point as SeatPart).seat_progress * 20.0,
		)
	elif point is BrokenPoint:
		var broken := point as BrokenPoint
		fields += ":%d:%d:%d" % [
			int(broken.has_glue),
			int(broken.is_holding),
			roundi(broken.hold_progress_sec * 20.0),
		]
	return fields


## Lights the target once its delay passes, and the tool or the
## fitting socket once the longer delay passes.
func _apply_desired_hints(level: Level) -> void:
	var desired := 0
	if _idle_sec >= G.settings.hint_delay_sec:
		desired = 1
	if _idle_sec >= G.settings.hint_tool_delay_sec:
		if (
			is_instance_valid(_get_tool_hint_tool(level))
			or is_instance_valid(_secondary_point)
			or _target_is_outbox
		):
			desired = 2
	if desired == _hint_level:
		return
	_clear_hints()
	_hint_level = desired
	if desired >= 1:
		_light_target(level)
	if desired >= 2:
		_light_tool(level)


func _light_target(level: Level) -> void:
	if is_instance_valid(_target_point):
		_target_point.set_hint_active(true)
		_lit_points.append(_target_point)
	elif is_instance_valid(_target_layer):
		_target_layer.set_hint_active(true)
		_lit_layers.append(_target_layer)
	elif is_instance_valid(_target_part):
		_target_part.set_hint_active(true)
		_lit_parts.append(_target_part)
	elif _target_is_drawers:
		for drawer in level.get_drawers():
			if drawer.state == Drawer.State.CLOSED:
				drawer.set_hint_active(true)
				_lit_drawers.append(drawer)
	# The outbox needs no call here. A finished item lights it
	# itself in Repairable._start_outline(), and it stays lit
	# until the item ships.


func _light_tool(level: Level) -> void:
	var tool := _get_tool_hint_tool(level)
	if is_instance_valid(tool):
		tool.set_hint_active(true)
		_lit_tools.append(tool)
	elif is_instance_valid(_secondary_point):
		_secondary_point.set_hint_active(true)
		_lit_points.append(_secondary_point)


## The stored tool the lit point needs, or null when the step
## takes no tool, the right tool is already in the hand, or the
## tool is already working the point.
func _get_tool_hint_tool(level: Level) -> Tool:
	if not is_instance_valid(_target_point):
		return null
	var held_tool: Tool = null
	if is_instance_valid(level.hand):
		held_tool = level.hand.get_held_tool()
	for tool_type in _target_point.accepted_tools:
		var tool := level.tools_by_type.get(tool_type) as Tool
		if not is_instance_valid(tool):
			continue
		if tool == held_tool:
			return null
		if tool.mode == Tool.Mode.STORED:
			return tool
	return null


func _clear_hints() -> void:
	for point in _lit_points:
		if is_instance_valid(point):
			point.set_hint_active(false)
	for layer in _lit_layers:
		if is_instance_valid(layer):
			layer.set_hint_active(false)
	for part in _lit_parts:
		if is_instance_valid(part):
			part.set_hint_active(false)
	for drawer in _lit_drawers:
		if is_instance_valid(drawer):
			drawer.set_hint_active(false)
	for tool in _lit_tools:
		if is_instance_valid(tool):
			tool.set_hint_active(false)
	_lit_points.clear()
	_lit_layers.clear()
	_lit_parts.clear()
	_lit_drawers.clear()
	_lit_tools.clear()
	_hint_level = 0
