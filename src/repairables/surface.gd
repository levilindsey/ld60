class_name Surface
extends Area2D
## A region of a part made of one material. Tools ask what is under
## them: the hammer dents METAL, oil soils CONTACTS
## (docs/design/repairables.md "Surfaces").
##
## A surface is a child of its layer, so it comes off with it. It is
## only active while that layer is exposed.


enum Type {
	PLASTIC,
	METAL,
	GLASS,
	CIRCUIT_BOARD,
	CONTACTS,
	RUBBER,
	PAPER_LABEL,
	PAINTED,
	GREASED,
	FELT,
	STICKER,
}

## Visible size of the decal a hard hit leaves, in pixels.
const _DENT_SMALL_SIZE_PX := 30.0
const _DENT_LARGE_SIZE_PX := 44.0
const _CRACK_SIZE_PX := 52.0

@export var type := Type.PLASTIC

## Pixels the rag has wiped over this surface.
var _wiped_px := 0.0
## Smear stage reached: 0 none, 1 minor, 2 ruined.
var _smear_stage := 0


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == Settings.PhysicsLayer.SURFACES)


## The layer this surface belongs to, or null.
func get_layer() -> RepairLayer:
	var node := get_parent()
	while is_instance_valid(node):
		if node is RepairLayer:
			return node as RepairLayer
		node = node.get_parent()
	return null


## True while this surface's layer is exposed.
func is_active() -> bool:
	var layer := get_layer()
	return is_instance_valid(layer) and layer.is_exposed()


## True for materials the rag must not wipe (docs/design/
## solvent.md). Wiping a GREASED part should also add a dry pivot.
## That waits for the oil can (LX21).
func is_sensitive() -> bool:
	return type in [
		Type.PAPER_LABEL,
		Type.PAINTED,
		Type.GREASED,
		Type.FELT,
		Type.STICKER,
	]


## The rag wiped this far over the surface, in pixels. A sensitive
## surface smears in stages, so stopping early stays cheap.
func on_wiped(distance_px: float) -> void:
	if not is_sensitive() or not is_active() or distance_px <= 0.0:
		return
	_wiped_px += distance_px
	var ruin_px := maxf(G.settings.sensitive_ruin_distance_px, 1.0)
	var fraction := _wiped_px / ruin_px
	if _smear_stage < 1 and fraction >= G.settings.sensitive_minor_fraction:
		_smear_stage = 1
		_add_defect(RepairQuality.Defect.SMEAR_MINOR, global_position)
	if _smear_stage < 2 and fraction >= 1.0:
		_smear_stage = 2
		_add_defect(RepairQuality.Defect.SMEAR_RUINED, global_position)


## The hammer struck here with this charge (docs/design/hammer.md).
## Light hits are harmless. Hard hits dent metal and crack plastic
## or glass.
func on_struck(at_position: Vector2, strength: float) -> void:
	if not is_active():
		return
	# Every hit squishes the piece a bit, damaging or not.
	var layer := get_layer()
	if is_instance_valid(layer):
		layer.squish(strength)
	var damage_at := G.settings.hammer_surface_damage_charge
	if strength < damage_at:
		return
	var is_far := strength >= damage_at + G.settings.hammer_far_margin
	# The material picks the damage, unless the piece overrules
	# its set (a metal screen cracks, a plastic panel dents).
	var defect: RepairQuality.Defect
	match type:
		Type.METAL:
			defect = (
				RepairQuality.Defect.DENT_LARGE
				if is_far
				else RepairQuality.Defect.DENT_SMALL
			)
		Type.PLASTIC, Type.GLASS:
			defect = RepairQuality.Defect.CRACK
		_:
			return
	if is_instance_valid(layer):
		defect = layer.get_hammer_defect(is_far, defect)
	_add_defect(defect, at_position)


func _add_defect(
	defect: RepairQuality.Defect,
	at_position: Vector2,
) -> void:
	var layer := get_layer()
	if not is_instance_valid(layer):
		return
	if is_instance_valid(layer.item):
		layer.item.quality.add_defect(defect, at_position, self)
	# Hammer damage shows: a fitted dent or crack on the part.
	match defect:
		RepairQuality.Defect.DENT_SMALL:
			layer.spawn_decal(
				DecalSpawner.Kind.DENT, at_position, _DENT_SMALL_SIZE_PX
			)
		RepairQuality.Defect.DENT_LARGE:
			layer.spawn_decal(
				DecalSpawner.Kind.DENT, at_position, _DENT_LARGE_SIZE_PX
			)
		RepairQuality.Defect.CRACK:
			layer.spawn_decal(
				DecalSpawner.Kind.CRACK, at_position, _CRACK_SIZE_PX
			)
		_:
			pass
