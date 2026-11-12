## Colour range: every texel within a fuzziness of a picked
## colour is chosen, into the selection in a mode or into a filter's mask.
##
## The document is three flat bands on the paint layer, a red, a red a little
## browner, and a blue, each read back through the coverage the engine wrote.
## The expected fraction is computed here from the same Oklab distance the
## kernel measures, so the suite says the maths is the page's rather than that
## a number came out.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const RED := Color(0.8, 0.2, 0.2, 1.0)
const NEAR := Color(0.72, 0.26, 0.2, 1.0)
const BLUE := Color(0.1, 0.3, 0.9, 1.0)

## One texel inside each band. The bands are chunk columns of a 512 square: red
## over the left half, the near red and the blue a quarter each on the right.
const IN_RED := Vector2i(100, 100)
const IN_NEAR := Vector2i(300, 100)
const IN_BLUE := Vector2i(450, 400)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _paint = _doc.get_node("Layer 1") as SaLayer
    _band(Rect2i(0, 0, 256, 512), RED)
    _band(Rect2i(256, 0, 128, 512), NEAR)
    _band(Rect2i(384, 0, 128, 512), BLUE)
    _doc.selection.deselect()
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _paint = null


func _band(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _paint)


## The coverage the selection holds at *at*, zero where it holds no chunk.
func _selected(at: Vector2i) -> float:
    var grid := Vector2i(floori(at.x / 256.0), floori(at.y / 256.0))
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    return Bench.texel(chunk.field(SaSelection.FIELD), at - grid * SaChunk.SIZE).r


## The Oklab distance between two display colours of an sRGB document, the
## number the kernel divides by the threshold.
static func _distance(a: Color, b: Color) -> float:
    return _oklab(a).distance_to(_oklab(b))


static func _oklab(c: Color) -> Vector3:
    var curve := SaTransferFunction.srgb()
    return SaOklab.from_linear_srgb(Vector3(curve.decode(c.r), curve.decode(c.g), curve.decode(c.b)))


func _range() -> SaColorRange:
    return SaColorRange.new(_doc)


func test_a_picked_colour_is_chosen_whole_a_far_one_not_and_a_near_one_in_part() -> void:
    var d := _distance(RED, NEAR)
    assert_true(d > 0.02 and d < 0.1, "The near red is near: %.3f in Oklab" % d)
    assert_true(_distance(RED, BLUE) > 0.3, "and the blue is far")
    _range().select(RED, 30.0, SaSelection.Mode.REPLACE, _easel.output)
    assert_true(_doc.selection.active, "A range is a selection")
    assert_almost_eq(_selected(IN_RED), 1.0, 0.001, "The picked colour is chosen whole")
    assert_almost_eq(_selected(IN_BLUE), 0.0, 0.001, "a colour past the threshold not at all")
    var expected := 1.0 - d / SaColorRange.threshold(30.0)
    assert_almost_eq(_selected(IN_NEAR), expected, 0.01, "and one within it by the linear falloff")
    assert_true(_selected(IN_NEAR) > 0.05 and _selected(IN_NEAR) < 0.95, "which is a fraction")

    var at_30 := _selected(IN_NEAR)
    _range().select(RED, 60.0, SaSelection.Mode.REPLACE, _easel.output)
    assert_true(_selected(IN_NEAR) > at_30, "More fuzziness chooses more of the near red")
    assert_almost_eq(_selected(IN_NEAR), 1.0 - d / SaColorRange.threshold(60.0), 0.01, "by the same falloff")


func test_the_box_is_measured_and_a_chunk_it_misses_is_dropped() -> void:
    _range().select(BLUE, 10.0, SaSelection.Mode.REPLACE, _easel.output)
    assert_eq(_doc.selection.bounds, Rect2i(384, 0, 128, 512), "The box is the blue band")
    assert_false(_doc.selection.chunks.has(Vector2i(0, 0)), "and the chunks it misses are not kept")


func test_a_range_adds_to_a_selection_and_is_taken_out_of_one() -> void:
    _range().select(RED, 5.0, SaSelection.Mode.REPLACE, _easel.output)
    assert_almost_eq(_selected(IN_BLUE), 0.0, 0.001, "The red alone")
    _range().select(BLUE, 5.0, SaSelection.Mode.ADD, _easel.output)
    assert_almost_eq(_selected(IN_RED), 1.0, 0.001, "Add keeps the red")
    assert_almost_eq(_selected(IN_BLUE), 1.0, 0.001, "and joins the blue")
    _range().select(RED, 5.0, SaSelection.Mode.SUBTRACT, _easel.output)
    assert_almost_eq(_selected(IN_RED), 0.0, 0.001, "Subtract takes the red out")
    assert_almost_eq(_selected(IN_BLUE), 1.0, 0.001, "and leaves the blue")
    assert_eq(_doc.selection.bounds, Rect2i(384, 0, 128, 512), "and the box shrinks to what is left")


func test_a_subtract_with_nothing_selected_does_nothing() -> void:
    _range().select(RED, 5.0, SaSelection.Mode.SUBTRACT, _easel.output)
    assert_false(_doc.selection.active, "Everything was selected and still is")


func test_a_transparent_texel_is_measured_over_the_mid_grey_and_not_as_black() -> void:
    _paint.release_chunks()
    var grey := SaColorRange.NEUTRAL_BACKDROP
    _range().select(grey, 10.0, SaSelection.Mode.REPLACE, null, _paint)
    assert_almost_eq(_selected(IN_RED), 1.0, 0.001, "An empty layer read alone is the grey behind it")
    _range().select(Color.BLACK, 10.0, SaSelection.Mode.REPLACE, null, _paint)
    assert_almost_eq(_selected(IN_RED), 0.0, 0.001, "and not black")


func test_the_layer_alone_is_read_when_sample_merged_is_off() -> void:
    # The paint switched to nothing, so the picture is the grey background and
    # only the layer itself still holds the red.
    _paint.opacity = 0.0
    _doc.invalidate_all_allocated_chunks()
    Bench.composite(_easel)
    _range().select(RED, 5.0, SaSelection.Mode.REPLACE, _easel.output)
    assert_almost_eq(_selected(IN_RED), 0.0, 0.001, "The merged picture holds no red")
    _range().select(RED, 5.0, SaSelection.Mode.REPLACE, null, _paint)
    assert_almost_eq(_selected(IN_RED), 1.0, 0.001, "and the layer read alone does")
    assert_almost_eq(_selected(IN_BLUE), 0.0, 0.001, "its blue still not")


func test_a_filters_mask_is_filled_from_the_docker_as_one_step() -> void:
    var record := SaFilterOps.new(_doc).attach(_paint, Bench.INVERT)
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    docker.item_list.picked.pick_filter(record)
    docker.actions.sync_from_active_layer()
    assert_true(docker.actions.menu_titles().has("Mask from Colour Range..."), "A picked filter's menu offers the colour range")
    var steps := _doc.history.step_count()
    # Sample merged, with the invert over the whole layer: the picture is read
    # with the filter off, or the blue would be its inverse and choose nothing.
    assert_true(docker.actions.apply_color_range(BLUE, 10.0, true), "The range fills the filter's mask")
    assert_not_null(record.mask, "giving the record one")
    assert_true(record.enabled, "and the filter is switched back on after the read")
    assert_almost_eq(
        Bench.texel(record.mask.texture_for(Vector2i(1, 1)), IN_BLUE - Vector2i(256, 256)).r, 1.0, 0.001, "over the blue"
    )
    assert_almost_eq(Bench.texel(record.mask.texture_for(Vector2i(0, 0)), IN_RED).r, 0.0, 0.001, "and not the red")
    assert_false(_doc.selection.active, "The selection is left alone")
    assert_eq(_doc.history.step_count(), steps + 1, "One step")
    _doc.undo()
    assert_null(record.mask, "and one undo takes the mask away again")
    assert_true(docker.actions.apply_color_range(RED, 5.0, false), "The layer alone is read with merged off")
    assert_almost_eq(Bench.texel(record.mask.texture_for(Vector2i(0, 0)), IN_RED).r, 1.0, 0.001, "and chooses its red")
    docker.free()
    canvas.free()
