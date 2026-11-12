## Colour Range at its default fuzziness keeps off a neutral ground, and
## previews, and at a hundred chooses every texel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A blue picked over a grey ground at the
## default fuzziness of forty chose the ground at about 60 percent, because the
## threshold was the fuzziness over a hundred taken as an Oklab distance and a
## mid blue is only 0.14 from a mid grey. The dialog showed nothing on the
## canvas while it was open, so the only way to tune the number was Apply, look
## and undo.
##
## The threshold is now a curve narrow at its low end, and the dialog fills a
## scratch selection the canvas's overlay draws as the quick mask's tint. The
## running app is
## `scenarios/colour-range-at-its-default-fuzziness-keeps-off-a-neutral-ground-and.json`.
##
## The curve once ended at an Oklab distance of one at a hundred, so a pure white
## pick left pure black at exactly zero at the top of the slider, and a float
## colour further out was out of reach. The top of the slider is now the whole
## picture, `SaColorRange.UNBOUNDED`, and the falloff below it is as it was.
##
## The picture is four patches of a 512 square, one chunk each: the grey ground,
## the blue picked, a yellow and a black. The expected coverage is
## computed here from the same Oklab distance the kernel measures, the way
## `test_color_range.gd` does it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const GREY := Color(0.5, 0.5, 0.5, 1.0)
const BLUE := Color(60.0 / 255.0, 120.0 / 255.0, 200.0 / 255.0, 1.0)
const YELLOW := Color(0.95, 0.85, 0.1, 1.0)
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
## A float document holds a colour far past white, which stands further from a
## white pick than black does.
const BRIGHT := Color(40.0, 40.0, 40.0, 1.0)

const IN_GREY := Vector2i(100, 100)
const IN_BLUE := Vector2i(400, 100)
const IN_YELLOW := Vector2i(100, 400)
const IN_BLACK := Vector2i(400, 400)

var _kept_embedding: bool = true
var _kept_foreground: Color = Color.BLACK
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _canvas: SaCanvas = null
var _overlay: SaSelectionOverlay = null
var _dialog: SaColorRangeDialog = null
var _host: Node = null
var _doc: SaDocument = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_foreground = SaColors.foreground
    _surface = SaSurface.create(&"test", Bench.easel(Vector2i(512, 512)), Fixtures.FakeView.new())
    _doc = _surface.easel.document
    var paint := _doc.get_node("Layer 1") as SaLayer
    for patch: Array in [
        [Rect2i(0, 0, 256, 256), GREY],
        [Rect2i(256, 0, 256, 256), BLUE],
        [Rect2i(0, 256, 256, 256), YELLOW],
        [Rect2i(256, 256, 256, 256), BLACK],
    ]:
        _doc.selection.select_rect(patch[0])
        _doc.fill_layer(patch[1], paint)
    _doc.selection.deselect()
    Bench.composite(_surface.easel)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    # The machine as the canvas's own child, which is where the dialog looks for
    # the overlay to hand its preview to.
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _canvas.add_child(_machine)
    _overlay = SaSelectionOverlay.attach_to(_canvas)
    _host = Node.new()
    _host.name = "S15TestHost"
    EventBus.add_child(_host)
    _dialog = SaColorRangeDialog.new()
    _host.add_child(_dialog)


func after_each() -> void:
    _dialog.free()
    _dialog = null
    _host.free()
    _host = null
    _canvas.remove_child(_machine)
    _canvas.easel = null
    _canvas.free()
    _canvas = null
    _overlay = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    SaColors.foreground = _kept_foreground
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func _open(fuzziness: float = SaColorRange.DEFAULT_FUZZINESS) -> void:
    _dialog.open(BLUE, fuzziness, true, int(SaSelection.Mode.REPLACE), true, _machine)


## What the dialog's next frame does, which a suite cannot wait for.
func _a_frame() -> void:
    _dialog._process(0.0)


static func _covered(region: Dictionary, at: Vector2i) -> float:
    var grid := Vector2i(floori(at.x / 256.0), floori(at.y / 256.0))
    var chunk: SaChunk = region.get(grid, null)
    if chunk == null:
        return 0.0
    return Bench.texel(chunk.field(SaSelection.FIELD), at - grid * SaChunk.SIZE).r


func _range(fuzziness: float, pick: Color = BLUE) -> Dictionary:
    return SaColorRange.new(_doc).coverage(pick, fuzziness, _surface.easel.output)


## The Oklab distance between two display colours of an sRGB document, the
## number the kernel divides by the threshold.
static func _distance(a: Color, b: Color) -> float:
    return _oklab(a).distance_to(_oklab(b))


static func _oklab(c: Color) -> Vector3:
    var curve := SaTransferFunction.srgb()
    return SaOklab.from_linear_srgb(Vector3(curve.decode(c.r), curve.decode(c.g), curve.decode(c.b)))


func test_the_curve_is_narrow_at_its_low_end_and_reaches_one_at_a_hundred() -> void:
    assert_almost_eq(SaColorRange.threshold(0.0), 0.0, 0.0001, "Nothing but the colour itself at zero")
    assert_almost_eq(SaColorRange.threshold(40.0), 0.101, 0.001, "0.10 at the default forty")
    assert_almost_eq(SaColorRange.threshold(60.0), 0.279, 0.001, "0.28 at sixty")
    assert_almost_eq(SaColorRange.threshold(99.0), 0.975, 0.001, "0.975 at ninety-nine, short of black to white")
    assert_eq(SaColorRange.threshold(100.0), SaColorRange.UNBOUNDED, "and no distance at a hundred")
    assert_eq(SaColorRange.threshold(250.0), SaColorRange.UNBOUNDED, "nor past it")
    var last := -1.0
    for fuzziness in range(0, 101, 5):
        var now := SaColorRange.threshold(float(fuzziness))
        assert_true(now > last, "The threshold grows with the fuzziness, at %d" % fuzziness)
        last = now


func test_at_the_default_a_mid_blue_leaves_the_grey_ground_at_zero() -> void:
    var d := _distance(BLUE, GREY)
    assert_almost_eq(d, 0.14, 0.01, "The reference blue is 0.14 from the grey in Oklab")
    assert_true(d > SaColorRange.threshold(SaColorRange.DEFAULT_FUZZINESS), "which lies past the default's threshold")
    var region := _range(SaColorRange.DEFAULT_FUZZINESS)
    assert_almost_eq(_covered(region, IN_BLUE), 1.0, 0.001, "The picked blue is chosen whole")
    assert_almost_eq(_covered(region, IN_GREY), 0.0, 0.001, "and the grey ground not at all, where it was 0.65")
    assert_almost_eq(_covered(region, IN_YELLOW), 0.0, 0.001, "nor the yellow")
    assert_almost_eq(_covered(region, IN_BLACK), 0.0, 0.001, "nor the black")


func test_at_sixty_the_grey_is_chosen_in_part() -> void:
    var expected := 1.0 - _distance(BLUE, GREY) / SaColorRange.threshold(60.0)
    var region := _range(60.0)
    assert_almost_eq(_covered(region, IN_GREY), expected, 0.01, "The grey by the linear falloff")
    assert_true(_covered(region, IN_GREY) > 0.3 and _covered(region, IN_GREY) < 0.7, "which is about half")
    assert_almost_eq(_covered(region, IN_YELLOW), 0.0, 0.001, "and the yellow still not")


func test_at_a_hundred_everything_is_chosen_at_full_strength() -> void:
    var region := _range(SaColorRange.MAX_FUZZINESS)
    for at: Vector2i in [IN_GREY, IN_BLUE, IN_YELLOW, IN_BLACK]:
        assert_almost_eq(_covered(region, at), 1.0, 0.0001, "Every patch is chosen whole at a hundred, %s" % at)


func test_a_white_pick_chooses_pure_black_at_a_hundred_and_not_at_ninety_nine() -> void:
    assert_true(_distance(WHITE, BLACK) > 0.99, "Black is a whole Oklab unit from white")
    var all := _range(SaColorRange.MAX_FUZZINESS, WHITE)
    for at: Vector2i in [IN_GREY, IN_BLUE, IN_YELLOW, IN_BLACK]:
        assert_almost_eq(_covered(all, at), 1.0, 0.0001, "A white pick at a hundred chooses every patch, %s" % at)
    var short := _range(99.0, WHITE)
    assert_almost_eq(_covered(short, IN_BLACK), 0.0, 0.001, "and at ninety-nine the black is still at zero")
    assert_true(_covered(short, IN_GREY) > 0.0, "while the grey is in part, the falloff below a hundred as it was")


func test_a_colour_far_past_white_is_chosen_at_a_hundred() -> void:
    _doc.selection.select_rect(Rect2i(0, 256, 256, 256))
    _doc.fill_layer(BRIGHT, _doc.get_node("Layer 1") as SaLayer)
    _doc.selection.deselect()
    Bench.composite(_surface.easel)
    assert_true(_distance(WHITE, BRIGHT) > 5.0, "The bright patch is far past one from white in Oklab")
    assert_almost_eq(_covered(_range(99.0, WHITE), IN_YELLOW), 0.0, 0.001, "At ninety-nine it is out of reach")
    assert_almost_eq(_covered(_range(SaColorRange.MAX_FUZZINESS, WHITE), IN_YELLOW), 1.0, 0.0001, "and at a hundred whole")


func test_the_preview_is_filled_while_the_dialog_is_open() -> void:
    _open()
    assert_null(_dialog.preview, "Nothing is measured before the first frame")
    _a_frame()
    assert_not_null(_dialog.preview, "The first frame of the open dialog fills the preview")
    assert_true(_dialog.preview.active, "which is a selection")
    assert_eq(_dialog.preview.chunks.size(), 4, "over every chunk the view shows")
    assert_almost_eq(_covered(_dialog.preview.chunks, IN_BLUE), 1.0, 0.001, "choosing the blue")
    assert_almost_eq(_covered(_dialog.preview.chunks, IN_GREY), 0.0, 0.001, "and not the grey")
    assert_false(_doc.selection.active, "The document's selection is left alone")
    assert_eq(_overlay.selection_preview, _dialog.preview, "The canvas's overlay is handed the preview")
    _overlay._process(0.0)
    var state := _overlay.capture_state()
    assert_true(bool(state["preview"]["on"]), "and says it draws it")
    assert_true(bool(state["tint"]["on"]), "as the quick mask's tint")


func test_moving_the_fuzziness_changes_the_preview_on_the_next_frame() -> void:
    _open()
    _a_frame()
    var before := _dialog.preview.chunks.duplicate()
    _dialog._fuzziness_row.drive(100)
    assert_eq(_dialog.preview.chunks, before, "A move is measured on the frame and not on the signal")
    _a_frame()
    assert_true(_covered(_dialog.preview.chunks, IN_GREY) > 0.5, "At a hundred the preview takes the grey in")
    var after := _dialog.preview.chunks.duplicate()
    _a_frame()
    assert_eq(_dialog.preview.chunks, after, "and a frame with nothing moved measures nothing")
    # The swatch holds a hex, so the grey it takes is 128 over 255 and not the
    # ground's half, a step the falloff leaves just under one.
    _dialog._color_row.drive("#808080")
    _dialog._fuzziness_row.drive(40)
    _a_frame()
    assert_true(_covered(_dialog.preview.chunks, IN_GREY) > 0.95, "A grey pick takes the ground")
    assert_almost_eq(_covered(_dialog.preview.chunks, IN_BLUE), 0.0, 0.001, "and leaves the blue")


func test_closing_the_dialog_clears_the_preview() -> void:
    for way: String in ["apply", "cancel", "escape or the corner"]:
        _open()
        _a_frame()
        assert_not_null(_dialog.preview, "%s: the preview is there while open" % way)
        match way:
            "apply":
                _dialog.apply_range()
            "cancel":
                _dialog.page.cancelled.emit()
            "escape or the corner":
                _dialog.close_requested.emit()
        assert_null(_dialog.preview, "%s clears the preview" % way)
        assert_null(_overlay.selection_preview, "%s takes it off the canvas" % way)
        assert_eq(int(_dialog.describe()["preview_chunks"]), -1, "%s: the dump says there is none" % way)


func test_the_preview_measures_only_the_chunks_the_view_shows() -> void:
    _surface.easel.shown_rect = func() -> Rect2: return Rect2(10.0, 300.0, 100.0, 100.0)
    _open()
    _a_frame()
    assert_eq(_dialog.preview.chunks.keys(), [Vector2i(0, 1)], "One chunk on screen, one chunk measured")
    _surface.easel.shown_rect = func() -> Rect2: return Rect2(300.0, 10.0, 100.0, 100.0)
    _a_frame()
    assert_eq(_dialog.preview.chunks.keys(), [Vector2i(1, 0)], "and a pan measures the chunk it shows")
    _surface.easel.shown_rect = func() -> Rect2: return Rect2(-900.0, -900.0, 100.0, 100.0)
    _a_frame()
    assert_true(_dialog.preview.chunks.is_empty(), "A view off the canvas measures nothing")
    _surface.easel.shown_rect = Callable()
