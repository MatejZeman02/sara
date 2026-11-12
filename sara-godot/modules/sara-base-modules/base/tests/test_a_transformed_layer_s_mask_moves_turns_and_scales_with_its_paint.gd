## A transformed layer's mask moves, turns and scales with its
## paint, and does not stay behind when the layer moves.
##
## The painting is four chunks across and two down, the grey background
## hidden, and one layer whose first chunk is opaque red all over, written
## whole rather than by a brush. Its mask hides the columns of the box's left
## half, x 64 to 127, and shows everything else, so a mask that stayed behind
## and a mask that moved read differently at every point the suite reads.
##
## The Transform tool's two paths are both read. An ordinary layer, with or
## without a selection, takes `SaTransform`'s lift, which the Enter commits,
## and a smart layer takes `SaLiveTransform`'s map, which a bake commits.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 512)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## The transform's box, the tight box of the paint the tool would draw.
const BOX := Rect2i(64, 64, 128, 128)
## The columns the mask hides, the box's left half.
const HIDDEN := Rect2i(64, 0, 64, 256)
## The selected square, across the mask's edge at x 128.
const SQUARE := Rect2i(96, 96, 64, 64)
const MOVE := Vector2i(64, 0)
const NEAR := 1.0e-3

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _pass: SaTransform = null
var _scratch: String = SaDataRoot.path("test_masked.sad")


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    var albedo := _layer.get_or_create_chunk(Vector2i.ZERO).albedo()
    var image := Image.create_empty(albedo.size.x, albedo.size.y, false, Image.FORMAT_RGBAF)
    image.fill(RED)
    if albedo.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    GlobalShaderCompiler.get_rd().texture_update(albedo.rid, 0, image.get_data())
    _layer.mark_unresolved(Vector2i.ZERO)
    assert_true(SaMaskOps.new(_doc).add(_layer), "The layer gets a mask")
    var field := SaMaskOps.mask_of(_layer).get_or_create(Vector2i.ZERO)
    var hidden := Image.create_empty(field.size.x, field.size.y, false, Image.FORMAT_RF)
    hidden.fill(Color(1, 0, 0, 0))
    hidden.fill_rect(HIDDEN, Color(0, 0, 0, 0))
    GlobalShaderCompiler.get_rd().texture_update(field.rid, 0, hidden.get_data())
    _pass = SaTransform.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_scratch))


## What *layer*'s mask reads at the document pixel *at*, its rest where the
## layer holds no chunk.
static func _mask_at(layer: SaLayer, at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaLayer.CHUNK_SIZE), floori(float(at.y) / SaLayer.CHUNK_SIZE))
    var texture := layer.get_field(grid, SaFieldSpec.MASK)
    if texture == null:
        return layer.mask.rest
    return Bench.texel(texture, at - grid * SaLayer.CHUNK_SIZE).r


static func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaLayer.CHUNK_SIZE), floori(float(at.y) / SaLayer.CHUNK_SIZE))
    var texture := layer.get_field(grid)
    return Bench.texel(texture, at - grid * SaLayer.CHUNK_SIZE).a if texture != null else 0.0


## What the view shows at *at*, its alpha.
func _shown_at(at: Vector2i) -> float:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, at).a


func test_a_move_with_no_selection_carries_the_mask_and_one_undo_puts_both_back() -> void:
    var steps := _doc.history.step_count()
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 1.0, NEAR, "Before the move the mask shows x 150")
    assert_true(_pass.lift(_layer, BOX), "The box over masked paint lifts")
    _pass.preview(MOVE)
    _pass.tick()
    assert_almost_eq(
        _mask_at(_layer, Vector2i(150, 100)), 0.0, NEAR, "While the hand moves, the mask hides where its hidden half went"
    )
    assert_almost_eq(_shown_at(Vector2i(150, 100)), 0.0, NEAR, "and the view shows nothing of the moved paint there")
    assert_almost_eq(_shown_at(Vector2i(220, 100)), 1.0, NEAR, "and shows the moved paint under the shown half")
    assert_true(_pass.commit(), "Enter writes the move down")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 0.0, NEAR, "The hidden half stands 64 px right, x 128 to 191")
    assert_almost_eq(_mask_at(_layer, Vector2i(220, 100)), 1.0, NEAR, "and the shown half beside it")
    assert_almost_eq(_alpha_at(_layer, Vector2i(220, 100)), 1.0, NEAR, "over the paint that moved with it")
    assert_almost_eq(_mask_at(_layer, Vector2i(100, 100)), _layer.mask.rest, NEAR, "The hole the paint left reads the rest")
    assert_almost_eq(_alpha_at(_layer, Vector2i(100, 100)), 0.0, NEAR, "and holds no paint")
    assert_almost_eq(_mask_at(_layer, Vector2i(100, 30)), 0.0, NEAR, "Outside the box the mask is as it was")
    assert_almost_eq(_mask_at(_layer, Vector2i(30, 100)), 1.0, NEAR, "on both sides")
    assert_almost_eq(_shown_at(Vector2i(150, 100)), 0.0, NEAR, "The view hides the moved hidden half")

    assert_true(_doc.undo(), "One undo")
    assert_almost_eq(_mask_at(_layer, Vector2i(100, 100)), 0.0, NEAR, "puts the mask's hidden half back")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 1.0, NEAR, "and its shown half")
    assert_almost_eq(_alpha_at(_layer, Vector2i(100, 100)), 1.0, NEAR, "and the paint with them")
    assert_almost_eq(_alpha_at(_layer, Vector2i(220, 100)), 1.0, NEAR, "which never left the rest of its chunk")

    assert_true(_doc.redo(), "A redo")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 0.0, NEAR, "moves the mask again")


func test_a_move_into_a_chunk_the_layer_does_not_hold_carries_the_mask_there() -> void:
    var far := Vector2i(256, 0)
    assert_true(_pass.lift(_layer, BOX), "The box lifts")
    _pass.preview(far)
    _pass.tick()
    assert_almost_eq(
        _shown_at(Vector2i(350, 100)), 0.0, NEAR, "While the hand moves, the new chunk's paint is hidden where the mask went"
    )
    assert_true(_pass.commit(), "Enter writes the move down")
    assert_almost_eq(_mask_at(_layer, Vector2i(350, 100)), 0.0, NEAR, "The hidden half stands in the second chunk")
    assert_almost_eq(_mask_at(_layer, Vector2i(420, 100)), 1.0, NEAR, "beside the shown half")
    assert_true(_doc.undo(), "One undo")
    assert_false(_layer.chunks.has(Vector2i(1, 0)), "takes the chunk the landing made away again")
    assert_almost_eq(_mask_at(_layer, Vector2i(100, 100)), 0.0, NEAR, "and puts the mask back")


func test_escape_puts_the_mask_back() -> void:
    assert_true(_pass.lift(_layer, BOX), "The box lifts")
    _pass.preview(MOVE)
    _pass.tick()
    _pass.preview(MOVE * 2)
    _pass.tick()
    _pass.cancel()
    assert_almost_eq(_mask_at(_layer, Vector2i(100, 100)), 0.0, NEAR, "Escape fills the mask's hole back in")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 1.0, NEAR, "and takes off both frames' landings")
    assert_almost_eq(_mask_at(_layer, Vector2i(220, 100)), 1.0, NEAR, "on the far side as well")


func test_a_quarter_turn_turns_the_mask() -> void:
    assert_almost_eq(_mask_at(_layer, Vector2i(156, 80)), 1.0, NEAR, "Before the turn the top right of the box shows")
    assert_true(_pass.lift(_layer, BOX), "The box lifts")
    _pass.preview_affine(Vector2i.ZERO, Vector2.ONE, PI / 2.0)
    _pass.tick()
    assert_true(_pass.commit(), "and turns a quarter clockwise")
    assert_almost_eq(_mask_at(_layer, Vector2i(156, 80)), 0.0, NEAR, "The hidden left half is now the top half")
    assert_almost_eq(_mask_at(_layer, Vector2i(80, 80)), 0.0, NEAR, "across the whole width")
    assert_almost_eq(_mask_at(_layer, Vector2i(80, 176)), 1.0, NEAR, "and the bottom half shows")
    assert_almost_eq(_mask_at(_layer, Vector2i(176, 176)), 1.0, NEAR, "on the far side as well")
    assert_true(_doc.undo(), "One undo")
    assert_almost_eq(_mask_at(_layer, Vector2i(156, 80)), 1.0, NEAR, "turns it back")


func test_a_scale_scales_the_mask() -> void:
    assert_almost_eq(_mask_at(_layer, Vector2i(40, 128)), 1.0, NEAR, "Before the scale x 40 shows")
    assert_true(_pass.lift(_layer, BOX), "The box lifts")
    _pass.preview_affine(Vector2i.ZERO, Vector2(1.5, 1.5), 0.0)
    _pass.tick()
    assert_true(_pass.commit(), "and scales by one and a half about its middle")
    assert_almost_eq(_mask_at(_layer, Vector2i(40, 128)), 0.0, NEAR, "The hidden half reaches x 40")
    assert_almost_eq(_mask_at(_layer, Vector2i(130, 128)), 1.0, NEAR, "and stops at the middle")


func test_a_selected_square_carries_the_mask_inside_it_and_leaves_the_rest() -> void:
    _doc.selection.select_rect(SQUARE)
    assert_true(_pass.lift(_layer, SQUARE), "The selected square lifts")
    _pass.preview(MOVE)
    _pass.tick()
    assert_true(_pass.commit(), "and moves 64 px right")
    assert_almost_eq(_mask_at(_layer, Vector2i(170, 120)), 0.0, NEAR, "Inside the landed square the hidden part moved")
    assert_almost_eq(_mask_at(_layer, Vector2i(210, 120)), 1.0, NEAR, "beside its shown part")
    assert_almost_eq(_mask_at(_layer, Vector2i(110, 120)), _layer.mask.rest, NEAR, "The hole reads the rest")
    assert_almost_eq(_mask_at(_layer, Vector2i(80, 120)), 0.0, NEAR, "Outside the square the hidden columns stay")
    assert_almost_eq(_mask_at(_layer, Vector2i(110, 170)), 0.0, NEAR, "below it too")
    assert_almost_eq(_mask_at(_layer, Vector2i(170, 80)), 1.0, NEAR, "and above the landing it still shows")
    assert_almost_eq(_mask_at(_layer, Vector2i(230, 120)), 1.0, NEAR, "and right of it")
    assert_true(_doc.undo(), "One undo")
    assert_almost_eq(_mask_at(_layer, Vector2i(110, 120)), 0.0, NEAR, "puts the square's mask back")
    assert_almost_eq(_mask_at(_layer, Vector2i(170, 120)), 1.0, NEAR, "and takes the landing off")


func test_a_smart_layer_s_bake_carries_the_mask() -> void:
    var map := SaLiveTransform.composed(Vector2(MOVE), 0.0, Vector2.ONE, Vector2(SIZE) * 0.5)
    assert_true(SaLiveTransform.put(_doc, _layer, map), "The layer takes a live move")
    assert_almost_eq(_shown_at(Vector2i(150, 100)), 0.0, NEAR, "and the view hides where the hidden half went")
    assert_true(SaLiveTransform.bake(_doc, _layer), "The bake runs")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 0.0, NEAR, "The baked mask hides x 128 to 191")
    assert_almost_eq(_mask_at(_layer, Vector2i(200, 100)), 1.0, NEAR, "and shows beside it")
    assert_true(_doc.undo(), "One undo")
    _doc.undo()
    assert_null(_layer.live_transform, "with the map's own step, takes the move off")
    assert_almost_eq(_mask_at(_layer, Vector2i(150, 100)), 1.0, NEAR, "and the mask is where it was")


func test_a_moved_mask_comes_back_from_a_save() -> void:
    assert_true(_pass.lift(_layer, BOX), "The box lifts")
    _pass.preview(MOVE)
    _pass.tick()
    assert_true(_pass.commit(), "and moves")
    assert_eq(SaExport.save_sad(_doc, ProjectSettings.globalize_path(_scratch), 0), OK, "The painting saves")
    var reopened := SaDocument.new()
    assert_eq(SaExport.load_sad(reopened, ProjectSettings.globalize_path(_scratch), SaCompositor.new()), OK, "and opens")
    var layer: SaLayer = null
    for child in reopened.get_children():
        if child is SaLayer and (child as SaLayer).mask != null:
            layer = child
    assert_not_null(layer, "with the masked layer")
    if layer != null:
        assert_almost_eq(_mask_at(layer, Vector2i(150, 100)), 0.0, NEAR, "whose mask hides where it was moved to")
        assert_almost_eq(_mask_at(layer, Vector2i(220, 100)), 1.0, NEAR, "and shows beside it")
    reopened.free()


## A press and its release at *at* in the document, which lays one dab.
static func _tap(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = at
        machine.active_tool.handle_input(event)


## A mask stroke painted while a live map stands lands in the layer's own
## pixels where the map takes the pointer back, so after the bake it stands
## under the pointer, over the paint it was painted on.
func test_a_mask_stroke_under_a_live_map_lands_where_the_paint_it_hides_is() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := surface.get_document()
    (doc.get_node("Background") as SaLayer).visible = false
    var layer := doc.active_layer
    layer.fill(RED)
    assert_true(SaMaskOps.new(doc).add(layer), "The layer gets a mask")
    var map := SaLiveTransform.composed(Vector2(MOVE), 0.0, Vector2.ONE, Vector2(256.0, 256.0))
    assert_true(SaLiveTransform.put(doc, layer, map), "and a live move of 64 px right")
    doc.mask_target = SaMaskOps.mask_of(layer)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    # Black hides, so the dab is a hole in the coverage the suite can find.
    machine.active_tool.settings.color = Color.BLACK
    var pointer := Vector2i(300, 200)
    _tap(machine, Vector2(pointer))
    assert_true(
        _mask_at(layer, pointer - MOVE) < 0.5,
        "The dab lands in the mask's own pixels under the paint the pointer is over, %f" % _mask_at(layer, pointer - MOVE)
    )
    assert_almost_eq(_mask_at(layer, pointer), 1.0, NEAR, "and not where the pointer is in the layer's unmoved pixels")
    doc.update_caches()
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    var shown := Bench.texel(surface.easel.output, pointer).a
    assert_true(shown < 0.5, "and the view hides the moved paint under the pointer, %f" % shown)
    assert_true(SaLiveTransform.bake(doc, layer), "The bake runs")
    assert_true(_mask_at(layer, pointer) < 0.5, "and the dab stands under the pointer with the paint")
    Fixtures.teardown(surface, machine)
