## A module's pixel kernel is a filter layer kind as every
## built-in filter is.
##
## The fixture module registers one `.gmacs` and nothing else. Its kernel
## is added over a painted layer the two ways the Filter dialog offers, Layer
## and Attach, its slider is set through the rows the layer's filter panel
## draws, and the document is saved and opened again: once with the module, to
## read the slider and the same texels, and once without it, to read the record
## kept and written back unchanged. Last, a record saved before the kernel
## gained a `uniform` opens with that uniform at the value its line declares.
##
## Before this row a pixel function showed a texture rather than recording a
## pass, so the chain skipped its record and the dialog dimmed Layer.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const FixtureModule = preload("res://tests/fixtures/modules/pixel-filter-fixture/module.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const KEY := &"pixel-filter-fixture.threshold"
## A grey whose luminance is 0.4, under the kernel's default level of 0.5 and
## over the level the slider is set to, so the slider is seen in the texels.
const GREY := Color(0.4, 0.4, 0.4, 1.0)
const HALF := Color(0.9, 0.6, 0.2, 0.5)
const LEVEL := 0.3

## The suite's own module for the record saved before a `uniform` was added,
## and the kernel as it was then and as it is now.
const LATER_MODULE := &"l3-suite"
const LATER_KEY := &"l3-suite.l3_later"
const BEFORE_SOURCE := """uniform float level: hint_range(0, 1) = 0.5

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(vec3(step(level, luminance(c.rgb))), c.a)
"""
const AFTER_SOURCE := """uniform float level: hint_range(0, 1) = 0.5
uniform float lift: hint_range(0, 1) = 0.25

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(vec3(max(step(level, luminance(c.rgb)), lift)), c.a)
"""

static var scratch_later_path: String = SaDataRoot.path("l3_later.gmacs")

var _registries: SaRegistries = null
var _paths: Array[String] = []
var _host: VBoxContainer = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var module := FixtureModule.new()
    module.register(_registries.context.for_module(module.get_id()))
    _paths = []


func after_each() -> void:
    _registries.context.for_module(&"pixel-filter-fixture").remove_all_registrations()
    for path in _paths:
        DirAccess.remove_absolute(path)
    DirAccess.remove_absolute(scratch_later_path)


## An easel whose chain answers keys from *filters*, the grey background
## hidden, the grey over the left chunk and the half alpha stroke over the
## right one.
func _painting(filters: SaFilterRegistry) -> SaEasel:
    var easel := _easel(filters)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(paint)
    paint.get_or_create_chunk(LEFT).clear(GREY)
    paint.get_or_create_chunk(RIGHT).clear(HALF)
    return easel


func _easel(filters: SaFilterRegistry) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = filters
    return easel


func _show(easel: SaEasel) -> PackedByteArray:
    easel.document.invalidate_chunks([LEFT, RIGHT])
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


func _texel(easel: SaEasel, bytes: PackedByteArray, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(bytes, easel.output.format, at.y * easel.output.size.x + at.x)


## The rows the layer's filter panel draws for *record*, the way the panel
## draws them: the one instance the registry holds, handed the record's values.
func _panel(easel: SaEasel, record: SaAttachedFilter) -> SaDialog:
    var filter := easel.compositor.filter_chain.registry.get_filter(record.key)
    assert_not_null(filter, "%s is registered" % record.key)
    if filter == null:
        return null
    var dialog := SaDialog.for_filter(filter)
    filter.set_parameters(record.parameters)
    _host = VBoxContainer.new()
    dialog.realize(_host)
    return dialog


## Moves the level slider of *record*'s panel to *value* and writes it back
## through the call the panel's own write back makes.
func _set_slider(easel: SaEasel, record: SaAttachedFilter, value: float) -> void:
    var dialog := _panel(easel, record)
    if dialog == null:
        return
    (dialog.row(&"level") as SaSlider).write(value)
    dialog.flush_rerun()
    var filter := easel.compositor.filter_chain.registry.get_filter(record.key)
    SaFilterOps.new(easel.document).set_parameters(record, filter.parameters())
    _free_panel()


func _slider(easel: SaEasel, record: SaAttachedFilter, name: StringName) -> Variant:
    var dialog := _panel(easel, record)
    if dialog == null:
        return null
    var value: Variant = dialog.row(name).read()
    _free_panel()
    return value


func _free_panel() -> void:
    if _host != null:
        _host.free()
        _host = null


func _saved(easel: SaEasel, file_name: String) -> String:
    var path := ProjectSettings.globalize_path(SaDataRoot.path(file_name))
    _paths.append(path)
    assert_eq(SaExport.save_sad(easel.document, path), OK, "%s saves" % file_name)
    return path


func _opened(path: String, filters: SaFilterRegistry) -> SaEasel:
    var easel := _easel(filters)
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "%s opens" % path.get_file())
    var layers: Array[SaLayer] = []
    for child in easel.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    return easel


func _layer(easel: SaEasel, name: String) -> SaLayer:
    return easel.document.get_node_or_null(name) as SaLayer


func test_the_kernel_added_through_layer_saves_its_slider_and_reopens_the_same() -> void:
    var easel := _painting(_registries.filters)
    var before := _show(easel)
    var conversion := SaFilterConversion.new(easel.document)
    var adjust := conversion.add_holding(KEY, {}, _registries.layer_types, "Threshold")
    assert_true(adjust != null and adjust.is_adjustment(), "The dialog's Layer way adds an adjustment layer")
    if adjust == null:
        easel.free()
        return
    var record := adjust.filters[0]
    assert_eq(record.key, KEY, "holding the module's kernel")
    var at_default := _show(easel)
    var grey_at := Vector2i(100, 100)
    var half_at := Vector2i(400, 100)
    assert_almost_eq(_texel(easel, at_default, grey_at).r, 0.0, 1e-4, "and the chain runs it: the grey is under 0.5")
    assert_almost_eq(_texel(easel, at_default, half_at).r, 1.0, 1e-4, "and the stroke over it")
    assert_true(at_default != before, "so the layer changed the picture")

    _set_slider(easel, record, LEVEL)
    assert_almost_eq(float(record.parameters.get("level", -1.0)), LEVEL, 1e-6, "The slider writes the record")
    var adjusted := _show(easel)
    assert_almost_eq(_texel(easel, adjusted, grey_at).r, 1.0, 1e-4, "and the grey is over the level it was set to")

    var path := _saved(easel, "l3_kernel_layer.sad")
    var opened := _opened(path, _registries.filters)
    var reopened := _layer(opened, adjust.name)
    assert_true(reopened != null and reopened.is_adjustment(), "It reopens as an adjustment layer")
    if reopened != null and reopened.filters.size() == 1:
        var kept := reopened.filters[0]
        assert_eq(kept.key, KEY, "holding the kernel's record")
        assert_almost_eq(float(_slider(opened, kept, &"level")), LEVEL, 1e-6, "whose slider reads the level it was set to")
    assert_eq(_show(opened), adjusted, "and the texels are the ones it saved")
    easel.free()
    opened.free()


func test_the_kernel_attached_to_the_paint_runs_in_the_chain_and_reopens() -> void:
    var easel := _painting(_registries.filters)
    var paint := _layer(easel, "Layer 1")
    var record := SaFilterOps.new(easel.document).attach(paint, KEY, {"level": LEVEL})
    assert_not_null(record, "The dialog's Attach way attaches the kernel to the paint")
    var shown := _show(easel)
    assert_almost_eq(_texel(easel, shown, Vector2i(100, 100)).r, 1.0, 1e-4, "and the chain runs it at the level")
    var path := _saved(easel, "l3_kernel_attached.sad")
    var opened := _opened(path, _registries.filters)
    var kept := _layer(opened, "Layer 1").filters
    assert_eq(kept.size(), 1, "The record reopens on the paint")
    assert_eq(_show(opened), shown, "and the texels are the ones it saved")
    easel.free()
    opened.free()


## A function with no margin records the point pass a written point filter
## records, run in place, and one with a margin the neighbourhood pass of it.
## The fixture reads `at` alone, so both draw the same texels.
func test_no_margin_is_a_point_pass_and_a_margin_a_neighbourhood_pass() -> void:
    var fixture := "res://tests/fixtures/modules/pixel-filter-fixture/threshold.gmacs"
    var easel := _painting(_registries.filters)
    var paint := _layer(easel, "Layer 1")
    var ctx := SaFilterContext.new(easel.document, paint, &"pixel-filter-fixture", "Threshold")
    var filter := _registries.filters.get_filter(KEY)
    assert_true(SaFilterApply.call_run(filter, ctx), "The kernel runs")
    assert_true(ctx.point != null and not ctx.point is SaNeighbourhoodPass, "as a point pass")
    SaFilterOps.new(easel.document).attach(paint, KEY, {"level": LEVEL})
    var pointed := _show(easel)

    var wide := SaFilterRegistry.new()
    assert_true(wide.register(SaPixelFilter.new(fixture, "Threshold", 2), LATER_MODULE), "With a margin it registers")
    var key := StringName("%s.threshold" % LATER_MODULE)
    var other := _painting(wide)
    var other_paint := _layer(other, "Layer 1")
    var wide_ctx := SaFilterContext.new(other.document, other_paint, LATER_MODULE, "Threshold")
    assert_true(SaFilterApply.call_run(wide.get_filter(key), wide_ctx), "and runs")
    var gathered := wide_ctx.point as SaNeighbourhoodPass
    assert_true(gathered != null and gathered.halo() == 2, "as a neighbourhood pass of its margin")
    SaFilterOps.new(other.document).attach(other_paint, key, {"level": LEVEL})
    assert_eq(_show(other), pointed, "and both draw the same texels")
    easel.free()
    other.free()


## The record of a module that is not installed is kept and written back as it
## was, and when the module is back the picture is the one first saved. The
## chain's error line naming the missing module is expected.
func test_without_the_module_the_record_is_kept_and_saved_again_unchanged() -> void:
    var easel := _painting(_registries.filters)
    var adjust := SaFilterConversion.new(easel.document).add_holding(KEY, {"level": LEVEL}, _registries.layer_types, "Threshold")
    var shown := _show(easel)
    var first := _saved(easel, "l3_kernel_first.sad")

    var bare := Fixtures.make_registries().filters
    assert_false(bare.has(KEY), "The registry the document reopens with has no such module")
    var without := _opened(first, bare)
    var kept := _layer(without, adjust.name)
    assert_true(kept != null and kept.is_adjustment(), "The adjustment layer is kept")
    if kept == null or kept.filters.size() != 1:
        easel.free()
        without.free()
        return
    assert_eq(kept.filters[0].key, KEY, "with the record's key")
    assert_eq(kept.filters[0].parameters, {"level": LEVEL}, "and its parameters")
    assert_true(kept.filters[0].enabled, "and still on")
    _show(without)
    var again := _saved(without, "l3_kernel_again.sad")

    var back := _opened(again, _registries.filters)
    var written := _layer(back, adjust.name)
    assert_true(written != null and written.filters.size() == 1, "The file written without the module holds the record")
    if written != null and written.filters.size() == 1:
        assert_eq(written.filters[0].key, KEY, "under the same key")
        assert_eq(written.filters[0].parameters, {"level": LEVEL}, "with the same parameters")
    assert_eq(_show(back), shown, "and with the module back the picture is the one first saved")
    easel.free()
    without.free()
    back.free()


## A record saved by a kernel with one `uniform` reopens under the kernel that
## gained a second, which reads the value its line declares.
func test_a_record_saved_before_a_uniform_was_added_reads_its_default() -> void:
    _write(scratch_later_path, BEFORE_SOURCE)
    var filters := SaFilterRegistry.new()
    assert_true(filters.register(SaPixelFilter.new(scratch_later_path), LATER_MODULE), "The kernel as it was registers")
    var easel := _painting(filters)
    var adjust := SaFilterConversion.new(easel.document).add_holding(LATER_KEY, {}, _registries.layer_types, "Later")
    assert_not_null(adjust, "and is added as an adjustment layer")
    if adjust == null:
        easel.free()
        return
    _set_slider(easel, adjust.filters[0], LEVEL)
    assert_eq(adjust.filters[0].parameters.keys(), ["level"], "Its record holds the one uniform")
    var path := _saved(easel, "l3_before_the_uniform.sad")

    _write(scratch_later_path, AFTER_SOURCE)
    var later := SaFilterRegistry.new()
    assert_true(later.register(SaPixelFilter.new(scratch_later_path), LATER_MODULE), "The kernel with a second uniform registers")
    var opened := _opened(path, later)
    var record := _layer(opened, adjust.name).filters[0]
    assert_false(record.parameters.has("lift"), "The record reopens naming no lift")
    assert_almost_eq(float(_slider(opened, record, &"lift")), 0.25, 1e-6, "and the lift's slider reads its default")
    assert_almost_eq(float(_slider(opened, record, &"level")), LEVEL, 1e-6, "while the level reads what was saved")
    var shown := _show(opened)
    var under := _texel(opened, shown, Vector2i(100, 100))
    assert_almost_eq(under.r, 1.0, 1e-4, "The grey is over the saved level")
    var filter := later.get_filter(LATER_KEY) as SaPixelFilter
    filter.set_parameters({"level": 0.9})
    assert_almost_eq(float(filter.values().get("lift", -1.0)), 0.25, 1e-6, "and the kernel is handed the lift's default")
    SaFilterOps.new(opened.document).set_parameters(record, {"level": 0.9})
    var lifted := _texel(opened, _show(opened), Vector2i(100, 100))
    assert_almost_eq(lifted.r, 0.25, 1e-4, "which the texels show once the grey is under the level")
    easel.free()
    opened.free()


func _write(path: String, source: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
