## The Ellipse offers anti-aliasing and the wand a Contiguous switch.
##
## The Lasso has Anti-aliasing and so has the Ellipse, and the Fill has
## Contiguous and so has the Wand, so a painter who wants one colour picked
## everywhere need not open Colour Range. The Ellipse
## now grades its edge by the signed distance from each pixel's centre to the
## ellipse, as the polygon does, under an `ellipse_anti_alias` row on by
## default, and a Wand click with `wand_contiguous` off selects every texel
## within the tolerance through the match the bucket fill's Contiguous off
## already used.
##
## Every mask is read back from VRAM and held against the same sum done here on
## the CPU, because a coverage that is merely plausible is what a wrong kernel
## returns.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Far enough from any number the GPU and the CPU disagree on over a few
## hundred pixels, and far closer than any grade a painter could see.
const CLOSE := 0.0001

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## Blue a tenth off in its red channel, past the wand's default tolerance of
## 0.1 by a hair once the tolerance is narrowed to 0.05.
const NEAR_BLUE := Color(0.1, 0.0, 1.0, 1.0)

## The three blue bars, on a red ground, each in a chunk
## column of its own so that a flood from one cannot reach another by a seam.
const BARS: Array[Rect2i] = [Rect2i(40, 60, 60, 300), Rect2i(300, 60, 60, 300), Rect2i(560, 60, 60, 300)]

## A circle 200 across over the seams of the top left four chunks, and an
## ellipse 400 by 120 over the vertical one.
const CIRCLE := Rect2i(100, 100, 200, 200)
const ELLIPSE := Rect2i(60, 300, 400, 120)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


## Three by two chunks, so the bars and the shapes can cross seams.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func test_the_ellipse_declares_anti_aliasing_and_the_marquee_does_not() -> void:
    assert_eq(_keys(&"marquee"), [&"selection_mode", &"feather"], "The Marquee keeps its two rows")
    assert_eq(
        _keys(&"ellipse_select"),
        [&"selection_mode", &"feather", &"ellipse_anti_alias"],
        "and the Ellipse has the lasso's third, after the Feather as the lasso's is"
    )
    var row := _row(&"ellipse_select", &"ellipse_anti_alias")
    assert_eq(row.label, "Anti-aliasing", "called what the lasso's row is called")
    assert_eq(row.kind, SaOptionSpec.Kind.BOOL, "a tick")
    assert_eq(row.property, ^"anti_alias", "on the tool's own property")
    assert_true(row.on_tool and not row.bar, "in Tool Options and off the bar, as the lasso's is")
    _machine.set_active_tool(&"ellipse_select")
    assert_true(_machine.active_tool.anti_alias, "A fresh Ellipse anti-aliases")


## The first half: a circle dragged with the row on has a ring of partial
## coverage, and every pixel of its box is the sum's.
func test_a_circle_dragged_with_anti_aliasing_on_has_a_graded_ring() -> void:
    _drag_ellipse(CIRCLE)
    var mask := _mask()
    var graded := 0
    for y in range(CIRCLE.position.y, CIRCLE.end.y):
        for x in range(CIRCLE.position.x, CIRCLE.end.x):
            var cover := _at(mask, x, y)
            if cover > 0.0 and cover < 1.0:
                graded += 1
    assert_true(graded > 600, "The ring holds part of a pixel all the way round: %d pixels" % graded)
    assert_eq(_mismatches(mask, CIRCLE, 1.0, CIRCLE.grow(2)), [], "and every pixel of the box is the sum's")
    assert_eq(_at(mask, 200, 200), 1.0, "The centre is whole")
    assert_eq(_at(mask, 101, 101), 0.0, "and the box's corner empty")
    assert_eq(_doc.selection.bounds, CIRCLE, "The bounds are the box dragged, the ring touching its four sides")
    assert_eq(_doc.selection.chunks.size(), 4, "over the four chunks the circle crosses")


## The second half: the row off, a circle dragged again is hard, and it
## is the mask a caller that does not ask has always had.
func test_the_row_off_gives_the_hard_circle_back() -> void:
    _machine.set_active_tool(&"ellipse_select")
    var tool := _machine.active_tool
    tool.set_indexed(_row(&"ellipse_select", &"ellipse_anti_alias").property, false)
    _drag_ellipse(CIRCLE)
    var hard := _mask()
    var soft := 0
    for y in range(CIRCLE.position.y, CIRCLE.end.y):
        for x in range(CIRCLE.position.x, CIRCLE.end.x):
            var cover := _at(hard, x, y)
            if cover > 0.0 and cover < 1.0:
                soft += 1
    assert_eq(soft, 0, "Off, no pixel holds part of a pixel")
    assert_eq(_mismatches(hard, CIRCLE, 0.0, CIRCLE.grow(2)), [], "and every pixel is the centre test's")
    _doc.selection.select_ellipse(CIRCLE)
    assert_true(_same(_mask(), hard), "and a caller that does not ask gets the same bytes")


## The grade is by area. Over a whole ellipse the parts a pixel holds add up to
## the ellipse's area, and on each pixel of the edge it is close to the share a
## sixteen by sixteen sampling of the pixel finds inside, which the hard test
## misses by up to a whole pixel.
func test_the_grade_is_the_share_of_each_pixel_the_ellipse_covers() -> void:
    _doc.selection.select_ellipse(ELLIPSE, SaSelection.Mode.REPLACE, true)
    var soft := _mask()
    _doc.selection.select_ellipse(ELLIPSE)
    var hard := _mask()
    var area := PI * ELLIPSE.size.x * 0.5 * ELLIPSE.size.y * 0.5
    var soft_sum := 0.0
    var soft_worst := 0.0
    var hard_worst := 0.0
    var edge := 0
    for y in range(ELLIPSE.position.y, ELLIPSE.end.y):
        for x in range(ELLIPSE.position.x, ELLIPSE.end.x):
            var cover := _at(soft, x, y)
            soft_sum += cover
            var share := _sampled(ELLIPSE, Vector2i(x, y))
            if share <= 0.0 or share >= 1.0:
                continue
            edge += 1
            soft_worst = maxf(soft_worst, absf(cover - share))
            hard_worst = maxf(hard_worst, absf(_at(hard, x, y) - share))
    assert_true(edge > 900, "The edge crosses %d pixels" % edge)
    assert_almost_eq(soft_sum / area, 1.0, 0.0005, "The parts add up to the ellipse's area")
    assert_true(soft_worst < 0.1, "and no pixel of the edge is a tenth from its share: %f" % soft_worst)
    assert_true(hard_worst > 0.45, "where the hard test is out by %f" % hard_worst)


## A box an odd number of pixels across puts a pixel's centre on the ellipse's,
## where the distance's estimate is nought over nought, and that pixel is
## whole. A two pixel box is all edge.
func test_the_centre_of_a_small_ellipse_is_whole() -> void:
    var odd := Rect2i(11, 11, 5, 5)
    _doc.selection.select_ellipse(odd, SaSelection.Mode.REPLACE, true)
    var mask := _mask()
    assert_eq(_at(mask, 13, 13), 1.0, "The pixel on the centre is whole")
    assert_eq(_mismatches(mask, odd, 1.0, odd.grow(2)), [], "and the rest of the box is the sum's")
    var tiny := Rect2i(40, 40, 2, 2)
    _doc.selection.select_ellipse(tiny, SaSelection.Mode.REPLACE, true)
    assert_eq(_mismatches(_mask(), tiny, 1.0, tiny.grow(2)), [], "A two pixel box is the sum's too")


## An add keeps the greater of the mask and the grade and a subtract the lesser
## of the mask and what the shape leaves, the polygon's rule, so the ring takes
## nothing back from a whole pixel and puts nothing back.
func test_a_graded_ellipse_adds_and_subtracts_as_the_polygon_does() -> void:
    _doc.selection.select_all(_doc.canvas_size)
    _doc.selection.select_ellipse(CIRCLE, SaSelection.Mode.SUBTRACT, true)
    var cut := _mask()
    var wrong: Array = []
    for y in range(CIRCLE.position.y, CIRCLE.end.y):
        for x in range(CIRCLE.position.x, CIRCLE.end.x):
            var want := 1.0 - _expected(CIRCLE, Vector2i(x, y), 1.0)
            if absf(_at(cut, x, y) - want) > CLOSE:
                wrong.append([Vector2i(x, y), _at(cut, x, y), want])
    assert_eq(wrong, [], "A subtract leaves each ring pixel the part the circle does not cover")

    _doc.selection.select_rect(Rect2i(100, 100, 100, 200))
    _doc.selection.select_ellipse(CIRCLE, SaSelection.Mode.ADD, true)
    var added := _mask()
    assert_eq(_at(added, 100, 200), 1.0, "An add over the rectangle keeps a ring pixel inside it whole")
    assert_almost_eq(_at(added, 299, 200), _expected(CIRCLE, Vector2i(299, 200), 1.0), CLOSE, "and grades past it")


func test_the_wand_declares_contiguous_on_by_default() -> void:
    assert_eq(
        _keys(&"wand"),
        [&"wand_tolerance", &"wand_contiguous", &"sample_merged", &"selection_mode", &"feather"],
        "Contiguous sits after the Tolerance, as the fill's does"
    )
    var row := _row(&"wand", &"wand_contiguous")
    assert_eq(row.label, "Contiguous", "called what the fill's row is called")
    assert_eq(row.kind, SaOptionSpec.Kind.BOOL, "a tick")
    assert_eq(row.property, ^"contiguous", "on the tool's own property")
    assert_true(row.on_tool and not row.bar, "in Tool Options and off the bar")
    assert_true(row.key != _row(&"bucket_fill", &"fill_contiguous").key, "and its own key, not the fill's")
    _machine.set_active_tool(&"wand")
    assert_true(_machine.active_tool.contiguous, "A fresh wand keeps to the region")


## The shot's case: a click on one blue bar with Contiguous on selects that bar,
## and with it off all three, over the merged picture as a fresh wand reads.
func test_a_click_on_one_bar_selects_it_and_with_contiguous_off_all_three() -> void:
    _paint_bars()
    _machine.set_active_tool(&"wand")
    var tool := _machine.active_tool
    assert_true(tool.sample_merged, "A fresh wand reads the picture as shown")
    var steps := _steps()
    _click(tool, Vector2(330, 200))
    assert_eq(_bars_held(), [false, true, false], "On, the click selects the bar it landed on")
    assert_eq(_doc.selection.bounds, BARS[1], "and nothing past it")

    tool.set_indexed(_row(&"wand", &"wand_contiguous").property, false)
    _click(tool, Vector2(330, 200))
    assert_eq(_bars_held(), [true, true, true], "Off, the same click selects all three bars")
    assert_almost_eq(_coverage(200, 200), 0.0, 0.001, "and none of the red between them")
    assert_eq(_doc.selection.bounds, Rect2i(BARS[0].position, BARS[2].end - BARS[0].position), "The box spans the three")
    assert_eq(_steps(), steps + 2, "Each click is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.WAND_TITLE, "named for the wand")

    tool.sample_merged = false
    _click(tool, Vector2(70, 200))
    assert_eq(_bars_held(), [true, true, true], "Read off the layer alone it finds the same three")


## Off, the click takes the tolerance and the mode the row beside it says, so a
## bar a tenth off joins only when the tolerance reaches it, and an add keeps
## the selection it is added to.
func test_contiguous_off_keeps_the_tolerance_and_the_mode() -> void:
    _paint_bars()
    _paint_rect(Rect2i(300, 400, 60, 60), NEAR_BLUE)
    _composite()
    _machine.set_active_tool(&"wand")
    var tool := _machine.active_tool
    tool.contiguous = false
    tool.tolerance = 0.05
    _click(tool, Vector2(70, 200))
    assert_eq(_bars_held(), [true, true, true], "Narrow, the three bars join")
    assert_almost_eq(_coverage(330, 430), 0.0, 0.001, "and the near blue does not")
    tool.tolerance = 0.15
    _click(tool, Vector2(70, 200))
    assert_almost_eq(_coverage(330, 430), 1.0, 0.001, "Wide enough, it does")

    tool.tolerance = 0.05
    _doc.selection.select_rect(Rect2i(700, 450, 40, 40))
    _click(tool, Vector2(70, 200), true)
    assert_eq(_bars_held(), [true, true, true], "Shift adds the three bars")
    assert_almost_eq(_coverage(720, 470), 1.0, 0.001, "to the square that was selected")
    _click(tool, Vector2(70, 200), false, true)
    assert_eq(_bars_held(), [false, false, false], "and Alt takes them out")
    assert_almost_eq(_coverage(720, 470), 1.0, 0.001, "leaving the square")


func _keys(tool: StringName) -> Array:
    var keys: Array = []
    for spec: SaOptionSpec in _machine.registry.get_descriptor(tool).options:
        keys.append(spec.key)
    return keys


func _row(tool: StringName, key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in _machine.registry.get_descriptor(tool).options:
        if spec.key == key:
            return spec
    return null


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## A drag of the Ellipse tool over *box*, from its corner to the opposite one.
func _drag_ellipse(box: Rect2i) -> void:
    _machine.set_active_tool(&"ellipse_select")
    var tool := _machine.active_tool
    _surface.view.mouse_position = Vector2(box.position)
    tool.handle_input(_button(true))
    _surface.view.mouse_position = Vector2(box.end)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


## A click of *tool* at *at*, in document pixels, with Shift or Alt as given.
func _click(tool: ToolState, at: Vector2, shift: bool = false, alt: bool = false) -> void:
    _surface.view.mouse_position = at
    tool.handle_input(_button(true, shift, alt))
    tool.handle_input(_button(false))


static func _button(pressed: bool, shift: bool = false, alt: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.alt_pressed = alt
    return event


## The layer red all over, and the three bars blue on it, composited as a
## frame of the running app would, since nothing here draws one.
func _paint_bars() -> void:
    _doc.selection.deselect()
    _doc.fill_layer(RED, _doc.active_layer)
    for bar: Rect2i in BARS:
        _paint_rect(bar, BLUE)
    _composite()


func _composite() -> void:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()


## Fills *rect* of the active layer with *color* through a masked fill, then
## drops the selection.
func _paint_rect(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _doc.active_layer)
    _doc.selection.deselect()


## Whether each bar is wholly selected: its four corners and its centre whole.
func _bars_held() -> Array:
    var mask := _mask()
    var out: Array = []
    for bar: Rect2i in BARS:
        var points := [bar.position, bar.end - Vector2i.ONE, bar.get_center()]
        points.append(Vector2i(bar.position.x, bar.end.y - 1))
        points.append(Vector2i(bar.end.x - 1, bar.position.y))
        var whole := true
        for point: Vector2i in points:
            whole = whole and is_equal_approx(_at(mask, point.x, point.y), 1.0)
        out.append(whole)
    return out


func _coverage(x: int, y: int) -> float:
    return _at(_mask(), x, y)


## Every mask chunk read back once, by grid position, as its texels and its
## width in texels.
func _mask() -> Dictionary:
    var out := {}
    for grid: Vector2i in _doc.selection.chunks:
        var texture: SaTexture = _doc.selection.chunks[grid].field(SaSelection.FIELD)
        out[grid] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.size.x]
    return out


## Whether two read masks hold the same chunks with the same bytes.
static func _same(one: Dictionary, other: Dictionary) -> bool:
    if one.size() != other.size():
        return false
    for grid: Vector2i in one:
        if not other.has(grid) or one[grid][0] != other[grid][0]:
            return false
    return true


## The coverage at a document pixel, 0 where no chunk is.
static func _at(mask: Dictionary, x: int, y: int) -> float:
    var size := SaChunk.SIZE
    var grid := Vector2i(floori(float(x) / size), floori(float(y) / size))
    if not mask.has(grid):
        return 0.0
    var bytes: PackedByteArray = mask[grid][0]
    var width: int = mask[grid][1]
    var texel: int = SaFieldSpec.BYTES_PER_TEXEL[SaSelection.FORMAT]
    return bytes.decode_float(((y - grid.y * size) * width + x - grid.x * size) * texel)


## What the kernel is to write at *pixel* for the ellipse in *box*, done here on
## the CPU: in or out at the centre, and with an *edge* above nought, 0.5 plus
## the centre's estimated signed distance over it, clamped.
static func _expected(box: Rect2i, pixel: Vector2i, edge: float) -> float:
    var centre := Vector2(box.position) + Vector2(box.size) * 0.5
    var radii := (Vector2(box.size) * 0.5).max(Vector2(0.5, 0.5))
    var d := (Vector2(pixel) + Vector2(0.5, 0.5) - centre) / radii
    if edge <= 0.0:
        return 0.0 if d.dot(d) > 1.0 else 1.0
    var k0 := d.length()
    var k1 := (d / radii).length()
    var signed := k0 * (1.0 - k0) / k1 if k1 > 0.0 else minf(radii.x, radii.y)
    return clampf(0.5 + signed / edge, 0.0, 1.0)


## The share of *pixel* inside the ellipse in *box*, sampled sixteen by sixteen.
static func _sampled(box: Rect2i, pixel: Vector2i) -> float:
    var centre := Vector2(box.position) + Vector2(box.size) * 0.5
    var radii := Vector2(box.size) * 0.5
    var inside := 0
    for j in 16:
        for i in 16:
            var d := (Vector2(pixel) + Vector2((i + 0.5) / 16.0, (j + 0.5) / 16.0) - centre) / radii
            if d.dot(d) <= 1.0:
                inside += 1
    return inside / 256.0


## Every pixel of *area* whose coverage is not the sum's for the ellipse in
## *box*, with both numbers.
func _mismatches(mask: Dictionary, box: Rect2i, edge: float, area: Rect2i) -> Array:
    var out: Array = []
    for y in range(area.position.y, area.end.y):
        for x in range(area.position.x, area.end.x):
            var want := _expected(box, Vector2i(x, y), edge)
            var have := _at(mask, x, y)
            if absf(have - want) > CLOSE:
                out.append([Vector2i(x, y), have, want])
    return out
