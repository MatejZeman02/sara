## Preferences > Tablet: what the pen is reporting, and where its usable travel
## ends.
##
## Sara cannot ask a driver what a pen's comfortable range is, and the figure
## that was compiled into the brush was one measurement on one machine. So the
## app measures it instead: press on the strip, push as hard as a stroke ever
## goes, and the hardest reading becomes full pressure.
##
## The strip reads the axis in `_gui_input`, and everything downstream of that
## goes through `sample_pressure()`. That split is not decoration: an injected
## mouse motion never reaches `gui_input`, so a test that pushed events at this
## page would exercise nothing at all, and the only honest way to drive it from
## a suite is to call the logic directly.
@tool
class_name SaTabletCalibration
extends VBoxContainer


## The strip a pen is dragged across.
##
## It draws what it is hearing, because a calibration you cannot see is
## indistinguishable from a driver reporting nothing. The axis is the whole
## hardware range, 0 to 1, so the marker at the calibrated maximum shows how much
## of the pen's travel is being thrown away.
class PressurePad:
    extends Control

    signal sampled(raw_pressure: float)

    ## Darker than the page behind it, and outlined. At the panel's own colour the
    ## strip was invisible, so an untouched pad read as a missing control rather
    ## than as an empty one. Read from the palette at draw time, so a theme
    ## switch recolours the gauge on its next redraw.

    ## The reading arriving right now, the hardest one so far, and the calibrated
    ## maximum. All three on the same 0 to 1 axis.
    var raw: float = 0.0
    var peak: float = 0.0
    var ceiling: float = SaTablet.DEFAULT_MAX_PRESSURE

    ## What the same reading becomes by the time the brush sees it: the maximum
    ## applied and the sweep correction through it, at a gamma of one.
    ##
    ## A second overlay rather than a second gauge, because the two numbers are
    ## nothing alike on a pen whose usable travel ends early. At a maximum of
    ## 0.6 a hardware 0.3 is a stroke pressure of 0.5, and the page said so in
    ## words at the bottom while the gauge went on showing only the hardware
    ## half.
    var stroke: float = 0.0

    ## How much of the pad's height the hardware lane takes, the rest being the
    ## Sara one.
    ##
    ## **Two lanes rather than two bars over each other.** An overlay drawn over
    ## the green one is unreadable exactly where it matters, which is wherever
    ## the two nearly agree, and a painter reading this page is comparing them.
    ## Stacked, both are always legible and the difference is a step in the
    ## middle of the pad rather than a colour to judge.
    const HARDWARE_LANE: float = 0.55

    func _init() -> void:
        custom_minimum_size = Vector2(0, float(SaUI.px(56)))
        tooltip_text = tr("Press here with your pen and push as hard as you would while painting.")

    ## Every motion event carries the axis, including the ones with nothing on it.
    ## Those are forwarded too, so the readout drops back to zero when the pen
    ## lifts rather than freezing at the last number it saw.
    func _gui_input(event: InputEvent) -> void:
        var pressure := SaTablet.pressure_of(event)
        if pressure >= 0.0:
            sampled.emit(pressure)

    func show_state(now: float, hardest: float, calibrated: float, sara: float = 0.0) -> void:
        raw = now
        peak = hardest
        ceiling = calibrated
        stroke = sara
        queue_redraw()

    ## Where each lane sits, in pixels down the pad. Answered rather than
    ## computed twice, because the draw and the capture step both want it and a
    ## proof that measured the wrong band would prove nothing.
    func lane_rects() -> Dictionary:
        var split := roundf(size.y * HARDWARE_LANE)
        return {
            "hardware": Rect2(Vector2.ZERO, Vector2(size.x, split)),
            "sara": Rect2(Vector2(0.0, split), Vector2(size.x, size.y - split)),
        }

    func _draw() -> void:
        var track := Rect2(Vector2.ZERO, size)
        draw_rect(track, SaTheme.palette.bg_track)
        var lanes := lane_rects()
        _draw_lane(lanes["hardware"], raw, SaTheme.palette.accent_gauge)
        _draw_lane(lanes["sara"], stroke, SaTheme.palette.accent_stroke)
        # The markers cross both lanes, because the calibrated maximum is what
        # turns one into the other and a marker in one lane only would read as
        # belonging to that one.
        if peak > 0.0:
            _draw_marker(peak, SaTheme.palette.text_muted)
        _draw_marker(ceiling, SaTheme.palette.accent_ceiling)
        draw_rect(track, SaTheme.palette.border_secondary, false, 1.0)

    ## One lane filled to *value* of its width. A lane with nothing in it is
    ## drawn as nothing rather than as a hairline, which is what says a pen is
    ## reaching Sara as a mouse.
    func _draw_lane(lane: Rect2, value: float, color: Color) -> void:
        var filled := clampf(value, 0.0, 1.0) * lane.size.x
        if filled <= 0.0:
            return
        draw_rect(Rect2(lane.position, Vector2(filled, lane.size.y)), color)

    func _draw_marker(at: float, color: Color) -> void:
        var x := clampf(at, 0.0, 1.0) * size.x
        draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, 2.0)


## The line under the strip: the live reading, the hardest, how many readings,
## and what the brush is sent. It stays one line, every figure beside its label.
##
## Wrapped by word, the line broke wherever the page ran out, and on a 1280
## window that put the `0%` of "Stroke pressure" on a line of its own, a figure
## with no label. So the label does not wrap: it is written in the longest form
## that fits the width it has, the labels shortening first, and only a page
## narrower than the shortest form breaks it between its figures, two to a line
## and then one, each figure still beside its label, and only a page narrower
## than one figure ends it in an ellipsis. A language longer than English needs
## the breaks: the test language's shortest form is 737 pixels where the page
## gives 615. The ellipsis is also what keeps its minimum width small: an
## unwrapped Label with none asks for its whole line, and that pushes the page
## wider than its pane.
class Readout:
    extends RefCounted

    ## Longest first, and each a form of the one before, shorter by its last
    ## label and then by its spaces. The labels are one set in every form, so a
    ## narrow page says the same words as a wide one.
    const FORMS: Array[String] = [
        "Current %.2f   Peak %.2f   Samples %d   Stroke pressure %d%%",
        "Current %.2f   Peak %.2f   Samples %d   Stroke %d%%",
        "Current %.2f  Peak %.2f  Samples %d  Stroke %d%%",
    ]

    var label: Label
    ## Now, hardest, readings and stroke pressure in percent, in the order the
    ## forms take them.
    var _values: Array = [0.0, 0.0, 0, 0]

    func _init(line: Label) -> void:
        label = line
        label.autowrap_mode = TextServer.AUTOWRAP_OFF
        label.text_overrun_behavior = SaTheme.TEXT_CUT
        label.resized.connect(_fit)

    func show_values(values: Array) -> void:
        _values = values
        _fit()

    ## The index of the form written, for a suite and a capture: one of
    ## `FORMS`, or past them the shortest broken onto two lines and then four.
    func form() -> int:
        var written := _written()
        for at in written.size():
            if label.text == written[at]:
                return at
        return -1

    ## The longest form that fits the width the label has. Before the label is
    ## laid out it has no width to ask, and the whole form is written.
    func _fit() -> void:
        var font := label.get_theme_font("font")
        var font_size := label.get_theme_font_size("font_size")
        var room := label.size.x - label.get_theme_stylebox("normal").get_minimum_size().x
        var chosen := ""
        for written: String in _written():
            chosen = written
            if room <= 0.0 or _widest_line(chosen, font, font_size) <= room:
                break
        label.text = chosen

    ## Every form as written now, longest first: `FORMS`, then the shortest
    ## broken at its double spaces, two figures to a line and then one. A
    ## catalogue that kept no double space has no break, and its line stays one.
    func _written() -> Array[String]:
        var out: Array[String] = []
        for form_text: String in FORMS:
            out.append(label.tr(form_text) % _values)
        var parts := out[-1].split("  ", false)
        if parts.size() < 2:
            return out
        var pairs: Array[String] = []
        for at in range(0, parts.size(), 2):
            pairs.append("  ".join(parts.slice(at, at + 2)))
        if pairs.size() > 1:
            out.append("\n".join(pairs))
        out.append("\n".join(parts))
        return out

    static func _widest_line(text: String, font: Font, font_size: int) -> float:
        var widest := 0.0
        for line in text.split("\n"):
            widest = maxf(widest, font.get_string_size(line.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
        return widest


var _recorder := SaTablet.new()
var _pad: PressurePad
var _readout: Readout
var _slider: HSlider
var _slider_label: Label
var _apply_button: Button
var _clear_button: Button
var _sweep_button: Button
var _curve: SaCurveEditor

## Whether the strip, the maximum and the curve are drawn as three rows of the
## Preferences row shape or as plain blocks. See [method _init].
var _as_rows: bool = false


## *as_rows* draws the three parts of the page as rows a Preferences search can
## see, which is what the Tablet page asks for. The welcome window's quick
## settings put the whole calibration inside one row of their own, and a row
## inside a row would be three titles the pane never declared, so it takes the
## default and gets the blocks bare.
func _init(as_rows: bool = false) -> void:
    _as_rows = as_rows
    add_theme_constant_override("separation", SaUI.px(10))

    var blurb := SaMake.label(self, "Blurb")
    blurb.text = tr(
        (
            "A pen's pressure axis is hardware, and no two report the same range. Most never reach the top of "
            + "theirs under any force a painter uses, so the last of the travel does nothing. Press on the strip "
            + "and push as hard as a stroke ever goes."
        )
    )
    blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(blurb, SaUI.fraction_of(11))

    _place(_build_strip(), tr("Pressure now"), tr("What the pen reports and what the brush receives, read live off the strip."))
    _place(_build_maximum(), tr("Full pressure at"), tr("The hardware reading that counts as a full-strength stroke."))

    SaMake.separator(self, "SweepSeparator")

    var sweep_blurb := SaMake.label(self, "SweepBlurb")
    sweep_blurb.text = tr(
        (
            "The maximum above is one number. A hand is a shape: most painters press too "
            + "little at the start of a stroke and too much at the end, and no two hands do it "
            + "the same way. Scratching three coated strips measures that shape and straightens "
            + "it, and the curve is yours to edit afterwards."
        )
    )
    sweep_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(sweep_blurb, SaUI.fraction_of(11))

    _place(
        _build_curve(), tr("Pressure curve"), tr("Raw pressure across, corrected pressure up, shaped by the sweep or by hand.")
    )

    # The sweep dialog writes the table while this page is behind it, so the
    # editor is refilled whenever the page comes back into view rather than
    # only when it is built.
    visibility_changed.connect(_show_curve)

    refresh()


## One part of the page, as a row with its title and explanation or bare. The
## caller translates both, and nothing past this point translates them again.
##
## A row shrinks anything that is not a slider, a text box or a dropdown to the
## control column's left edge, and each part is a box that has to fill the
## column, so the width is put back after the row is made.
func _place(block: VBoxContainer, title: String, hint: String) -> void:
    block.add_theme_constant_override("separation", SaUI.px(10))
    if not _as_rows:
        add_child(block)
        return
    SaSettingsRows.row(self, title, hint, block)
    block.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The strip, the readout under it, what the two lanes mean, and the two
## buttons that turn a measurement into the maximum or throw it away.
func _build_strip() -> VBoxContainer:
    var block := SaMake.column(null, "StripBlock")

    _pad = PressurePad.new()
    _pad.name = "PressurePad"
    _pad.sampled.connect(sample_pressure)
    block.add_child(_pad)

    _readout = Readout.new(SaMake.label(block, "Readout"))

    var hint := SaMake.label(block, "LaneHint")
    hint.text = tr(
        (
            "The upper lane is the live hardware reading, the lower one the pressure Sara sends the brush "
            + "after the maximum and the sweep. Grey marks the peak reading, amber the calibrated maximum. "
            + "A pen stuck at 0.00 while you press is reaching Sara as a mouse, and no number here will fix "
            + "that."
        )
    )
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(hint, SaUI.fraction_of(10))
    SaTheme.bind_font(hint, "text_muted")

    var buttons := SaMake.row(block, "MeasureButtons", 10)
    _apply_button = SaMake.button(buttons, "ApplyMeasuredButton", tr("Use Peak Pressure"))
    _apply_button.pressed.connect(apply_measured)
    _clear_button = SaMake.button(buttons, "ClearButton", tr("Clear", "clear a measurement"))
    _clear_button.pressed.connect(clear_measurement)
    return block


## The maximum's figure and its Reset button on one line and the slider on the
## next, rather than all three across. Preferences leaves about 380 logical
## units for a page, and three controls abreast put Reset past the right-hand
## edge.
func _build_maximum() -> VBoxContainer:
    var block := SaMake.column(null, "MaximumBlock")
    var slider_header := SaMake.row(block, "MaximumHeader", 10)
    _slider_label = SaMake.label(slider_header, "MaximumLabel")
    _slider_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var reset_button := SaMake.button(
        slider_header, "MaximumResetButton", tr("Reset"), tr("Back to the raw hardware range, uncalibrated.")
    )
    reset_button.pressed.connect(func() -> void: set_max_pressure(SaTablet.DEFAULT_MAX_PRESSURE))

    var slider_row := SaMake.row(block, "MaximumSliderRow")

    _slider = HSlider.new()
    _slider.name = "MaxPressureSlider"
    # The wheel belongs to the page that scrolls, which has no undo for a
    # value moved by a notch passing over the track.
    _slider.scrollable = false
    _slider.min_value = SaTablet.MIN_MAX_PRESSURE
    _slider.max_value = SaTablet.MAX_MAX_PRESSURE
    _slider.step = 0.01
    _slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _slider.tooltip_text = tr("The raw reading that counts as a full-strength stroke. Lower means less force for the same paint.")
    _slider.value_changed.connect(set_max_pressure)
    slider_row.add_child(_slider)
    return block


## The two buttons over the curve editor: the sweep that measures a hand, and
## the reset that forgets it.
func _build_curve() -> VBoxContainer:
    var block := SaMake.column(null, "CurveBlock")
    var sweep_row := SaMake.row(block, "SweepRow", 10)
    _sweep_button = SaMake.button(sweep_row, "SweepButton", tr("Calibrate by Sweeping..."))
    _sweep_button.pressed.connect(func() -> void: EventBus.tablet_sweep_requested.emit())
    var curve_reset := SaMake.button(
        sweep_row, "CurveResetButton", tr("Reset Curve"), tr("Back to a straight line, which is a pen with no correction at all.")
    )
    curve_reset.pressed.connect(reset_curve)

    _curve = SaCurveEditor.new()
    _curve.name = "PressureCurve"
    _curve.custom_minimum_size = Vector2(0.0, float(SaUI.px(160)))
    _curve.tooltip_text = tr("Raw pressure across, corrected pressure up. Click to add a point, drag it off to remove it.")
    _curve.curve_changed.connect(_on_curve_changed)
    block.add_child(_curve)
    return block


## The curve back to the diagonal, and the stored file with it.
func reset_curve() -> void:
    SaTablet.save_correction(PackedFloat32Array())
    if _curve != null:
        _curve.reset()


## Whatever the painter shaped by hand goes straight to the stored table, so the
## auto-tune and the hand edit are the same setting rather than two. The points
## go with it, so the page reopens on the handles the painter placed rather than
## on samples of the curve they made.
func _on_curve_changed() -> void:
    SaTablet.save_correction(_curve.samples(), _curve.points)


## Pulls the stored curve into the editor without writing it back.
##
## **The placed points when there are any**, rather than the table sampled at
## nine places, which brings a curve shaped from two points back as nine, and a
## handle placed on purpose at 0.3 back as handles at 0.25 and 0.375 nobody
## placed: nothing a stroke reads changes, and everything the painter can drag.
##
## A table with no points is a curve from the sweep dialog, which hands over a
## fit rather than a shape. Nine samples of it is exactly what that dialog drew,
## by the same rule in `SaTabletSweepDialog._curve_points`, so that fallback is
## the dialog's own record rather than an invention of this page.
func _show_curve() -> void:
    if _curve == null:
        return
    var stored := SaTablet.correction
    var points := PackedVector2Array()
    if stored.size() >= 2 and SaTablet.correction_points.size() >= 2:
        points = SaTablet.correction_points
    elif stored.size() >= 2:
        for i in range(9):
            var t := float(i) / 8.0
            points.append(Vector2(t, stored[int(round(t * float(stored.size() - 1)))]))
    else:
        points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    _curve.set_block_signals(true)
    _curve.set_points(points)
    _curve.set_block_signals(false)


## Feeds one raw reading in, from the strip or from a test.
func sample_pressure(raw_pressure: float) -> void:
    _recorder.observe(raw_pressure)
    _redraw_state(raw_pressure)


## Writes the hardest reading in as the maximum. Returns whether it was allowed:
## a measurement nobody has made yet is refused rather than written as zero.
func apply_measured() -> bool:
    if not _recorder.has_usable_peak():
        return false
    set_max_pressure(_recorder.peak)
    # The handle is the one thing the setter cannot move, so it is moved here.
    # Silently: announcing it would route straight back into set_max_pressure and
    # write the setting a second time.
    _slider.set_value_no_signal(SaSettings.tablet_max_pressure)
    return true


func clear_measurement() -> void:
    _recorder.reset()
    _redraw_state(0.0)


## The single writer of the setting on this page. Everything else routes here, so
## the clamp and the labels cannot disagree about what was stored.
func set_max_pressure(value: float) -> void:
    SaSettings.tablet_max_pressure = value
    _redraw_state(_pad.raw if _pad != null else 0.0)


## The hardest reading of the current measurement, before it is applied.
func measured_peak() -> float:
    return _recorder.peak


## Pulls the stored setting back into the controls. Silently on purpose: this
## reads the setting, and announcing the handle's new position would turn it into
## a write of the value it just read.
func refresh() -> void:
    if _slider != null:
        _slider.set_value_no_signal(SaSettings.tablet_max_pressure)
    _show_curve()
    _redraw_state(0.0)


func _redraw_state(raw_pressure: float) -> void:
    var ceiling: float = SaSettings.tablet_max_pressure
    # Gamma 1.0, the same reason the readout gives below: the brush's own
    # sensitivity curve is a separate setting, and folding it in would make this
    # page's second lane depend on which tool happens to be selected.
    var sara := SaTablet.normalize(raw_pressure, ceiling, 1.0)
    var peak := _recorder.peak
    var heard := _recorder.sample_count
    if _pad != null:
        _pad.show_state(raw_pressure, peak, ceiling, sara)
    if _slider_label != null:
        _slider_label.text = "%.2f" % ceiling
    if _apply_button != null:
        _apply_button.disabled = not _recorder.has_usable_peak()
    # Clear throws a measurement away, so it is dimmed while there is none, the
    # state [method clear_measurement] leaves behind.
    if _clear_button != null:
        _clear_button.disabled = heard == 0
    if _readout == null:
        return
    _readout.show_values([raw_pressure, peak, heard, int(round(sara * 100.0))])


## Feeds the calibration pad: each reading, and reports what both lanes drew,
## `{"pressure_pad": {"ramp": [0.0, 0.3, 0.6, 1.0]}}`.
##
## **The only honest door into this page**, and the file's own header says why:
## an injected mouse motion never reaches `_gui_input`, so a scenario that
## pushed events at the strip would exercise nothing. `sample_pressure` is the
## seam everything downstream of the strip already goes through, and this calls
## it once per value the way a pen dragged across the pad would.
##
## `max` sets the calibrated maximum first, because the difference between the
## two lanes *is* the maximum: at 1.00 they are the same bar twice and the shot
## would prove nothing.
##
## `curve` places points on the pressure curve the way a painter's clicks would,
## `[[0, 0], [0.3, 0.6], [1, 1]]`, which stores them through the page's own
## handler. Every call reports the curve's points after whatever else it did, so
## a scenario that closes Preferences and opens it again reads whether the page
## came back on the handles it was given.
static func capture_pad(tree: SceneTree, raw: Variant) -> String:
    var spec: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
    # By type rather than by name: `SaTabletPage` builds this with `new()` and
    # gives it no name, so Godot calls it "VBoxContainer" and a name lookup
    # found nothing while the page was on screen. The first run of this step
    # printed "no Tablet page open" four times over an open Tablet page.
    var found := tree.root.find_children("*", "SaTabletCalibration", true, false)
    var page: SaTabletCalibration = found[0] as SaTabletCalibration if not found.is_empty() else null
    if page == null:
        return "SaCapture: no Tablet page open to feed a pressure ramp to"

    var lines: Array[String] = []
    if spec.has("max"):
        page.set_max_pressure(float(spec["max"]))
        lines.append("SaCapture: pressure pad, full pressure at %.2f" % SaSettings.tablet_max_pressure)
    if bool(spec.get("clear", false)):
        page.clear_measurement()

    var lanes: Dictionary = page._pad.lane_rects() if page._pad != null else {}
    lines.append("SaCapture: pressure pad lanes hardware=%s sara=%s" % [lanes.get("hardware", ""), lanes.get("sara", "")])
    for value: Variant in spec.get("ramp", []) as Array:
        page.sample_pressure(float(value))
        lines.append(
            (
                "SaCapture: pressure pad raw=%.3f sara=%.3f peak=%.3f ceiling=%.3f"
                % [page._pad.raw, page._pad.stroke, page._pad.peak, page._pad.ceiling]
            )
        )
    if spec.has("curve") and page._curve != null:
        var placed := PackedVector2Array()
        for entry: Variant in spec["curve"] as Array:
            var pair := entry as Array
            if pair != null and pair.size() >= 2:
                placed.append(Vector2(float(pair[0]), float(pair[1])))
        page._curve.set_points(placed)
    if page._curve != null:
        var shown: Array[String] = []
        for point in page._curve.points:
            shown.append("(%.3f, %.3f)" % [point.x, point.y])
        lines.append("SaCapture: pressure curve %d point(s) %s" % [page._curve.points.size(), " ".join(shown)])
    if page._readout != null:
        var line := page._readout.label
        lines.append(
            (
                'SaCapture: readout form=%d width=%d lines=%d "%s"'
                % [page._readout.form(), int(line.size.x), line.get_line_count(), line.text]
            )
        )
    return "\n".join(lines)
