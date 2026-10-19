class_name Settings
extends Resource


enum PhysicsLayer {
	NONE = 0,
	TOOLS = 1 << 0,
	REPAIRABLES = 1 << 1,
	INTERACTION_POINTS = 1 << 2,
	TABLE = 1 << 3,
	TOOL_HOLDERS = 1 << 4,
	SURFACES = 1 << 5,
	PARTS = 1 << 6,
}

# --- General configuration ---

@export var dev_mode := true
@export var show_debug_console := false

@export var start_in_game := true
## Play the bird's window slam as soon as the game starts
## instead of waiting for its scheduled repairable. A
## playtesting convenience; the peeks follow as usual.
@export var show_bird_slam_at_start := false
## Show the credits card as soon as the game starts, the way
## winning does, instead of playing the day through. A
## playtesting convenience.
@export var show_credits_at_start := false
@export var full_screen := false
@export var move_preview_windows_to_other_display := true
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

# --- Game configuration ---

## Downward pull on everything that flies or falls (bench
## returns, throws), in pixels per second squared. Tuned high
## for this screen size: at 2200 a 300 px drop hung for over a
## third of a second and read as floaty.
@export var default_gravity_acceleration := 3600.0

@export var default_level_scene: PackedScene

@export_group("Hand")
## The pointing hand shown by default everywhere. This texture
## replaces the arrow shape.
@export var point_cursor_texture: Texture2D
## Where the point cursor's hot spot sits, in the resized
## texture's pixels: the fingertip.
@export var point_cursor_hotspot := Vector2(18.0, 2.0)
## The open hand shown over things the empty hand can grab. Godot
## has no grab cursor shape, so this texture replaces the
## pointing-hand shape wherever the hand offers a grab.
@export var grab_cursor_texture: Texture2D
## Where the grab cursor's hot spot sits, in the resized
## texture's pixels. Halfway between the palm and where the
## pointing hand's fingertip sits, so the open hand renders a
## little down-right of the pointer, roughly where the pointing
## hand's body is, while the palm stays near what it grabs.
@export var grab_cursor_hotspot := Vector2(24.0, 20.0)
## The grabbed hand shown while the hand holds something. This
## texture replaces the drag shape, so holding never falls back
## to the system drag cursor, and the cursor is never hidden.
@export var grabbed_cursor_texture: Texture2D
## Where the grabbed cursor's hot spot sits: cheated halfway
## toward the pointing hand's fingertip, like the grab cursor.
@export var grabbed_cursor_hotspot := Vector2(24.0, 20.0)
## Seconds for a held tool to ease into the pointer instead of jumping.
@export var tool_follow_ease_sec := 0.2
## Seconds a tool shakes when a point doesn't accept it.
@export var nope_shake_sec := 0.2
@export var nope_shake_px := 5.0
## Seconds the "nope" icon stays up.
@export var nope_icon_sec := 0.6
@export_group("")

@export_group("Layers")
## Seconds a loose layer waits before it lifts off.
@export var layer_lift_delay_sec := 0.3
## Seconds a layer takes to move to or from the set-aside spot.
@export var layer_move_sec := 0.4
## Scale of a set-aside layer, relative to its scale on the item.
@export var set_aside_scale := 0.8
## Offset between set-aside layers stacked on the spot.
@export var set_aside_stack_offset := Vector2(10.0, -10.0)
## A dragged layer dropped within this many world pixels of its home
## tweens into its exact place on the item.
@export var layer_seat_snap_px := 64.0
## Seconds and pixels of the shake when an unfinished item is pressed.
@export var item_shake_sec := 0.3
@export var item_shake_px := 4.0
## Seconds of one pulse on a point that still needs work.
@export var point_pulse_sec := 0.4
@export_group("")

@export_group("Item flow")
## Seconds an item takes to drop in from above, land and finish
## bouncing.
@export var item_arrival_sec := 0.9
## How high an arriving item's first bounce goes. Each later bounce is
## lower.
@export var item_arrival_bounce_px := 60.0
## The most an arriving item is turned, in degrees. It straightens as it
## lands.
@export var item_arrival_angle_max_deg := 8.0
## The camera shake when an arriving item first hits the bench. Each
## later bounce shakes less.
@export var item_landing_shake_px := 7.0
@export var item_landing_shake_sec := 0.15
## How long the outbox's "OUT" label takes to fade in or out with its
## outline.
@export var outbox_label_fade_sec := 0.25
## Seconds an item takes to ease back when it is dropped away from the
## outbox.
@export var item_return_sec := 0.3
## Seconds an item takes to drop into the tray, and then to slide off the
## left edge of the screen.
@export var item_tray_drop_sec := 0.15
@export var item_leave_sec := 0.4
## Seconds after an item goes into the outbox before the next one arrives.
@export var next_item_delay_sec := 0.5
## The most a dragged item tilts, in degrees, and the sideways drag speed
## in pixels per second that tilts it that far.
@export var drag_tilt_max_deg := 8.0
@export var drag_tilt_full_speed := 900.0
## How fast a dragged item's tilt catches up with its target. Higher is
## quicker.
@export var drag_tilt_follow_rate := 12.0
## The gradient outline that marks what can be pressed next: a layer
## ready to go back on, a resting screw that can come back, a finished
## item and the outbox. Sprite2D art gets this material. ColorRect and
## Polygon2D art gets the same rim drawn by OutlineHint instead.
@export var outline_hint_material: ShaderMaterial
## Opacity of the bench drop shadows (DropShadow). 0 turns them off.
@export var drop_shadow_alpha := 0.45
## The burst of sparkles when an item is finished.
@export var finish_sparkle_scene: PackedScene
@export_group("")


@export_group("Hints")
## Seconds without a correct interaction on the current repair
## step before the hint tracker outlines what to touch next. Any
## correct interaction restarts the count. See RepairSequence.
@export var hint_delay_sec := 7.0
## Seconds without a correct interaction before the tracker also
## outlines the stored tool the highlighted point needs, on top of
## the point itself. Counted from the same last correct
## interaction as `hint_delay_sec`, so it is the longer delay.
@export var hint_tool_delay_sec := 16.0
@export_group("")

@export_group("Drawers")
## Seconds an open drawer takes to slide to the center of the level,
## and back to its slot. The turn to the top-down view takes the
## same trip, so the two stay in step.
@export var drawer_move_sec := 0.35
## Seconds the drawer takes to slide out of its slot, before it
## turns and travels. The same slide runs in reverse at the end of
## a close, and out to the same point to take a part back.
@export var drawer_slide_sec := 0.3
## Seconds a drawer takes to open halfway to take a part back.
@export var drawer_half_open_sec := 0.15
## Seconds a returned part takes to rise over the drawer's top edge,
## and then to sink down into the drawer.
@export var part_put_away_sec := 0.22
## Seconds a drawer's stored parts take to fade in as it finishes
## opening. They fade back out in half this time as it starts to
## close.
@export var part_fade_sec := 0.25
## Wrong parts hidden alongside the parts an item needs, so the player
## has to pick the right one out of the drawers.
@export var decoy_part_count := 2
## How close a press may land to a loose part's center and still
## grab it, in world pixels.
@export var part_grab_radius_px := 30.0
@export_group("")

@export_group("Parts")
## One dedicated scene per part kind. Each scene's root sets
## its own kind, so the level spawns the kind's scene and the
## shared `part.tscn` stays for probes that set the kind by
## hand.
@export var gear_part_scene: PackedScene
@export var tube_part_scene: PackedScene
@export var tv_controls_part_scene: PackedScene
@export var letter_key_part_scene: PackedScene
@export var spacebar_part_scene: PackedScene
@export var led_part_scene: PackedScene
@export var joystick_part_scene: PackedScene
@export var circuit_part_scene: PackedScene
@export var crystal_part_scene: PackedScene
@export var bolt_part_scene: PackedScene
@export var nut_part_scene: PackedScene
@export_group("")

@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#ScaffolderLog.CATEGORY_DEFAULT,
	#ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	#ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	#ScaffolderLog.CATEGORY_INTERACTION,
	#ScaffolderLog.CATEGORY_BEHAVIORS,
	#ScaffolderLog.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var verbosity := ScaffolderLog.Verbosity.NORMAL
@export_group("")

@export_group("Repairables")
@export var flat_head_screw_repairable_scene: PackedScene
@export var phillips_repairable_scene: PackedScene
@export var toaster_scene: PackedScene
@export var atari_repairable_scene: PackedScene
@export var keyboard_repairable_scene: PackedScene
@export var tv_repairable_scene: PackedScene
@export var piano_repairable_scene: PackedScene
@export var game_n_watch_repairable_scene: PackedScene
@export var radio_repairable_scene: PackedScene
@export var shrink_ray_repairable_scene: PackedScene
## The day's order: the items that arrive, one after another. The game is
## won after the last one goes into the outbox.
@export var item_queue: Array[Repairable.Type] = []

## Which repairable, if any, the schedule skips ahead to. A
## playtesting convenience: pick one here and the day starts
## at its slot in `item_queue`, dropping everything before
## it, and plays from there. Pick the last item to skip to
## the end. `None` (or an item the queue doesn't hold) plays
## the queue as authored. The two test boxes stay on the
## list: the flat-head one exercises every interaction
## mechanic.
enum FirstRepairable {
	NONE,
	TEST_FLAT_HEAD,
	TEST_PHILLIPS,
	ATARI_JOYSTICK,
	KEYBOARD,
	TV,
	PIANO,
	GAME_N_WATCH,
	RADIO,
	TOASTER,
	SHRINK_RAY,
}

@export var first_repairable_override := FirstRepairable.NONE
@export_group("")

@export_group("Tools")
@export var flat_head_screw_driver_scene: PackedScene
@export var rag_scene: PackedScene
@export var air_blower_scene: PackedScene
@export var hammer_scene: PackedScene
## The placeholder bottle art stands in until the real one lands.
@export var glue_scene: PackedScene
@export var phillips_screw_driver_scene: PackedScene
@export_group("")

@export_group("Phillips")
## Slowest circle speed that still turns the screw, in radians
## per second. About half a turn per second.
@export var phillips_speed_min_rad_per_sec := 2.5
## Fastest circle speed that still turns the screw. Circling
## faster cams the bit out.
@export var phillips_speed_max_rad_per_sec := 10.0
## The speed at the end of the gauge's sweep.
@export var phillips_gauge_max_rad_per_sec := 14.0
## Width of the green speed zone, in radians per second. The zone
## slides counter-clockwise around the gauge, so its center keeps
## climbing and wraps from the fast end back to the slow end.
@export var phillips_zone_width_rad_per_sec := 3.5
## Slowest and fastest rate the zone center climbs at, in radians
## per second per second. It eases between fresh targets in this
## range, so the pace never stays put for long.
@export var phillips_zone_move_min_rad_per_sec := 0.8
@export var phillips_zone_move_max_rad_per_sec := 2.2
## Seconds between fresh zone-pace targets.
@export var phillips_zone_retarget_min_sec := 1.2
@export var phillips_zone_retarget_max_sec := 2.6
## Grip gained per second while the speed is in the band.
@export var phillips_fill_rate := 0.35
## Grip lost per second while the speed is out of the band.
@export var phillips_drain_rate := 0.28
## Grip a removal starts with, and an install starts with. It
## starts full: the meter is only the time left before the bit
## strips or slips out, never progress toward done.
@export var phillips_meter_start := 1.0
@export var phillips_install_meter_start := 1.0
## Grip level where the gauge face starts reddening. Above this
## the face stays plain.
@export var phillips_failure_tint_start := 0.55
## Grip level where the gauge face reaches its fullest red, a
## little before the meter empties and the bit slips out.
@export var phillips_failure_tint_full := 0.15
## Seconds input pauses after a cam-out.
@export var phillips_cam_out_pause_sec := 0.5
## Grace seconds at the start, while the gauge scales in.
@export var phillips_intro_sec := 0.33
## Dragging must add up to this much turning, in radians, before
## the grip or the screw starts to move. Sitting with the driver
## seated and not yet circling costs nothing until then.
@export var phillips_start_drag_rad := 1.5
## Seconds the speed needle smooths over. The needle carries
## the gauge's only momentum: the grip follows its position.
@export var phillips_speed_smoothing_sec := 0.65
## Pointer steps shorter than this don't count toward the turning.
@export var phillips_min_segment_px := 4.0
@export_group("")

@export_group("Rag")
## Hit points of grime removed per second at the speed cap.
@export var rag_wipe_rate := 2.0
## Drag speed in pixels per second that wipes at the full rate.
@export var rag_speed_cap_px_per_sec := 400.0
## Extra grime hit points removed each time the drag reverses.
@export var rag_reversal_bonus := 0.12
## Pixels wiped on a sensitive surface before it is ruined.
@export var sensitive_ruin_distance_px := 300.0
## The share of that distance that already costs a minor smear.
@export var sensitive_minor_fraction := 0.3
@export_group("")

@export_group("Air blower")
## How far a puff reaches, in pixels.
@export var air_cone_length_px := 200.0
## Half of the puff cone's width, in degrees.
@export var air_cone_half_angle_deg := 15.0
## Dust hit points removed per second of full strength spray.
@export var air_blow_rate := 1.5
## One tap counts as this many seconds of spray.
@export var air_puff_sec := 0.4
## Seconds the bulb stays squeezed after a tap.
@export var air_squeeze_sec := 0.18
## Spin a fan gains per second of full strength spray.
@export var fan_spin_gain := 8.0
@export_group("")

@export_group("Hammer")
## Seconds of holding that fill the strength ring.
@export var hammer_charge_sec := 1.2
## Degrees the hammer lifts at full charge.
@export var hammer_max_windup_deg := 70.0
## Seconds the swing down takes.
@export var hammer_swing_sec := 0.08
## Seconds hammer and target freeze on impact.
@export var hammer_hit_stop_sec := 0.06
## Seconds the recoil takes after a swing.
@export var hammer_recoil_sec := 0.2
## Strength ring radius in pixels, and the bigger touch one.
@export var hammer_reticle_radius_px := 40.0
@export var hammer_reticle_radius_touch_px := 64.0
## Past the band by this much, a hit is far too hard.
@export var hammer_far_margin := 0.2
## Charge where a bare surface starts to take damage.
@export var hammer_surface_damage_charge := 0.55
## How far the hardest hit squashes the piece, as a fraction of
## its height. Softer hits squash a share of this. It spreads
## sideways by half as much (like the radio).
@export var hammer_squish_amount := 0.12
## Seconds the piece takes to spring back from that squash.
@export var hammer_squish_recover_sec := 0.3
@export_group("")

@export_group("Radio")
## Once an item is fixed, the radio's chance to start glitching each
## second is one over this.
@export var radio_glitch_chance_window_sec := 300.0
## After the radio is fixed, how long before it can glitch again.
@export var radio_glitch_cooldown_sec := 300.0
## When the radio is the item, how long it crackles on the shelf before it
## flies down to the bench.
@export var shop_radio_break_sec := 0.6
## How long the radio takes to fly between the shelf and the bench.
@export var shop_radio_fly_sec := 0.7
@export_group("")

@export_group("Glue")
## Planned (LX22). Coverage gained per second on a crack sample.
@export var glue_flow_rate := 2.0
## Seconds a covered crack dries before it is done.
@export var glue_dry_sec := 3.0
## Coverage past this on one sample spawns a blob and a defect.
@export var glue_blob_coverage := 1.5
## How close the nozzle must be to a crack sample, in pixels.
@export var glue_radius_px := 10.0
## The smear an off target squeeze leaves for the rag.
@export var glue_smear_scene: PackedScene
## Radius of the hold game's safe core, in pixels. A dot
## fully inside it banks still time.
@export var broken_hold_inner_radius_px := 18.0
## Radius of the wide band around a broken point, in pixels.
## A dot overlapping it warns. A dot past it fails the hold.
@export var broken_hold_outer_radius_px := 46.0
## Radius of the hold game's dot itself, in pixels.
@export var broken_hold_dot_radius_px := 8.0
## How far above the point the hold ring draws, in world
## pixels, so the player's finger is not over the game.
@export var broken_hold_ring_offset_px := 96.0
## How close the held piece's centre must be to its point,
## in world pixels, before the hold game starts at all. On
## starting, the piece tweens to the exact centre.
@export var broken_hold_start_radius_px := 28.0
## Seconds the piece takes to settle onto the point's exact
## centre when the hold game starts.
@export var broken_hold_align_sec := 0.18
## How much the held piece's offset moves the dot, so a
## small hand movement reads clearly in the ring.
@export var broken_hold_dot_scale := 1.6
## How fast the dot drifts on its own, in pixels per second.
## The player counters it by nudging the piece.
@export var broken_hold_drift_speed_px_per_sec := 14.0
## Seconds between fresh drift directions.
@export var broken_hold_drift_retarget_sec := 0.45
@export_group("")

@export_group("Quality")
## The points each kind of defect costs. See RepairQuality.Defect.
@export var screw_damage_points := 2
@export var screw_stripped_points := 10
@export var pliers_scratch_points := 3
@export var small_dent_points := 8
@export var large_dent_points := 12
@export var crack_points := 15
@export var yanked_part_points := 8
@export var minor_smear_points := 3
@export var ruined_smear_points := 10
@export var oil_drip_points := 4
@export var glue_blob_points := 5
## A grime spot or dust clump left uncleaned when the item
## finishes, per spot.
@export var leftover_dirt_points := 3
## A bench dust clump left uncleaned when the item finishes,
## per clump. See `Level.spawn_bench_dust()`.
@export var bench_dust_points := 3
## A broken piece hold that leaves its ring, per failure.
@export var failed_glue_hold_points := 5
## A repair loses some points for every full interval it runs past its par
## time, up to a maximum.
@export var time_penalty_interval_sec := 2.0
@export var time_penalty_points_per_interval := 1
@export var time_penalty_max_points := 30
## The score that earns each number of stars. A lower score earns one star.
@export var three_star_score := 85
@export var two_star_score := 60
## The floating number that shows a defect's cost.
@export var defect_popup_scene: PackedScene
@export_group("")

@export_group("Flathead")
## Seconds one twist takes to turn the screw (docs/design/flathead.md).
@export var flathead_twist_duration_sec := 0.65
## Degrees one twist turns the screw and the driver while it comes out.
@export var flathead_twist_angle_deg := 90.0
## Seconds between twists, with no drift. The window to recenter.
@export var flathead_pause_sec := 0.25
## Seconds after a re-engage with kept twists before the first
## twist starts. Much shorter than the pause, so picking a
## slipped screw back up resumes turning right away.
@export var flathead_resume_delay_sec := 0.12
## Seconds before a twist that the creak and the handle squash warn of it.
@export var flathead_telegraph_sec := 0.15
## Each twist drifts the tip by a random fraction of the screw's seat
## tolerance in this range. The most is over 1, so one twist can unseat
## a tip the player does not correct during the twist.
@export var flathead_slip_min := 0.70
@export var flathead_slip_max := 1.02
## A touch drag moves the flathead's tip this many times as far as the
## finger (docs/design/flathead.md "Correcting"). Mouse motion is 1 to 1.
@export var flathead_touch_gain := 2.0
@export_group("")

@export_group("Workable area")
## Extra inset inside the `%WorkableArea` polygon, on top of each
## piece's own radius, that a returned piece aims for. It keeps
## the whole piece clear of the edge when it comes to rest.
@export var workable_edge_padding_px := 6.0
## Highest sideways drift, in pixels per second, of a piece that
## is dropped above the workable area and falls straight down
## under `default_gravity_acceleration`. A wider sideways gap
## stretches the fall instead of speeding the drift up.
@export var workable_fall_max_drift_px_per_sec := 700.0
## Lowest and highest arc peak, in pixels above the landing
## point, of a flick that brings a piece in from below or from
## the side. The peak grows with the distance to travel between
## these two.
@export var workable_flick_peak_min_px := 36.0
@export var workable_flick_peak_max_px := 160.0
## A landing slower than this, in pixels per second downward,
## does not bounce. It only skids.
@export var workable_bounce_min_speed_px_per_sec := 160.0
## Bounce kept from a landing, before the piece's size takes
## its share. The kept share is this minus the piece's radius
## in pixels times `workable_bounce_size_falloff`, clamped so
## even the biggest piece keeps a little bounce.
@export var workable_bounce_restitution := 0.42
@export var workable_bounce_size_falloff := 0.004
## Skid slowdown, in pixels per second squared, for a piece
## whose radius is 20 pixels. It scales with the square root
## of the radius, so a big piece stops in a shorter skid than
## a small one at the same landing speed.
@export var workable_skid_deceleration := 650.0
## Share of the skid speed kept as spin, as a turn per second
## per pixel per second of skid, divided by the radius. A
## smaller piece spins faster in its skid than a bigger one.
@export var workable_spin_factor := 1.0
## Smoothed cursor speed, in pixels per second, that a drag
## must pass on release for the piece to be thrown with the
## cursor's motion instead of falling or flicking in from
## rest. The throw keeps the smoothed speed, capped at the
## most below.
@export var workable_throw_min_speed_px_per_sec := 500.0
## Capped high enough that, under `default_gravity_acceleration`,
## a hard upward flick still leaves the top of the screen.
@export var workable_throw_max_speed_px_per_sec := 2100.0
## Fastest a dropped or thrown piece may ever move, in
## pixels per second. Gravity may speed a falling piece up
## past the throw cap, but never past this.
@export var workable_max_speed_px_per_sec := 2400.0
## Wind drag on a piece in the air, as the share of its
## speed it loses per second. It slows falls and throws a
## little without ever stopping them.
@export var workable_wind_drag_per_sec := 0.3
## Seconds the cursor's speed is smoothed over before a
## release reads it. A single jump of the pointer, the way a
## test pushes one, never reads as a throw: the speed has to
## hold up across the frames before the release.
@export var workable_cursor_smoothing_sec := 0.07
@export_group("")

@export_group("Screw rest")
## Where a pulled-out screw waits on the bench while its layer is off
## (docs/design/screw_pullout.md). The first removed screw rests at
## the level's `%ScrewSetAsideSpot` marker, and each next one a step
## along the row. A full row starts a new one a row step away.
@export var screw_rest_step := Vector2(26.0, 0.0)
@export var screw_rest_row_step := Vector2(0.0, 56.0)
@export var screw_rest_row_size := 5
## Seconds a screw takes to slide from its hole to its rest spot, and back.
@export var screw_travel_sec := 0.4
## A dragged screw dropped within this many world pixels of its
## hole, or of another empty hole of its type on its layer, tweens
## down into that hole, loose and ready to drive in.
@export var screw_seat_snap_px := 48.0
## How far above its hole a seating screw's arc peaks, in world
## pixels, so it always comes down into place from above.
@export var screw_seat_arc_px := 48.0
@export_group("")


## How many points a defect costs.
func get_defect_points(defect: RepairQuality.Defect) -> int:
	var points := 0
	match defect:
		RepairQuality.Defect.SCREW_DAMAGE:
			points = screw_damage_points
		RepairQuality.Defect.SCREW_STRIPPED:
			points = screw_stripped_points
		RepairQuality.Defect.PLIERS_SCRATCH:
			points = pliers_scratch_points
		RepairQuality.Defect.DENT_SMALL:
			points = small_dent_points
		RepairQuality.Defect.DENT_LARGE:
			points = large_dent_points
		RepairQuality.Defect.CRACK:
			points = crack_points
		RepairQuality.Defect.YANKED_PART:
			points = yanked_part_points
		RepairQuality.Defect.SMEAR_MINOR:
			points = minor_smear_points
		RepairQuality.Defect.SMEAR_RUINED:
			points = ruined_smear_points
		RepairQuality.Defect.OIL_DRIP:
			points = oil_drip_points
		RepairQuality.Defect.GLUE_BLOB:
			points = glue_blob_points
		RepairQuality.Defect.LEFTOVER_DIRT:
			points = leftover_dirt_points
		RepairQuality.Defect.BENCH_DUST_LEFT:
			points = bench_dust_points
		RepairQuality.Defect.FAILED_GLUE_HOLD:
			points = failed_glue_hold_points
		_:
			G.fatal()
	return points


## The repairable the schedule skips ahead to, as a
## `Repairable.Type`, or -1 when the override is `NONE`.
func get_first_repairable_override() -> int:
	match first_repairable_override:
		FirstRepairable.TEST_FLAT_HEAD:
			return Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE
		FirstRepairable.TEST_PHILLIPS:
			return Repairable.Type.TEST_PHILLIPS_REPAIRABLE
		FirstRepairable.ATARI_JOYSTICK:
			return Repairable.Type.ATARI_JOYSTICK
		FirstRepairable.KEYBOARD:
			return Repairable.Type.KEYBOARD
		FirstRepairable.TV:
			return Repairable.Type.TV
		FirstRepairable.PIANO:
			return Repairable.Type.PIANO
		FirstRepairable.GAME_N_WATCH:
			return Repairable.Type.GAME_N_WATCH
		FirstRepairable.RADIO:
			return Repairable.Type.RADIO
		FirstRepairable.TOASTER:
			return Repairable.Type.TOASTER
		FirstRepairable.SHRINK_RAY:
			return Repairable.Type.SHRINK_RAY
		_:
			return -1


func get_repairable_scene_from_type(type: Repairable.Type) -> PackedScene:
	match type:
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE:
			return flat_head_screw_repairable_scene
		Repairable.Type.TEST_PHILLIPS_REPAIRABLE:
			return phillips_repairable_scene
		Repairable.Type.TOASTER:
			return toaster_scene
		Repairable.Type.ATARI_JOYSTICK:
			return atari_repairable_scene
		Repairable.Type.KEYBOARD:
			return keyboard_repairable_scene
		Repairable.Type.TV:
			return tv_repairable_scene
		Repairable.Type.PIANO:
			return piano_repairable_scene
		Repairable.Type.GAME_N_WATCH:
			return game_n_watch_repairable_scene
		Repairable.Type.RADIO:
			return radio_repairable_scene
		Repairable.Type.SHRINK_RAY:
			return shrink_ray_repairable_scene
		_:
			G.fatal()
			return null


func get_part_scene_from_type(type: Part.Type) -> PackedScene:
	match type:
		Part.Type.GEAR:
			return gear_part_scene
		Part.Type.TUBE:
			return tube_part_scene
		Part.Type.TV_CONTROLS:
			return tv_controls_part_scene
		Part.Type.LETTER_KEY:
			return letter_key_part_scene
		Part.Type.SPACEBAR:
			return spacebar_part_scene
		Part.Type.LED:
			return led_part_scene
		Part.Type.JOYSTICK:
			return joystick_part_scene
		Part.Type.CIRCUIT:
			return circuit_part_scene
		Part.Type.CRYSTAL:
			return crystal_part_scene
		Part.Type.BOLT:
			return bolt_part_scene
		Part.Type.NUT:
			return nut_part_scene
		_:
			G.fatal()
			return null


func get_tool_scene_from_type(type: Tool.Type) -> PackedScene:
	match type:
		Tool.Type.FLAT_HEAD_SCREW_DRIVER:
			return flat_head_screw_driver_scene
		Tool.Type.RAG:
			return rag_scene
		Tool.Type.AIR_BLOWER:
			return air_blower_scene
		Tool.Type.HAMMER:
			return hammer_scene
		Tool.Type.GLUE:
			return glue_scene
		Tool.Type.PHILLIPS_SCREW_DRIVER:
			return phillips_screw_driver_scene
		_:
			G.fatal()
			return null
