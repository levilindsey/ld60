class_name RepairStep
extends RefCounted
## One step of a repair, derived from an item by `RepairSequence`.
##
## A step groups every point that can satisfy it, so unscrewing
## either of two screws counts for the same UNSCREW step. Whether
## the step can be acted on right now depends on live bench state:
## which layer is exposed, whether a socket still holds its broken
## part, whether its replacement is still shut in a drawer, and so
## on. `RepairSequence` builds the steps once from the item as
## authored. This class only reads state, it never changes it.


enum Kind {
	NONE,
	UNSCREW,
	REMOVE_LAYER,
	REPAIR,
	EXTRACT_PART,
	FETCH_PART,
	INSTALL_PART,
	REPLACE_LAYER,
	RETURN_SCREW,
	SCREW_IN,
	SHIP,
}

## The item this step repairs. The shipping step names no layer
## or point, so every step carries the item itself.
var item: Repairable
## What the player does in this step.
var kind := Kind.NONE
## The layer the step belongs to, or null for SHIP.
var layer: RepairLayer
## The points that can satisfy this step. Empty for layer, drawer
## and outbox steps, which name their target another way.
var points: Array[InteractionPoint] = []
## The socket of an EXTRACT_PART, FETCH_PART or INSTALL_PART step.
var socket: PartSocket


## The points of this step that still need work and can be reached
## now, in authored order.
func get_candidate_points() -> Array[InteractionPoint]:
	var candidates: Array[InteractionPoint] = []
	for point in points:
		if not is_instance_valid(point):
			continue
		if point.mode == InteractionPoint.Mode.FINISHED:
			continue
		if not point.is_exposed():
			continue
		if kind == Kind.REPAIR and point is PartSocket:
			continue
		if kind == Kind.REPAIR and point.type == InteractionPoint.Type.FAN:
			continue
		if kind == Kind.REPAIR and not point.needs_work():
			continue
		if kind == Kind.EXTRACT_PART:
			var part_socket := point as PartSocket
			if not is_instance_valid(part_socket):
				continue
			if not part_socket.has_tuggable_part():
				continue
		if kind == Kind.UNSCREW or kind == Kind.SCREW_IN:
			var screw := point as Screw
			if is_instance_valid(screw) and screw.travel != Screw.Travel.HOME:
				continue
		candidates.append(point)
	return candidates


## The resting screws of a RETURN_SCREW step that can come back now.
func get_returnable_screws() -> Array[Screw]:
	var screws: Array[Screw] = []
	for point in points:
		var screw := point as Screw
		if is_instance_valid(screw) and screw.can_come_back():
			screws.append(screw)
	return screws


## The tool types the candidate points accept, with no repeats.
## Empty for steps the empty hand or a dragged piece satisfies.
func get_accepted_tool_types() -> Array[Tool.Type]:
	var tool_types: Array[Tool.Type] = []
	for point in get_candidate_points():
		for tool_type in point.accepted_tools:
			if not tool_types.has(tool_type):
				tool_types.append(tool_type)
	return tool_types


## Lower sorts first when several steps can be acted on at once.
## Work on the exposed layer shares one tier, so the tracker may
## pick any of its points. Taking a loose layer off sorts after
## fixing that same layer, because its points become unreachable
## once it is set aside.
func get_priority() -> int:
	match kind:
		Kind.SHIP:
			return 0
		Kind.REMOVE_LAYER:
			return 20
		Kind.NONE:
			return 99
		_:
			return 10


## A short stable name for logs, probes and timer bookkeeping.
func get_signature() -> String:
	var layer_name := "none"
	if is_instance_valid(layer):
		layer_name = String(layer.name)
	var point_names: Array[String] = []
	for point in points:
		if is_instance_valid(point):
			point_names.append(String(point.name))
	return "%s:%s:%s" % [
		Kind.keys()[kind],
		layer_name,
		",".join(point_names),
	]


## True when this step's work is done, judged from live state.
## `level` may be null, in which case drawer steps only know
## about their socket.
func is_complete(level: Level) -> bool:
	match kind:
		Kind.NONE:
			return true
		Kind.SHIP:
			var item := _get_item()
			return (
				not is_instance_valid(item)
				or item.mode == Repairable.Mode.LEAVING
			)
		Kind.REMOVE_LAYER:
			return is_instance_valid(layer) and not layer.is_on
		Kind.REPLACE_LAYER:
			return is_instance_valid(layer) and layer.is_on
		Kind.EXTRACT_PART:
			return (
				is_instance_valid(socket)
				and not socket.has_broken_part
			)
		Kind.FETCH_PART:
			if not is_instance_valid(socket):
				return true
			if socket.mode == InteractionPoint.Mode.FINISHED:
				return true
			return is_instance_valid(_get_loose_part(level))
		Kind.INSTALL_PART:
			return (
				is_instance_valid(socket)
				and socket.mode == InteractionPoint.Mode.FINISHED
			)
		Kind.RETURN_SCREW:
			return get_returnable_screws().is_empty()
		_:
			for point in points:
				if not is_instance_valid(point):
					continue
				if point.mode != InteractionPoint.Mode.FINISHED:
					return false
			return true


## True when the player can act on this step right now.
func is_actionable(level: Level) -> bool:
	if is_complete(level):
		return false
	match kind:
		Kind.SHIP:
			var item := _get_item()
			return (
				is_instance_valid(item)
				and item.has_finished
				and item.mode == Repairable.Mode.UNDER_REPAIR
			)
		Kind.REMOVE_LAYER:
			return (
				is_instance_valid(layer)
				and layer.is_on
				and not layer.is_moving
				and not layer.is_innermost()
				and layer.is_loose()
				and layer.is_exposed()
			)
		Kind.REPLACE_LAYER:
			return (
				is_instance_valid(layer)
				and layer.is_ready_to_go_back()
			)
		Kind.UNSCREW:
			if _has_been_removed():
				return false
			return not get_candidate_points().is_empty()
		Kind.SCREW_IN:
			if not _has_been_removed():
				return false
			return not get_candidate_points().is_empty()
		Kind.RETURN_SCREW:
			return not get_returnable_screws().is_empty()
		Kind.EXTRACT_PART, Kind.FETCH_PART, Kind.INSTALL_PART:
			if not is_instance_valid(socket):
				return false
			if not socket.is_exposed():
				return false
			if socket.mode == InteractionPoint.Mode.FINISHED:
				return false
			match kind:
				Kind.EXTRACT_PART:
					return socket.has_tuggable_part()
				Kind.FETCH_PART:
					return (
						not socket.has_broken_part
						and not is_instance_valid(_get_loose_part(level))
					)
				Kind.INSTALL_PART:
					return (
						not socket.has_broken_part
						and is_instance_valid(_get_loose_part(level))
					)
			return false
		Kind.REPAIR:
			return not get_candidate_points().is_empty()
		_:
			return false


## The replacement part for this step's socket that is already out
## on the bench, or null. Installed and stored parts do not count.
func _get_loose_part(level: Level) -> Part:
	if not is_instance_valid(level) or not is_instance_valid(socket):
		return null
	return level.get_loose_part_of_type(socket.accepted_part)


func _get_item() -> Repairable:
	if is_instance_valid(item):
		return item
	if is_instance_valid(layer):
		return layer.item
	if is_instance_valid(socket):
		return socket.get_item()
	if not points.is_empty() and is_instance_valid(points[0]):
		return points[0].get_item()
	return null


func _has_been_removed() -> bool:
	return is_instance_valid(layer) and layer.has_been_removed
