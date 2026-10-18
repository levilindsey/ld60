class_name Crack
extends InteractionPoint
## A crack the glue traces over (docs/design/glue.md). Samples
## sit every 8 px along the path. Glue covers the samples near
## the nozzle. A flooded sample blobs once. A covered crack
## dries, then it is a seam.


## The crack's path. Its curve is the line to trace.
@export var path: Path2D

## True while a covered crack dries.
var is_drying := false
## Seconds of drying left.
var dry_left := 0.0

var _samples: Array[Vector2] = []
var _coverage: Array[float] = []
var _blobbed: Array[bool] = []
var _is_seam := false


func _ready() -> void:
	super._ready()
	type = Type.CRACK
	role = Role.REPAIR
	G.check(is_instance_valid(path))
	_build_samples()


func _process(_delta: float) -> void:
	if mode == Mode.ACTIVE or is_drying:
		queue_redraw()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_drying:
		return
	dry_left -= delta
	if dry_left <= 0.0:
		is_drying = false
		_is_seam = true
		G.audio.play_sound(&"ding")
		finish()


func _draw() -> void:
	if _samples.size() < 2:
		return
	var line_color := Color(0.12, 0.1, 0.1, 0.9)
	if _is_seam:
		line_color = Color(0.9, 0.85, 0.6, 0.9)
	draw_polyline(PackedVector2Array(_samples), line_color, 3.0, true)
	# The glossy bead grows with the coverage.
	for index in _samples.size():
		if _coverage[index] >= 0.15:
			draw_circle(
				_samples[index], 3.5, Color(1, 1, 1, 0.8)
			)
	if is_drying:
		var center := _get_center()
		var share := 1.0 - clampf(
			dry_left / maxf(G.settings.glue_dry_sec, 0.01), 0.0, 1.0
		)
		draw_arc(
			center,
			26.0,
			-PI * 0.5,
			-PI * 0.5 + share * TAU,
			32,
			Color(0.4, 1.0, 0.45),
			4.0,
			true,
		)


## Glue flowed at a world point. Samples within `radius` gain
## `amount` of coverage. Returns true if any sample took glue.
func on_glued(
	at_position: Vector2, radius: float, amount: float
) -> bool:
	if mode == Mode.FINISHED or is_drying or amount <= 0.0:
		return false
	var hit := false
	for index in _samples.size():
		var sample_world := to_global(_samples[index])
		if sample_world.distance_to(at_position) > radius:
			continue
		hit = true
		_coverage[index] += amount
		if (
			_coverage[index] > G.settings.glue_blob_coverage
			and not _blobbed[index]
		):
			_blobbed[index] = true
			_spawn_blob(sample_world)
	if not hit:
		return false
	mode = Mode.ACTIVE
	queue_redraw()
	if _is_covered():
		is_drying = true
		dry_left = G.settings.glue_dry_sec
	return true


## How many samples the crack has.
func get_sample_count() -> int:
	return _samples.size()


## The sample points, in the crack's own pixels.
func get_samples() -> Array[Vector2]:
	return _samples.duplicate()


## The least covered sample, from 0 to 1 and past it.
func get_min_coverage() -> float:
	var least := 0.0
	var is_first := true
	for value in _coverage:
		if is_first or value < least:
			least = value
			is_first = false
	return least


func _is_covered() -> bool:
	for value in _coverage:
		if value < 1.0:
			return false
	return not _coverage.is_empty()


func _spawn_blob(at_position: Vector2) -> void:
	var layer := get_layer()
	if is_instance_valid(layer) and is_instance_valid(layer.art):
		G.level.spawn_decal(
			DecalSpawner.Kind.GLUE_BLOB, layer.art, at_position, 16.0
		)
	var item := get_item()
	if is_instance_valid(item):
		item.quality.add_defect(
			RepairQuality.Defect.GLUE_BLOB, at_position, self
		)


func _get_center() -> Vector2:
	if _samples.is_empty():
		return Vector2.ZERO
	return _samples[_samples.size() / 2]


func _build_samples() -> void:
	_samples.clear()
	_coverage.clear()
	_blobbed.clear()
	if not is_instance_valid(path) or path.curve == null:
		return
	var curve := path.curve
	var length := curve.get_baked_length()
	var count := maxi(int(length / 8.0), 2)
	for index in count + 1:
		_samples.append(curve.sample_baked(float(index) * 8.0))
		_coverage.append(0.0)
		_blobbed.append(false)
	queue_redraw()
