## Logic for drawing strokes with pressure and tilt support.
##
## Handles sub-pixel interpolation between mouse/pen events and
## calculates which chunks need to be dispatched for the paint shader.
##
## **Three siblings carry what reads nothing off this tool**. [SaDabPacking]
## holds the push constants of the two paint kernels, [SaDabCadence] holds the
## spacing and the airbrush clock, which are Krita's
## `kis_paintop_plugin_utils.h`, and [SaStrokeDistance] is the walk itself. None
## of them reads settings, a stroke or a document, so none of them lives here.
## Two more read no tool: [SaStampPlacement] says where a dab lands and in what
## shape, and [SaStampSmudge] holds the stroke's smudge carry.
## What is left here is the state a stroke has while it is being made, which is
## the only thing a tool state is for.
extends ToolState

## The smallest dab worth dispatching, [constant SaStampPlacement.MIN_DAB_DIAMETER],
## which decides it and says how it was measured. Named here too because the
## suites that stand in for the dispatch read it here, and written out for the
## reason the bindings below are.
const MIN_DAB_DIAMETER: float = 0.2

## Where `dab.gmacs` declares the three things the tip binds, kept as names here
## because the suites and the capture harness call them that.
##
## Written out rather than read off `SaBrushTipMask`, which is what actually
## binds them: a `const` whose initializer names a global class is resolved
## before the class cache has it, and the engine then comes up with `Nonexistent
## function 'new' in base 'GDScript'` on an unrelated line.
## `test_the_binding_numbers_agree_with_the_mask` is what keeps the two in step.
const SOFTNESS_BINDING: int = 2
const TIP_IMAGE_BINDING: int = 3
const PATTERN_BINDING: int = 4
## The dab kernel's `height` image, the paint's height the eraser lowers,
## bound from `SaStrokeHeights.held`.
const HEIGHT_BINDING: int = 7

## The settings resource, which is the old one's fields plus the curve
## options. Named `BrushSettingsScript` still, because five other files and
## the capture harness call it that.
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
const StrokeStabilizerScript = preload("res://modules/sara-base-modules/stamp-brush/walk/stroke_stabilizer.gd")

## An image tip was loaded and selected, with the path it came from. Emitted
## from [method load_tip] on success only, so the Brush Editor's tip preview
## and its Tip Image list can follow a file the painter picked, which no
## option write announces because the load is an action rather than a value.
## A refusal says its piece on `EventBus.paint_refused` and emits nothing
## here.
signal tip_loaded(path: String)

var compute: SaCompute
var settings: BrushSettingsScript = BrushSettingsScript.new()
## The pen is flipped: its eraser end is on the tablet. Read from every motion
## event, so flipping the pen mid-hover erases and flipping it back paints.
## `eraser_toggled` is the key and the bar's button.
var is_eraser: bool = false
## Announced from the setter, because the bar writes it as a plain property
## and the toolbox and the other surface's bar listen.
var eraser_toggled: bool = false:
    set(val):
        if eraser_toggled == val:
            return
        eraser_toggled = val
        EventBus.brush_eraser_toggled.emit(eraser_toggled)

## Smooths the pointer before the interpolation. Its mode and amount come from
## the settings on every stroke, so a preset carries them.
var stabilizer: StrokeStabilizerScript = StrokeStabilizerScript.new()

# --- THE DYNAMICS ---
## The sample every sensor reads, carried across the whole stroke because the
## running totals it holds, the distance, the dab index and the locked angle,
## are what half the sensors are made of.
var stroke_info: SaStrokeInfo = SaStrokeInfo.new()
## When the stroke was pressed, on the pen's clock, which the time sensor counts from.
var _pressed_ms: float = 0.0

## The smudge stage of the stroke under way, [SaStampSmudge].
var _smudge := SaStampSmudge.new()

## One sample into one `SaDabParams`. Handed the settings at the press rather
## than at construction, because `ToolMachine` swaps the settings object in
## after the tool is built.
var dynamics: SaDynamics = SaDynamics.new()

## A handful of dabs spread along the stroke, for a state dump to read.
##
## The dynamics half is arithmetic with no picture of its own, so a capture that
## can only see pixels cannot say what the evaluator decided. Spread rather than
## the last few, because the last few of a stroke that ramps are all at the
## pressure it ended on and say nothing about the ramp.
var sampled_dabs: Array[SaDabParams] = []

## How many are kept. Bounded because a stroke is thousands of dabs and this is
## a debugging aid rather than a log.
const SAMPLED_DABS: int = 5
## How long a pen's press waits for a motion's pressure before it lays its dab
## at the pressure it has. Windows Ink sends no motion while a pen rests, so
## without the wait a press held still lays nothing until the pen moves or
## lifts.
const PRESS_WAIT_MS: float = 80.0

## The stroke's final dab, which the decimation is not guaranteed to keep and
## which is the one a reader looks at first.
var last_dab: SaDabParams = null

## One in how many dabs is kept, doubled each time the list fills.
var _dab_stride: int = 1

# --- HARDWARE STATE ---
## State flag indicating if a pen is currently being used
var is_tablet: bool = true
## Curve for pressure sensitivity (1.0 is linear, > 1.0 makes light touches more precise)
##
## Not applied by this file. `SaStrokeInfo.feed` normalizes without a gamma and
## the size and opacity curves carry this exponent inside them, which is what
## the migration multiplied it into. Kept as a name because the number is still
## the one those curves were built from and the capture harness reads it.
var pressure_gamma: float = 2.4

var has_last_pos: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
# `last_pressure` is declared on `ToolState`, so the Info docker reads it of any
# tool. It is raw, because the sensors want the calibrated space.
## The pen's tilt at the last sample, which the press event does not carry.
var last_tilt: Vector2 = Vector2.ZERO
## The walk's sub-pixel spacing: the offset carried as a vector, the spacing
## the last dab was painted with, and the dab number the kernel hashes against.
var stroke_distance: SaStrokeDistance = SaStrokeDistance.new()
## The samples the walk has not drawn past, and the curve through them. A
## segment is walked one sample late, and the last at pen up.
var _curve: SaStrokeCurve = SaStrokeCurve.new()
var is_drawing: bool = false
## A press dab, not laid yet because no motion has reported a pressure.
var _press_held: bool = false
## The press dab of a tip that turns with the stroke, held for its heading, and
## the fan at a corner.
var _turn := SaStrokeTurn.new()
## What the pen's last stroke touched down with, half before any.
var _touch_pressure: float = 0.5

## What the motions have shown of the pointer, a pen or a mouse, and the
## motions a stroke holds back while they have shown neither.
var _pointer: SaPenOrMouse = SaPenOrMouse.new()

## The GPU side of the tip: the image texture and the SOFT generator's falloff,
## held for as long as the tip is selected. Both are rebuilt only when what they
## were built from moves, because a painter dragging the softness slider
## mid-stroke would otherwise allocate a buffer per dab, and a uniform set built
## against a freed RID is a crash rather than a slow frame.
var tip_mask: SaBrushTipMask = SaBrushTipMask.new()
## The pattern the settings name, bound over the tip mask's stand-in.
var dab_pattern: SaDabPattern = SaDabPattern.new()
## What one input event's walk settles once for all its dabs.
var _walk_batch := SaWalkBatch.new(dynamics, dab_pattern, _smudge.submit)
## The frame's share of the walk, and the samples carried past it.
var _budget := SaWalkBudget.new()

## How this stroke reaches the canvas, decided at the press and held to the
## release.
##
## In wash, erase and alpha lock gather in the stroke buffer like any other
## stroke and land once through the buffer's own composite mode, rather than
## painting straight into the active layer for every dab, which is build-up
## whatever the painter chose: an eraser at half opacity would erase twice where
## its stroke crossed itself.
##
## It is fixed at the press rather than read per dab because the buffer holds
## one stroke's coverage and the commit applies one rule to it. A pen flipped to
## its eraser end halfway through would otherwise leave a buffer whose first
## half means paint and whose second half means a hole.
var _route: SaStrokeRoute = SaStrokeRoute.new()

## The stroke's own copies of the tip and masking block, which its dabs write
## on instead of the preset's.
var _stroke: SaStrokeTip = SaStrokeTip.new()
## Texels to a document pixel on the layer the stroke paints, read at the
## press, which keeps a pen on a double resolution layer out of the pixel mode
## (`SaSmallDab.enters_mode`).
var _density: float = 1.0


func _init() -> void:
    # The tool loads its own shader when created. `dab`, which is the engine's
    # kernel: `paint` stays where it is because the fill tool and the quick
    # mask reach it too.
    compute = SaCompute.new("dab")
    if not EventBus.document_color_space_changed.is_connected(warm_at):
        EventBus.document_color_space_changed.connect(warm_at)
    # Sara's first document sets its space before the machine builds any tool,
    # so the bus has spoken by the time this listens. One idle later the machine
    # has handed the tool its surface, and that document is warmed then.
    warm.call_deferred()


## Builds the stroke's kernels at the depth of the document this tool paints,
## and points the dab's pipelines at it, so its first stroke does not wait for
## either. A tool with no document yet, as a suite builds one, has nothing to
## build for.
func warm() -> void:
    var doc: SaDocument = document()
    if doc == null or GlobalShaderCompiler.get_rd() == null:
        return
    var format := doc.color_space.texel_format()
    compute.use_storage_format(format)
    SaSmudgeReservoir.warm(format)
    SaWalkBatch.warm(format)


## Builds the stroke's kernels at the depth *changed* declares, for a document
## that has just opened or changed its depth.
##
## **The cost is the compile, not the pipeline.** A kernel is built once per
## storage format, and the first dab on an F16 document built `dab` at F16
## there and then: 72 ms of the first stroke's 80 ms stall, and the pickup's
## 7 ms on a smudge stroke besides. The pipeline made from a build takes a
## tenth of a millisecond, which is why a second stroke never stalled although
## every stroke makes a new one.
##
## Called from the bus rather than from the document open path, because every
## door that sets a depth, File > New, File > Open, Assign and Convert,
## announces the space there, and the brush is the one that knows which kernels
## it dispatches. Only the brush's own document is warmed, so a document behind
## another tab builds nothing. The build is made through an object of its own,
## so the tool's `compute` is left to [method warm] and [method reset].
func warm_at(changed: SaDocument) -> void:
    if changed == null or surface == null or changed != document() or GlobalShaderCompiler.get_rd() == null:
        return
    var format := changed.color_space.texel_format()
    SaCompute.new("dab").use_storage_format(format)
    SaSmudgeReservoir.warm(format)
    SaWalkBatch.warm(format)


## Main entry point for all input events.
func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return

    var left: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
    # A press with a stroke open means its release was lost, to a focus change
    # with the pen down, so the open stroke ends where the pen last was, as the
    # release would have ended it, and the press begins a stroke of its own.
    if left and event.pressed and is_drawing:
        _cut()
    # The lock refuses a press, never the release of a stroke begun before it,
    # or the stroke stays open with no undo step. Only the
    # refused press says anything, wherever the stroke was turned away.
    if _locked_target(doc) and not (left and is_drawing and not event.pressed):
        # On a mask only the lock the painter set turns the stroke away, so
        # the lock is what is said, even where the mask is a group's.
        if left and event.pressed and doc.mask_target != null:
            EventBus.paint_refused.emit(SaContext.lock_refusal_line(tr("stroke")))
        elif left and event.pressed:
            SaContext.refuse_paint(doc.active_layer, tr("stroke"))
        return

    _analyze_pointer_type(event)
    # An eraser on an alpha-locked layer would paint nothing, and a hidden layer
    # nothing the painter sees, so either press is refused with a line, after the
    # pointer is read because the pen's flipped end is known from its motion. A
    # mask takes the erase whatever the layer's alpha lock says.
    if left and event.pressed and not is_drawing:
        if SaContext.refuse_press(doc.active_layer, _is_erasing(), doc.mask_target != null):
            return

    if left:
        _handle_stroke_state(event)
    elif event is InputEventMouseMotion and is_drawing:
        _handle_stroke_motion(event)
    _walk_batch.later()


## Whether the lock over what this stroke would write turns it away.
##
## Onto the paint it is the active layer's `refuses_paint`, the lock, a
## generated layer, which stores no paint for a stroke to land in, or a live
## transform a smudge is not painted through. Onto a mask it is the flag a
## painter switches on the mask's owner, and never `is_locked`: a group answers
## that as true for its whole life, as a group holds no paint of its own to
## lock, and a stroke on the mask a group carries touches no paint under it.
##
## The owner is the mask's own layer in the field form and the active layer in
## the own form, where the mask names none, because a group's and a filter's
## mask keep chunks of their own. The layers docker makes the row the painter
## pressed active before it aims the brush, so the two agree, and it clears the
## target rather than leaving it on a mask another layer owns.
func _locked_target(doc: SaDocument) -> bool:
    var mask: SaMask = doc.mask_target
    if mask == null:
        var active := doc.active_layer
        return active != null and active.refuses_paint(not settings.smudge_pickup_option.enabled)
    var owner: SaLayer = doc.active_layer if mask.is_own() else mask.layer
    if not is_instance_valid(owner):
        return false
    return owner._locked


## Puts the tool down, and a stroke still open is ended first as the pen's
## lift ends it.
##
## [ToolMachine] calls this when the tool in hand changes, a held Pan or
## Eyedropper included, and that can come with the pen down. The painter has
## seen the stroke drawn so far, so it is walked to its last sample, committed
## and kept as one undo step, rather than thrown away with nothing to undo.
func reset() -> void:
    if is_drawing and document() != null:
        _cut()
    else:
        _clear()


## Ends the open stroke where the pen is, as a release does, without waiting
## for a frame to walk what the stroke still carries.
func _cut() -> void:
    _pointer.lay_held(_lay_motion, 1.0)
    if _press_held:
        _press_held = false
        if not _turn.waiting:
            _stamp_brush(last_mouse_pos, last_pressure, last_tilt)
    # A lift kept for a walk still carried runs at the end of this take.
    _take(true)
    if is_drawing:
        _lift()


## Clears the stroke's interpolation and state.
func _clear() -> void:
    _take(true)
    has_last_pos = false
    last_mouse_pos = Vector2.ZERO
    last_pressure = 0.0
    last_tilt = Vector2.ZERO
    _press_held = false
    _turn = SaStrokeTurn.new()
    _pointer.clear()
    stroke_distance.reset()
    _curve.clear()
    is_drawing = false
    _stroke = SaStrokeTip.new()
    # `sampled_dabs` is deliberately not cleared here. `_clear()` runs on the pen
    # lift, and a dump taken after a stroke is exactly when somebody wants to
    # read what that stroke decided. The press clears it instead, and the
    # stabiliser with it.

    # What the frame held goes before the kernel it was laid with is let go.
    _walk_batch.flush()
    # Textures of scratchpad were deleted by document, clear compute wrapper
    compute = SaCompute.new("dab")
    _walk_batch = SaWalkBatch.new(dynamics, dab_pattern, _smudge.submit)
    # At the document's depth straight away, so the next stroke's first dab
    # does not make its pipelines again from the default format's.
    var doc: SaDocument = document()
    if doc != null and GlobalShaderCompiler.get_rd() != null:
        compute.use_storage_format(doc.color_space.texel_format())


## Toggles temporary eraser mode on this brush (like Krita's E shortcut)
func toggle_eraser() -> bool:
    eraser_toggled = not eraser_toggled
    return eraser_toggled


## Heuristics to bypass the Wayland "device 0" bug by analyzing raw telemetry,
## which [SaPenOrMouse] reads.
func _analyze_pointer_type(event: InputEvent) -> void:
    if not event is InputEventMouseMotion:
        return
    # The eraser end of the pen drives the eraser.
    is_eraser = event.pen_inverted
    match _pointer.read(event):
        SaPenOrMouse.Shown.PEN:
            is_tablet = true
            # Catch hover pressure: if the driver sends a motion event with pressure
            # just before the click event: save it to avoid a 0.0 pressure start
            if not is_drawing and event.pressure > 0.0:
                last_pressure = event.pressure
            # And the tilt with it, because a button event carries none and the
            # first dab of a stroke has sensors that want one.
            last_tilt = event.tilt
        SaPenOrMouse.Shown.MOUSE:
            is_tablet = false


func _handle_stroke_state(event: InputEventMouseButton) -> void:
    var doc: SaDocument = document()
    if event.pressed:
        _take(true)
        is_drawing = true
        has_last_pos = true
        stabilizer.begin(settings.stabilizer_mode, settings.stabilizer_amount)
        var pen := get_document_mouse_position()
        last_mouse_pos = stabilizer.feed(pen, SaPenClock.report_ms())
        stroke_distance.reset()
        _curve.clear()
        # Build-up folds the stroke opacity into every dab and begins the stroke at one, so the
        # buffer merges unscaled and overlapping dabs accumulate. Wash leaves it on the stroke and
        # the kernel darkens the alpha towards it instead.
        var washing := _is_washing()
        _route = SaStrokeRoute.decide(_is_erasing(), _is_alpha_locked(), washing, settings.smudge_mode)
        # The tip's mode, and a gradient map's ramp on the card before the
        # stroke opens, because nothing uploads while a stroke runs.
        SaStampBindings.of(tip_mask).ramp.settle(settings, doc.color_space)
        doc.begin_stroke(settings.opacity if washing else 1.0, settings.blend_mode, _route.buffer_mode())
        _smudge.drop()
        _stroke = SaStrokeTip.new()
        _density = doc.active_layer.resolution_scale if doc.active_layer != null else 1.0

        # The sensors and the evaluator are set up here rather than at
        # construction, because `ToolMachine` swaps the shared settings object in
        # after the tool is built and a stroke wants the one it was handed.
        dynamics.settings = settings
        dynamics.begin_stroke()
        stroke_info.begin(last_mouse_pos, stroke_seed if stroke_seed != 0 else SaPenClock.stroke_seed())
        doc.stroke_transaction.stroke_seed = stroke_info.stroke_seed
        stroke_info.feed_report(pen, SaPenClock.report_ms())
        _pressed_ms = SaPenClock.now_ms()
        sampled_dabs.clear()
        last_dab = null
        _dab_stride = 1

        # **A pen's press dab waits for the first motion's pressure**, as in
        # Krita: a press carries none and Windows Ink hovers at 0. A press held
        # still lays it at [constant PRESS_WAIT_MS] all the same. A tiltless
        # pen hovers as a mouse does, so once it has touched it is held too. A
        # tap with no motion takes the hover's pressure or the pen's last touch
        # when a pen was seen, and 1 otherwise. A mouse paints at once at 1.
        var seen := _pointer.pen_seen or _pointer.pen_touched
        last_pressure = (last_pressure if last_pressure > 0.0 else _touch_pressure) if seen else 1.0
        _press_held = is_tablet or _pointer.pen_touched
        _turn.press(settings)
        if not _press_held and not _turn.waiting:
            _stamp_brush(last_mouse_pos, 1.0, last_tilt)

    elif is_drawing:
        # A stroke let go before its pointer showed what it is lays what it
        # held back as a mouse's, since nothing showed a pen.
        _pointer.lay_held(_lay_motion, 1.0)
        if _press_held:
            _press_held = false
            if not _turn.waiting:
                _stamp_brush(last_mouse_pos, last_pressure, last_tilt)
        if not _budget.lift_later():
            _lift()


## The pen's lift, once the walk has caught up with it.
func _lift() -> void:
    var doc: SaDocument = document()
    _walk_stabilizer_finish()
    _finish_stroke_interpolation()
    _turn.lay_unturned(_stamp_brush, last_mouse_pos, last_pressure, last_tilt)
    _walk_batch.flush()
    SaStrokeNote.commit(doc, _route.erasing)
    _smudge.drop()
    _clear()


func _handle_stroke_motion(event: InputEventMouseMotion) -> void:
    if _budget.lifting:
        return
    var pen := get_document_mouse_position()
    # A plain motion of a pointer that has shown neither a pen nor a mouse waits
    # until one does, or a pen pressed from no pressure opens at a mouse's 1.
    if is_tablet and not _pointer.pen_seen:
        _pointer.hold(pen, SaPenClock.report_ms())
        return
    _pointer.lay_held(_lay_motion, 0.0 if is_tablet else 1.0)
    # Read raw pressure (force 1.0 if using mouse)
    _lay_motion(pen, SaPenClock.report_ms(), event.pressure if is_tablet else 1.0, event.tilt)


## Lays one motion of the stroke, at *pen* reported at *reported_ms*, whether
## it came just now or was held back until the pointer showed what it is.
func _lay_motion(pen: Vector2, reported_ms: float, raw_pressure: float, tilt: Vector2) -> void:
    # The speed is the pen's, read once a report where it arrived and when it was
    # made, so a burst of reports reads the pen rather than the dabs walked.
    stroke_info.feed_report(pen, reported_ms)
    # Smoothed first, interpolated after, so the dabs land along the smoothed
    # path rather than being smoothed once they have landed.
    var tex_pos: Vector2 = stabilizer.feed(pen, reported_ms)
    var touch := _pointer.touched(raw_pressure, is_tablet)
    if _press_held:
        # At the press point, so the walk from it is the one it always was.
        _press_held = false
        last_pressure = raw_pressure
        _touch_pressure = raw_pressure if touch else _touch_pressure
        if not _turn.waiting:
            _stamp_brush(last_mouse_pos, raw_pressure, last_tilt)

    _budget.push(tex_pos, raw_pressure, tilt)
    _take()


## Walks what the frame has room for of the carried stroke, or all of it, and
## lifts the pen once the last dab is laid if the lift was kept for it.
func _take(all: bool = false) -> void:
    _walk_batch.open(settings)
    var carried := func(at: Vector2, pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
        return _before_walk(_sample(at, pressure, tilt))
    var done := _budget.take(carried, stroke_distance, _stamp_brush, all)
    _walk_batch.close(_bind_tip)
    if done and _budget.lifted():
        _lift()


## The tip's radius in document pixels before any modulation.
##
## The document is the authority on size: the radius is a fraction of its
## `brush_side`, which a crop keeps so the brush keeps its pixels. A tool built
## before any document asks for the cursor radius, so it gets a sane default.
func _base_radius() -> float:
    var doc: SaDocument = document()
    if doc == null:
        return settings.radius * 1080.0
    return settings.radius * doc.brush_side


func get_cursor_radius() -> float:
    if surface == null:
        return -1.0
    # The ring is the tip at full pressure, which is what the size option answers
    # at the top of its curve whether or not it is switched on, so this needs no
    # sample and no evaluator.
    return maxf(0.05, _base_radius())


## Takes one sample of the stroke and walks the segment it completes.
##
## The segment is the one before the newest, along the curve `SaStrokeCurve`
## draws through the samples either side of it, so the stroke's end trails the
## pen by one report and the last segment is walked at pen up. The press opens
## the curve at the first sample it sees after it.
func _process_stroke_interpolation(tex_pos: Vector2, raw_pressure: float, tilt: Vector2) -> void:
    _walk(_sample(tex_pos, raw_pressure, tilt))


## Takes one sample and answers the segment it completes, or null.
func _sample(tex_pos: Vector2, raw_pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
    var span: SaStrokeCurve.Span = null
    if has_last_pos:
        if _curve.is_empty():
            _curve.begin(last_mouse_pos, last_pressure, last_tilt)
        span = _curve.feed(tex_pos, raw_pressure, tilt, SaStrokeTurn.fan_degrees(settings))
    has_last_pos = true
    last_mouse_pos = tex_pos
    last_pressure = raw_pressure
    last_tilt = tilt
    return span


## Walks what the stabiliser still owes at pen up, as motions at the last
## one's pressure and tilt, so the stroke ends where the pen lifted.
func _walk_stabilizer_finish() -> void:
    for owed in stabilizer.finish():
        _process_stroke_interpolation(owed, last_pressure, last_tilt)


## Walks the stroke's last segment, which waited for a sample that is not
## coming, at pen up and before the stroke is committed.
func _finish_stroke_interpolation() -> void:
    _walk(_curve.finish(SaStrokeTurn.fan_degrees(settings)))


## Walks one segment of the stroke whole, [class SaWalkBudget.Walk].
func _walk(span: SaStrokeCurve.Span) -> void:
    if span == null:
        return
    _walk_batch.open(settings)
    SaWalkBudget.walk(_before_walk(span), stroke_distance, _stamp_brush)
    _walk_batch.close(_bind_tip)


## What the turn owes before *span* is walked, the press dab or a corner's
## fan, [class SaStrokeTurn], and *span*.
func _before_walk(span: SaStrokeCurve.Span) -> SaStrokeCurve.Span:
    return _turn.before_walk(span, settings, stroke_distance, stroke_info, _stamp_brush)


## Feeds one dab's sample to the dynamics and dispatches the dab it answers
## with. The speed it reads is the pen's reports', never the dabs'.
##
## *tilt* defaults to none because two suites in the skeleton stamp one dab by
## hand to read a texel back, and a pen that is not leaning is what they meant.
##
## What the dynamics compute arrives as one `SaDabParams`, and what is done here
## is the half the seam keeps on this side: the document's colour space and the
## dispatch. The dynamics half never sees a colour, and the three colour offsets
## do not change that: it fills three numbers and the colour they move is built
## here, and Darken and Mix are two more numbers on the same footing.
func _stamp_brush(pos: Vector2, raw_pressure: float, tilt: Vector2 = Vector2.ZERO) -> void:
    var doc: SaDocument = document()
    stroke_info.hovering = false
    stroke_info.feed_dab(pos, raw_pressure, tilt, 0.0, SaPenClock.now_ms() - _pressed_ms, settings.maker_pressure_curve)
    stroke_info.next_dab()
    stroke_info.texture = dab_pattern.sensor_reading(settings, pos, stroke_info)

    var dab := dynamics.evaluate(stroke_info, 2.0 * _base_radius())
    var reads := _walk_batch.reads(settings, _density)

    # The picker speaks the document's gamut through sRGB's curve and the canvas
    # stores whatever the document declared. Writing the picked colour straight
    # in is correct for an RGB document on the sRGB curve and wrong for every
    # other one: mid grey landed in a linear document as 0.5, where it means
    # 0.214, so the paint came out lighter than the swatch that produced it.
    # Exactly a passthrough there, so nothing anyone has already painted moves.
    # The source's pick and the colour options first, on the picker's sRGB and
    # before the conversion below, since Oklab is defined against linear sRGB. A
    # plain brush no option modulates gets its colour back to the bit. The
    # background, which a plain Mix blends towards and a default ramp ends at,
    # is read off the settings so one resource holds everything a dab is from.
    var doc_space: SaColorSpace = doc.color_space if doc != null else null
    var shifted := SaColorDynamics.apply(
        settings.color, dab, reads.background, doc_space, settings.color_source, settings.gradient_ramp
    )
    var picked: Color = reads.picked(shifted, doc_space)
    # No exposure here: the paint exposure is the foreground's own stops in
    # `SaColors`, so the colour is painted as it was picked.
    # Build-up carries the stroke opacity on the dab, and so does a coverage
    # stroke, which writes straight in where no buffer composite can apply it.
    # Wash carries it on the stroke and gives the dab the tip's opacity alone.
    var dab_alpha: float = dab.opacity if reads.washing and not _writes_straight_in() else dab.opacity * settings.opacity
    dab.color = Color(picked.r, picked.g, picked.b, dab_alpha)

    _remember(dab)
    _dispatch_brush(dab)


## Keeps a spread of dabs for a state dump, oldest first.
##
## Exponential decimation, which is the cheap way to hold a sample of a sequence
## whose length nobody knows in advance: keep one in `_dab_stride`, and when the
## list fills, throw away every second entry and double the stride. The first dab
## of the stroke is always in it, and the rest are evenly spaced over whatever
## the stroke turned out to be.
func _remember(dab: SaDabParams) -> void:
    last_dab = dab
    if stroke_info.dab_index % _dab_stride != 0:
        return
    sampled_dabs.append(dab)
    if sampled_dabs.size() <= SAMPLED_DABS:
        return
    var kept: Array[SaDabParams] = []
    for i in range(sampled_dabs.size()):
        if i % 2 == 0:
            kept.append(sampled_dabs[i])
    sampled_dabs = kept
    _dab_stride *= 2


## Dispatches one dab.
##
## The chunk tiling, 8-alignment, direct-versus-buffered targeting and
## invalidation are SaPaintContext's rather than this module's, because every
## tool would otherwise copy them. It also clamps the workgroup count, so a
## sub-8px dab never dispatches zero groups.
func _dispatch_brush(dab: SaDabParams) -> void:
    var doc := document()
    if doc == null:
        return
    var reads := _walk_batch.reads(settings, _density)
    var view: SaView = surface.view if surface != null else null
    var placed := SaStampPlacement.new(dab, settings, reads, _stroke.tip(_tip()), view, doc.canvas_size.x)
    var pos := placed.position
    var tip := placed.tip
    var stroke_color := dab.color

    # The stroke's route, settled at the press. Build-up still paints an erase
    # and an alpha-locked stroke straight into the active layer, because that is
    # what build-up means. Wash sends them through the stroke buffer, so a
    # stroke crossing itself deposits once.
    var is_erasing: bool = _route.erasing

    # A dab the kernel cannot write, too small or wholly off the canvas, is
    # skipped rather than dispatched. The walk is still told where the sample
    # fell and what step it asked for, because the accumulator decides where the
    # next sample goes, and the distance, the angle and the spacing follow the
    # path the pen took and not the chord back. The step is the one this dab
    # really asked for rather than the floor's, so a size ramp coming back up
    # through the guard resumes where it would have.
    var paint: SaPaintContext = null
    if not placed.too_small:
        paint = _walk_batch.paint_for(doc, placed.region, _route.direct, dab.smudge, dab.stretch > 0.0, _route.blurring)
    if paint == null or paint.is_empty():
        stroke_distance.register_dab(pos, reads.step_for(tip, dab.spacing), stroke_color.a, reads.interval, false)
        return

    var mode_val: int = _route.dab_mode()
    var alpha_lock_val := _route.dab_alpha_lock()
    # The quick mask and a layer's or a filter's mask: coverage rather than
    # colour, straight into whichever mask the paint context chose on its own.
    # The chosen colour paints its lightness in the document's own numbers,
    # black hiding or deselecting, white showing or selecting and grey between,
    # which is Krita's rule for a mask and for its selection alike, and the
    # eraser takes coverage away. The dab's alpha carries opacity and flow over
    # it as over paint. Coverage is a fraction, so a colour past white shows
    # fully rather than writing above 1. The context's one flag is asked rather
    # than the document, so this engine never names the selection.
    if paint.paints_coverage:
        var light: float = doc.color_space.lightness(stroke_color) if doc.color_space != null else stroke_color.v
        var cover := 0.0 if is_erasing else clampf(light, 0.0, 1.0)
        stroke_color = Color(cover, cover, cover, stroke_color.a)
        mode_val = SaDabGeometry.PaintMode.OVER
        alpha_lock_val = false

    # The dab's block, packed once for as long as every number it is packed
    # from but the sequence holds, and placed on each target as it goes.
    var record := reads.record(
        tip,
        dab,
        stroke_color,
        placed.half_extent,
        placed.radians,
        placed.fade,
        mode_val,
        alpha_lock_val,
        placed.mirror_bits,
        float(stroke_distance.dab_sequence)
    )
    # A walk's plain dab waits for the walk's end and goes with its others as
    # one dispatch a chunk, and [SaWalkBatch] says which wait.
    # One that goes now sends what the walk held first, so the card paints in
    # the order the walk laid.
    var alone := reads.goes_alone(dab, tip, tip_mask, _stroke.masking(settings.masking))
    if _walk_batch.hold(paint, reads.packing(paint.chunk_size, stroke_info), dab.pattern_strength, alone, _bind_tip):
        stroke_distance.register_dab(pos, reads.step_for(tip, dab.spacing), stroke_color.a, reads.interval)
        return
    _walk_batch.send(_bind_tip)
    _bind_tip(compute)
    # The paper over the stand-in the tip's binder just put on binding 4.
    dab_pattern.bind(compute, settings, dab.pattern_strength)
    # The smudge stage's pickup, before the dab reads what it carried, and the
    # carry or the stand-in on binding 6 either way.
    if dab.smudge:
        var moves: bool = settings.smudge_move_height and not is_erasing and not paint.paints_coverage
        _smudge.pick_up(dab, placed, settings, surface, doc, moves, tip_mask)
    var smudged := _smudge.bind(compute, dab, is_erasing, paint)
    # The height the eraser lowers. Only a stroke erasing straight into a layer
    # lowers its height here. A buffered one is lowered by the document as each
    # dab's region lands, and a mask's chunk is the layer's but its paint is not.
    var lowers := paint.draw_direct and not paint.paints_coverage
    # A smudge that moves height binds the layer's own instead.
    var dispatcher := func(target: SaPaintContext.Target) -> void:
        compute.set_texture(0, target.texture.rid)
        var held := SaStrokeHeights.held(target.chunk if lowers else null)
        compute.set_texture(HEIGHT_BINDING, (smudged.height_for(target.grid_pos, held) if smudged != null else held).rid)
        compute.set_push_constant_float_array(paint.dab(reads.placed(record, target, paint.chunk_size, stroke_info), target))
    # A smudge dab goes the carry's way, [method SaStampSmudge.lay].
    if dab.smudge:
        _smudge.lay(paint, compute, dispatcher, _route.direct and not settings.smudge_sample_merged)
    else:
        paint.dispatch_batch(compute, "dab", dispatcher)
        _walk_batch.invalidate(paint)
    # The half of the walk that closes the loop: the accumulator is told the
    # spacing this dab was painted with, so the next question is asked
    # against it rather than against whatever the segment started at.
    stroke_distance.register_dab(pos, reads.step_for(tip, dab.spacing), stroke_color.a, reads.interval)


## One frame of the airbrush's clock, *delta* the engine's frame, which
## [method SaPenClock.frame_elapsed_ms] answers for unless a replay hands the
## recording's own.
##
## The pointer is not moving, so there is no input event to hang this on and no
## travel for the distance walk to measure. The accumulator is fed a segment of
## no length and the frame's own elapsed milliseconds, which is exactly what its
## timed walk was written for, and every parameter the dab reads comes from the
## last sample rather than from a new one: an airbrush that is not moving has
## nothing new to read.
##
## **Nothing happens when the airbrush is off**, which is one property read a
## frame for every other brush and every other tool. A resting pen's
## stabiliser closes on it first, by the stabiliser's `follow`.
##
## **The paper is settled here while no stroke runs**, so a
## preset whose curves read the texture sensor has its tile read back within a
## frame of the paper or the curve changing, whatever changed it: the brush
## editor, a preset, a door's `brush` step. A press with no hover before it,
## which is a door's stroke, finds the paper on the CPU already. Past the first
## frame after a change it is the curves walked and a key compared.
func tick(delta: float) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    if is_drawing and not _press_held and not _budget.lifting and stabilizer.follow(SaPenClock.now_ms()):
        _budget.push(stabilizer.answer, last_pressure, last_tilt)
    _take()
    _budget.frame()
    lay_waited_press(SaPenClock.now_ms())
    if not is_drawing:
        dab_pattern.prepare(settings)
    for _at: int in airbrush_dabs_for_frame(SaPenClock.frame_elapsed_ms(delta) / 1000.0):
        _stamp_brush(last_mouse_pos, last_pressure, last_tilt)
    _smudge.submit()


## Lays the press dab a pen has held still for [constant PRESS_WAIT_MS] by
## *now_ms*, at the pressure the press took, and answers whether it did.
func lay_waited_press(now_ms: float) -> bool:
    if not is_drawing or not _press_held or now_ms - _pressed_ms < PRESS_WAIT_MS:
        return false
    _press_held = false
    if not _turn.waiting:
        _stamp_brush(last_mouse_pos, last_pressure, last_tilt)
    return true


## How many dabs this frame's airbrush clock owes, and it advances that
## clock.
##
## The decision, without the dispatch, so a suite can advance the clock by hand
## and count what a held pen deposits over an interval it measured itself. A
## count read against a frame number rather than against a time is the failure
## this guards, and nothing outside the app can produce that count without it.
##
## Zero when the pen is up, when the airbrush is off, or when the interval has
## not come round. Never more than [constant SaDabCadence.MAX_DABS_PER_FRAME].
## The pen being down is the only half of that question this tool answers, and
## the rest is arithmetic on the walk.
func airbrush_dabs_for_frame(delta: float) -> int:
    if not is_drawing or _press_held or _turn.waiting:
        return 0
    return SaDabCadence.dabs_for_frame(stroke_distance, last_mouse_pos, SaDabCadence.interval_for(settings), delta)


## The step *dab* asks for: [SaDabCadence] plus what the cadence cannot see, whether this
## brush's airbrush ignores spacing and whether a small dab of it enters the pixel mode.
func _step_for(tip: Resource, dab: SaDabParams) -> SaStrokeDistance.Spacing:
    return _walk_batch.reads(settings, _density).step_for(tip, dab.spacing)


## Whether this brush is erasing: the eraser tool, the E toggle, or the flipped
## end of a pen.
func _is_erasing() -> bool:
    return eraser_toggled or settings.blend_mode == SaLayerScript.BLEND_MODE.ERASE or is_eraser


## Whether the layer this stroke lands on refuses to have its alpha moved.
##
## Read through `in` because the scratchpad in the brush editor paints into a
## document whose layer type is not the one the layers docker makes.
func _is_alpha_locked() -> bool:
    var doc: SaDocument = document()
    var active_layer := doc.active_layer if doc != null else null
    return active_layer != null and "alpha_locked" in active_layer and active_layer.alpha_locked


## Whether this brush is in wash rather than build-up, which a walk's dabs read
## once, see [method SaWalkBatch.Reads.washing_of].
func _is_washing() -> bool:
    return SaWalkBatch.Reads.washing_of(settings)


## Whether this stroke lays coverage straight in rather than gathering it in
## the stroke buffer: a blur on its route's word, a mask, the quick mask.
##
## A mask and the quick mask are not part of the picture, so the paint context
## sends them straight in and the commit hands back before any composite
## ([method SaDocument.commit_stroke]). Wash leaves the stroke opacity on the
## stroke for the buffer's composite to apply, which a coverage stroke never
## reaches, so this is where the dab has to carry it instead. Read here rather
## than copied at the press, because the paint context is what really decides
## and it is asked per dab.
func _writes_straight_in() -> bool:
    var doc: SaDocument = document()
    if doc == null:
        return false
    return _route.direct or doc.mask_target != null or doc.selection.editing


## The tip this brush paints with, and one that means "the old circle" when a
## preset saved before tips existed is loaded over the settings.
func _tip() -> Resource:
    if settings.tip == null:
        settings.tip = SaBrushTipScript.new()
    return settings.tip


## Binds everything the kernel samples onto *onto*, the dab's kernel or the
## walk's, and holds what it bound.
func _bind_tip(onto: SaCompute) -> void:
    var doc: SaDocument = document()
    # The document's own colour space goes with it, because what a lightness
    # shift means depends on what the chunks hold and the kernel cannot ask.
    var space: SaColorSpace = doc.color_space if doc != null else null
    tip_mask = SaStampBindings.bind(onto, _stroke.tip(_tip()), tip_mask, _stroke.masking(settings.masking), stroke_info, space)


## Loads an image tip from *path* and selects it, or says why it could not.
##
## The one door, called by the Load Tip action, by a scenario and by a test. An
## empty path puts the brush back on its procedural generator, which is what the
## Tip dropdown does and is why the two agree without talking.
func load_tip(path: String) -> bool:
    var mask := SaBrushTipMask.select(_tip(), path)
    if not mask.error.is_empty():
        EventBus.paint_refused.emit(mask.error)
        return false
    tip_mask = mask
    tip_loaded.emit(path)
    return true


## The Tip Image list as it stands now, which [SaTipChoices] builds from the
## stored tip and the mask bound last, the tips in the order the door's grid
## draws them. A suite reaches it here, because the tool is what it holds.
func tip_choices() -> Dictionary:
    return SaTipChoices.new(_tip(), tip_mask).choices()


## Whether the picture at *path* is one the brush can paint with, answered by
## [SaTipChoices] from the same two things.
func tip_readable(path: String) -> bool:
    return SaTipChoices.new(_tip(), tip_mask).readable(path)


## The Load Tip action's own method, which opens the dialog and then hands what
## it answers to [method load_tip].
func load_tip_dialog() -> void:
    SaBrushTipMask.choose_file(load_tip)


## The five blocks a capture's state dump takes from the brush: the dynamics
## vocabulary, the preset migration, the pressure ramp, the last dabs and the walk
## of the last stroke. The arithmetic is `SaBrushCaptureReport`'s, and lives in
## the module because the skeleton has to boot with `modules/` empty, so the
## tool answers the capture rather than the skeleton naming the brush's classes.
func capture_report(tool_name: StringName, active: bool) -> Dictionary:
    return SaBrushCaptureReport.new(self, String(tool_name), active).blocks()
