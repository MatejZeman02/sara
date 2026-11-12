## The noise brush while a stroke is being made: the pen's samples swept into
## one continuous stroke, a stretch of it an update, washed into the stroke
## buffer by the module's own kernel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Every piece of the pipeline is the door's.** The curve between samples is
## `SaStrokeCurve`, the sample the sensors read is `SaStrokeInfo`, one point of
## the path into what the tip and the colour are there is `SaDynamics`, a
## point's box is `SaDabGeometry`, the chunks a stretch reaches are
## `SaPaintContext` and the tip's GPU half is `SaBrushTipMask`. What is left
## here is the order they are called in and the kernel they feed, which is
## what makes this an engine rather than a copy of the stamp's. What one point
## is in the kernel's slots is `noise_point.gd`'s.
##
## **One swept stroke, no dab in it.** Each update hands the kernel the
## stretch of path the curve answered, its chord points with what the dynamics
## answer at each, in `NoiseStretch`'s buffer, and the kernel runs once over
## the stretch's own rectangle. A texel takes the tip at its nearest point of
## the path, so the stroke is the tip dragged rather than the tip repeated.
##
## **The pressure is the cut, and the field is read along the stroke** (designs
## 2 and 3 of the rework). Each point carries the pen's pressure, the
## travelled length less the drift, and Strength's shift, and a texel paints
## where the pressure at its nearest point reaches the field read at its stroke
## coordinates there plus the shift. The texture sensor reads the same field on
## the CPU down the middle of the path.
##
## **Always a wash, always into the stroke buffer.** The alpha of a texel is
## the strongest the stroke laid there, so a texel two stretches reach is not
## painted twice, and the stroke lands on the layer once at its opacity.
## Erasing and alpha lock are the buffer's composite mode, chosen at the press,
## so the kernel has one rule.
##
## **The height goes to the layer, not the buffer**. A stroke with a
## Thickness keeps an `SaStrokeHeights` for the active layer, which gains the
## layer its height and hands the kernel each chunk's height and the surface
## beneath it. An erasing stroke lays none, since the document lowers the
## height under a wash eraser as each stretch's region lands, and neither does
## a stroke under alpha lock or into a mask, whose paint lands on what is there.
##
## **Tilt and speed press the brush like a real one**. A sample carries
## the pen's tilt in degrees, the unit every sensor divides by, and the time it
## was made, and a point between two samples is fed the time between theirs,
## so the door's speed smoother sees a steady rate. The settings' stretch
## option turns the lean into a longer tip, along the lean for a round tip and
## along its own axes for a picture or any tip with an angle, the Thickness Lean
## row lays more height on the side the pen leans to, and their Thickness and
## Drift options read the elevation and the speed, all of them curves a painter
## unbinds. A tip with an angle is turned by the Rotation option alone, off in
## every fresh preset, so a picture tip lies as drawn whatever the pen does
## until a preset gives that option a sensor.
extends ToolState

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const NoiseFieldReadingScript = preload("res://modules/sara-noise-brush-engine/noise_field_reading.gd")
const NoiseDabListScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd")
const NoiseFieldBindingScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_field_binding.gd")
const NoiseFrameScript = preload("res://modules/sara-noise-brush-engine/noise_frame.gd")
const NoiseWarmScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_warm.gd")
const NoisePressSpeedScript = preload("res://modules/sara-noise-brush-engine/noise_press_speed.gd")
const NoisePointScript = preload("res://modules/sara-noise-brush-engine/noise_point.gd")

## An image tip was loaded and selected, with the path it came from. Emitted
## from [method load_tip] on success only, and the Tip Image list hears it.
signal tip_loaded(path: String)

## The kernel's shader and entry point, one name because the file holds one.
const KERNEL: String = "noise_dab"

## The longest step between two points of a stretch, as a share of the tip's
## diameter at full pressure, and never shorter than [constant MIN_POINT_STEP]
## pixels. The curve's chords are its points, and a chord longer than this is
## cut into equal steps, so what the dynamics answer, the size, the colour and
## the cut, is read along a fast stroke often enough that the line the kernel
## draws between two answers is never a visible corner.
const POINT_STEP: float = 0.25
const MIN_POINT_STEP: float = 1.0
## The most points one chord is cut into, a ceiling on a per-event loop rather
## than a count, so a pen that jumps across the canvas costs a bounded update.
const MAX_POINTS_A_CHORD: int = 64

## How soon after a stroke's release a press that brings no pressure is read as
## the pen bouncing off the paper rather than a tap of its own, in milliseconds.
## A pen lifting off a tablet can touch again within a few
## frames, and under Windows Ink that touch reports no pressure at all.
const BOUNCE_MS: float = 150.0
## How long a pen's press waits for a sample's pressure before it lays its
## point at the pressure it has. Windows Ink sends no motion while a pen rests,
## so a press held still painted nothing until the pen moved or lifted.
const PRESS_WAIT_MS: float = 80.0

## How many plain motions of one stroke, a pressure and a tilt of none, a
## pointer that has reported neither yet may send before it is taken for a
## mouse, the count the stamp and the cursor go by.
const MOUSE_MOTIONS: int = 10

var compute: SaCompute = SaCompute.new(KERNEL)
## What an event's stretch goes to the card in, one compute list an event,
## and the stretch itself, the points the update under way paints.
var dab_list: NoiseDabListScript = NoiseDabListScript.new(KERNEL)
var settings: Resource = NoiseBrushSettingsScript.new()

## The sample every sensor reads, carried across the stroke for the running
## totals it holds.
var stroke_info: SaStrokeInfo = SaStrokeInfo.new()
var dynamics: SaDynamics = SaDynamics.new()
## The tip's softness table and picture, held for as long as they are bound.
var tip_mask: SaBrushTipMask = SaBrushTipMask.new()
var is_drawing: bool = false
## A pen reports pressure or tilt, a mouse neither, and a mouse paints at one.
var is_tablet: bool = false
## Whether a run of plain motions in one stroke has said the pointer is a
## mouse, until a pen's reading says otherwise.
##
## **A pointer that is neither yet waits.** A pen pressed from no pressure
## reports what a mouse does, no pressure and no tilt, until its pressure
## rises. So the first stroke of a door session, which no hover has told the
## brush of, would take the pen for a mouse and lay its press and first motion
## at full width where every later stroke's are laid at a third of it. Its
## press waits as a pen's does, and its plain motions
## wait in [member _waiting_at] until a pen's reading lays them at the no
## pressure they reported, or [constant MOUSE_MOTIONS] of them lay them as a
## mouse's.
var _is_mouse: bool = false
## The plain motions of a stroke whose pointer is not known yet, where and when
## each came, laid by [method _lay_waiting].
var _waiting_at: PackedVector2Array = PackedVector2Array()
var _waiting_times: PackedFloat64Array = PackedFloat64Array()

var _curve: SaStrokeCurve = SaStrokeCurve.new()
## The storage format [method warm] last built for, or -1 before it has.
var _warmed_format: int = -1
var _last_position: Vector2 = Vector2.ZERO
var _last_pressure: float = 1.0
var _last_tilt: Vector2 = Vector2.ZERO
## A pen's press, not painted yet because no sample has reported a pressure.
var _press_held: bool = false
## A pen's press laid once it had waited [constant PRESS_WAIT_MS], at a
## pressure no sample reported, which the first sample still answers.
var _press_waited: bool = false
## The time of the last sample in milliseconds, what a sample that brings none
## is taken to have been made at, and the press's, which every point's time is
## measured from so the time sensor reads the stroke's age. A suite that passes
## no time paints every point at one instant, which reads as a pen at rest.
var _clock: float = 0.0
var _time_origin: float = 0.0
## The times of the samples the curve's window holds, the newest last, three at
## most, which is as far back as a span the curve answers reaches.
var _times: PackedFloat64Array = PackedFloat64Array()
## The pen's twist at the last sample in degrees, and the twists of the samples
## that window holds beside their times. Nought from every event, since Godot
## reports no twist, which `SaSensor`'s Rotation sensor says as well, so only a
## suite or a pen module that reads one passes it to [method add_sample]. It
## turns the tip through the Rotation option's sensor alone.
var _last_twist: float = 0.0
var _twists: PackedFloat64Array = PackedFloat64Array()
## The twist [method _point] feeds the sensors, set just before each call so
## its signature stays the one a recording subclass overrides.
var _point_twist: float = 0.0
## The eraser end of the pen, read off every motion.
var _pen_inverted: bool = false
## The Brush's own eraser, what E and the bar's Erase button switch, under the
## stamp's key so the one button follows whichever engine the Brush paints with.
## Announced from the setter, as the stamp's is, because the bar writes it as a
## plain property and the other surface's bar listens.
var eraser_toggled: bool = false:
    set(val):
        if eraser_toggled == val:
            return
        eraser_toggled = val
        EventBus.brush_eraser_toggled.emit(eraser_toggled)
## Whether the stroke under way reached the document at all. A press on a layer
## whose alpha is locked while erasing opens nothing, because the lock forbids
## the only thing the stroke would do.
var _stroking: bool = false
## Where and when the last stroke let go, with the pen's own pressure its tail
## ended on and the firmest it had pressed as the sensors read it, which a bounce at its end is laid at. The
## time is negative while no stroke has ended.
var _tail_position: Vector2 = Vector2.ZERO
var _tail_time: float = -1.0
var _tail_pressure: float = 0.0
var _tail_peak: float = 0.0

## The fields the Texture row can name, the shipped three unless the module
## handed its own through the settings, and what this brush binds for the one a
## stroke uses. Held for as long as the kernel may read them.
var fields: RefCounted = null
var field_binding: NoiseFieldBindingScript = NoiseFieldBindingScript.new()
## The seed the stroke under way was laid with, which a suite reads to tell two
## strokes' fields apart, and which the along-the-stroke rolls are drawn from.
var field_seed: int = 0
## The stroke's seed in 24 bits, the `stroke_seed` param a store into a half rounds from.
var _rounding_seed: int = 0
## How far the Drift row has carried the field along the stroke so far, in
## document pixels, which every point takes off its travelled length. It grows
## per point from the step since the last one, so a rate that changes along the
## stroke, the speed, adds its own share rather than rewriting what came before.
var field_slide: float = 0.0
var _drift_from: Vector2 = Vector2.ZERO
## The heights the stroke under way moves, or null while it lays none.
var _heights: SaStrokeHeights = null
## The smudge stage's carry for the stroke under way, the door's own, or null
## while no point of it has asked for the stage. Made by the first update that
## does, since the snapshot is taken under its newest point's box, and dropped
## at the lift.
var smudge: SaSmudgeReservoir = null
## The newest point the dynamics answered, which the smudge stage picks up
## at once an update.
var _newest: NoisePointScript = null
## The tip's generator, the one the kernel branches on, and the thickest any
## point of the update under way lays.
var _generator: int = 0
var _thickest: float = 0.0
## The points laid before a speed was measured, answered again once one is.
var _press: NoisePressSpeedScript = NoisePressSpeedScript.new()
## The update the frame's motions owe, laid at the frame, and whether the
## sample being added is a motion of the frame's rather than a suite's.
var _frame: NoiseFrameScript = null
var _gathering: bool = false


## Hands the brush's own settings a store, so the Picture field of a brush a
## suite or a preset's thumbnail made works as the module's does. Its pattern is
## made when a row or a preset names it, and a press only binds it. The store
## scans nothing until a pattern is asked of it. The tool machine swaps in the
## module's settings, which carry the module's store.
##
## It is warmed for the two things that make a first stroke wait, a document
## announcing its depth and a preset being chosen. Sara's first document sets its
## space before the machine builds any tool, so the bus has spoken by the time
## this listens, and one idle later the machine has handed the tool its surface.
func _init() -> void:
    _frame = NoiseFrameScript.new(_lay_owed)
    settings.pattern_store = SaPatternStore.new()
    if not EventBus.document_color_space_changed.is_connected(warm_at):
        EventBus.document_color_space_changed.connect(warm_at)
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    warm.call_deferred()


## Builds what the first stroke would build and a second would not, at the depth
## of the document this tool paints, which is `NoiseWarm`'s and the field's
## stand-in, and points the kernel at it. A tool with no document yet, as a suite
## builds one, has nothing to build for, and a depth already built for is not
## built again.
func warm() -> void:
    var doc: SaDocument = document()
    if doc == null or GlobalShaderCompiler.get_rd() == null:
        return
    var format := doc.color_space.texel_format()
    if format == _warmed_format:
        return
    _warmed_format = format
    compute.use_storage_format(format)
    NoiseWarmScript.build(KERNEL, format)
    field_binding.warm()


## Builds the kernels at the depth *changed* declares when it is this tool's
## own document, which has just opened or changed its depth. Every door that
## sets a depth, File > New, File > Open, Assign and Convert, announces it on
## the bus. The tool's own `compute` is left to [method warm] and [method reset].
func warm_at(changed: SaDocument) -> void:
    if changed != null and surface != null and changed == document():
        NoiseWarmScript.build(KERNEL, changed.color_space.texel_format())


## A preset was chosen, from the docker, a chord, the Pop-up Palette or the bar,
## so the brush is warmed for the document it paints.
func _on_preset_loaded(_stored_name: String) -> void:
    warm()


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    if _locked_target(doc):
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            EventBus.paint_refused.emit(tr("This layer is locked, so the stroke did nothing. Unlock it in the Layers docker."))
        return
    if event is InputEventMouseMotion:
        _read_pen(event)
    var now := SaPenClock.now_ms()
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and not SaContext.refuse_hidden(doc.active_layer, tr("stroke")):
            begin_stroke(get_document_mouse_position(), _last_pressure if is_tablet else 1.0, _last_tilt, now, not _is_mouse)
        elif is_drawing:
            # A stroke let go before its pointer said what it is lays what
            # waited as a mouse's, since nothing showed a pen.
            _lay_waiting(1.0)
            end_stroke()
    elif event is InputEventMouseMotion and is_drawing:
        var at := get_document_mouse_position()
        if not (is_tablet or _is_mouse):
            _wait(at, now)
            return
        _lay_waiting(0.0)
        gather_sample(at, event.pressure if is_tablet else 1.0, pen_tilt(event.tilt), now)


## Keeps a plain motion of a pointer not known yet, and past
## [constant MOUSE_MOTIONS] of them in the stroke takes the pointer for a mouse
## and lays them at a mouse's full pressure.
func _wait(at: Vector2, time_ms: float) -> void:
    _waiting_at.append(at)
    _waiting_times.append(time_ms)
    if _waiting_at.size() > MOUSE_MOTIONS:
        _is_mouse = true
        _lay_waiting(1.0)


## Lays the motions that waited for the pointer to say what it is, each at
## *pressure* and upright, since a motion waited only when it reported neither
## a pressure nor a tilt.
func _lay_waiting(pressure: float) -> void:
    for i in _waiting_at.size():
        gather_sample(_waiting_at[i], pressure, Vector2.ZERO, _waiting_times[i])
    _waiting_at.clear()
    _waiting_times.clear()


## Opens a stroke at *at* and lays its first point there, which is painted
## once the path says where it goes, or at the lift for a tap.
##
## Public, with [method add_sample] and [method end_stroke], so a suite paints
## the stroke a pen would without faking the pointer. *tilt* is in degrees,
## each axis -60 to 60, and *time_ms* is when the sample was made, a negative
## time meaning the one before. A *held* press lays nothing until the first
## sample, which lays it at the sample's pressure, the way a pen's press waits
## for a motion to say how hard. A stroke that ends first lays it at
## *pressure*, or at 1.0 when that is 0. *twist* is the pen's barrel rotation
## in degrees, -180 to 180.
func begin_stroke(
    at: Vector2, pressure: float, tilt: Vector2 = Vector2.ZERO, time_ms: float = -1.0, held: bool = false, twist: float = 0.0
) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    is_drawing = true
    _curve.clear()
    dab_list.clear()
    _thickest = 0.0
    _press = NoisePressSpeedScript.new()
    _last_position = at
    _last_pressure = pressure if pressure > 0.0 else 1.0
    _last_tilt = tilt
    _last_twist = twist
    _clock = time_ms if time_ms >= 0.0 else _clock
    _time_origin = _clock
    _times = PackedFloat64Array([_clock])
    _twists = PackedFloat64Array([twist])
    var erasing := _is_erasing()
    var locked := _is_alpha_locked()
    _stroking = not (erasing and locked)
    if not _stroking:
        # Said at the press, or the eraser reads as a broken pen.
        SaContext.refuse_erase(doc.active_layer)
        return
    var buffer_mode: StringName = &""
    if locked:
        buffer_mode = SaLayerScript.BLEND_MODE.ALPHA_LOCK
    elif erasing:
        buffer_mode = SaLayerScript.BLEND_MODE.ERASE
    doc.begin_stroke(settings.opacity, settings.blend_mode, buffer_mode)
    if buffer_mode.is_empty() and doc.mask_target == null and settings.thickness > 0.0:
        _heights = SaStrokeHeights.new(doc, doc.active_layer)
    dynamics.settings = settings
    settings.bind_chroma()
    dynamics.begin_stroke()
    field_seed = seed_for_stroke()
    stroke_info.begin(at, field_seed)
    _rounding_seed = doc.stroke_transaction.take_seed(stroke_seed)
    # The width the along-the-stroke rolls measure their features in, the
    # tip at full pressure, so a roll changes over a few of the stroke's own
    # widths whatever its size.
    stroke_info.tip_diameter = 2.0 * _base_radius()
    field_slide = 0.0
    _drift_from = at
    lay_field(field_seed)
    _press_held = held
    _press_waited = false
    smudge = null
    if not held:
        _point_twist = twist
        _point(at, _last_pressure, tilt, _clock)
        _send(false, _last_pressure)


func tick(_delta: float) -> void:
    lay_waited_press(SaPenClock.now_ms())


## Lays the press a pen has held still for [constant PRESS_WAIT_MS] by
## *now_ms*, at the pressure the press took, and answers whether it did.
##
## **The first sample lays it again.** A press carries no pressure, and one
## from a hover that reported none takes a tap's full one, so left at that a pen
## that rests a moment before it moves, or whose first motion comes after a slow
## frame, would open on a blot of full paint and a curve drawn down from it, and
## a pressure option bound to the stroke's peak would read the whole body
## against it. Until the stretch
## takes a second point the press shows only as the front, which the next update
## puts back, so the first sample begins the stroke's points again from the
## press at its own pressure, the way a press that waited for it is laid.
func lay_waited_press(now_ms: float) -> bool:
    var doc: SaDocument = document()
    if not is_drawing or not _press_held or now_ms - _time_origin < PRESS_WAIT_MS:
        return false
    _press_held = false
    _press_waited = true
    if _stroking and doc != null:
        _point_twist = _last_twist
        _point(_last_position, _last_pressure, _last_tilt, _clock)
        _send(false, _last_pressure)
    return true


## Sweeps the segment the sample before *at* completes, one sample late so the
## curve through the samples either side of it can be drawn. *tilt*,
## *time_ms* and *twist* are read as [method begin_stroke] reads them.
func add_sample(at: Vector2, pressure: float, tilt: Vector2 = Vector2.ZERO, time_ms: float = -1.0, twist: float = 0.0) -> void:
    if not is_drawing:
        return
    var now := time_ms if time_ms >= 0.0 else _clock
    var pressed := false
    if _press_held or _press_waited:
        _last_pressure = pressure
        if _stroking:
            if _press_waited:
                _unlay_press()
            _point_twist = _last_twist
            _point(_last_position, pressure, _last_tilt, _clock)
            pressed = true
        _press_held = false
        _press_waited = false
    if _stroking:
        if _curve.is_empty():
            _curve.begin(_last_position, _last_pressure, _last_tilt)
            _times = PackedFloat64Array([_clock])
            _twists = PackedFloat64Array([_last_twist])
        _note_time(at, now, twist)
        dynamics.hold()
        if not pressed and _rests_on_the_press(at):
            _point_twist = twist
            _point(at, pressure, tilt, now)
        _sweep(_curve.feed(at, pressure, tilt, 0.0), 3)
        dynamics.release()
        if _gathering:
            _frame.owe(pressure)
        else:
            _send(false, pressure)
    _clock = now
    _last_position = at
    _last_pressure = pressure
    _last_tilt = tilt
    _last_twist = twist


## [method add_sample] as a pen's motion: swept now, and laid with the frame's
## other motions at the frame, [method lay_frame], or by whatever sends first.
func gather_sample(at: Vector2, pressure: float, tilt: Vector2 = Vector2.ZERO, time_ms: float = -1.0, twist: float = 0.0) -> void:
    _gathering = true
    add_sample(at, pressure, tilt, time_ms, twist)
    _gathering = false


## Lays what the frame's gathered motions owe, which the frame's
## `process_frame` does unasked, and a suite asks for in place of a frame.
func lay_frame() -> void:
    _frame.lay()


## The frame's update at the newest motion's *pressure*, while the stroke it
## was owed to is still drawn.
func _lay_owed(pressure: float) -> void:
    if is_drawing and _stroking and document() != null:
        _send(false, pressure)


## Forgets the press [method lay_waited_press] laid, and everything the stroke
## read from it, before the first sample lays it again. Nothing of it reached
## the layer but the front, so the stretch and the press's speed start empty,
## the dynamics and the stroke info start at the press as [method begin_stroke]
## began them, and the seed and the field it laid stay the stroke's.
func _unlay_press() -> void:
    dab_list.stretch.clear()
    dab_list.front.forget_size()
    _press = NoisePressSpeedScript.new()
    _thickest = 0.0
    _newest = null
    dynamics.begin_stroke()
    var diameter := stroke_info.tip_diameter
    stroke_info.begin(_last_position, field_seed)
    stroke_info.tip_diameter = diameter
    field_slide = 0.0
    _drift_from = _last_position


## Whether a sample at *at* is the pen still exactly where it pressed, with no
## point laid anywhere else yet. The curve folds such a sample into the one
## before it, so it would reach no point, and a harder press there would be
## lost and never show in the front. It is laid as a point at the press
## instead, which the stretch holds back and writes onto the press when it is
## harder. A pen exactly still anywhere else is ahead of the
## points the curve has swept, so its samples stay folded, and the last one's
## pressure is the one the lift paints there, which a release at pressure 0
## needs to end on its faded tail.
func _rests_on_the_press(at: Vector2) -> bool:
    return stroke_info.total_length == 0.0 and at.is_equal_approx(stroke_info.position)


## Sweeps the last segment with the stroke's end cap and lands the stroke on
## the layer.
##
## A pen's press that no sample followed paints its tip here, at full pressure
## for a tap, since none came. A press that lands where the last stroke let go
## and within [constant BOUNCE_MS] of it is that stroke's pen bouncing as it
## lifts, and it takes the tail's pressure against the tail's peak, so the
## lift-up reads what the faded tail read rather than a fresh full-strength
## tip after it.
func end_stroke() -> void:
    var doc: SaDocument = document()
    if _press_held and _stroking and doc != null:
        if _bounces():
            stroke_info.max_pressure = _tail_peak
            _last_pressure = _tail_pressure
        _point_twist = _last_twist
        _point(_last_position, _last_pressure, _last_tilt, _clock)
    _press_held = false
    _press_waited = false
    var closed := _stroking and doc != null
    if closed:
        dynamics.hold()
        _sweep(_curve.finish(0.0), 2)
        dynamics.release()
        _send(true, _last_pressure)
        dab_list.front.drop_unreached(doc.stroke_layer)
        SaStrokeNote.commit(doc, _is_erasing())
    var peak := stroke_info.max_pressure
    _clear()
    if closed:
        _tail_position = _last_position
        _tail_time = _clock
        _tail_pressure = _last_pressure
        _tail_peak = peak


## Whether the press under way is the last stroke's pen bouncing as it lifts:
## soon after that stroke let go and within the tip's radius of where it did.
func _bounces() -> bool:
    if _tail_time < 0.0 or _tail_peak <= 0.0:
        return false
    if _time_origin < _tail_time or _time_origin - _tail_time > BOUNCE_MS:
        return false
    return _last_position.distance_to(_tail_position) <= maxf(1.0, _base_radius())


## Puts the tool down, and a stroke still open is ended first as the pen's
## lift ends it.
##
## [ToolMachine] calls this when the tool in hand changes, a held Pan or
## Eyedropper included, and that can come with the pen down. The stroke drawn
## so far is committed as one undo step and its stroke buffer emptied, rather
## than thrown away and left in the buffer for the next stroke to find.
func reset() -> void:
    if is_drawing:
        _lay_waiting(1.0)
        end_stroke()
    else:
        _clear()


## Clears the stroke's state.
func _clear() -> void:
    is_drawing = false
    _stroking = false
    _waiting_at.clear()
    _waiting_times.clear()
    _heights = null
    smudge = null
    _curve.clear()
    dab_list.clear()
    _newest = null
    # A scratchpad's textures die with its document, so the kernel's uniform
    # sets are made afresh rather than held against freed images.
    compute = SaCompute.new(KERNEL)
    # At the document's depth straight away, so the next stroke's first dispatch
    # does not make its pipelines again from the default format's.
    var doc: SaDocument = document()
    if doc != null and GlobalShaderCompiler.get_rd() != null:
        compute.use_storage_format(doc.color_space.texel_format())


## The ring is the tip at full pressure, the Size row as a width.
func get_cursor_radius() -> float:
    if surface == null:
        return -1.0
    return maxf(0.05, _base_radius())


func _base_radius() -> float:
    var doc: SaDocument = document()
    if doc == null:
        return settings.radius * 1080.0
    return settings.radius * doc.brush_side


func _read_pen(event: InputEventMouseMotion) -> void:
    _pen_inverted = event.pen_inverted
    # A hover's pressure, 0 as well, so a tap paints its tip at what the pen was
    # doing a moment before rather than at the last stroke's tail.
    if not is_drawing:
        _last_pressure = event.pressure
    if event.pressure > 0.0 or event.tilt != Vector2.ZERO or event.pen_inverted:
        is_tablet = true
        _is_mouse = false
        # And the tilt, so a press, which carries none, opens at it.
        _last_tilt = pen_tilt(event.tilt)


## A pen's tilt in the degrees every sensor reads. Godot reports each axis as
## -1 to 1 of the tablet's own reach, and a sensor divides by
## `SaSensor.TILT_RANGE`, so a full lean reads as the full swing. Fed raw, a
## full lean would read as one degree and the pen as upright whatever it did.
static func pen_tilt(reported: Vector2) -> Vector2:
    return reported * SaSensor.TILT_RANGE


## Keeps *at*'s time and *twist* beside the curve's window, the way the curve
## keeps the sample: a sample where the pen has not moved replaces the last
## one's.
func _note_time(at: Vector2, time_ms: float, twist: float) -> void:
    if not _times.is_empty() and _last_position.is_equal_approx(at):
        _times[_times.size() - 1] = time_ms
        _twists[_twists.size() - 1] = twist
        return
    _times.append(time_ms)
    _twists.append(twist)
    if _times.size() > 3:
        _times.remove_at(0)
        _twists.remove_at(0)


## What *window* holds at the two ends of the span the curve answers, which
## starts *back* samples from the newest, or *otherwise* at both ends when the
## window is short.
static func _span_of(window: PackedFloat64Array, back: int, otherwise: float) -> Vector2:
    var count := window.size()
    if count < back:
        return Vector2(otherwise, otherwise)
    return Vector2(window[count - back], window[count - back + 1])


## One span of the curve into the stretch, a point at every chord's end and
## between them wherever a chord is longer than [constant POINT_STEP] of the
## tip. The span starts *back* samples from the newest, whose times and twists
## its points are fed between. The span's first point is the stretch's newest
## already, so it is not added again.
func _sweep(span: SaStrokeCurve.Span, back: int) -> void:
    if span == null:
        return
    var times := _span_of(_times, back, _clock)
    var twists := _span_of(_twists, back, _last_twist)
    var path := span.path
    var step := maxf(MIN_POINT_STEP, POINT_STEP * 2.0 * _base_radius())
    for chord in range(1, path.size()):
        var from := path[chord - 1]
        var goal := path[chord]
        var from_parameter := span.parameter_at(chord - 1)
        var goal_parameter := span.parameter_at(chord)
        var pieces := clampi(ceili(from.distance_to(goal) / step), 1, MAX_POINTS_A_CHORD)
        for piece in range(1, pieces + 1):
            var share := float(piece) / float(pieces)
            var parameter := lerpf(from_parameter, goal_parameter, share)
            _point_twist = rad_to_deg(lerp_angle(deg_to_rad(twists.x), deg_to_rad(twists.y), parameter))
            _point(
                from.lerp(goal, share), span.pressure_at(parameter), span.tilt_at(parameter), lerpf(times.x, times.y, parameter)
            )


## One sample into one point of the stretch: what the dynamics answer there,
## in the stretch's slots, and the box its tip reaches. The pen's twist is
## [member _point_twist].
func _point(at: Vector2, pressure: float, tilt: Vector2, time_ms: float) -> void:
    stroke_info.hovering = false
    stroke_info.feed(at, pressure, tilt, _point_twist, time_ms - _time_origin)
    stroke_info.next_dab()
    _drift(at)
    if _press.heard(at, pressure, tilt, _point_twist, time_ms - _time_origin, field_slide, stroke_info):
        field_slide = _press.replay(stroke_info.stroke_seed, stroke_info.tip_diameter, field_slide, _answer.bind(true))
    _answer(stroke_info, field_slide, false)


## What the dynamics answer at the point *info* reads with the field slid by
## *slide*, laid in the stretch, or written again onto that point while it
## waits when *restating*, at the first speed the smoother measured.
func _answer(info: SaStrokeInfo, slide: float, restating: bool) -> void:
    # The texture sensor's reading, the field down the middle of the path at
    # the point, drifted as the kernel reads it. Read on the CPU from the
    # numbers the press wrote, since a readback would stall the stroke.
    var along := info.total_length - slide
    info.texture = NoiseFieldReadingScript.sensor_reading(field_binding.values, field_binding.mask, along)
    var dab := dynamics.evaluate(info, 2.0 * _base_radius())
    dab.size = NoisePointScript.thinned(dab.size, 2.0 * _base_radius())
    var space := document().color_space
    var point := NoisePointScript.new(settings, info, dab, along, space, shift_for(info), band_for(dab), lean_for(info))
    _generator = point.generator
    _thickest = maxf(_thickest, point.thickness)
    if restating:
        dab_list.stretch.restate(point.slots, point.reach)
        return
    dab_list.stretch.add(point.slots, point.reach, point.tip_reach)
    _newest = point


## The smudge stage's pickup, once an update at the stretch's newest point,
## queued before the stretch that reads what it carried, the stamp's own call.
## What it picks up is the point's to say, in `pick_up_into`. Nothing while the
## stage is off there. The carry is made by the first pickup, over the composite
## or over the layer being painted as Sample Merged says.
func _pick_up() -> void:
    var point := _newest
    if point == null or not point.dab.smudge:
        return
    _open_smudge()
    point.pick_up_into(smudge, settings)


## Makes the stroke's carry and its snapshot on the first update that smudges,
## before any front is laid, since the composite shows a front until the next
## frame and a carry that copied one opened the stroke on the brush's own blot.
func _open_smudge() -> void:
    var point := _newest
    if smudge != null or point == null or not point.dab.smudge:
        return
    var doc: SaDocument = document()
    smudge = SaSmudgeReservoir.new(
        surface.easel if surface != null else null,
        doc.active_layer if doc != null else null,
        settings.smudge_sample_merged,
        point.reach,
        null,
        false,
        settings.blend_mode
    )


## Lays the stretch this update walked, and sends it as one list, with the
## smudge stage's queue after it in that list while the stroke smudges, the
## order the card met them in before either was a list. *closing* is the
## stroke's last update, which paints the end cap the others leave to the
## update after them.
##
## Every other update lays the front after it, the end cap the closing update
## would paint now, so the round tip shows under the pen, a pen at rest
## included. It goes in the update's own list, after the body,
## and the next update puts it back before its own body. While the stroke
## smudges the body is in the stage's queue, so the front follows in a list of
## its own after that, and an update is two lists. The front's end takes *pressure*, the pen's raw reading
## now, as a point reads it.
func _send(closing: bool, pressure: float) -> void:
    var doc: SaDocument = document()
    _frame.settled()
    _open_smudge()
    _lay(closing)
    if smudge != null:
        dab_list.send_before(smudge)
    if not closing and _shows_front():
        tip_mask = SaBrushTipMask.bind(compute, settings.tip, tip_mask, stroke_info)
        var stage := smudge if _newest != null and _newest.dab.smudge else null
        if smudge != null:
            smudge.take_in(Rect2i(dab_list.stretch.front_box().grow(1.0)))
        dab_list.lay_front(doc, compute, _values(), SaSmudgeReservoir.carry_of(stage), _pressure_now(pressure), _heights)
    dab_list.send()


## *raw* read the way [method _point] reads a sample's pressure, through the
## painter's correction, on a reading of its own so the stroke's stays as the
## last point left it.
func _pressure_now(raw: float) -> float:
    var reading := SaStrokeInfo.new()
    reading.feed(_last_position, raw, Vector2.ZERO, 0.0, 0.0)
    return reading.pressure


## Whether the stroke shows its front under the pen. A stroke into a mask or the
## quick mask paints straight in with no stroke buffer, and a fresh chunk of a
## mask opens at the mask's rest, which the front's put back cannot write, so
## those strokes keep their end for the lift. So does an eraser over a layer
## with a height, because the document lowers that height under every region an
## eraser's stroke lands and never raises it again, and a front put back would
## leave it lowered where the path never went.
func _shows_front() -> bool:
    var doc: SaDocument = document()
    if not settings.front_shown or doc == null or doc.stroke_layer == null or doc.mask_target != null or doc.selection.editing:
        return false
    var active := doc.active_layer
    return not (_is_erasing() and active != null and active.carries_height())


## The stretch into every chunk its rectangle reaches, once for the stroke and
## once more for each image the document's symmetry paints, each through its
## own map. The points go to the buffer even when no chunk is reached, since
## the next update starts from them. What the last front painted over is put
## back first, whether the stretch has anything to lay or not.
func _lay(closing: bool) -> void:
    var doc: SaDocument = document()
    var points := dab_list.stretch
    if doc == null:
        return
    dab_list.put_back_front()
    if not points.is_waiting(closing):
        return
    var contexts := dab_list.reach(doc, points.region())
    dab_list.front.reached(contexts)
    var cover := -1.0
    if contexts[0].paints_coverage:
        cover = 0.0 if _is_erasing() else 1.0
    points.write(closing, cover)
    var heights := _heights if _thickest > 0.0 else null
    _thickest = 0.0
    if contexts.all(func(paint: SaPaintContext) -> bool: return paint.is_empty()):
        return
    tip_mask = SaBrushTipMask.bind(compute, settings.tip, tip_mask, stroke_info)
    points.bind(compute)
    _pick_up()
    var stage := smudge if _newest != null and _newest.dab.smudge else null
    var values := _values()
    values["point_count"] = float(points.count)
    values["first_laid"] = points.first_laid
    values["open_end"] = 1.0 if points.open_end else 0.0
    dab_list.lay_images(compute, values, heights, SaSmudgeReservoir.carry_of(stage), stage)


## The kernel's numbers that are the brush's rather than the stretch's, which
## the body and the front both send.
func _values() -> Dictionary:
    return {
        "generator": float(_generator),
        "shape": float(settings.tip.shape),
        "antialias": 1.0 if settings.tip.antialias_edges else 0.0,
        "paint_load": clampf(settings.paint_load, 0.0, 1.0),
        "push_below": 1.0 if settings.push_colour_below else 0.0,
        "stroke_seed": float(_rounding_seed),
        "field_origin": dab_list.stretch.field_origin,
        "field_axis": Vector2.ZERO if settings.texture_drift > 0.0 else dab_list.stretch.field_axis,
        "field_along": dab_list.stretch.field_along,
    }


## Which way this sample's height grows across the tip and by how much, as
## [method NoisePointScript.lean_for] answers it.
func lean_for(info: SaStrokeInfo) -> Vector2:
    return NoisePointScript.lean_for(settings, info)


## *option*'s answer for the sample under way, or one while it is off, the
## factor a row is multiplied by.
func _option_factor(option: SaCurveOption) -> float:
    if option == null or not option.enabled:
        return 1.0
    return option.size_like(stroke_info)


## Slides the field along the stroke by the Drift row's share of the step from
## the last point to *at*. Before the point's size is known, so a point too
## small to paint still moves the field on.
func _drift(at: Vector2) -> void:
    var drift := clampf(float(settings.texture_drift) * _option_factor(settings.drift_option), 0.0, 1.0)
    field_slide += (at - _drift_from).length() * drift
    _drift_from = at


## The width of the soft band under the cut at this point, as
## [method NoisePointScript.band_for] answers it. Two suites override it to
## watch what the stroke read.
func band_for(dab: SaDabParams) -> float:
    return NoisePointScript.band_for(settings, dab)


## The seed the next stroke is laid with. A seed the tool is handed wins, the
## preset thumbnail's. Otherwise Randomness at nought holds the preset's own,
## and above nought every stroke draws one from the clock.
func seed_for_stroke() -> int:
    if stroke_seed != 0:
        return stroke_seed
    if settings.randomness <= 0.0:
        return settings.held_seed if settings.held_seed != 0 else 1
    return SaPenClock.now_usec()


## Writes the field a stroke laid with *stroke_seed_value* paints through: the chosen
## field's numbers, the stroke's offset, and the picture when the field is one.
## Once a stroke, at the press, so every stretch reads one field, and binds it
## there on the stroke's kernel, or on its own pass for a field that brings one.
##
## **Nothing is read back here**. The picture and the grey mask
## the texture sensor reads are the settings' `chosen_picture`, made when the
## pattern was named, and the press binds them. Settings that named a pattern
## while they had no store have none to bind, and the stroke paints as if solid
## with a warning rather than reading the tile inside it.
func lay_field(stroke_seed_value: int) -> void:
    var registry := field_registry()
    registry.reread()
    var chosen: SaBrushFieldRegistry.Field = registry.chosen(settings)
    if chosen != null and chosen.is_picture():
        var made: NoiseFieldsScript.Picture = settings.get("chosen_picture")
        if field_binding.pick(made, String(settings.picture_name)) == null:
            push_warning("Noise brush: the Picture field paints as if solid, %s" % field_binding.error)
    else:
        field_binding.clear_picture()
    # After the pick, so a picture's numbers carry its tone range.
    field_binding.write(field_binding.with_picture(registry.numbers_for(settings, stroke_seed_value, 2.0 * _base_radius())))
    compute = NoiseFieldsScript.OwnField.compute_for(chosen, compute)
    field_binding.bind(compute)


## The fields this brush reads, the settings' own when the module set them.
func field_registry() -> RefCounted:
    if fields == null and settings.fields != null:
        fields = settings.fields
    if fields == null:
        fields = NoiseFieldsScript.new()
        fields.register_shipped()
    return fields


## Both readings of the field over *region* of document pixels, the pressure
## map in red and the lightness in green, for a straight stroke through *start*
## along *direction*, *along* its travelled length there less the drift, whose
## tip reaches *half_width* pixels either side of it. The field is the one
## [method lay_field] last wrote, read by the binding that holds it.
func probe_field(region: Rect2i, start: Vector2, direction: Vector2, along: float, half_width: float) -> SaTexture:
    return field_binding.probe(region, start, direction, along, half_width)


## How far the field is shifted against the pressure at this point, as
## [method NoisePointScript.shift_for] answers it.
func shift_for(info: SaStrokeInfo) -> float:
    return NoisePointScript.shift_for(settings, info)


## Loads an image tip from *path* onto the settings' tip and selects it, or says
## why it could not. The Tip Image list's pick and the Load Tip action both
## come here, and so do a scenario and a suite, through the door's
## `SaBrushTipMask.select` the stamp's `load_tip` calls. An empty path puts the
## tip back on its procedural generator.
func load_tip(path: String) -> bool:
    var mask := SaBrushTipMask.select(settings.tip, path)
    if not mask.error.is_empty():
        EventBus.paint_refused.emit(mask.error)
        return false
    tip_mask = mask
    tip_loaded.emit(path)
    return true


## The Load Tip action's own method, which opens the picker and hands what it
## answers to [method load_tip].
func load_tip_dialog() -> void:
    SaBrushTipMask.choose_file(load_tip)


## Toggles erasing with this engine, which is what E does while the Brush paints
## with it, and answers the new state.
func toggle_eraser() -> bool:
    eraser_toggled = not eraser_toggled
    return eraser_toggled


func _is_erasing() -> bool:
    return eraser_toggled or settings.blend_mode == SaLayerScript.BLEND_MODE.ERASE or _pen_inverted


func _is_alpha_locked() -> bool:
    var doc: SaDocument = document()
    var active := doc.active_layer if doc != null else null
    return active != null and "alpha_locked" in active and active.alpha_locked


## Whether the lock over what this stroke would write turns it away: the
## active layer's own lock, or the lock on a mask's owner, which is the flag a
## painter switches rather than a group's `is_locked`.
func _locked_target(doc: SaDocument) -> bool:
    var mask: SaMask = doc.mask_target
    if mask == null:
        var active := doc.active_layer
        return active != null and "is_locked" in active and active.is_locked
    var owner: SaLayer = doc.active_layer if mask.is_own() else mask.layer
    if not is_instance_valid(owner):
        return false
    return owner._locked
