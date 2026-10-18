class_name RustSpot
extends DirtSpot
## A patch of rust. Rust stays (docs/design/decals.md "Dirt and
## wear"): no tool in the jam cleans it, so the point is optional
## and never needs work. On a screw it means seized; that is the
## screw's own `is_seized`, not this point. The oil can may give
## rust a job later (LX21). The art, its set and its color are
## configured on the shared `DirtSpot` base.


func _init() -> void:
	is_required = false


func _ready() -> void:
	super._ready()
	type = Type.RUST_SPOT
	role = Role.REPAIR
	_set_up_art()
