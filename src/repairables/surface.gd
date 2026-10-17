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

@export var type := Type.PLASTIC


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
