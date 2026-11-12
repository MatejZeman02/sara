## One modulated parameter: a set of sensors reduced to one number.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own. Every mechanism here is written below from what it does, so
## this file ports no code and carries no copyright line but its own.
##
## **One setting, and everything a painter said should move it.** A brush has
## nine of these, one per modulated setting, and each is a set of sensors, the
## curves drawn over them and the rule for putting the readings together. The
## setting itself is not here: this answers a number and the dynamics above
## decide what to do with it.
##
## **Three buckets, not one list.** Each sensor's `parameter()` lands in exactly
## one of them by its kind: additive sensors are summed, the one absolute
## rotation sensor overwrites an offset, and everything else is collected and
## combined by `combine`. That is why a sensor's kind is a property of the sensor
## and not of the option, and why getting a kind wrong is not a wrong number but
## a number in the wrong bucket.
##
## **The two reducers swap the roles of two of those buckets.** A size-like value
## multiplies and converts the additive part into a scaling one. A rotation-like
## value adds and converts the scaling part into an additive one. They also
## disagree about the bounds: size-like is clamped to the option's own range and
## rotation-like is wrapped over -1 to 1, because half a turn past the end is
## half a turn before the start and clamping an angle would stick a brush at its
## limit rather than turning it round.
##
## **`use_curve` off is a constant, not an off switch.** The option answers its
## `strength` and stops reading sensors. `enabled` is the separate flag that
## turns the option off, and both are load-bearing: the editor draws a switch
## at the top of the page for one and "Enable pen settings" under it for the
## other, and a painter uses them for different things. Off is "this brush does not do that". A
## constant is "this brush does that, by this much, always".
class_name SaCurveOption
extends Resource

## What two or more plain sensors do to each other. Multiply is the default and
## the one a painter expects: two halves make a quarter, and any sensor at rest
## leaves the others alone. The other four are there for the strokes multiply
## cannot describe, a floor, a ceiling and a spread.
##
## **The order is an interchange constant**, not a preference. A preset stores
## the choice as a number, and these five in this order are what such a number
## means in a `.kpp` written elsewhere, so re-ordering them would silently change
## every imported brush.
enum Combine { MULTIPLY, ADD, MAXIMUM, MINIMUM, DIFFERENCE }

## The fuzzy sensors a roll can be drawn on, which [method bind_random] binds
## one of: along the stroke, which the noise brush rolls on, per dab, which
## the stamp keeps, and once a stroke.
const RANDOM_CLOCKS: Array[SaSensor.Id] = [
    SaSensor.Id.FUZZY_ALONG_STROKE, SaSensor.Id.FUZZY_PER_DAB, SaSensor.Id.FUZZY_PER_STROKE
]

## Whether the option does anything at all: the switch at the top of its page
## in the editor, and the dot beside its name in the page list.
@export var enabled: bool = true

## Whether the sensors are read. Off leaves the option a constant at `strength`,
## which is not the same as off.
@export var use_curve: bool = true

## One curve shared by every sensor of this option, which is what a painter
## usually means: they drew a response, not a response per input. Each sensor's
## own curve is kept and ignored while this is on, so turning it off gives them
## back.
@export var use_same_curve: bool = true
@export var common_curve: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])

@export var combine: Combine = Combine.MULTIPLY

## The constant the reduced value is multiplied by, and the bounds the size-like
## reducer clamps to. The bounds are the option's own range rather than a user
## setting: Size is 0 to 1, Softness is 0.1 to 1, Scatter is 0 to 5.
@export var strength: float = 1.0
@export var strength_min: float = 0.0
@export var strength_max: float = 1.0

## What the option lays, as one number a slider can hold: the strength while it
## is ticked and nought while it is not, the way an unticked Colour Rate reads.
## Written, it ticks the option and sets the strength, so the Paint and Smudge
## slider dragged to the paint end lays the brush's colour whatever the switch
## read before. Computed and not stored, so a preset carries `enabled` and
## `strength` alone, and a sensor curve keeps scaling what this sets.
var ticked_strength: float:
    get:
        return strength if enabled else 0.0
    set(value):
        enabled = true
        strength = clampf(value, strength_min, strength_max)

## Sensor id -> `SaSensor`, holding only the sensors worth carrying: the active
## ones and any whose curve is not the identity. A default option is one entry,
## pressure, active, identity curve.
##
## Untyped on purpose. A typed export saves as `Dictionary[int, SaSensor](...)`
## rather than `{...}`, which is a change of every preset's text on disk, and
## the stamp brush's suite reads that text. The type waits for a change of the
## preset format.
@export var sensors: Dictionary = {}

## The sensors this stroke will actually read, built once at the press rather
## than once per dab. A stroke cannot gain or lose a sensor while it is being
## drawn, so the set is known at the press, and a dab is the hot path: nine
## options walking a dictionary each, several hundred times, is a cost with
## nothing to show for it.
var _prepared: Array[SaSensor] = []
var _prepared_ready: bool = false

## The kind of each prepared sensor, in the same order, and the one sensor
## when the option reads exactly one plain sensor, else null. Both are set at
## the press with the list, since neither can change before the next one.
## The lone sensor is the commonest option of all, and it is read without the
## buckets: one factor under no offset and no nudge is that factor. A lone
## drawing angle is the commonest rotation, kept the same way for the same
## reason.
var _prepared_kinds := PackedInt32Array()
var _lone_plain: SaSensor = null
var _lone_absolute: SaSensor = null

## What [method _read] read out of the sensors at the last reading, one member
## a bucket, and the option's constant, or one where the caller dropped it.
## Every absent part holds the value that leaves the reduction alone, and the
## flags say which parts a sensor actually wrote, since a reducer tells a part
## at its rest value from one that was never read.
var _read_constant: float = 1.0
var _read_scaling: float = 1.0
var _read_additive: float = 0.0
var _read_offset: float = 0.0
var _read_has_scaling: bool = false
var _read_has_additive: bool = false
var _read_has_offset: bool = false


## The option every parameter starts as: pressure, active, identity curve.
##
## Pressure because it is the one input every tablet has and the one a painter
## reaches for first, and the identity curve because a fresh option should
## answer the reading itself until somebody bends it.
static func create_default() -> SaCurveOption:
    var option := SaCurveOption.new()
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    return option


## Puts *sensor* in the set under its own id, replacing whatever was there.
##
## **A sensor switched on switches the curve on with it**. The tick and the
## "Enable pen settings" box were two separate acts, so every sensor a painter
## ticked was dead until they found the box, and the option answered its constant
## while showing a ticked sensor. The rule lives here rather than in the control
## because a preset, a scenario and the editor all arrive through this method and
## only one of them is the control.
func set_sensor(sensor: SaSensor) -> void:
    sensors[int(sensor.id)] = sensor
    if sensor.active:
        use_curve = true
    _prepared_ready = false


## Switches the lift-up sensor on, bound so that it takes paint away as the pen
## lets go. *offset* is true for an option read as a signed shift, Saturation
## or Value, and false for a multiplier such as Opacity, which is what picks
## between `SaSensor.LIFT_UP_GREYS` and `SaSensor.LIFT_UP_THINS`.
##
## **This is the binding both engines' pages make when a painter ticks the
## sensor.** An untouched curve would read the sensor the wrong way round: the
## identity multiplies opacity by nought at the landing, and an offset at nought
## is a full shift the other way. So the lift-up gets its own falling curve, and
## the option stops sharing one, since a shared curve would bend pressure the
## same way. Each sensor already active is handed the shared curve it was being
## read through first, so ticking lift-up changes what the lift-up does and
## nothing else. A lift-up already on is left as the painter has it.
func bind_lift_up(offset: bool) -> void:
    var lift := sensor_for(SaSensor.Id.LIFT_UP)
    if lift != null and lift.active:
        return
    if use_same_curve:
        for sensor in active_sensors():
            sensor.curve = common_curve.duplicate()
        use_same_curve = false
    if lift == null:
        lift = SaSensor.create(SaSensor.Id.LIFT_UP, true)
    lift.active = true
    lift.curve = (SaSensor.LIFT_UP_GREYS if offset else SaSensor.LIFT_UP_THINS).duplicate()
    set_sensor(lift)


## Binds the randomise control beside a setting's row: one fuzzy sensor, on
## *clock*, whose curve lowers the setting by up to *amount* of itself. The
## clock is one of [constant RANDOM_CLOCKS], the sensor the roll is drawn by.
## The row's value is the ceiling and a roll lands anywhere between it and that
## fraction below, which at one is the identity curve over the fuzzy reading.
##
## **The control owns no number of its own.** Amount and clock are this
## sensor's curve and its id, so a preset carries them, the curve editor shows
## them, and the page's control reads them back through [method random_amount]
## and [method random_clock]. The clocks are one choice, so binding one drops
## the others, and nought drops them all rather than switching them off:
## `ensure_one_active` would revive pressure under an option left with a
## sensor and none of them on, and a Size nobody bound to the pen would start
## following it.
##
## *key* is the option's own name, which the per stroke and along the stroke
## sensors draw their numbers by, so two settings rolled on one clock do not
## move together. Sharing one curve goes off as the lift-up's binding turns it
## off, each active sensor keeping the shared curve it was read through,
## because a shared curve would lay the pressure line over the roll's.
func bind_random(amount: float, clock: SaSensor.Id, key: String) -> void:
    var clamped := clampf(amount, 0.0, 1.0)
    for each: SaSensor.Id in RANDOM_CLOCKS:
        sensors.erase(int(each))
    _prepared_ready = false
    if clamped <= 0.0 or clock not in RANDOM_CLOCKS:
        return
    if use_same_curve:
        for sensor in active_sensors():
            sensor.curve = common_curve.duplicate()
        use_same_curve = false
    var roll := SaSensor.create(clock, true)
    roll.curve = PackedVector2Array([Vector2(0.0, 1.0 - clamped), Vector2(1.0, 1.0)])
    roll.resource_name = key
    enabled = true
    set_sensor(roll)


## Binds the texture sensor as a colour offset swinging by *spread* either way:
## the line from a half less half the spread at a texture of nought to a half
## more at one. A middle grey is then no shift, and the most a dab moves is the
## option's strength times the spread, which is the shape the lift-up's greying
## curve has for the same reason.
##
## Nought drops the sensor rather than switching it off, for the reason
## [method bind_random] gives. A texture sensor already on that very line is
## left as it is, so an engine that binds at every press writes nothing a saved
## preset would call a change. Sharing one curve goes off as it does for the
## other two bindings.
##
## **Beside a lift-up the two readings meet in the option's combine,** which
## multiplies by default, and a product of two readings centred on a half is not
## centred on a half. An option with both ticked wants Add, or a curve drawn for
## it by hand.
func bind_texture(spread: float) -> void:
    var clamped := clampf(spread, 0.0, 1.0)
    var line := PackedVector2Array([Vector2(0.0, 0.5 - 0.5 * clamped), Vector2(1.0, 0.5 + 0.5 * clamped)])
    var bound := sensor_for(SaSensor.Id.TEXTURE)
    if clamped <= 0.0:
        if bound != null:
            sensors.erase(int(SaSensor.Id.TEXTURE))
            _prepared_ready = false
        return
    if bound != null and bound.active and bound.curve == line and not use_same_curve:
        return
    if use_same_curve:
        for sensor in active_sensors():
            sensor.curve = common_curve.duplicate()
        use_same_curve = false
    var reading := SaSensor.create(SaSensor.Id.TEXTURE, true)
    reading.curve = line
    enabled = true
    set_sensor(reading)


## How far the roll bound by [method bind_random] reaches below the row, nought
## to one: the spread of the curve the fuzzy sensor is read through. Nought when
## no fuzzy sensor is on or the option is not reading its sensors, and a curve
## drawn by hand in the editor reads as the range it spans.
func random_amount() -> float:
    var roll := _random_sensor()
    if roll == null or not enabled or not use_curve:
        return 0.0
    var points: PackedVector2Array = common_curve if use_same_curve else roll.curve
    if points.is_empty():
        return 0.0
    var low := points[0].y
    var high := points[0].y
    for point in points:
        low = minf(low, point.y)
        high = maxf(high, point.y)
    return clampf(high - low, 0.0, 1.0)


## Which clock the roll is drawn on, the id of its fuzzy sensor. Along the
## stroke when no clock is on, because that is the clock the noise brush's
## randomise control opens on: the hard, soft and lost edges its spec asks for
## are a Hardness rolled along the stroke.
func random_clock() -> SaSensor.Id:
    var roll := _random_sensor()
    return SaSensor.Id.FUZZY_ALONG_STROKE if roll == null else roll.id


## The active fuzzy sensor, in the order of [constant RANDOM_CLOCKS], or null.
func _random_sensor() -> SaSensor:
    for id: SaSensor.Id in RANDOM_CLOCKS:
        var sensor := sensor_for(id)
        if sensor != null and sensor.active:
            return sensor
    return null


## The sensor for *id*, or null.
func sensor_for(id: SaSensor.Id) -> SaSensor:
    return sensors.get(int(id), null)


## Every sensor that is switched on, in id order so two runs agree.
func active_sensors() -> Array[SaSensor]:
    var found: Array[SaSensor] = []
    var ids := sensors.keys()
    ids.sort()
    for id: Variant in ids:
        var sensor: SaSensor = sensors[id]
        if sensor != null and sensor.active:
            found.append(sensor)
    return found


## At least one sensor stays active, and pressure is the one switched on when a
## set comes with none. Enforced where a preset arrives rather than where one is
## read, because a stroke should not be deciding what a preset meant.
##
## The reason is what the editor shows. An option carrying sensors with none of
## them active draws a row of unticked boxes over a curve graph, which reads as
## "listening, and nothing is coming through", while what it does is answer a
## constant. One of the two has to give, and reviving pressure is the one that
## matches what the page looks like.
##
## **An option carrying no sensor at all is left carrying none.** That is the
## state of eight of the nine on a new brush, and there is nothing to look as
## though it were listening: the control draws no ticked box for it and the
## option answers its strength, which is what a painter who has touched nothing
## should get.
func ensure_one_active() -> void:
    if not active_sensors().is_empty():
        return
    # An empty set is not a preset with everything switched off, it is an option
    # nobody has touched, and inventing pressure for it would be this file
    # deciding a brush should respond to something the painter never asked for.
    # It matters because every option is born with the curve on: without this
    # line Flow, which nothing in Sara has ever modulated, would pick up a
    # pressure sensor at the first press.
    if sensors.is_empty():
        return
    var pressure := sensor_for(SaSensor.Id.PRESSURE)
    if pressure == null:
        pressure = SaSensor.create(SaSensor.Id.PRESSURE, true)
        set_sensor(pressure)
        return
    pressure.active = true
    _prepared_ready = false


## Rebuilds the prepared list, which is what a stroke calls at the press.
##
## `use_same_curve` is applied here rather than at read time, so a dab never asks
## which curve it should be using. **It is applied to a working copy**, rather
## than to the stored sensor as `sensor.curve = common_curve`, because
## `SaSensor.curve` is an `@export` that reaches a preset's `.tres`: one press
## with Share one curve on would write the shared curve over every curve a
## painter had drawn for a sensor, and the next save would put the loss on disk. There is no undo in
## that window and the two curves are then indistinguishable, so nothing can tell
## the damage from a curve somebody meant.
##
## The other way out would be to leave the stored sensors alone and pick the
## curve at read time, which means the sensor asking its option which curve it
## should be using: a back reference this file does not have and
## `SaSensor.parameter` has no argument for. A working copy per active sensor per
## press is the same answer with the branch on this side of the seam, and it
## costs one allocation at the press rather than one per dab.
func begin_stroke() -> void:
    ensure_one_active()
    _prepared = active_sensors()
    if use_same_curve:
        _prepared = _sharing_the_common_curve(_prepared)
    _prepared_kinds.resize(_prepared.size())
    for index in _prepared.size():
        _prepared_kinds[index] = _prepared[index].kind()
    _lone_plain = null
    _lone_absolute = null
    if _prepared.size() == 1 and _prepared_kinds[0] == SaSensor.Kind.PLAIN:
        _lone_plain = _prepared[0]
    if _prepared.size() == 1 and _prepared_kinds[0] == SaSensor.Kind.ABSOLUTE:
        _lone_absolute = _prepared[0]
    _prepared_ready = true


## Working copies of *stored*, each carrying `common_curve` in place of its own.
##
## `duplicate()` copies the exported fields and leaves the lookup caches behind,
## so a copy builds its own table off the curve it was handed. The originals are
## untouched, so what a painter drew for a sensor is still there when Share one
## curve goes off again, and a preset saved mid-stroke carries it.
func _sharing_the_common_curve(stored: Array[SaSensor]) -> Array[SaSensor]:
    var shared: Array[SaSensor] = []
    for sensor in stored:
        var working: SaSensor = sensor.duplicate()
        working.curve = common_curve.duplicate()
        shared.append(working)
    return shared


## The three buckets, filled from every prepared sensor, into the members
## below [member _read_constant].
##
## **Three and not one list, because a reading means three different things
## depending on the sensor it came from.** A plain reading is a factor and joins
## the others under `combine`. An additive one is a signed amount and is summed,
## because two nudges in the same direction should add rather than shrink each
## other the way two factors under a half would. An absolute angle is neither: it
## is a direction, so the last one read wins outright rather than combining with
## anything. Getting a sensor's kind wrong is therefore not a wrong number, it is
## a number in the wrong bucket.
##
## **Members and running totals rather than a parts object and a list**,
## because this is read ten times a point of a noise stroke, and the object and
## the list each reading made were a third of what a reading cost. Every one of
## the five reductions is kept as it goes, in the order the sensors are read,
## so each answers what reducing the list answered, to the bit: a product from
## one, a sum from nought, and the largest and smallest, whose difference is
## the fifth. The sensors are read in the prepared order as before, which keeps
## a per dab roll drawing the numbers it drew.
##
## *use_strength* drops the option's constant, for a caller that is going to
## apply the setting itself somewhere else and would otherwise apply it twice.
## **Nothing in Sara passes false today**, and that is not an oversight: the
## case it exists for is painting through a temporary layer that takes the
## preset's opacity once at the merge, and Sara composites a stroke straight
## onto its layer. The flag stays because the seam is real and the day Sara
## grows that layer it is where the answer goes, and because a reader who meets
## it should be told it is unused rather than left to grep.
func _read(info: SaStrokeInfo, use_strength: bool) -> void:
    _read_constant = strength if use_strength else 1.0
    _read_scaling = 1.0
    _read_additive = 0.0
    _read_offset = 0.0
    _read_has_scaling = false
    _read_has_additive = false
    _read_has_offset = false
    if not use_curve:
        return
    if not _prepared_ready:
        begin_stroke()
    var product := 1.0
    var sum := 0.0
    var largest := -INF
    var smallest := INF
    var plain := 0
    for index in _prepared.size():
        var reading := _prepared[index].parameter(info)
        var kind := _prepared_kinds[index]
        if kind == SaSensor.Kind.ADDITIVE:
            _read_additive += reading
            _read_has_additive = true
        elif kind == SaSensor.Kind.ABSOLUTE:
            _read_offset = reading
            _read_has_offset = true
        else:
            plain += 1
            product *= reading
            sum += reading
            largest = maxf(largest, reading)
            smallest = minf(smallest, reading)
    if plain == 0:
        return
    _read_has_scaling = true
    if plain == 1:
        # One sensor bypasses the switch. Every one of the five reductions
        # answers the value itself when there is only one of them, so the
        # branch would be five ways of writing the same line.
        _read_scaling = product
        return
    match combine:
        Combine.ADD:
            _read_scaling = sum
        Combine.MAXIMUM:
            _read_scaling = largest
        Combine.MINIMUM:
            _read_scaling = smallest
        Combine.DIFFERENCE:
            _read_scaling = largest - smallest
        _:
            _read_scaling = product


## A multiplicative factor bounded to the option's range: what size, opacity,
## flow, ratio, softness and rate all want, because each of them is a quantity
## that is scaled and has a floor and a ceiling it must not leave.
##
## Every absent part is 1.0 rather than 0.0, which is the whole reason this
## reducer reads as a chain of multiplications: an option with no additive sensor
## multiplies by one rather than collapsing to nothing.
func size_like(info: SaStrokeInfo, use_strength: bool = true) -> float:
    if _lone_plain != null and use_curve and _prepared_ready:
        # The product below with the offset and the nudge at one, which is
        # this product to the bit.
        return clampf((strength if use_strength else 1.0) * _lone_plain.parameter(info), strength_min, strength_max)
    if not use_curve or (_prepared_ready and _prepared.is_empty()):
        # No sensor read, so the product is the constant alone, times ones.
        return clampf(strength if use_strength else 1.0, strength_min, strength_max)
    _read(info, use_strength)
    var offset: float = _read_offset if _read_has_offset else 1.0
    var additive: float = SaSensor.additive_to_scaling(_read_additive) if _read_has_additive else 1.0
    return clampf(_read_constant * offset * _read_scaling * additive, strength_min, strength_max)


## A value in half-turns, wrapped over -1 to 1 rather than clamped, because an
## angle has no ends: half a turn past one limit is half a turn before the other,
## and clamping would stick a tip at its limit where turning it round is what a
## painter drew.
##
## *base_angle* is the canvas rotation normalised to 0 to 1, so a tip keeps its
## angle to the paper when the painter turns the canvas under it. *flipped* is
## true when the image coordinates are mirrored on exactly one axis, which
## reverses the sense of an absolute direction and not of a relative nudge, so it
## is applied to the offset alone. `coeff` is the caller's sign, -1 where a
## positive sensor should turn the tip anticlockwise, and *disable_scaling*
## drops the relative part while hovering, where there is no stroke for it to be
## relative to.
func rotation_like(
    info: SaStrokeInfo,
    base_angle: float,
    flipped: bool,
    coeff: float = 1.0,
    disable_scaling: bool = false,
    use_strength: bool = true
) -> float:
    if _lone_absolute != null and use_curve and _prepared_ready:
        # The sum below with no factor and no nudge read, written out the same
        # way so it rounds the same way.
        var reading := _lone_absolute.parameter(info)
        var turned := 0.5 - reading if flipped else reading
        return wrap_signed(2.0 * turned + (strength if use_strength else 1.0) * (coeff * 0.0 + 0.0))
    _read(info, use_strength)
    var offset := base_angle
    if _read_has_offset:
        offset = 0.5 - _read_offset if flipped else _read_offset
    var scaling := 0.0
    if _read_has_scaling and not disable_scaling:
        scaling = SaSensor.scaling_to_additive(_read_scaling)
    return wrap_signed(2.0 * offset + _read_constant * (coeff * scaling + _read_additive))


## A value in half-turns brought back into one full turn, keeping the sign: -1
## and 1 are the same direction and the range stays centred on zero, so a small
## angle either side of straight ahead stays a small number.
static func wrap_signed(value: float) -> float:
    var span := 2.0
    var shifted := fmod(value + 1.0, span)
    if shifted < 0.0:
        shifted += span
    return shifted - 1.0


## What the option answers and what it is made of, for a state dump. Both
## reducers, because a regression in one of them is invisible in the other.
func report(info: SaStrokeInfo, base_angle: float = 0.0) -> Dictionary[String, Variant]:
    var names: Array[String] = []
    for sensor in active_sensors():
        names.append(SaSensor.key_of(sensor.id))
    return {
        "enabled": enabled,
        "use_curve": use_curve,
        "use_same_curve": use_same_curve,
        "combine": int(combine),
        "strength": strength,
        "bounds": [strength_min, strength_max],
        "active": names,
        "size_like": snappedf(size_like(info), 0.000001),
        "rotation_like": snappedf(rotation_like(info, base_angle, false), 0.000001),
    }
