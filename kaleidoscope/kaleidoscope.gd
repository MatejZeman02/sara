# Filter > Kaleidoscope. Read it after the box blur beside it: that one is a
# slider and a kernel, and this one shows the rest of what a filter can bring.
# A widget of its own on the base class a module's control extends, which the
# wheel, a pan and the arrow keys turn and a scenario moves, presets a painter
# can save, a pass that reads the whole layer rather than a neighbourhood, and
# a suite under `tests`, which the test runner finds by the folder alone.
#
# **This file is one filter, and `module.gd` beside it is the folder.** The
# `id()` and `title()` below name the fold a painter picks in the Filter menu
# and a record keeps, and one module may register several filters with an `id`
# each of its own. The loader never reads them: what it tells one module from
# another by is `get_id` and `get_name` over there and the version in its
# `manifest.cfg`.
#
# One `run` serves both forms. Filter > Kaleidoscope applies it to the layer
# once, and Attach keeps it on the layer, where it is evaluated again whenever
# the paint under it changes and nothing is baked until a flatten.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaFilter

const MIN_MIRRORS := 2
const MAX_MIRRORS := 24

## What a record keeps and a preset holds: the mirror lines through the centre,
## the angle the first wedge starts at in degrees, and the centre as a
## percentage of the canvas.
const DEFAULTS := {"mirrors": 6, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}

## Where an older profile keeps a painter's presets: one `ConfigFile` section
## each in the first form, then one `.tres` each in a directory of its own.
## Both are read once into the row's store by
## [method carry_over], so an upgrade keeps what a painter saved. Names under
## the data root, which a run with its own settings folder moves.
const OLD_PRESET_FILE := "kaleidoscope_presets.cfg"
const OLD_PRESET_DIR := "kaleidoscope_presets"

## The dial the dialog draws, or null while no dialog has been built.
var dial: WedgeDial = null


func _init() -> void:
    carry_over(SaDataRoot.path(OLD_PRESET_FILE), SaDataRoot.path(OLD_PRESET_DIR), id())


func id() -> StringName:
    return &"kaleidoscope"


func title() -> String:
    return "Kaleidoscope"


## No: every pixel reads the wedge the mirrors fold it into, which can be
## anywhere on the layer, so a brush has nothing local to paint.
func can_be_a_brush() -> bool:
    return false


## The base module's Distort section, because it moves pixels rather than
## changing their colour.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Repeats one wedge of the picture round a centre, every other copy mirrored."


## The rows bind to the filter's values by their keys, `mirrors`, `centre_x` and
## `centre_y`, and the dial binds to `angle`, which it holds itself as the base
## class of a module's own control does. The dialog adds the title, the pictures
## and the buttons.
func build(ui: SaDialog) -> void:
    ui.parameter(&"angle", DEFAULTS["angle"], -180.0, 180.0)
    ui.custom("Wedges", _make_dial).named(&"angle")
    # The dial holds the angle and draws the count, which is this row's: a value
    # a plain row can hold goes in a plain row.
    ui.slider("Mirrors", MIN_MIRRORS, MAX_MIRRORS, DEFAULTS["mirrors"]).changed.connect(_show_on_dial.unbind(1))
    ui.slider("Centre X", 0, 100, int(DEFAULTS["centre_x"]), {"suffix": "%"})
    ui.slider("Centre Y", 0, 100, int(DEFAULTS["centre_y"]), {"suffix": "%"})
    ui.presets()
    # A record or a preset writes the count behind the dial's back.
    if not store.changed.is_connected(_show_on_dial):
        store.changed.connect(_show_on_dial)


func run(ctx: SaFilterContext) -> void:
    var values := parameters()
    # The centre is a percentage of the canvas, whatever is selected or painted.
    var canvas := Vector2(ctx.canvas_size())
    var centre := Vector2(canvas.x * float(values["centre_x"]), canvas.y * float(values["centre_y"])) / 100.0
    # A fold a texel. The canvas preview of a drag hands the kernel a larger
    # block through the runner, and nothing a record keeps is ever coarser.
    var params := {"mirrors": int(values["mirrors"]), "angle": deg_to_rad(float(values["angle"])), "centre": centre, "block": 1}
    # A folded stroke lands all round the centre, where the layer holds no
    # chunk yet, so the pass writes the canvas and not only the layer's chunks.
    ctx.neighbourhood_pass("kaleidoscope", "kaleidoscope", params, SaFilterContext.WHOLE_NODE, {}, SaFilterContext.WRITES_CANVAS)
    # But a change lands only where the fold carries it, so an attached one
    # redraws that and not the whole canvas on every dab.
    var recorded := ctx.point as SaNeighbourhoodPass
    if recorded != null:
        recorded.carries = folded_boxes.bind(centre, float(params["angle"]), int(params["mirrors"]))


## Where a change over *area* of the canvas shows once folded round *centre*
## by *mirrors* mirror lines from *angle*, as the rectangles of the canvas whose
## texels read it, for [member SaNeighbourhoodPass.carries]. *canvas* is not
## read, the caller cuts to it.
##
## A texel reads the one wedge that starts at *angle* and nothing else, so a
## change that misses the wedge lands nowhere past itself. One that meets it
## lands on the wedge turned by every even multiple of the wedge, and on its
## mirror image across the first mirror line turned the same, two boxes a
## mirror line, which is the kernel's `folded` read backwards. The whole of
## *area* is turned rather than its part inside the wedge, which costs a
## chunk now and then and keeps the geometry to four corners a box.
##
## *area* grows by a texel first, because the kernel's read is bilinear and a
## texel is read from as far as one texel off, and each box by two more for the
## difference between the kernel's floats and these.
static func folded_boxes(area: Rect2i, _canvas: Vector2i, centre: Vector2, angle: float, mirrors: int) -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    var grown := Rect2(area.grow(1))
    var wedge := PI / float(maxi(mirrors, 1))
    if not _meets_wedge(grown, centre, angle, wedge):
        return out
    var corners: Array[Vector2] = [
        grown.position, Vector2(grown.end.x, grown.position.y), grown.end, Vector2(grown.position.x, grown.end.y)
    ]
    for turn in maxi(mirrors, 1):
        for mirrored: bool in [false, true]:
            var box := Rect2()
            for i in corners.size():
                var away := corners[i] - centre
                if mirrored:
                    # Across the line through the centre at *angle*.
                    var local := away.rotated(-angle)
                    away = Vector2(local.x, -local.y).rotated(angle)
                var at := centre + away.rotated(2.0 * wedge * turn)
                box = Rect2(at, Vector2.ZERO) if i == 0 else box.expand(at)
            var first := Vector2i(box.position.floor()) - Vector2i(2, 2)
            out.append(Rect2i(first, Vector2i(box.end.ceil()) + Vector2i(2, 2) - first))
    return out


## Whether *area* holds a point of the wedge that starts at *angle* from
## *centre* and is *wedge* wide, a sector with no far edge. A rectangle that
## does not hold the centre sees it under an angle short of a half turn, so the
## span of its four corners seen from the centre is the span of the whole.
static func _meets_wedge(area: Rect2, centre: Vector2, angle: float, wedge: float) -> bool:
    if area.grow(1.0).has_point(centre):
        return true
    var towards := (area.get_center() - centre).angle()
    var low := INF
    var high := -INF
    for corner: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
        var off := wrapf((corner - centre).angle() - towards, -PI, PI)
        low = minf(low, off)
        high = maxf(high, off)
    var start := fposmod(towards + low - angle, TAU)
    var slack := 1e-4
    return start <= wedge + slack or start + (high - low) >= TAU - slack


## The dial, which asks for its runs through the row it is bound to rather than
## through the callable a custom row is handed.
func _make_dial(_rerun: Callable) -> Control:
    dial = WedgeDial.new(int(parameter(&"mirrors")), float(parameter(&"angle")))
    return dial


## Shows the kept count on the dial, without asking for a run.
func _show_on_dial() -> void:
    if dial != null and is_instance_valid(dial):
        dial.show_mirrors(int(parameter(&"mirrors")))


## Reads the presets of both older forms, *old_file* and the `.tres` files
## under *old_dir*, into the presets of the filter *filter_id*, and removes what
## it read.
##
## Removed rather than left where they are, because the read is meant to happen
## once and files still holding them would be a second copy on the next launch.
## A save that fails leaves them alone, so nothing a painter saved is lost to a
## full disk. A `.tres` is read as text, because the script it names is not in
## the build and loading it as a resource would fail.
static func carry_over(old_file: String, old_dir: String, filter_id: StringName) -> void:
    var found: Dictionary = {}
    var file := ConfigFile.new()
    if FileAccess.file_exists(old_file) and file.load(old_file) == OK:
        for section: String in file.get_sections():
            var values := DEFAULTS.duplicate()
            for key: String in DEFAULTS:
                values[key] = file.get_value(section, key, DEFAULTS[key])
            found[section] = values
    var old_presets: PackedStringArray = []
    if DirAccess.dir_exists_absolute(old_dir):
        for file_name: String in DirAccess.get_files_at(old_dir):
            if file_name.ends_with(".tres"):
                old_presets.append(old_dir.path_join(file_name))
                found[file_name.trim_suffix(".tres")] = _values_in_text(
                    FileAccess.get_file_as_string(old_dir.path_join(file_name))
                )
    var into := SaFilterPreset.store_for(filter_id)
    for preset_name: String in found:
        if into.save_preset(preset_name, SaFilterPreset.of(found[preset_name])).is_empty():
            return
    if FileAccess.file_exists(old_file):
        DirAccess.remove_absolute(old_file)
    for path in old_presets:
        DirAccess.remove_absolute(path)
    if DirAccess.dir_exists_absolute(old_dir) and DirAccess.get_files_at(old_dir).is_empty():
        DirAccess.remove_absolute(old_dir)


## The four values an old preset's `.tres` text holds, each one it leaves out
## at its default, which is what the saver left out.
static func _values_in_text(text: String) -> Dictionary:
    var values := DEFAULTS.duplicate()
    for line in text.split("\n"):
        var pair := line.split(" = ", true, 1)
        if pair.size() == 2 and DEFAULTS.has(pair[0]):
            values[pair[0]] = float(str_to_var(pair[1]))
    return values


## A circle cut into the wedges the mirrors make, the one that is repeated
## filled in. Its value is the angle the first wedge starts at in degrees,
## clockwise from the right on screen, which is the direction a document's y
## grows in too. Dragging turns it, and the wheel, a touchpad's scroll and the
## arrow keys turn it a step at a time through the base class, which also
## prints it and lets a scenario move it.
class WedgeDial:
    extends SaValueControl

    ## Degrees one wheel notch, pan or arrow key turns the wedge by.
    const TURN_STEP := 5.0

    ## The count the dial draws, which the Mirrors row holds.
    var mirrors: int = 6

    func _init(start_mirrors: int, start_angle: float) -> void:
        super(start_angle, -180.0, 180.0, TURN_STEP)
        mirrors = start_mirrors
        name = "KaleidoscopeDial"
        custom_minimum_size = Vector2(SaUI.px(160), SaUI.px(160))
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tooltip_text = tr("Drag, scroll or use the arrow keys to turn the wedge.")

    ## Draws *count* wedges, for the Mirrors row or a preset that moved it.
    func show_mirrors(count: int) -> void:
        mirrors = count
        queue_redraw()

    func _pointer_input(event: InputEvent) -> bool:
        var press := event as InputEventMouseButton
        if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
            _turn_to(press.position)
            return true
        var motion := event as InputEventMouseMotion
        if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
            _turn_to(motion.position)
            return true
        return false

    func _turn_to(at: Vector2) -> void:
        var offset := at - size / 2.0
        if not offset.is_zero_approx():
            move_to(roundf(rad_to_deg(offset.angle())))

    func _draw() -> void:
        var middle := size / 2.0
        var radius := minf(size.x, size.y) / 2.0 - SaUI.pxf(4.0)
        if radius <= 0.0:
            return
        var ink := get_theme_color("font_color", "Label")
        var faint := Color(ink, 0.35)
        var wedge := PI / float(mirrors)
        var start := deg_to_rad(value)
        var fan := PackedVector2Array([middle])
        for slice in 17:
            fan.append(middle + radius * Vector2.from_angle(start + wedge * float(slice) / 16.0))
        draw_colored_polygon(fan, Color(ink, 0.3))
        for line in 2 * mirrors:
            var colour := ink if line < 2 else faint
            draw_line(middle, middle + radius * Vector2.from_angle(start + wedge * float(line)), colour, SaUI.pxf(1.0), true)
        draw_arc(middle, radius, 0.0, TAU, 96, faint, SaUI.pxf(1.0), true)
        var font := get_theme_font("font", "Label")
        var font_size := get_theme_font_size("font_size", "Label")
        var words := tr_n("%d mirror", "%d mirrors", mirrors) % mirrors
        draw_string(font, Vector2(0.0, float(font_size)), words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, ink)
