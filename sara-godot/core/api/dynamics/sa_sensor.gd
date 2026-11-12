## One sensor: a named function from the sample to a number, plus one curve.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `tilt_elevation` is the one port in this file, and **its copyright line is in
## [`PROVENANCE.md`](PROVENANCE.md)**, beside it in the door.
## That one formula is a normalisation no rewrite could derive without changing
## what a leaning pen paints. Every other mechanism here is written below from
## what it does.
##
## **A sensor is a reading and a response.** The reading is a number the pen or
## the stroke already knows, pressure, a tilt, how far the stroke has come. The
## response is a curve the painter drew over it. This class is the pair, and it
## knows nothing about which setting the answer will end up moving: that is the
## curve option above it, which is what lets one sensor drive size on one option
## and opacity on another with two different curves.
##
## **Three kinds, and the kind is what the curve is applied through.** A plain
## sensor answers 0 to 1 and multiplies. An additive one answers -1 to 1 and
## sums, and has to be moved into 0 to 1 before the curve and back after, because
## a curve is drawn on a unit square and has no opinion about negative numbers.
## The one absolute rotation sensor answers a whole turn as 0 to 1, and is
## offset by half a turn on both sides so that a zero angle sits in the middle of
## the graph rather than at its corner: a painter drawing a response to "the
## direction I am moving" wants straight ahead under the middle of the curve, not
## split between its two ends. Getting that wrong is not a visible bug in a
## screenshot, it is a curve that reads backwards at one end.
##
## **The response is a sampled table, not the spline.** The curve is evaluated
## once into `TRANSFER_SIZE` entries and read between neighbours afterwards,
## because a dab asks for it several hundred times a stroke and the spline costs
## a search each time. The spline itself is Sara's own monotone cubic in
## `SaMonotoneCurve.sample`, the one `SaCurveEditor.sample_curve` draws, so the
## editor a painter already has is the editor. An identity curve is detected
## once and the lookup skipped, so an untouched sensor costs one branch.
class_name SaSensor
extends Resource

## Every sensor Sara can answer, in the spec's order. `PERSPECTIVE` is
## reserved and answers its neutral value, so a preset naming it round-trips
## through a build that cannot read it yet.
##
## **`DEPLETION` is Sara's own and comes after the sixteen**. The sixteen before
## it are Krita's, in Krita's order, and `sa_kpp_sensors.gd` maps a preset onto
## them by name: nothing in a `.kpp` can name this one, which is the point of
## putting it last rather than among them. `LIFT_UP` is Sara's own for the same
## reason and comes after it, so a preset naming either keeps its ordinal.
## `TEXTURE` is the third of Sara's own, after both, and `FUZZY_ALONG_STROKE`
## the fourth, after it.
##
## **A module adds a sensor without a line here.** It registers it through
## `SaSensorRegistry`, the door's `sensors`, and `id` then holds a number above
## the enum's that the registry answers for its key. `key_of`, `id_of` and
## `value` ask the registry for any id past the twenty, so a preset ticks a
## module's sensor by its key and a curve reads it as it reads pressure.
enum Id {
    PRESSURE,
    PRESSURE_IN,
    TILT_X,
    TILT_Y,
    TILT_DIRECTION,
    TILT_ELEVATION,
    SPEED,
    DRAWING_ANGLE,
    ROTATION,
    DISTANCE,
    TIME,
    FADE,
    FUZZY_PER_DAB,
    FUZZY_PER_STROKE,
    PERSPECTIVE,
    TANGENTIAL,
    DEPLETION,
    LIFT_UP,
    TEXTURE,
    FUZZY_ALONG_STROKE,
}

## What a reading means to the option that reads it, the three kinds of the
## header: a factor, a signed amount summed with the others, or a direction.
enum Kind { PLAIN, ADDITIVE, ABSOLUTE }

## The id as it is stored, so a preset file never holds an enum ordinal: an
## ordinal changes meaning the day a sensor is inserted in the middle.
const KEYS: Array[String] = [
    "pressure",
    "pressure_in",
    "tilt_x",
    "tilt_y",
    "tilt_direction",
    "tilt_elevation",
    "speed",
    "drawing_angle",
    "rotation",
    "distance",
    "time",
    "fade",
    "fuzzy_per_dab",
    "fuzzy_per_stroke",
    "perspective",
    "tangential",
    "depletion",
    "lift_up",
    "texture",
    "fuzzy_along_stroke",
]

## The lowest id a module's sensor is given, far above the enum so that a
## built-in added in years to come never meets one. `SaSensorRegistry` hands
## ids from here on, and a dab compares against it before it asks the registry.
const FIRST_MODULE_ID: int = 1 << 16

## The built-ins that sum rather than multiply, read by [method is_additive].
const ADDITIVE: Array[int] = [Id.TILT_DIRECTION, Id.ROTATION, Id.FUZZY_PER_DAB, Id.FUZZY_PER_STROKE, Id.FUZZY_ALONG_STROKE]

## The sensor that is reserved rather than built, named here so the count in a
## test is a statement rather than a magic number.
const DEFERRED: Array[Id] = [Id.PERSPECTIVE]

## Sensors this build reads but no input may feed, and why.
##
## **Not the same thing as `DEFERRED` above.** A deferred sensor has no
## `parameter` branch at all and is a reserved id, so it never appears in the
## editor. One here is built, read, and answers the honest value for an input
## that does not arrive, which for barrel rotation is zero at every angle,
## because a sensor a painter can tick and watch do nothing is worse than one
## they can see is unavailable.
##
## **Rotation's input never arrives, and tangential pressure's arrives while a
## pen source reads an airbrush's wheel.** Godot's pen event carries no wheel,
## so only a module reading the kernel's node does, the Linux pen module on
## Linux, and [method is_available] asks the registered source whether it reads
## one. That is decided each time it is asked, and the brush editor builds a
## curve option's page each time the page is shown, so a page shown after the
## module found the airbrush's node has the row live.
##
## Kept rather than removed, so a preset that names one round-trips and means
## what it says the day the input arrives. The editor greys the row and says
## why, and `is_available` rather than a name test in the control is what
## keeps that true for every engine: a second engine's sensor gets the same treatment by
## declaring itself here.
const UNAVAILABLE: Dictionary[int, String] = {
    Id.ROTATION: "Barrel rotation is not available yet, so this sensor always reads 0.",
    Id.TANGENTIAL:
    (
        "Tangential pressure is an airbrush's finger wheel, which needs the Linux pen module and an airbrush. "
        + "No wheel is being read, so this sensor always reads 0."
    ),
}


## Whether *sensor_id* has an input behind it now. Tangential pressure has one
## while *source*, or where it is null the source `SaContext.pens` asks, reads
## an airbrush's wheel.
static func is_available(sensor_id: Id, source: SaPenSource = null) -> bool:
    if not UNAVAILABLE.has(sensor_id):
        return true
    if sensor_id != Id.TANGENTIAL:
        return false
    var asked := source if source != null else SaPenSource.registered()
    return asked != null and asked.reads_wheel()


## Why *sensor_id* is unavailable, or an empty string when it is not, *source*
## as [method is_available] reads it.
static func unavailable_reason(sensor_id: Id, source: SaPenSource = null) -> String:
    if is_available(sensor_id, source):
        return ""
    return SaTyped.text_at(UNAVAILABLE, sensor_id, "")


## How far a pen has to lean before a tilt sensor reads its full swing, in
## degrees. Sixty rather than ninety, because a pen held at sixty degrees off
## vertical is already as far as a hand comfortably goes and the last thirty
## would be a part of the range no painter reaches. It is also what a preset
## written for another program assumes, so a tilt curve drawn there means the
## same thing here.
const TILT_RANGE: float = 60.0

## How many entries the response is sampled into. Two hundred and fifty six over
## 0 to 1 is finer than a dab can show, since the value it moves lands on a
## setting a painter reads as a pixel or a percent, and it is small enough to
## rebuild between two frames while a curve point is being dragged.
const TRANSFER_SIZE: int = 256

## How many sampled curves [member _tables] keeps before it starts again,
## which is more than every option of a brush holds and few enough that a
## painter dragging a curve's point for a minute never grows it past reason.
const TABLES_KEPT: int = 64

## Every curve's sampled table, by the curve's points, made once for every
## sensor that reads that curve. A sensor that shares its option's curve is a
## new copy at every stroke, and sampling its table again at each was a third
## of what a stamp stroke's dynamics cost. A table is only ever read, and a
## packed array is copied on a write, so a sensor can never change another's.
static var _tables: Dictionary[PackedVector2Array, PackedFloat32Array] = {}

## What one sweep is worth for the four sensors that have to be told, when the
## preset does not say: thirty pixels, thirty milliseconds, a thousand dabs, and
## a thousand pressure-weighted pixels of ink.
##
## The first three are the same defaults a preset written for another program
## leaves out, so a file that omits them means here what it meant there. The
## fourth is Sara's own and answers to nothing outside: a pen good for a thousand
## pixels of full-pressure stroke dies about two thirds of the way across a
## 1920-wide canvas, which is a marker running dry rather than a marker that was
## already dry or one that never ran out.
const DEFAULT_LENGTH_DISTANCE: int = 30
const DEFAULT_LENGTH_TIME: int = 30
const DEFAULT_LENGTH_FADE: int = 1000
const DEFAULT_LENGTH_DEPLETION: int = 1000

## The two curves a lift-up binding starts on, one per way an option reads a
## sensor. Both answer "no effect" at the landing, where the sensor reads nought,
## and the most the option can take away at a pen lifted clear.
##
## A multiplier such as Opacity is untouched at one, so its curve falls from one
## to nought and the paint thins to nothing as the pen leaves. An offset such as
## Saturation is untouched at a half, because `SaDynamics` moves the reading onto
## -1 to 1 before it shifts the colour, so its curve falls from a half to nought
## and the paint greys by the option's whole strength. Read by
## `SaCurveOption.bind_lift_up`, which is where a binding is made.
const LIFT_UP_THINS: PackedVector2Array = [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]
const LIFT_UP_GREYS: PackedVector2Array = [Vector2(0.0, 0.5), Vector2(1.0, 0.0)]

## What the texture sensor reads where there is no texture: a middle grey, the
## reading a colour offset such as Hue or Saturation treats as no shift, and the
## lightness a two-channel field flattens to at a Relief of nought.
const NEUTRAL_TEXTURE: float = 0.5

## How far apart the along-the-stroke roll draws its numbers, in tip
## diameters, so a stroke rises or falls over a few widths of itself and never
## from one point to the next. Four is a pick, and reversible: it is the
## shortest spacing at which a chord point a quarter of a diameter from the
## last, the farthest the noise brush lays two apart, moves the roll by less
## than a twentieth of its range.
const ALONG_SPACING: float = 4.0

## The tip diameter the along-the-stroke roll is measured in where the engine
## wrote none, in document pixels: the stamp's default brush, so its features
## are about two hundred pixels apart.
const ALONG_FALLBACK_DIAMETER: float = 50.0

## The name the along-the-stroke roll draws its stroke's seed by, after the
## option's own, so the per stroke number of the same option is not its seed.
const ALONG_SEED_KEY: String = ":along"

@export var id: Id = Id.PRESSURE
@export var active: bool = false
## The response curve's control points, in 0 to 1 on both axes. The identity is
## two points and is what a fresh sensor carries.
@export var curve: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])

## Distance, time, fade and depletion only. What one full sweep of the sensor is
## worth, and whether it sweeps again or stops at the far end.
##
## Depletion joins the three because a reservoir *is* a sweep: `length` is what
## the pen holds and the sweep is what it has spent. Its default for `periodic`
## is the other way round, and `create` sets it, because a marker that refills
## itself halfway along a stroke is a rhythm rather than a marker. A painter who
## wants the rhythm ticks the box.
@export var length: int = DEFAULT_LENGTH_DISTANCE
@export var periodic: bool = true

## The drawing angle sensor only.
@export var lock_angle: bool = false
@export var angle_offset: float = 0.0
## A fan is what a stroke does at a corner when the tip is not round: the
## direction changes faster than the walk lays dabs, so extra ones are emitted in
## between, `fan_step` degrees apart, to keep the edge from cutting. Read through
## [method fan_degrees].
@export var fan_corners: bool = false
@export var fan_step: float = 30.0

## The lookup, built once from `curve` and dropped when the curve is the
## identity. Not exported: it is derived and a stored copy would be a second
## authority on what the curve says.
var _transfer: PackedFloat32Array = PackedFloat32Array()
var _transfer_curve: PackedVector2Array = PackedVector2Array()
var _identity: bool = true
## Whether the lookup has been built for [member _transfer_curve]. A flag of
## its own, because an identity curve leaves the lookup empty, and reading an
## empty lookup as "not built" copied the curve and tested it at every reading.
var _transfer_built: bool = false

## Which of the three kinds of the header this sensor's id is, kept for
## [member _kind_of], so a reading asks once rather than twice a point. A
## module's id is asked every time, since its module may register after a
## first reading.
var _kind_of: int = -1
var _kind: Kind = Kind.PLAIN

## The along-the-stroke roll's seed, for the stroke seed and the name it was
## drawn by, and the four numbers it draws round [member _along_cell], so a
## point inside the cell of the point before it draws none. The roll moves a
## cell every four tip diameters, so most points of a stroke stay in one.
var _along_stroke_seed: int = 0
var _along_name: String = ""
var _along_seed: int = -1
var _along_cell: int = 0
var _along_drawn := PackedFloat64Array()

## The pen's lean [method tilt_elevation] last answered for, and its answer.
## Several options of one brush read the elevation at the same point, and the
## answer is a pure function of the two tilts.
static var _elevation_x: float = NAN
static var _elevation_y: float = NAN
static var _elevation: float = 0.0


## A sensor of *sensor_id*, with the length default that id carries.
static func create(sensor_id: Id, is_active: bool = false) -> SaSensor:
    var sensor := SaSensor.new()
    sensor.id = sensor_id
    sensor.active = is_active
    sensor.length = default_length(sensor_id)
    sensor.periodic = default_periodic(sensor_id)
    return sensor


## What one sweep is worth for a sensor that has a length, and 0 for one that
## does not, which is not a length of zero but the absence of the field.
static func default_length(sensor_id: Id) -> int:
    match sensor_id:
        Id.DISTANCE:
            return DEFAULT_LENGTH_DISTANCE
        Id.TIME:
            return DEFAULT_LENGTH_TIME
        Id.FADE:
            return DEFAULT_LENGTH_FADE
        Id.DEPLETION:
            return DEFAULT_LENGTH_DEPLETION
        _:
            return 0


## Whether a fresh sensor of *sensor_id* sweeps again from the far end.
##
## True for the three that came from Krita, because that is what a preset written
## there means when it leaves the field out, and false for depletion, because a
## pen that refills itself without being lifted is not what the sensor is named
## after.
static func default_periodic(sensor_id: Id) -> bool:
    return sensor_id != Id.DEPLETION


## The stored key of *sensor_id*, a module's sensor's key where a module
## registered it, and an empty string for an id nothing holds.
static func key_of(sensor_id: Id) -> String:
    var at := int(sensor_id)
    if at >= 0 and at < KEYS.size():
        return KEYS[at]
    var registered := SaSensorRegistry.shared().sensor(at)
    return registered.key if registered != null else ""


## The id a stored key names, a module's sensor's where a module registered it,
## or -1 when nothing does. A preset naming a sensor this build has never heard
## of is a preset to keep rather than to repair, so the caller decides and this
## only reports.
static func id_of(key: String) -> int:
    var at := KEYS.find(key)
    return at if at >= 0 else SaSensorRegistry.shared().id_of(key)


## An additive sensor sums rather than multiplies, and is mapped through the
## curve in 0 to 1 rather than in -1 to 1. A module's sensor says which it is
## when it registers.
func is_additive() -> bool:
    if id < FIRST_MODULE_ID:
        return id in ADDITIVE
    var registered := SaSensorRegistry.shared().sensor(id)
    return registered != null and registered.additive


## There is exactly one, and it is the drawing angle.
func is_absolute_rotation() -> bool:
    return id == Id.DRAWING_ANGLE


## The step this sensor's fan asks for at a corner, in degrees, or 0.0 for no
## fan.
##
## **Four things have to hold, and each is a different kind of no.** It has to be
## the drawing angle sensor, because that is the only sensor whose reading is
## the direction the stroke is going and so the only one a corner moves. It has
## to be `active`, or nothing is following the stroke's direction and a fan would
## turn a tip that was never meant to turn. `fan_corners` has to be on, which is
## the painter's switch and is where a `.kpp` already puts it. And the angle must
## not be locked: every dab of a locked stroke draws at `locked_angle`, so a fan
## would be a stack of identical dabs at one point.
##
## Answering a step rather than a bool is what lets the walk ask one question. A
## step under the floor is the walk's to refuse rather than this one's, because
## the floor is about how many dispatches a corner costs and that is the walk's
## business.
func fan_degrees() -> float:
    if id != Id.DRAWING_ANGLE or not active or not fan_corners or lock_angle:
        return 0.0
    return maxf(0.0, fan_step)


## An additive reading, -1 to 1, moved onto the square a curve is drawn on.
## Zero lands in the middle, which is where a painter expects "no effect" to sit.
static func additive_to_scaling(reading: float) -> float:
    return 0.5 * (1.0 + reading)


## The way back out, so what the curve answered is a signed amount again.
static func scaling_to_additive(reading: float) -> float:
    return -1.0 + 2.0 * reading


## An angle brought back into one turn. Used on both sides of the curve by the
## absolute rotation sensor, whose half-turn offset can push a reading past
## either end and where wrapping is right and clamping would be wrong: an angle
## has no ends.
static func wrap_unit(reading: float) -> float:
    var wrapped := fmod(reading, 1.0)
    return wrapped + 1.0 if wrapped < 0.0 else wrapped


## The sensor's own reading of *info*, before any curve, id by id, and a
## module's sensor through `SaSensorRegistry` in the last branch.
##
## **The order of the branches is a cost and not a meaning.** A match tries its
## patterns one after another, and each try was a tenth of a microsecond, so
## the noise along the stroke, last of twenty, spent two of its three
## microseconds finding its own branch. The sensors a stock preset reads at
## every point therefore come first, pressure and the drawing angle of the
## stamp's presets and then the noise brush's, and the rest keep the order of
## the ids.
func value(info: SaStrokeInfo) -> float:
    match id:
        Id.PRESSURE:
            return info.pressure
        Id.DRAWING_ANGLE:
            return _drawing_angle_value(info)
        Id.FUZZY_ALONG_STROKE:
            return 0.0 if info.hovering else _along_stroke(info)
        Id.TEXTURE:
            # The brush's texture at the dab's centre, which the engine reads
            # and writes into the sample, since only the engine knows its
            # texture. A middle grey while hovering and wherever an engine has
            # no texture to read, because a half is what a colour offset reads
            # as no shift.
            return NEUTRAL_TEXTURE if info.hovering else info.texture
        Id.TILT_ELEVATION:
            return tilt_elevation(info.tilt_x, info.tilt_y)
        Id.SPEED:
            return info.drawing_speed()
        Id.PRESSURE_IN:
            return 0.0 if info.hovering else info.max_pressure
        Id.TILT_X:
            return 1.0 - absf(info.tilt_x) / TILT_RANGE
        Id.TILT_Y:
            return 1.0 - absf(info.tilt_y) / TILT_RANGE
        Id.TILT_DIRECTION:
            return scaling_to_additive(tilt_direction(info.tilt_x, info.tilt_y))
        Id.ROTATION:
            return info.barrel_rotation / 180.0
        Id.DISTANCE:
            return 1.0 if info.hovering else _swept(info.total_length)
        Id.TIME:
            return 1.0 if info.hovering else _swept(info.elapsed_ms)
        Id.FADE:
            return 1.0 if info.hovering else _swept_int(info.dab_index)
        Id.FUZZY_PER_DAB:
            return 0.0 if info.hovering else 2.0 * info.random.randf() - 1.0
        Id.FUZZY_PER_STROKE:
            return 0.0 if info.hovering else 2.0 * info.stroke_random(resource_name) - 1.0
        Id.PERSPECTIVE:
            # Reserved, and neutral. Perspective is what a drawing assistant
            # would scale a dab by as it recedes, and Sara has no assistants, so
            # the honest answer is the one that changes nothing.
            return 1.0
        Id.TANGENTIAL:
            # The airbrush's finger wheel, through the pen source the stroke
            # took at its press, and nought, its resting value, with none.
            return info.wheel()
        Id.DEPLETION:
            # What is left in the pen, so an untouched curve dies out along the
            # stroke and an inverted one grows. Full while hovering, like the
            # three other sweeps: a pen held over the canvas has spent nothing.
            return 1.0 if info.hovering else 1.0 - _swept(info.total_ink)
        Id.LIFT_UP:
            return 0.0 if info.hovering else lift_up(info.pressure, info.max_pressure)
        _:
            # A module's sensor, or nought, the reading of an input that does
            # not arrive, where its module is not loaded.
            var registered := SaSensorRegistry.shared().sensor(id)
            return registered.read(info, self) if registered != null else 0.0


## The sensor's reading with its curve applied, which is what a curve option
## sums or multiplies.
##
## The three kinds of the header, in one place: the curve is always evaluated on
## 0 to 1, so an additive reading is mapped in and back out, an absolute angle is
## turned half a turn in and half a turn back, and a plain one goes straight
## through. The identity short circuit is first, because a sensor whose curve the
## painter never touched should cost a comparison and not a table read.
func parameter(info: SaStrokeInfo) -> float:
    # Pressure and the drawing angle are read here without going through
    # `value`, since one or the other is what nearly every stock option reads,
    # and the call and its match were a third of what such a reading cost.
    var raw: float
    if id == Id.PRESSURE:
        raw = info.pressure
    elif id == Id.DRAWING_ANGLE:
        raw = _drawing_angle_value(info)
    else:
        raw = value(info)
    # Asked here rather than inside the rebuild, which saves a call at every
    # reading of a curve that has not changed, nearly all of them.
    if not _transfer_built or _transfer_curve != curve:
        _rebuild_transfer()
    if _identity:
        return raw
    var reading_kind := _kind if _kind_of == id else kind()
    var scaled := raw
    if reading_kind == Kind.ADDITIVE:
        scaled = additive_to_scaling(raw)
    elif reading_kind == Kind.ABSOLUTE:
        scaled = wrap_unit(raw + 0.5)
    # The table read between the two neighbours of the reading, which is not
    # the spline and is deliberately not: the spline drew the table once, and
    # reading it straight is what makes a sensor cost a lookup rather than a
    # search. Written here rather than called, as this is every reading.
    var count := _transfer.size()
    if count >= 2:
        var along := clampf(scaled, 0.0, 1.0) * float(count - 1)
        var low := floori(along)
        var high := mini(low + 1, count - 1)
        scaled = lerpf(_transfer[low], _transfer[high], along - float(low))
    if reading_kind == Kind.ADDITIVE:
        return scaling_to_additive(scaled)
    if reading_kind == Kind.ABSOLUTE:
        return wrap_unit(scaled + 0.5)
    return scaled


## Which of the three kinds this sensor's reading is, as [method is_additive]
## and [method is_absolute_rotation] answer it.
func kind() -> Kind:
    if _kind_of == id:
        return _kind
    var found := Kind.ADDITIVE if is_additive() else (Kind.ABSOLUTE if is_absolute_rotation() else Kind.PLAIN)
    if id < FIRST_MODULE_ID:
        _kind_of = id
        _kind = found
    return found


## Which way the pen leans, as a whole turn in 0 to 1.
##
## `atan2(-x, y)` rather than the usual `atan2(y, x)`, which is the same angle
## measured from a different place: this one has zero pointing up the canvas and
## grows clockwise, which is how a painter describes a lean and how the tilt the
## tablet reports is signed. The half added at the end is the same re-centring
## the header describes, so a pen held upright reads at the middle of the curve.
static func tilt_direction(tilt_x_degrees: float, tilt_y_degrees: float) -> float:
    return atan2(-tilt_x_degrees, tilt_y_degrees) / TAU + 0.5


## How upright the pen is, 0 flat and 1 vertical. **The one port left in this
## file**.
##
## A tablet reports two independent lean angles and there is no single pen
## direction that both of them describe, so turning the pair into one elevation
## is a choice rather than a derivation. This is the choice Krita made: `e` takes
## whichever tilt is the *smaller* in magnitude, which reads as a mistake until
## it is drawn, and is the length of the in-plane component of a unit pen leaning
## on the larger axis. A rewrite could write down what elevation ought to mean,
## and every honest reading of it answers a different number here, which would
## move every stroke a tilt-elevation curve has ever driven. So the formula stays
## as it is and the row stays a port.
static func tilt_elevation(tilt_x_degrees: float, tilt_y_degrees: float) -> float:
    if tilt_x_degrees == _elevation_x and tilt_y_degrees == _elevation_y:
        return _elevation
    var x := clampf(tilt_x_degrees / TILT_RANGE, -1.0, 1.0)
    var y := clampf(tilt_y_degrees / TILT_RANGE, -1.0, 1.0)
    var e := sqrt(1.0 + y * y) if absf(x) > absf(y) else sqrt(1.0 + x * x)
    var cos_alpha := clampf(sqrt(x * x + y * y) / e, -1.0, 1.0)
    _elevation_x = tilt_x_degrees
    _elevation_y = tilt_y_degrees
    _elevation = acos(cos_alpha) / (PI * 0.5)
    return _elevation


## How far the pen has lightened since the firmest point of its stroke, 0 at
## that point and 1 with the pen lifted clear. The lift-up sensor's reading.
##
## **What the name means.** A lift-up desaturates the way water would: a wet brush that lets go
## of the paper leaves a thinner, greyer mark than the one it pressed. Krita has
## no such sensor. Its nearest is Pressure (in), the stroke's running peak, which
## only ever rises and so cannot tell a pen pressing on from a pen letting go.
## Lift-up is the part of that peak the pen has since given back, over the peak:
## `(peak - pressure) / peak`. It is nought where the pen lands, since the first
## sample is its own peak, and nought all along a stroke held firm, and it rises
## towards one as the stroke goes on and the pen lightens, whatever the peak was,
## so a light hand and a heavy one lift the same way. Relative to the peak rather
## than to full pressure, because a painter who never presses hard still lifts,
## and a sensor reading the absolute drop would hardly move for them.
##
## Nought while hovering and nought before any pressure has arrived, because a
## pen that has not touched has nothing to let go of.
static func lift_up(pressure: float, peak: float) -> float:
    if peak <= 0.0:
        return 0.0
    return clampf((peak - pressure) / peak, 0.0, 1.0)


## A smooth noise of *along*, in -1 to 1, which draws a number at every whole
## *along* from *seed_value* and passes between them. The along-the-stroke
## roll's reading, with *along* in [constant ALONG_SPACING] tip diameters.
##
## **A uniform cubic B-spline over the drawn numbers**, rather than a curve
## through them, because with numbers in -1 to 1 its slope never passes one and
## a half a unit of *along*, half the three a smoothstep between two of them
## reaches. That bound is what lets a roll swing across its range over a few
## diameters and still move a point a sixteenth of a unit on, a quarter of a
## diameter, by less than a twentieth of the range. A B-spline passes inside
## its numbers rather than through them, so each is drawn pushed towards the
## ends, the square root of a uniform number with its sign, and the roll still
## reaches across most of its range along a stroke of a few dozen diameters.
static func along_noise(along: float, seed_value: int) -> float:
    var cell := floori(along)
    var t := along - float(cell)
    var t2 := t * t
    var t3 := t2 * t
    var before := (1.0 - t) * (1.0 - t) * (1.0 - t)
    var here := 3.0 * t3 - 6.0 * t2 + 4.0
    var next := -3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0
    var sum := (
        before * _drawn(seed_value, cell - 1)
        + here * _drawn(seed_value, cell)
        + next * _drawn(seed_value, cell + 1)
        + t3 * _drawn(seed_value, cell + 2)
    )
    return sum / 6.0


## The number [method along_noise] draws at *cell*, -1 to 1 and pushed towards
## both ends, the same for the same seed on every run and machine.
static func _drawn(seed_value: int, cell: int) -> float:
    var uniform := 2.0 * float(hash([seed_value, cell]) & 0xFFFFFF) / float(0xFFFFFF) - 1.0
    return signf(uniform) * sqrt(absf(uniform))


## Whether *points* is the identity curve, in which case the lookup is skipped.
static func is_identity_curve(points: PackedVector2Array) -> bool:
    if points.size() != 2:
        return false
    return points[0].is_equal_approx(Vector2.ZERO) and points[1].is_equal_approx(Vector2.ONE)


## The direction the stroke is going, re-centred and shifted by the painter's
## offset.
##
## Half a turn puts straight ahead under the middle of the curve, the offset is
## in degrees because that is what the editor asks for, and one subtraction is
## enough to come back into range because the offset is bounded to a turn and the
## angle is already inside one.
func _drawing_angle_value(info: SaStrokeInfo) -> float:
    var result := 0.5 + info.drawing_angle(lock_angle) / TAU + angle_offset / 360.0
    if result > 1.0:
        result -= 1.0
    return result


## Distance, time and depletion: how far through one sweep the stroke is.
##
## Periodic means the sensor sweeps again from the far end, so a painter gets a
## repeating pattern along the stroke. Not periodic means it stops at the end of
## its first sweep and stays there, which is a ramp-in rather than a rhythm.
##
## Depletion reads this backwards, `1 - swept`, so its ramp-in is a ramp-out: the
## sweep is what the pen has spent and the sensor answers what is left.
func _swept(total: float) -> float:
    var span := float(maxi(1, length))
    var swept := fmod(total, span) if periodic else minf(total, span)
    return swept / span


## The along-the-stroke roll: the smooth noise of how far the stroke has come,
## measured in the tip diameters the engine wrote, and seeded by the stroke and
## the option's own name, so two strokes roll two ways and two options of one
## stroke do not move together.
func _along_stroke(info: SaStrokeInfo) -> float:
    var diameter := info.tip_diameter if info.tip_diameter > 0.0 else ALONG_FALLBACK_DIAMETER
    # The seed is a pure function of the stroke's seed and the name, which is
    # what `stroke_random` draws by, so it is kept for the two of them.
    if _along_seed < 0 or _along_stroke_seed != info.stroke_seed or _along_name != resource_name:
        _along_stroke_seed = info.stroke_seed
        _along_name = resource_name
        _along_seed = int(info.stroke_random(resource_name + ALONG_SEED_KEY) * float(0xFFFFFF))
        _along_drawn = PackedFloat64Array()
    return _along_noise_kept(info.total_length / (ALONG_SPACING * diameter))


## [method along_noise] at *along* for [member _along_seed], with the four
## numbers round the cell kept while the cell stays. The same arithmetic in the
## same order, so it answers what [method along_noise] answers to the bit.
func _along_noise_kept(along: float) -> float:
    var cell := floori(along)
    if _along_drawn.is_empty() or cell != _along_cell:
        _along_cell = cell
        _along_drawn = PackedFloat64Array(
            [
                _drawn(_along_seed, cell - 1),
                _drawn(_along_seed, cell),
                _drawn(_along_seed, cell + 1),
                _drawn(_along_seed, cell + 2)
            ]
        )
    var t := along - float(cell)
    var t2 := t * t
    var t3 := t2 * t
    var before := (1.0 - t) * (1.0 - t) * (1.0 - t)
    var here := 3.0 * t3 - 6.0 * t2 + 4.0
    var next := -3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0
    var sum := before * _along_drawn[0] + here * _along_drawn[1] + next * _along_drawn[2] + t3 * _along_drawn[3]
    return sum / 6.0


## Fade, which counts dabs rather than measuring a distance, so its wrap is an
## integer modulo. `fmod` over a dab count would answer a fraction at the wrap
## and put a phantom part-dab between the last of one sweep and the first of the
## next.
func _swept_int(total: int) -> float:
    var span := maxi(1, length)
    var swept := total % span if periodic else mini(total, span)
    return float(swept) / float(span)


func _rebuild_transfer() -> void:
    _transfer_built = true
    _transfer_curve = curve.duplicate()
    _identity = is_identity_curve(curve)
    if _identity:
        _transfer = PackedFloat32Array()
        return
    if not _tables.has(curve):
        if _tables.size() >= TABLES_KEPT:
            _tables.clear()
        _tables[curve.duplicate()] = SaMonotoneCurve.sample(curve, TRANSFER_SIZE)
    _transfer = _tables[curve]
