## Threshold is a pixel function the
## base module registers through the call a module's own takes, under the same
## key, so a document saved with the written one opens unchanged.
##
## The two documents in `tests/data` were saved by the build before the move,
## one stored in sRGB and one in Oklab. Each holds a painted layer, an
## adjustment layer of Threshold at a level of 0.4 above it, and, hidden, the
## same painting thresholded in place by the written class at that level. The
## picture the adjustment layer makes now is the one that hidden layer holds,
## and so is the paint thresholded in place by the pixel function.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const MODULE_ID := &"sara-base-modules"
const KEY := &"sara-base-modules.threshold"
const LEVEL := 0.4
const SAVED: Array[String] = [
    "res://tests/data/threshold_before_the_move_srgb.sad",
    "res://tests/data/threshold_before_the_move_oklab.sad",
]
const SIZE := Vector2i(512, 256)
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const TOLERANCE := 1.0e-5

var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var module := BaseModule.new()
    module.register(_registries.context.for_module(module.get_id()))


func after_each() -> void:
    _registries.context.for_module(MODULE_ID).remove_all_registrations()


func _opened(path: String) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = _registries.filters
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "%s opens" % path.get_file())
    var layers: Array[SaLayer] = []
    for child in easel.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    return easel


func _layer(easel: SaEasel, name: String) -> SaLayer:
    return easel.document.get_node_or_null(name) as SaLayer


func _show(easel: SaEasel) -> PackedByteArray:
    easel.document.invalidate_chunks(GRIDS)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The widest gap between *got* and *want*, two textures of *format* and *size*
## read back, and where it is.
static func _worst(got: PackedByteArray, want: PackedByteArray, format: int, size: Vector2i) -> Array:
    if got == want:
        return [0.0, Vector2i.ZERO]
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    for y in size.y:
        for x in size.x:
            var at := y * size.x + x
            var off := _apart(SaFieldSpec.decode_texel(got, format, at), SaFieldSpec.decode_texel(want, format, at))
            if off > worst:
                worst = off
                worst_at = Vector2i(x, y)
    return [worst, worst_at]


func test_threshold_is_the_pixel_function_under_its_key_and_section() -> void:
    var filter := _registries.filters.get_filter(KEY)
    assert_true(filter is SaPixelFilter, "The base module registers Threshold as a pixel function")
    if filter is SaPixelFilter:
        var pixels := (filter as SaPixelFilter).pixels
        assert_true(pixels.path.ends_with("base/usual/threshold.gmacs"), "made from its `.gmacs`: %s" % pixels.path)
        assert_true(pixels.compute != null, "which compiles")
    assert_eq(_registries.filters.section_of(KEY), &"tone", "under Tone, where the written class was listed")
    assert_eq(filter.title() if filter != null else "", "Threshold", "with the title it had")


func test_each_document_saved_before_the_move_shows_the_same_picture() -> void:
    for path in SAVED:
        var errors := SaErrorCatcher.new()
        OS.add_logger(errors)
        var easel := _opened(path)
        var adjust := _layer(easel, "Threshold")
        assert_true(adjust != null and adjust.is_adjustment(), "%s holds the adjustment layer" % path.get_file())
        if adjust == null or adjust.filters.size() != 1:
            OS.remove_logger(errors)
            easel.free()
            continue
        assert_eq(adjust.filters[0].key, KEY, "whose record names Threshold's key")
        assert_almost_eq(float(adjust.filters[0].parameters.get("level", -1.0)), LEVEL, 1e-6, "at the level it was saved at")
        var adjusted := _show(easel)
        OS.remove_logger(errors)
        var said := "\n".join(errors.texts([SaErrorCatcher.ERROR]))
        assert_false(said.contains(String(KEY)), "and the chain runs it with nothing to say: %s" % said)

        _layer(easel, "Paint").visible = false
        adjust.visible = false
        _layer(easel, "Expected").visible = true
        var expected := _show(easel)
        var found := _worst(adjusted, expected, easel.output.format, easel.output.size)
        assert_true(
            float(found[0]) <= TOLERANCE,
            "%s shows what the written class wrote, worst %s at %s" % [path.get_file(), found[0], found[1]]
        )
        easel.free()


func test_the_pixel_function_thresholds_the_paint_as_the_written_class_did() -> void:
    for path in SAVED:
        var easel := _opened(path)
        var paint := _layer(easel, "Paint")
        var expected := _layer(easel, "Expected")
        var filter := _registries.filters.get_filter(KEY)
        filter.set_parameters({"level": LEVEL})
        var ctx := SaFilterContext.new(easel.document, paint, MODULE_ID, filter.title())
        assert_true(SaFilterApply.call_run(filter, ctx), "Threshold runs on %s" % path.get_file())
        assert_true(SaFilterOps.one_shot(ctx, filter), "and writes the paint")
        for grid in GRIDS:
            var got := paint.get_field(grid)
            var want := expected.get_field(grid)
            if got == null or want == null:
                assert_true(got == null and want == null, "%s holds chunk %s in both layers" % [path.get_file(), grid])
                continue
            var rd := GlobalShaderCompiler.get_rd()
            var found := _worst(rd.texture_get_data(got.rid, 0), rd.texture_get_data(want.rid, 0), got.format, got.size)
            assert_true(
                float(found[0]) <= TOLERANCE,
                "%s chunk %s holds what the written class wrote, worst %s at %s" % [path.get_file(), grid, found[0], found[1]]
            )
        easel.free()


## The written class recorded a point pass, so a Threshold attached to the whole
## document could be flattened into its layers, and the pixel function keeps it.
func test_threshold_on_the_document_is_still_flattened() -> void:
    var easel := _opened(SAVED[0])
    _layer(easel, "Threshold").visible = false
    var record := SaFilterOps.new(easel.document).attach(null, KEY, {"level": LEVEL})
    assert_not_null(record, "Threshold attaches to the document")
    _show(easel)
    assert_true(SaFilterOps.new(easel.document).flatten(null, record), "and flattens into its layers")
    easel.free()
