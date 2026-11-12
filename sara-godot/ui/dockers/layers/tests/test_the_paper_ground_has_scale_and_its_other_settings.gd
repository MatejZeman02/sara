## The paper ground has a scale and its two colours among its rows.
##
## `SaGeneratedLayer` has always kept a `scale` and a `second` colour for every
## ground, and the paper kernel and the view shader read both, but the Layers
## docker showed the paper a choice and a Tooth and nothing else, so a painter
## could not reach either. The suite reads the rows for a paper and for a
## canvas, each row's write and its one undo step, a swatch's two-way
## conversion in an Oklab document, and the composite and the view shader
## reading what the rows wrote.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null
var _rows: SaGroundRows = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(512, 256))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _rows = SaGroundRows.new()
    _easel.process_pending_composite()


func after_each() -> void:
    _rows.free()
    _rows = null
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(x: int, y: int) -> Color:
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


## A ground of *type_id* under the paint, the rows shown for it.
func _add_ground(type_id: StringName) -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(type_id, _registries.layer_types)
    _doc.set_active_layer(paint)
    _rows.show_layer(_doc, ground, _registries.layer_types)
    _resolve()
    return ground


func _resolve() -> void:
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()


## How much neighbouring texels of one row of the composite differ, on average:
## a fine grain changes at every step and a coarse one hardly at all.
func _roughness() -> float:
    var total := 0.0
    var previous := _texel(8, 128)
    for x in range(9, 200):
        var here := _texel(x, 128)
        total += absf(here.r - previous.r) + absf(here.g - previous.g) + absf(here.b - previous.b)
        previous = here
    return total / 191.0


func test_a_paper_shows_a_scale_and_two_colours() -> void:
    var paper := _add_ground(&"paper")
    assert_true(_rows.visible, "A paper shows the ground rows")
    assert_true(_rows.scale_slider.get_parent().visible, "with a Scale row")
    assert_almost_eq(_rows.scale_slider.value, 20.0, 0.0001, "at the paper's own scale")
    assert_eq(_rows.scale_slider.suffix, " px", "in document pixels")
    assert_true(_rows.swatches["color"].get_parent().visible, "and a row of colours")
    var first: Color = _doc.color_space.to_display(paper.generator_params["color"])
    var second: Color = _doc.color_space.to_display(paper.generator_params["second"])
    assert_true(_rows.swatches["color"].color.is_equal_approx(first), "whose first swatch is the paper's first colour")
    assert_true(_rows.swatches["second"].color.is_equal_approx(second), "and whose second is its second")
    assert_false(_rows.weave_sliders["thickness"].get_parent().visible, "A paper still shows no thread rows")


func test_a_canvas_shows_the_colours_and_its_spacing_but_no_second_scale() -> void:
    _add_ground(&"canvas")
    assert_true(_rows.swatches["second"].get_parent().visible, "A canvas gets the colours too")
    assert_false(_rows.scale_slider.get_parent().visible, "and its scale is the Spacing row, not a second Scale")
    assert_true(_rows.weave_sliders["scale"].get_parent().visible, "which still shows")


func test_the_scale_row_writes_the_scale_as_one_undo_step() -> void:
    var paper := _add_ground(&"paper")
    _rows.scale_slider.value_changed.emit(40.0)
    _rows.scale_slider.value_changed.emit(64.0)
    assert_almost_eq(float(paper.generator_params["scale"]), 64.0, 0.0001, "The row writes the scale")
    _doc.undo()
    assert_almost_eq(float(paper.generator_params["scale"]), 20.0, 0.0001, "and a drag is one step to undo")
    _doc.redo()
    assert_almost_eq(float(paper.generator_params["scale"]), 64.0, 0.0001, "and to redo")
    _rows.scale_slider.value_changed.emit(100000.0)
    assert_almost_eq(float(paper.generator_params["scale"]), 256.0, 0.0001, "A value past the range is held to it")


func test_a_swatch_writes_its_colour_as_one_undo_step() -> void:
    var paper := _add_ground(&"paper")
    var before_first: Color = paper.generator_params["color"]
    var before_second: Color = paper.generator_params["second"]
    var red := Color(0.8, 0.1, 0.1, 1.0)
    var blue := Color(0.1, 0.1, 0.8, 1.0)
    _rows.swatches["second"].color_changed.emit(red)
    _rows.swatches["second"].color_changed.emit(blue)
    assert_true(paper.generator_params["second"].is_equal_approx(blue), "The second swatch writes the second colour")
    assert_true(paper.generator_params["color"].is_equal_approx(before_first), "and leaves the first")
    _doc.undo()
    assert_true(paper.generator_params["second"].is_equal_approx(before_second), "A drag of it is one step to undo")
    _doc.redo()
    assert_true(paper.generator_params["second"].is_equal_approx(blue), "and to redo")

    _rows.swatches["color"].color_changed.emit(red)
    assert_true(paper.generator_params["color"].is_equal_approx(red), "The first swatch writes the first colour")
    _doc.undo()
    assert_true(paper.generator_params["color"].is_equal_approx(before_first), "in a step of its own")
    assert_true(paper.generator_params["second"].is_equal_approx(blue), "which leaves the second where it was")


func test_a_swatch_converts_into_the_documents_space_and_back() -> void:
    _doc.color_space = SaColorSpace.oklab()
    var paper := _add_ground(&"paper")
    var picked := Color(0.8, 0.3, 0.2, 1.0)
    _rows.swatches["color"].color_changed.emit(picked)
    var stored: Color = paper.generator_params["color"]
    assert_false(stored.is_equal_approx(picked), "An Oklab document stores L, a and b, not the picker's triple")
    assert_true(stored.is_equal_approx(_doc.color_space.from_display(picked)), "but what a fill would store")
    _rows.show_layer(_doc, paper, _registries.layer_types)
    assert_true(_rows.swatches["color"].color.is_equal_approx(picked), "and the swatch shows the picked colour again")


func test_the_composite_reads_the_colours_and_the_scale() -> void:
    var paper := _add_ground(&"paper")
    var red := Color(0.9, 0.1, 0.1, 1.0)
    _rows.swatches["color"].color_changed.emit(red)
    _rows.swatches["second"].color_changed.emit(red)
    _resolve()
    var flat := _texel(300, 128)
    assert_almost_eq(flat.r, red.r, 0.02, "With both swatches one colour the composite is that colour")
    assert_almost_eq(flat.g, red.g, 0.02, "in every channel")
    assert_almost_eq(flat.b, red.b, 0.02, "and so in blue")

    var blue := Color(0.1, 0.1, 0.9, 1.0)
    _rows.swatches["second"].color_changed.emit(blue)
    _rows.scale_slider.value_changed.emit(4.0)
    _resolve()
    var fine := _roughness()
    var seen := _texel(300, 128)
    assert_almost_eq(seen.r + seen.b, red.r + red.b, 0.1, "A grain between the two lies on the line between them")
    assert_almost_eq(seen.g, 0.1, 0.02, "and the second colour reached the kernel")
    _rows.scale_slider.value_changed.emit(128.0)
    _resolve()
    var coarse := _roughness()
    assert_true(fine > coarse * 4.0, "A scale of 4 grains finer than 128 (%f against %f)" % [fine, coarse])
    assert_almost_eq(float(paper.generator_params["scale"]), 128.0, 0.0001, "by the number the row wrote")


## The view beyond the document is told what the rows wrote. `apply_view`
## finds the paper's shader through the main window's registries, which a suite
## has none of, so this reads what the canvas syncs from and that the shader
## declares the uniforms `apply_view` sets, and the scenario photographs the
## edge.
func test_the_view_shader_reads_the_new_values() -> void:
    var paper := _add_ground(&"paper")
    SaLayerOps.new(_doc).move(paper, -1)
    var before := SaGeneratedLayer.view_state(_doc)
    _rows.swatches["second"].color_changed.emit(Color(0.1, 0.6, 0.2, 1.0))
    var after_colour := SaGeneratedLayer.view_state(_doc)
    assert_false(after_colour == before, "A colour the swatch wrote moves what the canvas syncs the view from")
    _rows.scale_slider.value_changed.emit(90.0)
    assert_false(SaGeneratedLayer.view_state(_doc) == after_colour, "and so does the scale the row wrote")
    var shader := load(paper_view_path()) as Shader
    assert_not_null(shader, "The paper's view shader loads")
    if shader == null:
        return
    var declared: Array[String] = []
    for uniform: Dictionary in shader.get_shader_uniform_list():
        declared.append(String(uniform["name"]))
    for name_read: String in ["color_a", "color_b", "scale"]:
        assert_true(declared.has(name_read), "and declares %s, which apply_view sets from the layer" % name_read)


func paper_view_path() -> String:
    return _registries.layer_types.get_descriptor(&"paper").generator_view
