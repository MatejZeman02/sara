## One sample in, one dab out: every curve option read in the order the dab
## pipeline needs them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own. Every mechanism here is written below from what it does, so
## this file ports no code and carries no copyright line but its own.
##
## **The order is load-bearing and it is derived, not chosen.** Size first,
## because everything under it is either a scaling of the dab or a length
## measured against it. Rotation and ratio next, because between them they finish
## describing the shape. Scatter fourth, because how far a dab may wander is a
## fraction of the dab, so it cannot be read until the three above have said how
## big that dab is. Opacity, flow, softness and spacing last, because none of
## them needs anything but the sample, and the texture's strength and the mirror
## for the same reason. Reordering this list is not a refactor, it changes where
## paint lands.
##
## **A disabled option is skipped, not evaluated.** Its neutral value is 1 for a
## size-like parameter, 0 for rotation and no offset for scatter, and that is not
## the same as what the option would answer if it were read. `rotation_like` of a
## switched-off option still folds in the canvas rotation through its base angle,
## so evaluating it would turn every brush on a rotated canvas.
##
## **What this half never touches.** A texture, a compute list, or the document's
## colour space. `SaDabParams.color` is filled by the caller, because converting
## a picked colour into the document's encoding is the dab pipeline's job, and
## [SaDabParams] is the seam that keeps the two halves apart.
class_name SaDynamics
extends RefCounted

## Where the mirror option's value stops meaning "as the tip is" and starts
## meaning "turned over".
##
## Krita's own number, `kis_pressure_mirror_option.cpp` reading
## `sensorResult < 0.5`, and it is a threshold rather than an angle because a
## mirror has two states and no in-between: half a flip is not a shape. Half way
## up the option's range, so a fuzzy sensor flips about as often as it does not
## and a pressure sensor flips where the painter presses past the middle.
const MIRROR_THRESHOLD: float = 0.5

## The options read through `_offset_like`, a signed shift whose neutral is a
## reading of a half rather than one. Named here, beside the reducer that makes
## them so, for a control that has to know which way round a curve means "no
## effect" before it can draw one, which is what the lift-up binding asks.
const OFFSET_OPTIONS: Array[StringName] = [&"saturation_option", &"value_option"]

## The options [method evaluate] reads, which index the readings [method _settle]
## settles. Each is the field of its name in lower case with `_option` after it.
enum Reads {
    SIZE,
    ROTATION,
    RATIO,
    SCATTER,
    OPACITY,
    FLOW,
    SOFTNESS,
    HARDNESS,
    SPACING,
    TEXTURE,
    SHARPNESS,
    HUE,
    SATURATION,
    VALUE,
    DARKEN,
    MIX,
    MIRROR,
    SMUDGE_PICKUP,
    SMUDGE_COLOR_RATE,
    SMUDGE_LENGTH,
}
static var _read_fields: Array[StringName] = _fields_of_reads()

## The plain fields beside the options, in the order [method _settle] reads
## them. A row an option modulates rather than replaces is read here, because
## the dab is filled here and the other half never sees the sensors that decide
## how much of the row to take.
const _ROWS: Array[StringName] = [&"sharpness", &"scatter_axis_x", &"scatter_axis_y", &"mirror_axis_x", &"mirror_axis_y"]

## The readings [method _settle] settles in groups, kept as lists once rather
## than written as a literal it builds again at every settle.
const _TURNING: Array[Reads] = [Reads.ROTATION, Reads.HUE, Reads.SATURATION, Reads.VALUE, Reads.DARKEN, Reads.MIX]
const _SHAPE: Array[Reads] = [
    Reads.SIZE,
    Reads.RATIO,
    Reads.OPACITY,
    Reads.FLOW,
    Reads.SOFTNESS,
    Reads.HARDNESS,
    Reads.SPACING,
    Reads.TEXTURE,
    Reads.SHARPNESS,
    Reads.SMUDGE_PICKUP,
]

## The settings the options are read from. Any resource carrying the
## `SaCurveOption` fields, which is the stamp brush's settings today.
var settings: Resource = null

## The options [method hold] looked up, by field, while a walk is painting.
## Empty and unread outside one.
var _held_options: Dictionary[StringName, SaCurveOption] = {}
var _holding: bool = false

## What [method _settle] found out of each [enum Reads], once a hold or a dab.
var _settled: bool = false
## The option when it is switched on, or null.
var _enabled: Array[SaCurveOption] = []
## The option when [method _modulates] says it has something to say, or null.
var _modulating: Array[SaCurveOption] = []
## The option read at every dab, or null when its reading is [member _fixed].
var _live: Array[SaCurveOption] = []
## The reading of an option that is off, the 1, or of one that reads no sensor.
var _fixed := PackedFloat64Array()
## The one sensor a live option reads when that is a plain factor, or null.
var _single: Array[SaSensor] = []
## The pressure a [member _single] pressure sensor last answered, and its reading.
var _pressed_at := PackedFloat64Array()
var _pressed_to := PackedFloat64Array()
## Whether any of the five colour options modulates.
var _shifts_colour: bool = false
## The settings' own rows the readings are taken with.
var _sharpness_row: float = 0.0
var _scatter_x: bool = true
var _scatter_y: bool = true
var _mirror_x: bool = true
var _mirror_y: bool = false

## What [method _learn_fields] learnt, and of which settings and script.
var _carried := PackedByteArray()
var _carried_by: Object = null
var _carried_script: Variant = null


func _init(from_settings: Resource = null) -> void:
    settings = from_settings


## Whether *option* has anything to say, which for a rotation is the difference
## between no turn and a half turn.
##
## Switched on is not enough. `rotation_like` answers `wrap_signed(2 * base_angle
## + constant * (coeff * scaling + additive))`, and the expression that reads it
## is `(1 + value) * PI`, so the value that means *no turn* is 1 or -1 and the
## value an option with nothing to modulate with answers is 0. That is a half
## turn: Rotation switched on with no sensor ticked would stamp every image tip
## upside down.
##
## Two states answer nothing: no active sensor, which `ensure_one_active` leaves
## alone on purpose because an untouched option must not be given a pressure
## sensor it never had, and the curve switched off, where `_read`
## never reads a sensor at all. In both the option is a constant, and **a
## constant rotation is no rotation**, which the header above already gives for
## a switched-off option: the
## neutral value is 0 for rotation, and folding the base angle in on its own
## would turn every brush on a rotated canvas.
##
## Written here rather than as a method on `SaCurveOption`, because it is a fact
## about how *this* file reads an option rather than about the option, and
## because the two fields it asks for are public.
func _modulates(option: SaCurveOption) -> bool:
    if option == null or not option.enabled or not option.use_curve:
        return false
    # The sensors the option prepared are the ones it has ticked, so once it has
    # prepared them they answer without the sort `active_sensors` makes. They
    # are read rather than prepared here, since preparing ticks one for an
    # option with none, which an option that is only being asked must not be.
    if option._prepared_ready:
        return not option._prepared.is_empty()
    return not option.active_sensors().is_empty()


## Prepares every option that is going to be read, once per press.
##
## Only the options that are both enabled and reading their sensors. That is not
## an optimisation: `SaCurveOption.begin_stroke()` calls `ensure_one_active()`,
## which puts a pressure sensor into an option that has none, so preparing an
## option nobody switched on would give it a sensor, and saving the preset
## afterwards would write that sensor into the file. An untouched option has to
## stay untouched.
func begin_stroke() -> void:
    _settled = false
    for option: SaCurveOption in _live_options():
        option.begin_stroke()


## One sample into one dab.
##
## *base_diameter* is the tip's diameter in document pixels before any
## modulation, *base_angle* is the canvas rotation normalised to 0 to 1 and
## *flipped* is true when the image is mirrored on exactly one axis. The last two
## are read from the view, because a tip that keeps its angle to the paper has to
## be told how the paper is lying.
func evaluate(info: SaStrokeInfo, base_diameter: float, base_angle: float = 0.0, flipped: bool = false) -> SaDabParams:
    if not _holding or not _settled:
        _settle(info)
    var dab := SaDabParams.new()
    # Every reading below asks first whether its option is live, and takes the
    # number the settle fixed when it is not, in place of a call to
    # `_scaled` that answers the same. A stamp's dab has ten fixed readings
    # and two live ones, and the calls for the ten were a microsecond of it.
    dab.position = info.position

    # 1. Size, which everything below either scales or is measured against.
    dab.size = base_diameter * (_fixed[Reads.SIZE] if _live[Reads.SIZE] == null else _scaled(Reads.SIZE, info))

    # 2. Rotation. Two conversions live here rather than in `rotation_like`,
    # which is the reducer and is shared with anything else rotation-like. The
    # coefficient is -1 so that a sensor reading higher turns the tip
    # anticlockwise, which is the direction a painter reads as "more". The
    # `1 + value` turns the reducer's half-turns, centred on zero, into the
    # angle a tip is drawn at, which is measured from the other end: one and
    # minus one both mean no turn there, and zero means half a turn.
    #
    # Krita's own is `1 - value`, a turn anticlockwise on the screen, and the
    # dab kernel draws a positive angle clockwise, from x towards y, which runs
    # down. Read as Krita wrote it, every tip turned the mirror way: a drawing
    # angle's tip stood across the stroke only at nought and a quarter turn,
    # and lay along it at 45 degrees. Negating it here puts
    # every sensor into the kernel's frame at once, the drawing angle's heading
    # and the "more" above alike, and leaves the tip's own angle as it was.
    var rotation_option := _modulating[Reads.ROTATION]
    if rotation_option != null:
        dab.rotation = (1.0 + rotation_option.rotation_like(info, base_angle, flipped, -1.0)) * PI

    # 3. Ratio, the tip's minor over major axis.
    dab.ratio = _fixed[Reads.RATIO] if _live[Reads.RATIO] == null else _scaled(Reads.RATIO, info)

    # 4. Scatter, whose amplitude is the dab the three above just described.
    dab.scatter = _scatter(info, dab) if _enabled[Reads.SCATTER] != null else Vector2.ZERO

    # 5. The five that need nothing but the sample. Hardness sits beside
    # softness because they are read the same way and not because they mean the
    # same thing: softness scales the tip's fade and hardness scales the brush's
    # Hardness row, which is the number the fade pair is built from.
    dab.opacity = _fixed[Reads.OPACITY] if _live[Reads.OPACITY] == null else _scaled(Reads.OPACITY, info)
    dab.flow = _fixed[Reads.FLOW] if _live[Reads.FLOW] == null else _scaled(Reads.FLOW, info)
    dab.softness = _fixed[Reads.SOFTNESS] if _live[Reads.SOFTNESS] == null else _scaled(Reads.SOFTNESS, info)
    dab.hardness = _fixed[Reads.HARDNESS] if _live[Reads.HARDNESS] == null else _scaled(Reads.HARDNESS, info)
    dab.spacing = _fixed[Reads.SPACING] if _live[Reads.SPACING] == null else _scaled(Reads.SPACING, info)

    # 6. The texture's strength, which needs nothing but the sample either. Not
    # read when it is off, unlike the size, because the neutral 1 is not what an
    # option that is off means here: no pattern, a strength of nought.
    if _enabled[Reads.TEXTURE] != null:
        dab.pattern_strength = _fixed[Reads.TEXTURE] if _live[Reads.TEXTURE] == null else _scaled(Reads.TEXTURE, info)

    # 7. Sharpness, which needs nothing but the sample either.
    # Read when it is off, unlike the texture above, because the settings row
    # is the value and the option is how much of it this dab gets: the neutral
    # 1 a switched-off option answers therefore sends the row through untouched,
    # which is what a preset that never ticked the option has to keep painting. Nothing above it is measured against it.
    var sharp := _fixed[Reads.SHARPNESS] if _live[Reads.SHARPNESS] == null else _scaled(Reads.SHARPNESS, info)
    dab.sharpness = clampf(_sharpness_row * sharp, 0.0, 1.0)

    # 8. The three colour offsets, which need nothing but the sample either and
    # sit below the shape because nothing above them reads a colour.
    # Hue goes through the rotation-like reducer because a hue is an angle and
    # wraps: a shift past the far side of the circle comes back round rather
    # than sticking there, which is the same argument `rotation_like` is written
    # under. The base angle is nought and the flip is false, because the canvas
    # being turned or mirrored under the painter does not move a colour. A walk
    # none of the five modulates leaves the dab's noughts as they are.
    if _shifts_colour:
        var hue_option := _modulating[Reads.HUE]
        if hue_option != null:
            dab.hue_shift = hue_option.rotation_like(info, 0.0, false)
        dab.saturation_shift = _offset_like(_modulating[Reads.SATURATION], info)
        dab.value_shift = _offset_like(_modulating[Reads.VALUE], info)
        # Darken and Mix go through a third reducer, because they are amounts
        # rather than offsets: there is no negative darkening and no negative
        # mix, so the reading stays on 0 to 1 instead of being moved onto -1 to 1.
        dab.darken = _amount_like(_modulating[Reads.DARKEN], info)
        dab.mix = _amount_like(_modulating[Reads.MIX], info)

    # 9. The mirror, which needs nothing but the sample either and so could
    # stand anywhere below the shape. Last because it is the only one whose
    # neutral value is not a number the dab can be painted with: minus one is
    # the option off, and the consumer reads that as the tip's own two booleans.
    dab.mirror = _mirror(info) if _enabled[Reads.MIRROR] != null else -1

    # 10. The smudge stage, which needs nothing but the sample either. The
    # pickup option's own `enabled` is the switch, rather than the neutral one
    # of an option that is off, which would turn the stage on for every brush.
    # Length takes that one, so a switched-off length never fades the carry.
    # The colour rate is the one option of the stage whose off is nought, as
    # Krita's unticked Color Rate is, so Pickup ticked alone lays the carry in
    # full and none of the brush's colour: a pure smudge.
    dab.smudge = _enabled[Reads.SMUDGE_PICKUP] != null
    if dab.smudge:
        var pickup := _fixed[Reads.SMUDGE_PICKUP] if _live[Reads.SMUDGE_PICKUP] == null else _scaled(Reads.SMUDGE_PICKUP, info)
        dab.smudge_pickup = clampf(pickup, 0.0, 1.0)
        if _enabled[Reads.SMUDGE_COLOR_RATE] != null:
            var rate := (
                _fixed[Reads.SMUDGE_COLOR_RATE]
                if _live[Reads.SMUDGE_COLOR_RATE] == null
                else _scaled(Reads.SMUDGE_COLOR_RATE, info)
            )
            dab.smudge_color_rate = clampf(rate, 0.0, 1.0)
        else:
            dab.smudge_color_rate = 0.0
        var length := _fixed[Reads.SMUDGE_LENGTH] if _live[Reads.SMUDGE_LENGTH] == null else _scaled(Reads.SMUDGE_LENGTH, info)
        dab.smudge_length = clampf(length, 0.0, 1.0)

    return dab


## The airbrush interval in milliseconds, which the rate option can only
## lengthen.
##
## A rate is dabs per second, so the gap between two of them is a second divided
## by the rate, and the option scales the rate rather than the gap: a painter who
## drew a curve that halves the rate expects half as many dabs, not dabs half as
## far apart in some other sense.
##
## Here rather than in `SaDabParams` because it is a property of the stroke's
## timing rather than of one dab.
func airbrush_interval(info: SaStrokeInfo, rate: float) -> float:
    var value := _size_like(_option("rate_option"), info)
    if rate <= 0.0 or value <= 0.0:
        return 0.0
    return 1000.0 / (rate * value)


## Where this dab lands relative to where the stroke put it.
##
## The draw is uniform rather than normal, so a painter setting scatter to a
## given amount gets dabs anywhere inside that amount and none outside it. A bell
## would concentrate them near the middle and let a few out past the edge, which
## reads as a setting that does less than it says and occasionally more.
##
## With both axes on it draws twice and offsets on image X and image Y
## independently, which fills a disc. With one on it draws once and offsets along
## the drawing direction or along its left normal, which is what makes a one-axis
## scatter read as a stroke that wanders rather than a cloud.
func _scatter(info: SaStrokeInfo, dab: SaDabParams) -> Vector2:
    if _enabled[Reads.SCATTER] == null or not (_scatter_x or _scatter_y):
        return Vector2.ZERO

    # The dab it is scattering, which is why this is read fourth. Height is the
    # minor axis, so the larger of the two is the major one whenever ratio is at
    # most 1, and taking the maximum rather than the width keeps that true for a
    # ratio above 1, where the roles swap.
    var amplitude := maxf(dab.size, dab.size * dab.ratio) * _scaled(Reads.SCATTER, info)
    if is_zero_approx(amplitude):
        return Vector2.ZERO

    if _scatter_x and _scatter_y:
        return Vector2(_signed(info) * amplitude, _signed(info) * amplitude)
    var along := Vector2.from_angle(info.drawing_angle(false))
    if not _scatter_x:
        # The left normal of the drawing direction, which is the other axis of
        # the same one-dimensional scatter.
        along = Vector2(-along.y, along.x)
    return along * _signed(info) * amplitude


## Which axes this dab is turned over on, as the bits to flip, or minus one when
## the option has nothing to say.
##
## **The bits are a flip and not a state**, which is Krita's arithmetic: it adds
## the option's answer to the canvas mirror and takes the parity, so the option
## turns an axis over rather than deciding it. Sara's resting state is the tip's
## own two booleans, so a flip of bit 0 un-mirrors a tip already mirrored
## horizontally, and the two never disagree about which of them is in charge.
##
## `mirror_axis_x` and `mirror_axis_y` are which axes the option is allowed to
## touch, Krita's two Mirror checkboxes, and they sit beside the option on the
## settings for the same reason `scatter_axis_x` does: they change what the one
## number means rather than what it is, and `SaCurveOption` is a set of sensors
## and a curve with no room for a pair of axes. Neither on is the option
## switched off by another name, so it answers minus one rather than a flip of
## nothing, and the tip keeps its own mirror.
##
## Read through `size_like`, so an option that is on with no sensor answers its
## `strength` of 1 and never flips: a constant mirror is no mirror, which is the
## same rule as for a constant rotation.
func _mirror(info: SaStrokeInfo) -> int:
    if _enabled[Reads.MIRROR] == null or not (_mirror_x or _mirror_y):
        return -1
    if _scaled(Reads.MIRROR, info) >= MIRROR_THRESHOLD:
        return 0
    return (1 if _mirror_x else 0) | (2 if _mirror_y else 0)


## One uniform draw in -1 to 1 from the per-dab stream.
func _signed(info: SaStrokeInfo) -> float:
    return 2.0 * info.random.randf() - 1.0


## *option*'s reading as a signed offset, or the nought a colour nobody
## modulated wants.
##
## **Not `_size_like`, and the neutral value is why.** A scaled parameter wants
## 1 when nothing modulates it and a colour offset wants 0, and the two are not
## the same number written twice: an offset of one is the whole of the shift.
##
## The reading itself is `size_like` without the strength, which is the option's
## sensors and curve reduced onto 0 to 1, moved onto the -1 to 1 the curve is
## drawn against by the same conversion `rotation_like` uses inside itself, and
## then scaled by the strength. **The strength is applied after the move and not
## before**, because before it a painter turning the strength down would drag
## the shift towards the bottom of its range rather than towards no shift at
## all: half strength has to mean half as much colour moved, in whichever
## direction the sensor is asking for.
##
## *option* is null unless `_modulates` says it has something to say, the
## rule made for rotation. An option with no active sensor is a constant, and
## a constant here is a brush that paints one shifted colour for the whole
## stroke, which is not what a painter ticking a box with no sensor under it drew.
func _offset_like(option: SaCurveOption, info: SaStrokeInfo) -> float:
    if option == null:
        return 0.0
    return clampf(option.strength * SaSensor.scaling_to_additive(option.size_like(info, false)), -1.0, 1.0)


## *option*'s reading as an amount on 0 to 1, or the nought an option that is not
## modulating means.
##
## The third of the three reducers over a curve option, and the plainest: the
## reading without its strength, times the strength. `_size_like` above answers a
## multiplier whose neutral is one and `_offset_like` a signed offset whose
## neutral is nought, and this answers a quantity whose neutral is nought and
## which has no far side of nought to reach for.
##
## The strength is applied after the reading rather than inside it for the reason
## `_offset_like` gives: `size_like` clamps its product to the option's own band,
## so a strength folded in before the clamp makes half strength mean a different
## curve rather than half as much of the same one.
##
## *option* is null unless `_modulates` says it has something to say, the
## rule made for rotation: a constant here is a stroke painted one shade
## darker or one step towards the background from end to end.
func _amount_like(option: SaCurveOption, info: SaStrokeInfo) -> float:
    if option == null:
        return 0.0
    return clampf(option.strength * option.size_like(info, false), 0.0, 1.0)


## Whether the option at *field* is read as a signed shift, see
## [constant OFFSET_OPTIONS].
static func is_offset(field: StringName) -> bool:
    return OFFSET_OPTIONS.has(field)


## *option*'s size-like value, or the 1 a parameter nobody modulated wants.
func _size_like(option: SaCurveOption, info: SaStrokeInfo) -> float:
    if option == null or not option.enabled:
        return 1.0
    return option.size_like(info)


## The value of the option at *read* the way [method _size_like] reads it,
## from what [method _settle] settled.
func _scaled(read: Reads, info: SaStrokeInfo) -> float:
    var option := _live[read]
    if option == null:
        return _fixed[read]
    var sensor := _single[read]
    if sensor == null:
        return option.size_like(info)
    if info.pressure == _pressed_at[read]:
        return _pressed_to[read]
    # `size_like`'s product with the absolute offset and the additive part at
    # the one they are when no sensor gives them, so the same number to the bit.
    var scaled := clampf(option.strength * sensor.parameter(info), option.strength_min, option.strength_max)
    if sensor.id == SaSensor.Id.PRESSURE:
        _pressed_at[read] = info.pressure
        _pressed_to[read] = scaled
    return scaled


## Settles what [method evaluate] reads, for this dab and, held, every dab to
## [method release]. A reading of no sensor is taken once. Only an option read
## whenever it is on is prepared, as one it skips would gain a sensor, see `begin_stroke`.
func _settle(info: SaStrokeInfo) -> void:
    _settled = true
    var count := Reads.size()
    if _fixed.size() != count:
        for list: Array in [_enabled, _modulating, _live, _single]:
            list.resize(count)
        _fixed.resize(count)
        _pressed_at.resize(count)
        _pressed_to.resize(count)
    _fixed.fill(1.0)
    _pressed_at.fill(NAN)
    _modulating.fill(null)
    _single.fill(null)
    # The settings asked here directly rather than through `_option`'s held
    # table, which the settle would only fill for nobody, and only for the
    # fields they carry. One list is written per option and the other copied
    # whole after it, since a settle runs at every frame of a noise stroke and
    # its twenty options were most of what it cost.
    var held: Resource = settings
    _learn_fields()
    for read in count:
        var option: SaCurveOption = null
        if _carried[read] != 0:
            var found: Variant = held.get(_read_fields[read])
            option = found if found is SaCurveOption else null
        _enabled[read] = option if option != null and option.enabled else null
    _live.assign(_enabled)
    _shifts_colour = false
    for read: Reads in _TURNING:
        var turning: SaCurveOption = _enabled[read]
        if turning != null and not _modulates(turning):
            turning = null
        _modulating[read] = turning
        _shifts_colour = _shifts_colour or (read != Reads.ROTATION and turning != null)
    var row := count
    _sharpness_row = SaTyped.real(held.get(&"sharpness")) if _carried[row] != 0 else 0.0
    _scatter_x = SaTyped.flag(held.get(&"scatter_axis_x"), true) if _carried[row + 1] != 0 else true
    _scatter_y = SaTyped.flag(held.get(&"scatter_axis_y"), true) if _carried[row + 2] != 0 else true
    _mirror_x = SaTyped.flag(held.get(&"mirror_axis_x"), true) if _carried[row + 3] != 0 else true
    _mirror_y = SaTyped.flag(held.get(&"mirror_axis_y")) if _carried[row + 4] != 0 else false
    for read: Reads in _SHAPE:
        _fix(read, info)
    if _scatter_x or _scatter_y:
        _fix(Reads.SCATTER, info)
    if _mirror_x or _mirror_y:
        _fix(Reads.MIRROR, info)
    if _enabled[Reads.SMUDGE_PICKUP] != null:
        _fix(Reads.SMUDGE_COLOR_RATE, info)
        _fix(Reads.SMUDGE_LENGTH, info)


## Which of the fields [method _settle] reads the settings carry, the twenty
## options in the order of [enum Reads] and then [constant _ROWS], learnt once
## for each settings object and script. Asking a field the settings do not
## carry is not free: a settings class that answers made up names through its
## own `_get` runs it for every one, and the noise brush's carries none of
## twelve of the twenty, so a settle spent half of itself on a dozen nulls.
## A class's fields are its declarations, which do not come and go.
func _learn_fields() -> void:
    var script: Variant = settings.get_script() if settings != null else null
    if _carried.size() > 0 and _carried_by == settings and _carried_script == script:
        return
    _carried_by = settings
    _carried_script = script
    _carried.resize(_read_fields.size() + _ROWS.size())
    _carried.fill(0)
    if settings == null:
        return
    for index in _read_fields.size():
        _carried[index] = 1 if _read_fields[index] in settings else 0
    for index in _ROWS.size():
        _carried[_read_fields.size() + index] = 1 if _ROWS[index] in settings else 0


## Settles the reading at *read* when its option is on and reads no sensor, or
## keeps the one sensor it reads when that is all, see [method _settle].
func _fix(read: Reads, info: SaStrokeInfo) -> void:
    var option := _enabled[read]
    if option == null:
        return
    if option.use_curve and not option._prepared_ready:
        option.begin_stroke()
    if not option.use_curve or option._prepared.is_empty():
        _fixed[read] = option.size_like(info)
        _live[read] = null
    else:
        # The option's one sensor when it reads one plain sensor, which is the
        # case the shortcut is for, and null for any other.
        _single[read] = option._lone_plain


func _option(field: StringName) -> SaCurveOption:
    if _holding and _held_options.has(field):
        return _held_options[field]
    var held: Variant = settings.get(field) if settings != null else null
    var option: SaCurveOption = held if held is SaCurveOption else null
    if _holding:
        _held_options[field] = option
    return option


## Keeps each option [method evaluate] looks up until [method release], and
## what [method _settle] found out at the first dab, so the dabs after it ask
## the settings by name once rather than twenty times a dab. The holder says how
## long: a walk or a frame, never past a change a painter can make between two.
func hold() -> void:
    _held_options.clear()
    _holding = true
    _settled = false


## Forgets what [method hold] kept, so the next dab reads the settings afresh.
func release() -> void:
    _held_options.clear()
    _holding = false
    _settled = false


## Every option a stroke is going to read, which is what `begin_stroke` prepares.
func _live_options() -> Array[SaCurveOption]:
    var live: Array[SaCurveOption] = []
    if settings == null or not settings.has_method("options"):
        return live
    # The settings are a module's resource, which core cannot name, so the
    # table is asked for by name and typed where it lands.
    var options: Dictionary = settings.call("options")
    for key: String in options:
        var option: SaCurveOption = options[key]
        if option != null and option.enabled and option.use_curve:
            live.append(option)
    return live


## Each of [enum Reads] as the name of its field, the name in lower case with
## `_option` after it, made once for the class.
static func _fields_of_reads() -> Array[StringName]:
    var fields: Array[StringName] = []
    for key: String in Reads.keys():
        fields.append(StringName(key.to_lower() + "_option"))
    return fields
