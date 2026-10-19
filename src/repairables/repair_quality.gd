class_name RepairQuality
extends RefCounted
## The mistakes made while repairing one item, and the score and stars they
## add up to.
##
## Every tool records its defects here with `add_defect()`. The item fills in
## `repair_time_sec` and `par_time_sec` when it is finished. The numbers come
## from the "Quality" group in `Settings`. See docs/design/quality.md.


## A defect was recorded. `points` is what it cost, as a positive number. It
## is the net cost: a ruined smear that replaces a minor one only costs the
## difference, so the floating numbers add up to the receipt. The
## `global_position` is where to show it.
signal defect_added(defect: Defect, points: int, global_position: Vector2)


enum Defect {
	SCREW_DAMAGE,
	SCREW_STRIPPED,
	PLIERS_SCRATCH,
	DENT_SMALL,
	DENT_LARGE,
	CRACK,
	YANKED_PART,
	SMEAR_MINOR,
	SMEAR_RUINED,
	OIL_DRIP,
	GLUE_BLOB,
	LEFTOVER_GRIME,
	LEFTOVER_DUST,
	FAILED_GLUE_HOLD,
	BENCH_DUST_LEFT,
}

## Every item starts with this many points.
const MAXIMUM_SCORE := 100

## An item earns between one and this many stars.
const MAXIMUM_STARS := 3

const _MEDIUM_STARS := 2
const _MINIMUM_STARS := 1

## How long the repair took, from the item landing until it was finished.
## Paused time doesn't count. The item fills this in.
var repair_time_sec := 0.0
## How long the repair may take before it starts to cost points. The item
## fills this in. Zero or less means there is no par time, so no penalty.
var par_time_sec := 0.0

var _records: Array[Record] = []


## Records a defect and returns the points it cost.
##
## Pass the thing that was damaged as `source` (a surface or a screw). Smears
## need it: a surface's `SMEAR_RUINED` replaces its `SMEAR_MINOR`, and a minor
## smear on a surface that is already ruined costs nothing. Without a source,
## every smear counts on its own.
func add_defect(
	defect: Defect,
	global_position: Vector2,
	source: Object = null,
) -> int:
	var source_id := 0
	if source != null:
		source_id = source.get_instance_id()

	if defect == Defect.SMEAR_MINOR and _has_smear(source_id):
		return 0

	var record := Record.new()
	record.defect = defect
	record.points = G.settings.get_defect_points(defect)
	record.global_position = global_position
	record.source_id = source_id

	var points := record.points
	if defect == Defect.SMEAR_RUINED:
		var replaced_points := _remove_minor_smear(source_id)
		points = maxi(points - replaced_points, 0)

	_records.append(record)
	defect_added.emit(defect, points, global_position)
	return points


func get_defect_count() -> int:
	return _records.size()


## The points lost to defects, not counting the time penalty.
func get_defect_points_total() -> int:
	var total := 0
	for record in _records:
		total += record.points
	return total


## The points lost to a slow repair: a point for every full interval past
## the par time, up to a maximum. It's worked out here, not stored as a
## defect.
func get_time_penalty() -> int:
	if par_time_sec <= 0.0 or repair_time_sec <= par_time_sec:
		return 0
	var interval_sec := maxf(G.settings.time_penalty_interval_sec, 0.01)
	var over_sec := repair_time_sec - par_time_sec
	var interval_count := floori(over_sec / interval_sec)
	return mini(
		interval_count * G.settings.time_penalty_points_per_interval,
		G.settings.time_penalty_max_points,
	)


## From 0 to 100.
func get_score() -> int:
	return clampi(
		MAXIMUM_SCORE - get_defect_points_total() - get_time_penalty(),
		0,
		MAXIMUM_SCORE,
	)


## From 1 to 3. A finished item always gets at least one star.
func get_stars() -> int:
	var score := get_score()
	if score >= G.settings.three_star_score:
		return MAXIMUM_STARS
	if score >= G.settings.two_star_score:
		return _MEDIUM_STARS
	return _MINIMUM_STARS


## One line for each kind of defect that was recorded, in enum order. This is
## what the receipt lists.
func get_summary() -> Array[SummaryLine]:
	var lines: Array[SummaryLine] = []
	for defect in Defect.values():
		var line := SummaryLine.new()
		line.defect = defect
		for record in _records:
			if record.defect == defect:
				line.count += 1
				line.points += record.points
		if line.count > 0:
			lines.append(line)
	return lines


## The receipt's clerk notes: what cost points, as short
## tags, biggest cost first, at most four of them. A tag that
## happened more than once carries its count (`glue mess ×2`).
## The score and the exact points stay hidden (see
## docs/design/quality.md): the words only say why the stamp
## fell short. An empty list means a clean, on-time repair.
func get_receipt_tags() -> Array[String]:
	# Tag word, then the defect kinds that feed it. Related
	# kinds share a tag: small and large dents are both
	# "dented", a glue blob and a failed hold are both a
	# "glue mess", bench dust and item dust are both "dust".
	var categories: Array = [
		["stripped screws", [Defect.SCREW_STRIPPED]],
		["slipped screws", [Defect.SCREW_DAMAGE]],
		["cracked", [Defect.CRACK]],
		["dented", [Defect.DENT_SMALL, Defect.DENT_LARGE]],
		["glue mess", [Defect.GLUE_BLOB, Defect.FAILED_GLUE_HOLD]],
		["grime", [Defect.LEFTOVER_GRIME]],
		["dust", [Defect.LEFTOVER_DUST, Defect.BENCH_DUST_LEFT]],
		["smudged", [Defect.SMEAR_MINOR, Defect.SMEAR_RUINED]],
		["scratched", [Defect.PLIERS_SCRATCH]],
		["yanked", [Defect.YANKED_PART]],
		["oil stain", [Defect.OIL_DRIP]],
	]
	var by_defect := {}
	for line in get_summary():
		by_defect[line.defect] = line
	var found: Array = []
	for category in categories:
		var count := 0
		var points := 0
		for defect in category[1]:
			var line := by_defect.get(defect) as SummaryLine
			if is_instance_valid(line):
				count += line.count
				points += line.points
		if count > 0:
			found.append([points, category[0], count])
	var time_penalty := get_time_penalty()
	if time_penalty > 0:
		found.append([time_penalty, "slow", 0])
	found.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] > b[0]
	)
	var tags: Array[String] = []
	for entry in found.slice(0, 4):
		if (entry[2] as int) > 1:
			tags.append("%s ×%d" % [entry[1], entry[2]])
		else:
			tags.append(entry[1] as String)
	return tags


## The name the receipt shows for a defect.
static func get_defect_name(defect: Defect) -> String:
	match defect:
		Defect.SCREW_DAMAGE:
			return "Screw damage"
		Defect.SCREW_STRIPPED:
			return "Stripped screw"
		Defect.PLIERS_SCRATCH:
			return "Pliers scratch"
		Defect.DENT_SMALL:
			return "Small dent"
		Defect.DENT_LARGE:
			return "Large dent"
		Defect.CRACK:
			return "Crack"
		Defect.YANKED_PART:
			return "Yanked part"
		Defect.SMEAR_MINOR:
			return "Smudge"
		Defect.SMEAR_RUINED:
			return "Ruined finish"
		Defect.OIL_DRIP:
			return "Oil stain"
		Defect.GLUE_BLOB:
			return "Glue blob"
		Defect.LEFTOVER_GRIME:
			return "Grime left"
		Defect.LEFTOVER_DUST:
			return "Dust left"
		Defect.FAILED_GLUE_HOLD:
			return "Failed glue hold"
		Defect.BENCH_DUST_LEFT:
			return "Dust on the bench"
		_:
			G.fatal()
			return ""


## Whether this surface or screw already has a smear of either kind. Without
## a source there is nothing to match, so the answer is always no.
func _has_smear(source_id: int) -> bool:
	if source_id == 0:
		return false
	for record in _records:
		var is_smear := (
			record.defect == Defect.SMEAR_MINOR
			or record.defect == Defect.SMEAR_RUINED
		)
		if is_smear and record.source_id == source_id:
			return true
	return false


## Removes this source's minor smear, if it has one, and returns what it had
## cost.
func _remove_minor_smear(source_id: int) -> int:
	if source_id == 0:
		return 0
	for index in _records.size():
		var record := _records[index]
		if (
			record.defect == Defect.SMEAR_MINOR
			and record.source_id == source_id
		):
			_records.remove_at(index)
			return record.points
	return 0


## One recorded defect.
class Record extends RefCounted:
	var defect: Defect
	## The full cost, whatever it replaced.
	var points := 0
	var global_position := Vector2.ZERO
	## The instance id of what was damaged, or 0 if no source was given.
	var source_id := 0


## All the recorded defects of one kind, for the receipt.
class SummaryLine extends RefCounted:
	var defect: Defect
	var count := 0
	var points := 0
