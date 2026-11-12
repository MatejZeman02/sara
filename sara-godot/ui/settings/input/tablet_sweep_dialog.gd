## Preferences > Tablet > Calibrate by Sweeping: the scratch card.
##
## Three blocks under a glitter coat, one lying across the dialog, one turned to
## run down it and one turned to run corner to corner. The painter sweeps each
## in one stroke from the dot to the far end, pressing what feels to their hand
## like an even ramp from nothing to full, and the pen scratches the coat off a
## fixed gamma 3 gradient, [`SaTabletSweepStrip`](tablet_sweep_strip.gd). The
## dialog records the raw pressure against **where the pen is along the
## block**, never against time, so however fast the hand goes the coat comes off
## under it and the recording is the same.
##
## At each lift the sweep is checked (`SaTabletSweep.refusal_of`). One that
## began at the far end, stopped short or peaked early is not counted: its coat
## comes back and the line above the blocks says why. When all three count they
## are fitted (`SaTabletSweep.correction_of`) and the curve stands beside the
## blocks. Try It puts the coats back with the correction live, and the pen
## paints over them at the lightness of the pressure it now sends, so a sweep the
## correction fits paints the gradient the first pass revealed. A drag of the
## curve lays the Try It strokes again through it at once.
##
## A block is one left-to-right band in its own space, and the angle its slot
## turns it to is the only thing that decides which way the pen travels.
##
## **The three bands are one size**: each is a third of the height the dialog
## opens into and one thickness, and the slot round it is the box the turned
## band covers. The dialog is sized from the bands rather than the bands from
## the dialog, because the same sweep has to be the same gesture on all three.
##
## Nothing here reads a real pen except `_gui_input` on the strips, for the
## reason `tablet_calibration.gd` gives: an injected motion never reaches
## `gui_input`, so a scenario and a test drive `begin_sweep`, `feed` and
## `end_sweep` directly and everything downstream of the pen event is the real
## path.
@tool
class_name SaTabletSweepDialog
extends SaDialogWindow

## The painter kept a fitted curve. *table* is what to store.
signal curve_accepted(table: PackedFloat32Array)

## The three strips, as the label each carries and the angle it is turned to on
## screen. Zero runs across the dialog, 90 runs down it, and -45 runs from the
## bottom left corner to the top right one, Y being down.
const STRIPS: Array = [
    {"label": "Left to right", "angle": 0.0},
    {"label": "Top to bottom", "angle": 90.0},
    {"label": "Corner to corner", "angle": -45.0},
]

## How thick every band is, in logical pixels.
##
## 72 rather than the 60 it was, because the label under the upright band is as
## wide as the band, and "bottom" at the label's size measured about 62 on the
## capture harness's screen.
const STRIP_THICKNESS := 72.0

## The share of the height the dialog opens into that a band is long, a third of
## the screen's height.
const HOST_SHARE := 1.0 / 3.0

## The height the bands are sized for while the dialog is out of the tree and
## has nowhere to ask.
const UNPLACED_HOST_HEIGHT := 1080.0

## The margin round the column and the gap beside a turned strip, in logical
## pixels, named because `content_minimum` adds them up.
const MARGIN := SaTheme.PAD
const ROW_SEPARATION := SaTheme.GAP

## What the dialog is doing.
enum Phase {
    ## Sweeping the three coats, for the recording.
    RECORD,
    ## The fitted curve is shown beside the strips it redraws, with Keep,
    ## Start Again and Try It.
    REVIEW,
    ## The coats are back and the correction is live, so the painter can see
    ## whether an even hand now leaves an even ramp.
    TEST,
}

var phase: Phase = Phase.RECORD

## One `PackedVector2Array` of `Vector2(along the block, raw pressure)` per
## strip, emptied again when a sweep is not counted.
var sweeps: Array = []

## Per strip, whether its sweep was counted.
var counted: Array[bool] = []

## Per strip, the Try It pen events as `[where on the block, raw pressure,
## whether the pen landed there, whether it lifted after]`, kept so a drag of
## the curve can lay them again.
var _tries: Array = []

## Why the last sweep was not counted, or [constant SaTabletSweep.Refusal.NONE].
var refused: SaTabletSweep.Refusal = SaTabletSweep.Refusal.NONE

var _strips: Array = []
var _strip_section: VBoxContainer = null
## The row the two turned strips stand in, and the fitted curve beside them.
var _turned_row: HBoxContainer = null
var _margin: MarginContainer = null
## Every strip's slot and label, by strip index, so a new length reaches all
## three.
var _slots: Array[Control] = []
var _labels: Array[Label] = []
## How long every band is, in logical pixels. Written only by
## [method size_strips_for_host].
var strip_length: float = 0.0
var _instruction: Label = null
var _editor: SaCurveEditor = null
var _keep_button: Button = null
var _repeat_button: Button = null
var _test_button: Button = null
## The fitted curve, or an empty array before there is one.
var fitted: PackedFloat32Array = PackedFloat32Array()

## The correction that was live before Try It put the fitted one in its place,
## and whether Try It has, so every way out but Keep puts it back.
var _live_before_trying: PackedFloat32Array = PackedFloat32Array()
var _trying: bool = false


func _init() -> void:
    # A placeholder until the first open measures the bands.
    _init_dialog("TabletSweepDialog", tr("Calibrate by Sweeping"), Vector2i(520, 620), Vector2i(420, 520))

    _margin = SaMake.margin(content, "Margin", MARGIN)
    _margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(_margin, "Column", SaTheme.GAP)
    # The words and the strips scroll when the host is shorter than they are,
    # so the buttons stay on it. At an interface scale of 2 the dialog opened
    # 584 tall in a window 512 tall, with Keep under the bottom edge.
    var middle_view := SaMake.scroll(column, "MiddleScroll")
    middle_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    middle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = middle_view
    var middle := SaMake.column(middle_view, "Middle", SaTheme.GAP)
    middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _instruction = SaMake.label(middle, "Instruction")
    _instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    for index in range(STRIPS.size()):
        _labels.append(_make_label(index))
        _slots.append(_make_strip(index))

    _build_strip_section(middle)

    _editor = SaCurveEditor.new()
    _editor.name = "FittedCurve"
    # Small enough to stand in the row beside the two turned strips rather than
    # under them. Stacked, the curve and the three strips together needed 630
    # logical pixels of a dialog that opens at 620, and the review answered that
    # by hiding the strips. Beside them it costs no height at all, and the
    # geometry report says the content fits again.
    _editor.custom_minimum_size = Vector2(float(SaUI.px(120)), float(SaUI.px(110)))
    _editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Live rather than a picture. The painter is meant to tune the fit by hand,
    # and the three strips beside it are what says whether the tuning helped, so
    # every drag repaints them.
    _editor.curve_changed.connect(_on_curve_dragged)
    _editor.visible = false
    _turned_row.add_child(_editor)

    # Cancel first and Keep last, the order of every dialog's row. The cross was
    # the only other way out, and `_on_closed` takes back a curve Try It put
    # live by either route.
    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    _repeat_button = SaMake.button(buttons, "RepeatButton", tr("Start Again"))
    _repeat_button.pressed.connect(restart)
    _test_button = SaMake.button(
        buttons, "TestButton", tr("Try It"), tr("Clear the test strokes and try again with the new curve.")
    )
    _test_button.pressed.connect(enter_test)
    _keep_button = SaMake.button(buttons, "KeepButton", tr("Keep"))
    _keep_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    _keep_button.pressed.connect(_on_keep)

    size_strips_for_host(UNPLACED_HOST_HEIGHT)
    visibility_changed.connect(_on_shown)
    visibility_changed.connect(_on_closed)
    # Deferred, so a label that rewraps once it is laid out is measured after it
    # has.
    _margin.minimum_size_changed.connect(_grow_to_content, CONNECT_DEFERRED)
    restart()


## The three strips as they sit on screen: the flat one across the top, and
## under it the diagonal beside the upright one, rather than three full-width
## rows stacked, which leave a turned strip no room to be turned in.
##
## Every label stands under its own strip, and every slot is exactly the box its
## band turns into rather than a share of the room, so nothing a container hands
## out can change a band's length, and a label under a narrow slot does not wrap
## a letter a line.
func _build_strip_section(column: VBoxContainer) -> void:
    _strip_section = SaMake.column(column, "Strips", 6)
    _strip_section.size_flags_vertical = Control.SIZE_EXPAND_FILL

    # At the left rather than stretched, so the flat band stands above the two
    # turned ones and its label is its own width.
    _slots[0].size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _labels[0].size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _strip_section.add_child(_slots[0])
    _strip_section.add_child(_labels[0])

    _turned_row = SaMake.row(_strip_section, "TurnedStrips", ROW_SEPARATION)
    _turned_row.size_flags_vertical = Control.SIZE_EXPAND_FILL

    for turned: Array in [["DiagonalColumn", 2], ["UprightColumn", 1]]:
        var strip_column := SaMake.column(_turned_row, String(turned[0]), 6)
        strip_column.add_child(_slots[int(turned[1])])
        strip_column.add_child(_labels[int(turned[1])])


## The label naming a strip's direction. It is small on purpose: once a strip
## is turned the way it is swept, the words are a confirmation rather than the
## only clue.
func _make_label(index: int) -> Label:
    var spec: Dictionary = STRIPS[index]
    var label := SaMake.label(null, "Strip%dLabel" % index, tr(String(spec["label"])))
    # Between words only. `AUTOWRAP_WORD_SMART` breaks a word that does not fit,
    # which is how "bottom" came out a letter a line.
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    SaTheme.bind_font(label, "text_muted")
    return label


## One strip in a slot of its own. The slot is what a container lays out, and
## the band inside it is turned and centred by hand, because a Container writes
## a child's position and size every layout pass and would undo both.
func _make_strip(index: int) -> Control:
    var spec: Dictionary = STRIPS[index]
    var degrees := float(spec["angle"])

    var slot := Control.new()
    slot.name = "Strip%dSlot" % index
    slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var strip := SaTabletSweepStrip.new()
    strip.name = "Strip%d" % index
    strip.moved.connect(_on_strip_moved.bind(index))
    strip.released.connect(end_sweep.bind(index))
    slot.add_child(strip)
    slot.resized.connect(func() -> void: _centre_strip(slot, strip, degrees))

    _strips.append(strip)
    sweeps.append(PackedVector2Array())
    counted.append(false)
    _tries.append([])
    return slot


## Turns *strip* to *degrees* and centres it in *slot*. The band's size is set
## already, so this only places it, again whenever a container hands the slot a
## new size.
static func _centre_strip(slot: Control, strip: Control, degrees: float) -> void:
    var room := slot.size.max(slot.custom_minimum_size)
    strip.pivot_offset = strip.size * 0.5
    strip.rotation_degrees = degrees
    strip.position = (room - strip.size) * 0.5
    strip.queue_redraw()


## The box a band of size *band* covers once turned by *degrees*. A band of
## length L and thickness T turned by a covers `L*|cos a| + T*|sin a|` by
## `L*|sin a| + T*|cos a|`, rounded up so a slot never clips a corner, less a
## thousandth so the cosine of 90 degrees does not round a whole pixel on.
static func turned_box(band: Vector2, degrees: float) -> Vector2:
    var radians := deg_to_rad(degrees)
    var across := absf(cos(radians))
    var down := absf(sin(radians))
    return Vector2(ceilf(band.x * across + band.y * down - 0.001), ceilf(band.x * down + band.y * across - 0.001))


## Every band *host_height* times [constant HOST_SHARE] long and
## [constant STRIP_THICKNESS] thick, every slot the box its band turns into, and
## every label as wide as that box.
##
## Public because the test drives it at two heights, and a dialog out of the
## tree has no host to ask. The length never comes from the slot any more,
## which is what left one dialog's bands 496, 199 and 301 long.
func size_strips_for_host(host_height: float) -> void:
    var thickness := SaUI.pxf(STRIP_THICKNESS)
    strip_length = maxf(roundf(host_height * HOST_SHARE), thickness * 2.0)
    var band := Vector2(strip_length, thickness)
    for index in range(_strips.size()):
        var degrees := float(STRIPS[index]["angle"])
        var box := turned_box(band, degrees)
        var strip: SaTabletSweepStrip = _strips[index]
        strip.size = band
        _slots[index].custom_minimum_size = box
        _labels[index].custom_minimum_size = Vector2(box.x, 0.0)
        _centre_strip(_slots[index], strip, degrees)


## The height the dialog opens into, in logical pixels: the main window's below
## its top bar for an embedded dialog, which cannot leave it, and the usable
## screen's for one the OS hosts.
func _host_height() -> float:
    var host := host_rect().size
    if host.y <= 0:
        return UNPLACED_HOST_HEIGHT
    if is_embedded():
        return float(host.y)
    return float(host.y) / SaUI.window_scale(self)


## Every open sizes the bands from where the dialog is opening and the window
## from the bands, then centres it again, because `popup_centered` centred the
## size the window had before.
func _on_shown() -> void:
    if not visible or not is_inside_tree():
        return
    size_strips_for_host(_host_height())
    var wanted := content_minimum()
    logical_min_size = wanted
    logical_size = wanted
    min_size = SaUI.window_size_for(self, wanted)
    size = min_size
    move_to_center()


## A label that rewrapped once laid out, or an instruction that got longer, asks
## for more room than the open measured. The window grows by that much about
## its own centre, so a centred dialog stays centred, and never shrinks, because
## the bands it was sized from have not changed.
##
## The growth is the dialog fit's, so it stops at the host the way every other
## dialog's does. This grew past it on its own, and on a host shorter than the
## strips put Keep under the bottom edge again a frame after the fit had put it
## back.
func _grow_to_content() -> void:
    if not visible or not is_inside_tree():
        return
    var wanted := content_minimum()
    if wanted.x <= logical_min_size.x and wanted.y <= logical_min_size.y:
        return
    logical_min_size = logical_min_size.max(wanted)
    fit_opening_size()


## The smallest the window can be and still show the bands, the words and the
## curve, in logical units.
##
## The curve is hidden until review, and its room is counted from the start, so
## the window is one size in every phase rather than growing when the fit
## arrives. Public because the test reads it.
func content_minimum() -> Vector2i:
    var needed := _margin.get_combined_minimum_size()
    if not _editor.visible:
        var row := _turned_row.get_combined_minimum_size().x + float(SaUI.px(ROW_SEPARATION))
        needed.x = maxf(needed.x, row + _editor.get_combined_minimum_size().x + float(SaUI.px(MARGIN) * 2))
    var bar := maxf(drag_handle.size.y, drag_handle.get_combined_minimum_size().y)
    return Vector2i(int(ceil(needed.x)), int(ceil(needed.y + bar)))


## Back to three whole coats and no recording, which is what opening and Start
## Again both mean.
func restart() -> void:
    phase = Phase.RECORD
    fitted = PackedFloat32Array()
    refused = SaTabletSweep.Refusal.NONE
    for index in range(_strips.size()):
        sweeps[index] = PackedVector2Array()
        counted[index] = false
        _tries[index] = []
        (_strips[index] as SaTabletSweepStrip).clear()
    _sync()


## Starts a stroke on *index*. In the record pass that throws away whatever was
## on that block, coat and recording. Public because a scenario and a test
## drive the sweep directly.
func begin_sweep(index: int) -> void:
    if index < 0 or index >= sweeps.size():
        return
    var strip: SaTabletSweepStrip = _strips[index]
    if phase == Phase.TEST:
        strip.lift()
        return
    if phase != Phase.RECORD:
        return
    sweeps[index] = PackedVector2Array()
    counted[index] = false
    strip.clear()


## One pen event at *along* the block's axis, 0 at the dot and 1 at the far
## end, *across* pixels off its middle, as a scenario and a test describe one.
## The pen's own events arrive through [method _on_strip_moved] in the block's
## pixels instead.
func feed(index: int, along: float, raw_pressure: float, across: float = 0.0) -> void:
    if index < 0 or index >= sweeps.size():
        return
    var strip: SaTabletSweepStrip = _strips[index]
    _take(index, strip.point_at(clampf(along, 0.0, 1.0), across), raw_pressure)


## The pen at *at* on *index*'s block, which scratches in the record pass and
## paints in Try It. A pen off the surface, reading nought, starts nothing.
##
## The reading is taken through the painter's peak pressure first, because a
## stroke reads the correction after that maximum (`SaTablet.normalize`). A
## sweep recorded on the raw scale would be fitted where the peak is a fifth of
## the range and then read where it is all of it, a curve that runs full at
## the lightest touch.
func _take(index: int, at: Vector2, raw_pressure: float) -> void:
    if not is_finite(raw_pressure):
        return
    var strip: SaTabletSweepStrip = _strips[index]
    var pressure := SaTablet.normalize(maxf(raw_pressure, 0.0), SaSettings.tablet_max_pressure, 1.0, PackedFloat32Array())
    match phase:
        Phase.RECORD:
            var sweep: PackedVector2Array = sweeps[index]
            if sweep.is_empty():
                if pressure <= 0.0:
                    return
                begin_sweep(index)
                sweep = sweeps[index]
            sweep.append(Vector2(strip.along_of(at), pressure))
            sweeps[index] = sweep
            strip.scratch_to(at)
        Phase.TEST:
            var tries: Array = _tries[index]
            var landing := tries.is_empty() or bool(tries[tries.size() - 1][3])
            if landing and pressure <= 0.0:
                return
            tries.append([at, pressure, landing, false])
            strip.paint_to(at, lightness_of(pressure))


## Ends the stroke on *index*. In the record pass the sweep is counted or
## refused, and the third counted one fits.
func end_sweep(index: int) -> void:
    if index < 0 or index >= sweeps.size():
        return
    var strip: SaTabletSweepStrip = _strips[index]
    strip.lift()
    if phase == Phase.TEST:
        var tries: Array = _tries[index]
        if not tries.is_empty():
            tries[tries.size() - 1][3] = true
        return
    if phase != Phase.RECORD or (sweeps[index] as PackedVector2Array).is_empty():
        return
    refused = SaTabletSweep.refusal_of(sweeps[index])
    if refused != SaTabletSweep.Refusal.NONE:
        sweeps[index] = PackedVector2Array()
        counted[index] = false
        strip.clear()
        _sync()
        return
    counted[index] = true
    if _all_counted():
        _fit()
    else:
        _sync()


## What Try It paints for *raw_pressure*: the pressure through [member fitted],
## shown on the gradient's own scale.
##
## On that scale full is the sweep's own full, the corrected
## [constant SaTabletSweep.SWEEP_PEAK] the hand's peak is given, so a sweep the
## correction fits paints black to white as the gradient does, and a press into
## the room above the sweep stays white.
func lightness_of(raw_pressure: float) -> float:
    return clampf(SaTablet.correct(raw_pressure, fitted) / SaTabletSweep.SWEEP_PEAK, 0.0, 1.0)


## Every Try It stroke laid again through [member fitted], which is what a drag
## of the curve means.
func _repaint_tries() -> void:
    for index in range(_strips.size()):
        var strip: SaTabletSweepStrip = _strips[index]
        strip.clear_paint()
        for event: Array in _tries[index]:
            if bool(event[2]):
                strip.lift()
            strip.paint_to(event[0], lightness_of(float(event[1])))
        strip.lift()


func _all_counted() -> bool:
    for each: bool in counted:
        if not each:
            return false
    return counted.size() == SaTabletSweep.SWEEP_COUNT


func _fit() -> void:
    fitted = SaTabletSweep.correction_of(sweeps)
    if not fitted.is_empty():
        # Before the phase changes, on purpose. `set_points` emits
        # `curve_changed` like a drag does, and the handler would answer it by
        # replacing the 256 entry fit with the curve drawn from it.
        _editor.set_points(_curve_points(fitted))
    phase = Phase.REVIEW
    _sync()


## A drag of the fitted curve. The table is taken from the editor rather than
## refitted, because the point of the drag is that the painter disagreed with
## the fit. In Try It the dragged curve is the live one, and the strokes over
## the coats are laid again through it at once.
func _on_curve_dragged() -> void:
    if phase == Phase.RECORD:
        return
    fitted = _editor.samples(SaTabletSweep.SAMPLES)
    if phase == Phase.TEST:
        SaTablet.correction = fitted.duplicate()
        _repaint_tries()
    _sync()


## The fitted table as a handful of points, so the editor draws it as a curve
## rather than as 256 segments. Nine is enough to show the shape and few
## enough that the painter can see them.
static func _curve_points(table: PackedFloat32Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(9):
        var t := float(i) / 8.0
        var index := int(round(t * float(table.size() - 1)))
        points.append(Vector2(t, table[index]))
    return points


## The coats return with the correction live, so the painter sweeps again and
## the pen paints the pressure it now sends.
func enter_test() -> void:
    if fitted.is_empty():
        return
    if not _trying:
        _live_before_trying = SaTablet.correction.duplicate()
        _trying = true
    SaTablet.correction = fitted.duplicate()
    phase = Phase.TEST
    for index in range(_strips.size()):
        _tries[index] = []
        (_strips[index] as SaTabletSweepStrip).clear()
    _sync()


func _on_keep() -> void:
    if fitted.is_empty():
        hide()
        return
    # Kept, so what Try It put live stays, and the store it goes to is the
    # listener's.
    _trying = false
    curve_accepted.emit(fitted.duplicate())
    hide()


## Every way out but Keep keeps nothing: Cancel, the cross and a plain hide put
## back the correction Try It replaced, so a painter who tries a curve and
## closes the window does not go on painting through a curve nobody kept.
func _on_closed() -> void:
    if visible or not _trying:
        return
    _trying = false
    SaTablet.correction = _live_before_trying


func _on_strip_moved(at: Vector2, raw_pressure: float, index: int) -> void:
    _take(index, at, raw_pressure)


## The instruction, which buttons are live, and whether the fitted curve has a
## place, from the phase alone.
##
## The strips never go away. In review they are the answer to what the curve
## does, so the curve joins them rather than replacing them, and the editor
## shares the room with them.
func _sync() -> void:
    _editor.visible = phase != Phase.RECORD and not fitted.is_empty()
    _keep_button.disabled = fitted.is_empty()
    _test_button.disabled = fitted.is_empty() or phase == Phase.TEST
    _repeat_button.disabled = false
    match phase:
        Phase.REVIEW:
            _instruction.text = tr(
                (
                    "All three sweeps count, and the orange line is the correction they make. "
                    + "Drag it to tune it, then keep it, start again, or try it on the coats."
                )
            )
        Phase.TEST:
            _instruction.text = tr(
                (
                    "The coats are back and the new curve is live. Sweep each block again: the pen "
                    + "paints the pressure it now sends, black at nothing and white at full, and a "
                    + "curve that fits your hand paints the gradient you scratched. Drag the curve "
                    + "and your strokes follow."
                )
            )
        _:
            var ask := tr(
                (
                    "Sweep each block in one stroke from the dot to the far end, pressing from "
                    + "nothing to full. The pen scratches the coat off a gradient from black to "
                    + "white, and the gradient is the even ramp to aim your hand at."
                )
            )
            var why := _refusal_text()
            _instruction.text = ask if why.is_empty() else "%s\n%s" % [why, ask]


## Why the last sweep was not counted, a line above the instruction, or
## nothing when it was.
func _refusal_text() -> String:
    match refused:
        SaTabletSweep.Refusal.TOO_FEW:
            return tr("That was a tap rather than a sweep, so it was not counted.")
        SaTabletSweep.Refusal.FAR_END:
            return tr("That sweep began at the far end, so it was not counted. Start at the dot.")
        SaTabletSweep.Refusal.SHORT:
            return tr("That sweep stopped short of the far end, so it was not counted. Sweep a little slower.")
        SaTabletSweep.Refusal.EARLY_PEAK:
            return tr("That sweep pressed hardest too early, so it was not counted. Sweep slower, pressing harder all the way.")
    return ""
