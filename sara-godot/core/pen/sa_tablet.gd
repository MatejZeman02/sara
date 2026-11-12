## What a pen reports, and what a brush is supposed to make of it.
##
## A tablet's pressure axis is hardware rather than a standard. A pen reaches
## 1.0 only under more force than anyone paints with, so a stroke that used the
## raw number never reached a full-strength dab and the top of the range was
## dead. What fixes it is one per-machine figure: the pressure a hand comfortably
## reaches, which is the one that maps to full strength.
##
## That figure is `SaSettings.tablet_max_pressure`, which Preferences > Tablet
## measures from the pen in front of you rather than a constant measured once on
## one tablet, because every pen and every hand reaches its own. This class
## is the maths those two share, plus the recorder that watches a calibration
## press, so the page and the brush cannot drift apart.
class_name SaTablet
extends RefCounted

## The lowest maximum that is still a calibration.
##
## Under this every touch is already full strength, and the division below is
## dominated by whatever noise the driver reports. It is also what stops a
## hand-edited config from dividing by zero.
const MIN_MAX_PRESSURE: float = 0.05

## The top of the hardware range. Nothing above it exists to be reported.
const MAX_MAX_PRESSURE: float = 1.0

## A pen whose maximum nobody has measured. Raw pressure passes straight
## through, which is the only honest answer for hardware that has not been held.
const DEFAULT_MAX_PRESSURE: float = MAX_MAX_PRESSURE

## Readings a calibration press must gather before its peak is worth offering.
##
## One stray event is not a measurement. Without this, a pen brushing the pad on
## its way past would arm the button with a maximum of near zero, and accepting
## that would make every touch afterwards full strength.
const MIN_SAMPLES: int = 4


## Clamps a maximum to the range that means something, defaulting a value that
## is not a number at all.
##
## Applied in the setter rather than at the point of use, so a figure typed into
## the config file by hand is bounded exactly like one dragged on a slider.
static func clamp_max_pressure(value: float) -> float:
    if not is_finite(value):
        return DEFAULT_MAX_PRESSURE
    return clampf(value, MIN_MAX_PRESSURE, MAX_MAX_PRESSURE)


## Where the sweep calibration's table is kept, beside the settings file.
const CURVE_FILE: String = "pressure_curve.txt"

## Where the points a painter placed on the curve are kept, beside the table.
## One `x y` pair a line. The table is what a stroke reads and the points are
## what the page reopens on, so the curve a painter drags is the curve they made
## rather than nine samples of it.
const CURVE_POINTS_FILE: String = "pressure_curve_points.txt"

## The correction the sweep calibration fitted, indexed by rescaled pressure,
## or empty for a pen nobody has swept. Static because every stroke reads it
## and there is one pen.
static var correction: PackedFloat32Array = PackedFloat32Array()

## The control points *correction* was sampled from, or empty when nobody placed
## any. A curve from the sweep dialog has none, because the dialog hands over a
## fitted table and not a hand-placed shape.
static var correction_points: PackedVector2Array = PackedVector2Array()

## Where a changed correction is announced, as the table before and the table
## now. The stamp module listens here to carry the brush in hand and the
## presets made under the old curve on to the new one, and nothing in this
## class names who listens.
static var curve_changes: CurveChanges = CurveChanges.new()

## The table the file held when last read or written, which is what a change is
## announced from. Not *correction*, because the sweep dialog puts a fitted
## table live before the painter keeps it, and a Keep then announced from the
## live table would name the fitted one as the old curve and the presets made
## under the real old one would be left behind.
static var _stored: PackedFloat32Array = PackedFloat32Array()


## The one signal of *curve_changes*. An inner class because a static signal
## is not a thing GDScript has, and one object every stroke can reach is what
## an announcement from a static class needs.
class CurveChanges:
    extends RefCounted

    ## *was* and *now* as `SaTablet.stamp()` would write them, so a listener
    ## compares stamps with stamps.
    signal changed(was: PackedFloat32Array, now: PackedFloat32Array)


## Raw pen pressure as a 0 to 1 stroke strength.
##
## Three steps that are not interchangeable. The maximum rescales the part of
## the hardware range a hand actually reaches, so ordinary force gives a full
## dab. The correction then straightens the hand itself, which is what the
## sweep calibration measured. The gamma bends what is left, which is taste
## rather than hardware, and belongs to the brush.
##
## The correction goes after the maximum and before the gamma on purpose. It
## is fitted from sweeps recorded through the maximum, so it speaks that
## scale, and putting it after the gamma would correct the painter's taste
## instead of their hand.
##
## A driver that reports a NaN gets zero rather than a clamp. Clamping would
## launder it into a plausible pressure and paint with it.
##
## *table* is the correction to read through, the painter's own unless the
## caller has another. A stamp preset passes the table it was made under, so one
## preset answers one curve in every painter's hands. The maximum is never a
## preset's, because it measures the hardware rather than the hand, and it runs
## before either curve.
static func normalize(raw_pressure: float, max_pressure: float, gamma: float, table: PackedFloat32Array = correction) -> float:
    if not is_finite(raw_pressure):
        return 0.0
    var normalized: float = clampf(raw_pressure / clamp_max_pressure(max_pressure), 0.0, 1.0)
    return pow(correct(normalized, table), gamma)


## *pressure* through *table*, the stored correction unless another is named,
## read between two entries. The identity for a table of fewer than two
## entries, so the cost of the feature on an uncalibrated pen is one array size
## check per event.
static func correct(pressure: float, table: PackedFloat32Array = correction) -> float:
    var count := table.size()
    if count < 2:
        return pressure
    var at := clampf(pressure, 0.0, 1.0) * float(count - 1)
    var low := floori(at)
    var high := mini(low + 1, count - 1)
    return lerpf(table[low], table[high], at - float(low))


## The painter's correction as a table a preset can carry, which is never
## empty: an uncalibrated pen is the diagonal written out as two entries. Empty
## is kept for a preset nobody has stamped, so the two cannot be mistaken for
## each other, and a stamped diagonal is a table a saved file writes down
## rather than a default it leaves out.
static func stamp() -> PackedFloat32Array:
    return correction.duplicate() if correction.size() >= 2 else PackedFloat32Array([0.0, 1.0])


## Whether two tables bend pressure the same way, read at 257 points rather
## than entry by entry. The diagonal as two entries and as 256 are one curve,
## and a table read back from `pressure_curve.txt` carries six decimals where
## the one still in memory carries a float's, so the tolerance is a little over
## that rounding.
static func same_table(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
    for i in range(257):
        var at := float(i) / 256.0
        if absf(correct(at, a) - correct(at, b)) > 1e-5:
            return false
    return true


## Where the table lives, which is beside the settings file so a painter can
## copy their calibration with the rest of their profile.
static func curve_path() -> String:
    return SaSettings.get_settings_dir().path_join(CURVE_FILE)


## Where the placed points live, beside the table.
static func curve_points_path() -> String:
    return SaSettings.get_settings_dir().path_join(CURVE_POINTS_FILE)


## Reads the stored table, leaving the correction empty when there is none or
## when the file is not a table. Called once at startup.
static func load_correction() -> void:
    correction = PackedFloat32Array()
    correction_points = PackedVector2Array()
    var file := FileAccess.open(curve_path(), FileAccess.READ)
    if file == null:
        return
    var values := PackedFloat32Array()
    for line in file.get_as_text().split("\n", false):
        var text := String(line).strip_edges()
        if text.is_empty():
            continue
        if not text.is_valid_float():
            push_warning("SaTablet: '%s' in the pressure curve is not a number, ignoring the file." % text)
            return
        values.append(clampf(text.to_float(), 0.0, 1.0))
    if values.size() >= 2:
        correction = values
        correction_points = _load_points()
    _stored = stamp()


## The placed points, or none when the file is missing or any line of it is not
## a pair of numbers. A table with no points is still a table, so a bad points
## file costs the painter their handles and not their calibration.
static func _load_points() -> PackedVector2Array:
    var file := FileAccess.open(curve_points_path(), FileAccess.READ)
    if file == null:
        return PackedVector2Array()
    var points := PackedVector2Array()
    for line in file.get_as_text().split("\n", false):
        var pair := String(line).strip_edges().split(" ", false)
        if pair.is_empty():
            continue
        if pair.size() != 2 or not pair[0].is_valid_float() or not pair[1].is_valid_float():
            push_warning("SaTablet: '%s' in the pressure curve's points is not a pair, ignoring the points." % line)
            return PackedVector2Array()
        points.append(Vector2(clampf(pair[0].to_float(), 0.0, 1.0), clampf(pair[1].to_float(), 0.0, 1.0)))
    return points if points.size() >= 2 else PackedVector2Array()


## Writes *table* and applies it at once, or removes the file when *table* is
## empty or the identity, so a Reset leaves nothing behind to load.
##
## *points* are the handles the table was sampled from, stored beside it so the
## page reopens on them. Left empty by the sweep dialog, whose curve is a fit
## and not a shape anyone placed, and then no points file is written, so a
## stale one from an earlier hand edit cannot outlive the table it described.
##
## Every save announces the change on *curve_changes*, from the table the file
## held before to the one it holds now, and a save that changes nothing says
## nothing.
static func save_correction(table: PackedFloat32Array, points: PackedVector2Array = PackedVector2Array()) -> void:
    DirAccess.remove_absolute(curve_points_path())
    correction_points = PackedVector2Array()
    if table.size() < 2 or SaTabletSweep.is_identity(table):
        correction = PackedFloat32Array()
        DirAccess.remove_absolute(curve_path())
        _announce()
        return
    correction = table.duplicate()
    _announce()
    DirAccess.make_dir_recursive_absolute(SaSettings.get_settings_dir())
    var file := FileAccess.open(curve_path(), FileAccess.WRITE)
    if file == null:
        push_warning("SaTablet: could not write the pressure curve to '%s'." % curve_path())
        return
    for value in table:
        file.store_line("%.6f" % value)
    if points.size() < 2:
        return
    var handles := FileAccess.open(curve_points_path(), FileAccess.WRITE)
    if handles == null:
        push_warning("SaTablet: could not write the pressure curve's points to '%s'." % curve_points_path())
        return
    for point in points:
        handles.store_line("%.6f %.6f" % [point.x, point.y])
    correction_points = points.duplicate()


## Tells whoever listens that the painter's curve moved, once per change.
static func _announce() -> void:
    var was := _stored
    _stored = stamp()
    if not same_table(was, _stored):
        curve_changes.changed.emit(was, _stored.duplicate())


## The raw pressure an input event carries, or -1.0 when it carries none.
##
## Only motion events have the axis. A button press does not, which is why the
## calibration pad asks for a press and a drag rather than a tap.
static func pressure_of(event: InputEvent) -> float:
    var motion := event as InputEventMouseMotion
    return motion.pressure if motion != null else -1.0


## The highest raw pressure seen since the last `reset()`.
var peak: float = 0.0

## How many usable readings arrived. A press that reported nothing is not a
## calibration however long it lasted.
var sample_count: int = 0


## Feeds one raw reading in. Returns true when it moved the peak.
##
## Zero and below is what a mouse reports, and what a pen in range but off the
## surface reports. Counting those would let waving the wrong device over the pad
## look like a finished measurement.
func observe(raw_pressure: float) -> bool:
    if not is_finite(raw_pressure) or raw_pressure <= 0.0:
        return false
    sample_count += 1
    if raw_pressure <= peak:
        return false
    peak = raw_pressure
    return true


## Whether the peak is worth offering as a calibration.
func has_usable_peak() -> bool:
    return sample_count >= MIN_SAMPLES and peak >= MIN_MAX_PRESSURE


func reset() -> void:
    peak = 0.0
    sample_count = 0
