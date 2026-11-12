## The Magnetic Lasso clings to the edge a rough trace follows.
##
## A soft-edged shape on a noisy ground of its own lightness and another hue,
## traced by eight points up to six pixels off its edge, is selected within a
## pixel of the edge over nearly all its length. A photograph's pear is
## selected the same way against its mask. Backspace takes anchors away, kept
## from the layer's Clear while a trace is under way, and a
## click on the first anchor closes the trace, and a move of the pointer on a
## 4000 by 4000 picture is timed. Every reading is a pixel of the selection's
## mask, so a trace that closed some other way cannot pass on a flag.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FIXTURES := "res://modules/sara-base-modules/base/magnetic/tests/fixtures/"
const SIDE := 512
const CENTRE := Vector2(256.0, 256.0)
## The shape's radius, which runs round it as a wave of three lobes.
const RADIUS := 150.0
const LOBES := 25.0
## The two colours, Oklab L 0.65 both: a coral, a 0.12 and b 0.06, on a teal,
## a -0.08 and b -0.04, so only the hue tells them apart.
const SHAPE := Color(0.8335, 0.4209, 0.3847)
const GROUND := Color(0.2497, 0.6219, 0.6682)
## How far each channel of the ground and the shape is shaken, either way.
const NOISE := 0.04
## How far off the edge each of the eight points of the trace lies, outward
## for a positive one.
const OFF: Array[float] = [6.0, -5.0, 4.0, -6.0, 5.0, -3.0, 6.0, -4.0]
## Where round the pear the first of the eight points lies, in radians, which
## brings the seventh to the tip of the stem, so the trace goes up the stem
## and down its other side as a painter's would.
const STEM_TURN := 0.48
## Document pixels the pointer moves between two readings of a trace.
const STEP := 3.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"magnetic_lasso")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_a_rough_trace_of_eight_points_selects_the_soft_shape_within_a_pixel_of_its_edge() -> void:
    var doc := _surface.get_document()
    SaImageImport.upload(doc, doc.active_layer, _shape_picture())
    var tool := _machine.active_tool
    tool.sample_merged = false
    var points: Array[Vector2] = []
    for i in OFF.size():
        var angle := TAU * float(i) / float(OFF.size())
        points.append(CENTRE + Vector2.from_angle(angle) * (_radius_at(angle) + OFF[i]))
    _trace(tool, points)
    assert_null(tool.trace, "The click on the first anchor closed the trace")
    assert_true(doc.selection.active, "and the selection holds what it closed round")

    var mask := _mask(doc, Vector2i(SIDE, SIDE))
    var near := 0
    var edge := 0
    var both := 0
    var either := 0
    for y in SIDE:
        for x in SIDE:
            var inside := mask[y * SIDE + x] >= 0.5
            var truth := _signed_distance(Vector2(x, y) + Vector2(0.5, 0.5)) >= 0.0
            both += 1 if inside and truth else 0
            either += 1 if inside or truth else 0
    for crossing: Vector2 in _boundary(mask, Vector2i(SIDE, SIDE)):
        edge += 1
        near += 1 if absf(_signed_distance(crossing)) <= 1.0 else 0
    var share := float(near) / float(maxi(edge, 1))
    var overlap := float(both) / float(maxi(either, 1))
    print("Magnetic Lasso, soft shape: %.1f%% of the boundary within 1 px, overlap %.4f" % [share * 100.0, overlap])
    assert_true(share >= 0.95, "The boundary lies within 1 px of the edge over %.1f%% of its length" % (share * 100.0))
    assert_true(overlap >= 0.98, "and the selection overlaps the shape by %.4f" % overlap)


func test_a_trace_round_the_photograph_s_pear_overlaps_its_mask() -> void:
    var picture := Image.load_from_file(ProjectSettings.globalize_path(FIXTURES + "pear.jpg"))
    var marked := Image.load_from_file(ProjectSettings.globalize_path(FIXTURES + "pear_mask.png"))
    assert_not_null(picture, "The photograph loads")
    assert_not_null(marked, "and its mask")
    if picture == null or marked == null:
        return
    var size := picture.get_size()
    Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(size)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"magnetic_lasso")
    var doc := _surface.get_document()
    SaImageImport.upload(doc, doc.active_layer, picture)
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var tool := _machine.active_tool
    tool.sample_merged = true

    marked.convert(Image.FORMAT_L8)
    var centre := Vector2.ZERO
    var count := 0
    for y in size.y:
        for x in size.x:
            if marked.get_pixel(x, y).r >= 0.5:
                centre += Vector2(x, y)
                count += 1
    centre /= float(maxi(count, 1))
    var points: Array[Vector2] = []
    for i in OFF.size():
        var angle := TAU * float(i) / float(OFF.size()) + STEM_TURN
        points.append(_edge_along(marked, centre, angle) + Vector2.from_angle(angle) * OFF[i])
    _trace(tool, points)
    assert_true(doc.selection.active, "The trace round the pear closed into a selection")

    var mask := _mask(doc, size)
    var both := 0
    var either := 0
    for y in size.y:
        for x in size.x:
            var inside := mask[y * size.x + x] >= 0.5
            var truth := marked.get_pixel(x, y).r >= 0.5
            both += 1 if inside and truth else 0
            either += 1 if inside or truth else 0
    var overlap := float(both) / float(maxi(either, 1))
    print("Magnetic Lasso, the pear: overlap %.4f" % overlap)
    assert_true(overlap >= 0.92, "The selection overlaps the pear's mask by %.4f" % overlap)


func test_backspace_takes_two_of_four_anchors_away_and_a_click_on_the_first_closes() -> void:
    var doc := _surface.get_document()
    SaImageImport.upload(doc, doc.active_layer, _shape_picture())
    var tool := _machine.active_tool
    tool.sample_merged = false
    tool.frequency = 0.0
    var corners: Array[Vector2] = []
    for i in 12:
        var angle := TAU * float(i) / 12.0
        corners.append(CENTRE + Vector2.from_angle(angle) * _radius_at(angle))
    _press_at(tool, corners[0])
    for i in range(1, 4):
        _move_along(tool, corners[i - 1], corners[i])
        _press_at(tool, corners[i])
    assert_eq(tool.trace.anchors.size(), 4, "Four clicks lay four anchors")
    # Through the machine, the router's door, which answers true so the
    # layer's Clear on Backspace never runs beside it.
    assert_true(_machine.handle_key_event(_key(KEY_BACKSPACE)), "The trace keeps Backspace from the shortcuts")
    _machine.handle_key_event(_key(KEY_BACKSPACE))
    assert_eq(tool.trace.anchors.size(), 2, "and Backspace twice leaves two")
    assert_false(doc.selection.active, "with nothing selected yet")

    for i in range(2, 12):
        _move_along(tool, corners[i - 1], corners[i])
        _press_at(tool, corners[i])
    _move_along(tool, corners[11], corners[0])
    _press_at(tool, tool.trace.anchors[0] + Vector2(3.0, -2.0))
    assert_null(tool.trace, "A click beside the first anchor closes the trace")
    assert_true(doc.selection.active, "into a selection")
    var mask := _mask(doc, Vector2i(SIDE, SIDE))
    assert_true(mask[256 * SIDE + 256] >= 0.5, "that holds the shape's middle")
    assert_true(mask[10 * SIDE + 10] < 0.5, "and not the ground's corner")


func test_escape_abandons_the_trace() -> void:
    var tool := _machine.active_tool
    _press_at(tool, Vector2(100, 100))
    _move_along(tool, Vector2(100, 100), Vector2(200, 140))
    assert_false(tool.preview_shape().is_empty(), "A trace under way shows its outline")
    tool.handle_input(_key(KEY_ESCAPE))
    assert_null(tool.trace, "Escape abandons it")
    assert_true(tool.preview_shape().is_empty(), "and the outline goes")
    assert_false(_machine.handle_key_event(_key(KEY_BACKSPACE)), "and Backspace is the shortcuts' again")
    assert_false(_surface.get_document().selection.active, "with nothing selected")


func test_a_move_of_the_pointer_on_a_4000_pixel_picture_is_timed() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(Vector2i(4000, 4000))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"magnetic_lasso")
    var doc := _surface.get_document()
    var centre := Vector2(2000.0, 2000.0)
    var disc := PackedVector2Array()
    for i in 128:
        disc.append(centre + Vector2.from_angle(TAU * float(i) / 128.0) * 600.0)
    doc.selection.select_polygon(disc, SaSelection.Mode.REPLACE, true)
    doc.fill_layer(SHAPE, doc.active_layer)
    doc.selection.deselect()
    var tool := _machine.active_tool
    tool.sample_merged = false

    var times: Array[float] = []
    _press_at(tool, centre + Vector2(600.0, 0.0))
    for i in range(1, 400):
        var angle := TAU * 0.25 * float(i) / 400.0
        var off := 4.0 * sin(float(i) * 0.7)
        _surface.view.mouse_position = centre + Vector2.from_angle(angle) * (600.0 + off)
        var asked := Time.get_ticks_usec()
        tool.handle_input(InputEventMouseMotion.new())
        times.append(float(Time.get_ticks_usec() - asked) / 1000.0)
    times.sort()
    @warning_ignore("integer_division")
    var median := times[times.size() / 2]
    var high := times[int(float(times.size()) * 0.95)]
    print(
        (
            (
                "Magnetic Lasso, 4000 by 4000: a move's update takes %.2f ms at the median, %.2f ms at the 95th percentile, "
                + "over %d moves and %d windows"
            )
            % [median, high, times.size(), tool.trace.windows]
        )
    )
    assert_true(median < 16.0, "The median update takes %.2f ms, under a frame" % median)
    assert_true(tool.trace.anchors.size() > 1, "and the trace laid anchors on its own as it went")


## Clicks *points*' first, moves the pointer through the rest and back, and
## clicks the first anchor.
func _trace(tool: ToolState, points: Array[Vector2]) -> void:
    _press_at(tool, points[0])
    for i in range(1, points.size()):
        _move_along(tool, points[i - 1], points[i])
    _move_along(tool, points[points.size() - 1], points[0])
    _press_at(tool, tool.trace.anchors[0] + Vector2(2.0, 2.0))


func _press_at(tool: ToolState, at: Vector2) -> void:
    _surface.view.mouse_position = at
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))


func _move_along(tool: ToolState, from: Vector2, to: Vector2) -> void:
    var steps := maxi(1, ceili(from.distance_to(to) / STEP))
    for i in range(1, steps + 1):
        _surface.view.mouse_position = from.lerp(to, float(i) / float(steps))
        tool.handle_input(InputEventMouseMotion.new())


func _radius_at(angle: float) -> float:
    return RADIUS + LOBES * sin(3.0 * angle)


## How far inside the shape's edge *at* lies, negative outside, measured along
## the ray from the centre, which a wave this gentle keeps within a tenth of a
## pixel of the distance to the edge itself near it.
func _signed_distance(at: Vector2) -> float:
    var from := at - CENTRE
    var slope := 3.0 * LOBES * cos(3.0 * from.angle()) / maxf(_radius_at(from.angle()), 1.0)
    return (_radius_at(from.angle()) - from.length()) / sqrt(1.0 + slope * slope)


## The shape over the ground, each a channel shaken by up to [constant NOISE],
## its edge graded over three pixels.
func _shape_picture() -> Image:
    var picture := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBF)
    var noise := RandomNumberGenerator.new()
    noise.seed = 902
    for y in SIDE:
        for x in SIDE:
            var cover := clampf(0.5 + _signed_distance(Vector2(x, y) + Vector2(0.5, 0.5)) / 3.0, 0.0, 1.0)
            var colour := GROUND.lerp(SHAPE, cover)
            colour.r += noise.randf_range(-NOISE, NOISE)
            colour.g += noise.randf_range(-NOISE, NOISE)
            colour.b += noise.randf_range(-NOISE, NOISE)
            picture.set_pixel(x, y, colour)
    return picture


## The last pixel of *mask* that is set along the ray out of *centre* at
## *angle*.
func _edge_along(mask: Image, centre: Vector2, angle: float) -> Vector2:
    var last := centre
    var size := mask.get_size()
    for r in range(0, 2 * maxi(size.x, size.y)):
        var at := centre + Vector2.from_angle(angle) * float(r)
        if at.x < 0.0 or at.y < 0.0 or at.x >= size.x or at.y >= size.y:
            break
        if mask.get_pixelv(Vector2i(at)).r >= 0.5:
            last = at
    return last


## The selection's boundary, where its coverage crosses one half between two
## pixels side by side, each crossing placed between their middles by the
## coverage either side, the way an outline is drawn through an anti-aliased
## edge. One a pair of neighbours across the boundary, so a stretch of it is
## counted as often as it is pixels long.
func _boundary(mask: PackedFloat32Array, size: Vector2i) -> PackedVector2Array:
    var found := PackedVector2Array()
    for y in size.y:
        for x in size.x:
            var here := mask[y * size.x + x]
            for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
                var next := Vector2i(x, y) + step
                if next.x >= size.x or next.y >= size.y:
                    continue
                var there := mask[next.y * size.x + next.x]
                if (here >= 0.5) == (there >= 0.5):
                    continue
                var t := (here - 0.5) / (here - there)
                found.append(Vector2(x, y) + Vector2(0.5, 0.5) + Vector2(step) * t)
    return found


## The selection's coverage of every pixel of a canvas of *size*, row after row.
func _mask(doc: SaDocument, size: Vector2i) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(size.x * size.y)
    var side := SaChunk.SIZE
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in doc.selection.chunks:
        var texture := (doc.selection.chunks[grid] as SaChunk).field(SaSelection.FIELD)
        var values := rd.texture_get_data(texture.rid, 0).to_float32_array()
        for y in side:
            for x in side:
                var at := grid * side + Vector2i(x, y)
                if at.x < size.x and at.y < size.y:
                    out[at.y * size.x + at.x] = values[y * texture.size.x + x]
    return out


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event
