class_name Glue
extends Tool
## The glue bottle (docs/design/glue.md). Press and hold to
## squeeze, then trace a crack to cover it. Flooding a spot, or
## squeezing over a plain surface, leaves a blob.


## How often an off-target squeeze blobs, in seconds.
const _OFF_TARGET_BLOB_SEC := 0.5

## The bottle art. It squashes a little while squeezing.
@export var art: Node2D

var _is_squeezing := false
var _off_target_sec := 0.0


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _is_squeezing or delta <= 0.0:
		return
	var nozzle := get_tip_position()
	var amount := G.settings.glue_flow_rate * delta
	var hit := false
	if is_instance_valid(G.level) and is_instance_valid(
		G.level.active_repairable
	):
		for layer in G.level.active_repairable.layers:
			for point in layer.get_points():
				if not (point is Crack):
					continue
				var crack := point as Crack
				if not crack.is_exposed() or not crack.is_visible_in_tree():
					continue
				if crack.on_glued(
					nozzle, G.settings.glue_radius_px, amount
				):
					hit = true
	if hit:
		_off_target_sec = 0.0
		return
	_off_target_sec += delta
	if _off_target_sec >= _OFF_TARGET_BLOB_SEC:
		_off_target_sec = 0.0
		_blob_on_surface(nozzle)


func is_effect_tool() -> bool:
	return true


## A press starts the squeeze where the nozzle lands.
func on_effect_pressed(_global_point: Vector2) -> void:
	_is_squeezing = true
	_off_target_sec = 0.0
	art.scale = Vector2(1.0, 0.9)
	if is_instance_valid(G.level):
		G.level.hand.set_input_owner(self)
	G.audio.play_sound(&"scrape")


func on_pointer_released(_global_point: Vector2) -> void:
	_stop_squeezing()


func put_away() -> void:
	_stop_squeezing()
	super.put_away()


func _stop_squeezing() -> void:
	_is_squeezing = false
	if is_instance_valid(art):
		art.scale = Vector2.ONE
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


## Glue on a plain surface: a blob decal and a defect.
func _blob_on_surface(at_position: Vector2) -> void:
	if not is_instance_valid(G.level):
		return
	var surface := G.level.hand.find_surface(at_position)
	if not is_instance_valid(surface) or not surface.is_active():
		return
	var layer := surface.get_layer()
	if not is_instance_valid(layer) or not is_instance_valid(layer.art):
		return
	G.level.spawn_decal(
		DecalSpawner.Kind.GLUE_BLOB, layer.art, at_position, 16.0
	)
	if is_instance_valid(layer.item):
		layer.item.quality.add_defect(
			RepairQuality.Defect.GLUE_BLOB, at_position, surface
		)
