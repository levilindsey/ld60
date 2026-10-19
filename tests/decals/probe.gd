extends "res://tests/probe_base.gd"
## The decal textures (LX58). Boots the game, then checks the
## tinted decal sets, the fitted hammer dents and cracks, and the
## sprite dirt points (dust, grime, rust) with their set and color
## configuration.
##
## Run it with `tests/run.ps1 -Name decals`, or from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/decals/probe.tscn
## Exit code 0 means every check passed.


const _MAIN_SCENE_PATH := "res://src/core/main.tscn"
const _DUST_SCENE_PATH := "res://src/interaction_points/dust_clump.tscn"
const _GRIME_SCENE_PATH := "res://src/interaction_points/grime_spot.tscn"
const _RUST_SCENE_PATH := "res://src/interaction_points/rust_spot.tscn"
const _SEAT_SCENE_PATH := "res://src/interaction_points/seat_part.tscn"
const _BENT_SCENE_PATH := "res://src/interaction_points/bent_part.tscn"
const _TIMEOUT_SEC := 90.0

var _item: Repairable
var _cover: RepairLayer


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
	_cover = _item.layers[_item.layers.size() - 1]

	_check_sets()
	_check_fitted_spawns()
	await _check_surface_damage()
	await _check_strikable_damage()
	await _check_dirt_points()


## Every spawner kind has a set with textures, and the damage sets
## carry the tints Levi asked for.
func _check_sets() -> void:
	var spawner := G.level.get_node("%Decals") as DecalSpawner
	_expect(is_instance_valid(spawner), "the level has a decal spawner")
	for kind: DecalSpawner.Kind in DecalSpawner.Kind.values():
		var decal_set := spawner.get_set(kind)
		_expect(
			is_instance_valid(decal_set) and not decal_set.textures.is_empty(),
			"kind %s has a set with textures" % DecalSpawner.Kind.keys()[kind],
		)
	_expect(
		spawner.dent_set.tint.r < 0.9
		and is_equal_approx(spawner.dent_set.tint.r, spawner.dent_set.tint.g),
		"dents are tinted gray (%s)" % spawner.dent_set.tint,
	)
	_expect(
		spawner.crack_set.tint.r < 0.35,
		"cracks are tinted dark gray (%s)" % spawner.crack_set.tint,
	)
	_expect(
		spawner.rust_set.tint.r > spawner.rust_set.tint.g * 1.5,
		"rust is tinted rust colored (%s)" % spawner.rust_set.tint,
	)
	_expect(
		not spawner.scratch_set.has_random_rotation,
		"scratches keep their authored orientation",
	)
	_expect(
		not spawner.glue_blob_set.has_random_rotation,
		"glue keeps its authored orientation",
	)


## Runtime decals land where asked, shrink to fit a small part and
## keep the fixed orientation of the scratch and glue sets.
func _check_fitted_spawns() -> void:
	var art := _cover.art
	var spawner := G.level.get_node("%Decals") as DecalSpawner
	var center := _art_global(art, Vector2(50, 50))

	var dent := _cover.spawn_decal(
		DecalSpawner.Kind.DENT, _art_global(art, Vector2(2, 2)), 34.0
	)
	if _expect(is_instance_valid(dent), "a fitted dent spawns"):
		_expect(dent.get_parent() == art, "the dent parents to the part art")
		_expect(
			dent.modulate == spawner.dent_set.tint,
			"the dent wears the set tint",
		)
		var local: Vector2 = (
			art.get_global_transform().affine_inverse() * dent.global_position
		)
		_expect(
			Rect2(Vector2.ZERO, Vector2(100, 100)).grow(1.0).has_point(local),
			"the corner dent is nudged inside the part (%s)" % local,
		)
		_expect(
			_visible_size(dent) <= 34.0 * 1.2,
			"the dent is about the asked size (%.1f)" % _visible_size(dent),
		)

	var crack := _cover.spawn_decal(
		DecalSpawner.Kind.CRACK, center, 400.0
	)
	if _expect(is_instance_valid(crack), "an oversized crack spawns"):
		_expect(
			_visible_size(crack) <= 115.0,
			"the crack shrinks to fit the part (%.1f)" % _visible_size(crack),
		)

	var scratch := G.level.spawn_decal(
		DecalSpawner.Kind.SCRATCH, art, center, 30.0
	)
	if _expect(is_instance_valid(scratch), "a scratch spawns"):
		_expect(
			scratch.texture.resource_path.contains("decals/scratches"),
			"the scratch uses the scratch textures",
		)
		_expect(
			is_equal_approx(
				scratch.global_rotation,
				art.get_global_transform().get_rotation(),
			)
			and not scratch.flip_v,
			"the scratch stays upright, thick end down",
		)

	var blob := G.level.spawn_decal(
		DecalSpawner.Kind.GLUE_BLOB, art, center, 30.0
	)
	if _expect(is_instance_valid(blob), "a glue blob spawns"):
		_expect(
			blob.texture.resource_path.contains("decals/glue"),
			"the blob uses the glue textures",
		)
		_expect(
			is_equal_approx(
				blob.global_rotation,
				art.get_global_transform().get_rotation(),
			),
			"the glue blob stays upright",
		)


## A hard hammer hit on a bare surface leaves the matching decal.
func _check_surface_damage() -> void:
	var surface: Surface = null
	for candidate in _cover.get_surfaces():
		surface = candidate
	if not _expect(is_instance_valid(surface), "the cover has a surface"):
		return
	var art := _cover.art
	var center := _art_global(art, Vector2(50, 50))

	var cracks_before := _decal_count(art, "decals/cracks")
	surface.on_struck(center, 1.0)
	_expect(
		_decal_count(art, "decals/cracks") == cracks_before + 1,
		"a hard hit cracks a plastic surface, with a decal",
	)

	surface.type = Surface.Type.METAL
	var dents_before := _decal_count(art, "decals/dents")
	surface.on_struck(center, 1.0)
	_expect(
		_decal_count(art, "decals/dents") == dents_before + 1,
		"a hard hit dents a metal surface, with a decal",
	)

	# The piece can overrule the material's set: a metal screen
	# cracks, a plastic panel dents.
	_cover.hammer_decal = RepairLayer.HammerDecal.CRACK
	cracks_before = _decal_count(art, "decals/cracks")
	dents_before = _decal_count(art, "decals/dents")
	surface.on_struck(center, 1.0)
	_expect(
		_decal_count(art, "decals/cracks") == cracks_before + 1
		and _decal_count(art, "decals/dents") == dents_before,
		"a piece set to crack cracks even on metal",
	)
	_cover.hammer_decal = RepairLayer.HammerDecal.DENT
	surface.type = Surface.Type.PLASTIC
	cracks_before = _decal_count(art, "decals/cracks")
	dents_before = _decal_count(art, "decals/dents")
	surface.on_struck(center, 1.0)
	_expect(
		_decal_count(art, "decals/dents") == dents_before + 1
		and _decal_count(art, "decals/cracks") == cracks_before,
		"a piece set to dent dents even on plastic",
	)
	_cover.hammer_decal = RepairLayer.HammerDecal.DEFAULT


## An over hard hit on a strikable point leaves its decal too.
func _check_strikable_damage() -> void:
	var art := _cover.art
	var seat: SeatPart = (
		(load(_SEAT_SCENE_PATH) as PackedScene).instantiate()
	)
	_cover.add_child(seat)
	seat.position = Vector2(-25, 25)
	var bent: BentPart = (
		(load(_BENT_SCENE_PATH) as PackedScene).instantiate()
	)
	_cover.add_child(bent)
	bent.position = Vector2(25, 25)
	await _physics_frames(2)

	var cracks_before := _decal_count(art, "decals/cracks")
	seat.on_struck(1.0)
	_expect(
		seat.mode == InteractionPoint.Mode.FINISHED
		and _decal_count(art, "decals/cracks") == cracks_before + 1,
		"a hard seating cracks the board, with a decal",
	)

	var dents_before := _decal_count(art, "decals/dents")
	bent.on_struck(1.0)
	_expect(
		bent.current_error_deg < 0.0
		and _decal_count(art, "decals/dents") == dents_before + 1,
		"a hard hit flips the bend and dents the part, with a decal",
	)

	# The piece's set wins over the point's own choice too: a
	# seating on a dent piece dents instead of cracking.
	_cover.hammer_decal = RepairLayer.HammerDecal.DENT
	var seat_again: SeatPart = (
		(load(_SEAT_SCENE_PATH) as PackedScene).instantiate()
	)
	_cover.add_child(seat_again)
	seat_again.position = Vector2(-25, -25)
	await _physics_frames(2)
	cracks_before = _decal_count(art, "decals/cracks")
	dents_before = _decal_count(art, "decals/dents")
	seat_again.on_struck(1.0)
	_expect(
		_decal_count(art, "decals/dents") == dents_before + 1
		and _decal_count(art, "decals/cracks") == cracks_before,
		"a seating on a dent piece dents instead of cracking",
	)
	_cover.hammer_decal = RepairLayer.HammerDecal.DEFAULT


## The dirt points pick a texture from the configured set, wear
## the configured color, and still clean the way they used to.
func _check_dirt_points() -> void:
	var dust: DustClump = (
		(load(_DUST_SCENE_PATH) as PackedScene).instantiate()
	)
	dust.texture_set = DirtSpot.TextureSet.SECOND
	dust.tint = Color(1.0, 0.5, 0.5)
	_cover.add_child(dust)
	dust.position = Vector2(-30, -30)

	var grime: GrimeSpot = (
		(load(_GRIME_SCENE_PATH) as PackedScene).instantiate()
	)
	_cover.add_child(grime)
	grime.position = Vector2(30, -30)

	var grime_two: GrimeSpot = (
		(load(_GRIME_SCENE_PATH) as PackedScene).instantiate()
	)
	grime_two.texture_set = DirtSpot.TextureSet.SECOND
	_cover.add_child(grime_two)
	grime_two.position = Vector2(0, 32)

	var rust: RustSpot = (
		(load(_RUST_SCENE_PATH) as PackedScene).instantiate()
	)
	_cover.add_child(rust)
	rust.position = Vector2(32, 8)
	await _physics_frames(2)

	var dust_art := dust.art as Sprite2D
	_expect(
		dust_art.texture.resource_path.contains("decals/dust2"),
		"the dust wears the second dust set",
	)
	_expect(
		is_equal_approx(dust_art.modulate.g, dust.get_active_set().tint.g * 0.5),
		"the dust wears its color configuration",
	)
	dust.on_sprayed(1.0, Vector2.RIGHT, 10.0)
	await _seconds(0.6)
	_expect(
		dust.mode == InteractionPoint.Mode.FINISHED,
		"a puff still blows the dust off",
	)

	_expect(
		(grime.art as Sprite2D).texture.resource_path.contains("decals/grime0"),
		"the grime wears the first grime set",
	)
	_expect(
		(grime_two.art as Sprite2D).texture.resource_path
		.contains("decals/grime2"),
		"the grime wears the second grime set",
	)
	grime.on_wiped(5.0, 0.1)
	_expect(
		grime.mode == InteractionPoint.Mode.FINISHED
		and is_zero_approx(grime.art.modulate.a),
		"a wipe still cleans the grime",
	)

	_expect(
		rust.type == InteractionPoint.Type.RUST_SPOT
		and not rust.needs_work(),
		"rust is an optional point that stays",
	)
	_expect(
		(rust.art as Sprite2D).texture.resource_path.contains("decals/rust"),
		"the rust wears the rust set",
	)


## How many decals showing `texture_marker` sit on the part art.
func _decal_count(art: CanvasItem, texture_marker: String) -> int:
	var count := 0
	for child in art.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if (
				sprite.texture != null
				and sprite.texture.resource_path.contains(texture_marker)
			):
				count += 1
	return count


## The longer side of the decal's visible art, in world pixels.
func _visible_size(decal: Sprite2D) -> float:
	var region := decal.region_rect
	var longer := maxf(region.size.x, region.size.y)
	if longer <= 0.0 and decal.texture != null:
		longer = maxf(decal.texture.get_width(), decal.texture.get_height())
	return longer * decal.get_global_transform().get_scale().x


## A point of the part art, by its ColorRect local pixels.
func _art_global(art: CanvasItem, local_point: Vector2) -> Vector2:
	return art.get_global_transform() * local_point
