class_name RepairSequence
extends RefCounted
## The steps of one repair, in the order the bench presents them.
##
## The sequence is autodetermined from the item as authored: its
## layers from outermost to innermost, the fasteners and faults on
## each layer, and which sockets start with a broken part in them.
## No item author writes a step list. A two layer item with a gear
## socket inside derives unscrew, remove the cover, wiggle the gear
## out, fetch a gear, fit it, replace the cover, return its screws,
## drive them in, and ship. A layer with no fasteners derives no
## unscrew step. A socket that starts empty derives no extraction.
##
## The built list is the intended order. Live play may still fix
## exposed faults in any order, so `get_current_steps()` rejudges
## every step against the bench and returns the actionable steps
## in the best tier, best first. Steps that are not reachable yet,
## covered by a layer or waiting on a drawer, are skipped until
## the bench makes them reachable.


## The item these steps repair.
var item: Repairable
## Every derived step, in intended order. The last one ships.
var steps: Array[RepairStep] = []
## Steps of optional work (dirt the item can ship without), one
## per layer. They are not in `steps`: they never gate the
## repair or its completion count. `get_current_steps()` adds
## the reachable ones when no required step offers a point,
## so leftover grime and dust can still take the idle hint.
var _optional_steps: Array[RepairStep] = []


## Derives the sequence for an item from its layers and points.
static func build_for(
	target_item: Repairable,
) -> RepairSequence:
	var sequence := RepairSequence.new()
	sequence.item = target_item
	if not is_instance_valid(target_item):
		return sequence
	var layers := target_item.layers
	# Taking it apart, outermost layer first. The innermost layer
	# is never removed, so it gets no removal or return steps.
	for index in range(layers.size() - 1, 0, -1):
		sequence._add_fastener_step(
			layers[index], RepairStep.Kind.UNSCREW,
		)
		sequence._add_layer_repair_steps(layers[index])
		sequence._add_step(RepairStep.Kind.REMOVE_LAYER, layers[index])
	if not layers.is_empty():
		sequence._add_layer_repair_steps(layers[0])
	# Putting it back, innermost cover first.
	for index in range(1, layers.size()):
		var layer := layers[index]
		sequence._add_step(RepairStep.Kind.REPLACE_LAYER, layer)
		sequence._add_fastener_step(
			layer, RepairStep.Kind.RETURN_SCREW,
		)
		sequence._add_fastener_step(
			layer, RepairStep.Kind.SCREW_IN,
		)
	sequence._add_step(RepairStep.Kind.SHIP, null)
	return sequence


## The actionable steps in the best tier right now, best first.
## Steps in one tier can be satisfied in any order. The hint
## tracker highlights one candidate among them.
func get_current_steps(level: Level) -> Array[RepairStep]:
	var actionable: Array[RepairStep] = []
	for step in steps:
		if step.is_actionable(level):
			actionable.append(step)
	actionable.sort_custom(
		func(first: RepairStep, second: RepairStep) -> bool:
			if first.get_priority() != second.get_priority():
				return first.get_priority() < second.get_priority()
			return steps.find(first) < steps.find(second)
	)
	if actionable.is_empty():
		return actionable
	var best_priority := actionable[0].get_priority()
	var current: Array[RepairStep] = []
	for step in actionable:
		if step.get_priority() == best_priority:
			current.append(step)
	# Optional dirt rides along only when no required step
	# offers a point to act on: while a screw, socket or layer
	# still claims the bench it keeps the hint, and the dirt
	# lights only once it is the work that is left.
	var has_candidates := false
	for step in current:
		if not step.get_candidate_points().is_empty():
			has_candidates = true
			break
	if not has_candidates:
		for step in _optional_steps:
			if step.is_actionable(level):
				current.append(step)
	return current


## The first of `get_current_steps()`, or null when the bench is
## between items or every reachable step is done.
func get_current_step(level: Level) -> RepairStep:
	var current := get_current_steps(level)
	if current.is_empty():
		return null
	return current[0]


## How many derived steps are complete right now, of how many.
## Drawer steps need the level to know about loose parts.
func get_completed_count(level: Level) -> int:
	var count := 0
	for step in steps:
		if step.is_complete(level):
			count += 1
	return count


func _add_step(
	kind: RepairStep.Kind,
	layer: RepairLayer,
) -> RepairStep:
	var step := RepairStep.new()
	step.item = item
	step.kind = kind
	step.layer = layer
	steps.append(step)
	return step


func _add_fastener_step(
	layer: RepairLayer,
	kind: RepairStep.Kind,
) -> void:
	var fasteners := layer.get_fasteners()
	if fasteners.is_empty():
		return
	# Returning screws only applies to screws, which rest on the
	# bench. Other fasteners go straight to the drive in step.
	if kind == RepairStep.Kind.RETURN_SCREW:
		var screws: Array[InteractionPoint] = []
		for fastener in fasteners:
			if fastener is Screw:
				screws.append(fastener)
		if screws.is_empty():
			return
		fasteners = screws
	var step := _add_step(kind, layer)
	step.points = fasteners


## Adds the fault steps of one layer: one REPAIR step grouping its
## tool faults, then the extraction, fetch and fitting steps of
## each of its sockets, in authored order. Optional dirt on the
## layer gets a step of its own, kept aside in `_optional_steps`.
func _add_layer_repair_steps(layer: RepairLayer) -> void:
	var faults: Array[InteractionPoint] = []
	var sockets: Array[PartSocket] = []
	var optional_dirt: Array[InteractionPoint] = []
	for point in layer.get_points():
		if point.role != InteractionPoint.Role.REPAIR:
			continue
		if not point.is_required:
			# Dirt the item can ship without still costs rating
			# when left, so it earns a step the hint can offer
			# once nothing required claims the bench.
			if point is DirtSpot:
				optional_dirt.append(point)
			continue
		if point is PartSocket:
			sockets.append(point as PartSocket)
		elif point.type != InteractionPoint.Type.FAN:
			# A fan never finishes in the jam build, so it can
			# never be a required step. See Fan.
			faults.append(point)
	if not optional_dirt.is_empty():
		var optional_step := RepairStep.new()
		optional_step.item = item
		optional_step.kind = RepairStep.Kind.REPAIR
		optional_step.layer = layer
		optional_step.points = optional_dirt
		optional_step.is_optional = true
		_optional_steps.append(optional_step)
	if not faults.is_empty():
		var step := _add_step(RepairStep.Kind.REPAIR, layer)
		step.points = faults
	for part_socket in sockets:
		if part_socket.starts_with_broken_part:
			var extract := _add_step(
				RepairStep.Kind.EXTRACT_PART, layer,
			)
			extract.socket = part_socket
			extract.points = [part_socket]
		var fetch := _add_step(RepairStep.Kind.FETCH_PART, layer)
		fetch.socket = part_socket
		fetch.points = [part_socket]
		var install := _add_step(RepairStep.Kind.INSTALL_PART, layer)
		install.socket = part_socket
		install.points = [part_socket]
