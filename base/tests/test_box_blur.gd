## Sara's Box Blur, and the box blur the spec prints.
##
## The base module's Box Blur. A square pixel function that sums its whole
## window costs 160,801 reads a pixel at the typed radius of 200, so the
## shipped blur is a class whose pass averages across, then down, then
## blends, and the spec's kernel is kept beside this suite as
## `pixel_blur.gmacs`, held to the page and to the shipped blur's pixels.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
## The module that registers the filter, and the owner its contexts are made for.
const OWNER := &"sara-base-modules"
const SaExportScript = preload("res://core/export/sa_export.gd")
## The spec's pixel function, kept beside this suite.
const PIXEL_BLUR := "tests/pixel_blur.gmacs"
## Half precision's step at one, the most a texel of the three steps may part
## from the square's after two stores between the steps.
const HALF_STEP := 1.0 / 1024.0

## Where the blur runs in every case below: inside chunk (1,1) and away from its
## edges, so a neighbourhood read has room on every side.
const PAINTED := Vector2i(1, 1)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaFilter = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    _filter = load(MODULE_DIR.path_join("usual/box_blur_filter.gd")).new()


func after_each() -> void:
    _filter = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    return SaExportScript.get_texture_image_float(texture).get_pixel(x, y)


## A layer with one bright column down the middle of chunk (1,1) and black
## either side, which is the shortest picture a box blur visibly changes.
func _paint_a_line() -> void:
    var chunk := _layer.get_or_create_chunk(PAINTED)
    chunk.clear(Color(0.0, 0.0, 0.0, 1.0))
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 1.0))
    for y in SaChunk.SIZE:
        image.set_pixel(SaChunk.SIZE >> 1, y, Color(1.0, 1.0, 1.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())


## The filter and its kernel sit in the base module's `usual/` beside Gaussian
## Blur, the base module registers it with its other filters, and the folder
## that held the module `box_blur` is gone.
func test_the_filter_is_one_of_the_base_modules_blurs() -> void:
    for name: String in ["usual/box_blur.gmacs", "usual/box_blur_filter.gd"]:
        assert_true(FileAccess.file_exists(MODULE_DIR.path_join(name)), "%s is in the base module" % name)
    assert_false(DirAccess.dir_exists_absolute("res://modules/sara-base-modules/box-blur"), "and the box-blur folder is gone")
    var registrations := FileAccess.get_file_as_string(MODULE_DIR.path_join("filter_registrations.gd"))
    assert_true(registrations.contains("ctx.register_filter(BoxBlurFilter.new())"), "the base module registers it")


## A record saved when Box Blur was a module of its own names the key
## `box_blur.box_blur`, and the registry hands it to the base module's filter
## with its radius as it was, which is what opens an older document's
## attachment and effect layer as Box Blur.
func test_a_record_under_the_former_key_reads_as_the_base_modules_box_blur() -> void:
    var registry := SaFilterRegistry.new()
    var blur: SaFilter = load(MODULE_DIR.path_join("usual/box_blur_filter.gd")).new()
    assert_true(registry.register(blur, OWNER), "the filter registers under the base module")
    var made := SaFilterRegistry.record_for(&"box_blur.box_blur", {"radius": 7.0})
    assert_eq(made, [&"sara-base-modules.box_blur", {"radius": 7.0}], "the former key reads as the base module's, radius and all")
    registry.unregister_module(OWNER)


## A student's copy of the box blur in a folder `box-blur` is the module
## `box_blur` and registers under the former key itself, and then what it
## saves stays its own rather than opening as the base module's.
func test_a_students_box_blur_under_the_former_key_keeps_its_own_records() -> void:
    var registry := SaFilterRegistry.new()
    var blur: SaFilter = load(MODULE_DIR.path_join("usual/box_blur_filter.gd")).new()
    var copy: SaFilter = load(MODULE_DIR.path_join("usual/box_blur_filter.gd")).new()
    assert_true(registry.register(blur, OWNER), "the base module's registers")
    assert_true(registry.register(copy, &"box_blur"), "and the student's beside it")
    var made := SaFilterRegistry.record_for(&"box_blur.box_blur", {"radius": 7.0})
    assert_eq(made, [&"box_blur.box_blur", {"radius": 7.0}], "the student's record stays the student's")
    registry.unregister_module(&"box_blur")
    registry.unregister_module(OWNER)


## The spec's kernel listing diffs empty against the pixel function kept
## beside this suite. The class listing is the student's and not the shipped
## class's, so it is held only to the door it extends.
##
## Reads the spec off the disk rather than a copy of it, because a copy is the
## thing that goes stale. The spec lives above `res://`, so the path is
## globalized: `FileAccess` opens an absolute one.
func test_the_specs_kernel_is_the_pixel_function_kept_beside_the_suite() -> void:
    var spec_path := ProjectSettings.globalize_path("res://").path_join("../docs/specs/scripting.md").simplify_path()
    if not FileAccess.file_exists(spec_path):
        skip("the scripting spec is not in this copy of the source")
        return
    var spec := FileAccess.get_file_as_string(spec_path)
    assert_false(spec.is_empty(), "the scripting spec is where this suite looks for it")
    if spec.is_empty():
        return
    var section := spec.substr(spec.find("## The whole box blur"))
    section = section.substr(0, section.find("## The kernel language"))

    var listings: Array[String] = []
    var at := section.find("```")
    while at >= 0 and listings.size() < 2:
        var opened := section.find("\n", at) + 1
        var closed := section.find("```", opened)
        listings.append(section.substr(opened, closed - opened))
        at = section.find("```", closed + 3)
    assert_eq(listings.size(), 2, "the spec prints two listings")
    if listings.size() != 2:
        return

    var written := FileAccess.get_file_as_string(MODULE_DIR.path_join(PIXEL_BLUR))
    assert_eq(written, listings[0], "pixel_blur.gmacs is the spec's listing, character for character")
    assert_true(listings[1].contains("extends SaPixelFilter"), "and the class the spec prints is a pixel filter's")


## The Filter menu read "Box blur" among Gaussian Blur and Motion Blur, with a
## tooltip that named its module and promised a chord it did not have. The
## class hands the title to the pixel filter and the kernel's leading comment
## is the sentence, and the key the door steps and a saved attachment name it by
## is the one the old title made.
func test_the_filter_is_named_and_described_for_a_painter() -> void:
    assert_eq(_filter.title(), "Box Blur", "every word capital, the way the base module's blurs read")
    assert_eq(
        _filter.sentence(),
        "Soften the picture with a flat average of each pixel's neighbours in a square whose reach is the radius, in pixels.",
        "and a sentence on what it does to the picture"
    )
    assert_eq(_filter.family(), &"blur", "in the Blur section beside the base module's blurs")
    var key := SaFilterRegistry.key_for(OWNER, _filter)
    assert_eq(key, &"sara-base-modules.box_blur", "the registry key is the base module's, since the id lowercases the title")
    assert_eq(SaFilterRegistry.command_for(key, _filter), &"filter_sara-base-modules_box_blur", "and so is its command")


func test_the_filter_builds_the_dialog_the_spec_prints() -> void:
    var dialog := SaDialog.for_filter(_filter)
    var host := VBoxContainer.new()
    dialog.realize(host)

    assert_eq(_filter.title(), "Box Blur", "the title is the one the filter writes")
    assert_eq(dialog.dialog_title, "Box Blur", "and the dialog took it")
    assert_not_null(dialog.preview_control, "the dialog added the thumbnail")
    assert_not_null(dialog.canvas_box, "and the Preview box")
    assert_not_null(dialog.apply_button, "and the two buttons")
    var radius := dialog.row(&"radius") as SaSlider
    assert_not_null(radius, "the row the spec declares is an SaSlider keyed radius")
    if radius != null:
        assert_almost_eq(float(radius.value), 3.0, 0.001, "at the default the spec writes")
        assert_almost_eq(radius.max_value, 200.0, 0.001, "with the option's hard ceiling")
        assert_almost_eq(radius.soft_max, 20.0, 0.001, "and the soft one the drag stops at")
    assert_almost_eq(float(_filter.parameter(&"radius")), 3.0, 0.001, "which the filter keeps")
    host.free()


## Three steps of one neighbourhood pass, so a texel pays 2r + 1 reads a
## direction rather than the square's (2r + 1) squared.
func test_the_pass_is_three_steps_across_down_and_the_blend() -> void:
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _filter.set_parameters({"radius": 40})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
    _filter.run(ctx)
    var recorded := ctx.point as SaNeighbourhoodPass
    assert_not_null(recorded, "the run recorded a neighbourhood pass")
    if recorded == null:
        return
    assert_eq(recorded.shader, "sara-base-modules/box_blur", "of the kernel beside the class, the folder under modules its owner")
    var kernels: Array[String] = []
    for step: SaNeighbourhoodPass.Step in recorded.steps:
        kernels.append(step.kernel)
    assert_eq(kernels, ["blur_across", "blur_down", "blur"] as Array[String], "across, down and the blend")
    assert_eq(recorded.radius, 40, "reaching as far as the radius together")
    assert_not_null(ctx.kernel(recorded.shader), "and the kernel compiled")


func test_the_run_the_spec_prints_blurs_the_layer() -> void:
    _paint_a_line()
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    var dialog := SaDialog.for_filter(_filter)
    var host := VBoxContainer.new()
    dialog.realize(host)

    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
    _filter.run(ctx)
    # The run records a neighbourhood pass and shows no
    # texture, so the blur is read off the layer Apply wrote.
    assert_true(ctx.point is SaNeighbourhoodPass, "the run recorded a neighbourhood pass")
    assert_null(ctx.shown, "and showed no texture")
    if not ctx.point is SaNeighbourhoodPass:
        host.free()
        return
    assert_eq((ctx.point as SaNeighbourhoodPass).radius, 3, "reading as far as the slider says")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply walks over the layer")

    var at := PAINTED * SaChunk.SIZE + Vector2i(SaChunk.SIZE >> 1, SaChunk.SIZE >> 1)
    var centre := _layer_texel(at.x, at.y)
    var beside := _layer_texel(at.x + 2, at.y)
    var away := _layer_texel(at.x + 5, at.y)
    # A box of 7 by 7 over a column one pixel wide is seven bright texels in
    # forty-nine, which is what every texel within three of the column reads,
    # and nothing at all four away. That flatness is the box blur rather than a
    # defect in it: a falling curve would be a weighted kernel.
    assert_almost_eq(centre.r, 7.0 / 49.0, 0.002, "the bright column came down to its share of the box")
    assert_almost_eq(beside.r, 7.0 / 49.0, 0.002, "and the black two texels away came up to the same")
    assert_almost_eq(away.r, 0.0, 0.002, "while five away, outside the radius, nothing moved")
    host.free()


## The kernel sums premultiplied colour, so a transparent
## neighbour, black where nothing was painted, counts for nothing. One opaque red
## texel on an empty layer blurred at radius 1 leaves its neighbour red at an
## alpha of one ninth, where the straight sum left a ninth of red, a dark fringe.
func test_a_transparent_neighbour_lends_no_colour() -> void:
    var chunk := _layer.get_or_create_chunk(PAINTED)
    chunk.clear(Color(0.0, 0.0, 0.0, 0.0))
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    var middle := SaChunk.SIZE >> 1
    image.set_pixel(middle, middle, Color(1.0, 0.0, 0.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _filter.set_parameters({"radius": 1})
    assert_almost_eq(float(_filter.parameter(&"radius")), 1.0, 0.001, "the radius is one")

    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
    _filter.run(ctx)
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "apply wrote")

    var at := PAINTED * SaChunk.SIZE + Vector2i(middle, middle)
    var beside := _layer_texel(at.x + 1, at.y)
    assert_almost_eq(beside.a, 1.0 / 9.0, 0.002, "the neighbour holds a ninth of the coverage")
    assert_almost_eq(beside.r, 1.0, 0.002, "and its colour is red, not a ninth of red")
    assert_almost_eq(beside.g, 0.0, 0.002, "with no green")
    var centre := _layer_texel(at.x, at.y)
    assert_almost_eq(centre.r, 1.0, 0.002, "the texel itself stays red too")
    assert_almost_eq(centre.a, 1.0 / 9.0, 0.002, "at the same ninth")
    assert_almost_eq(_layer_texel(at.x + 2, at.y).a, 0.0, 0.002, "and two away nothing moved")


func test_apply_writes_the_blur_and_undo_takes_it_back() -> void:
    _paint_a_line()
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    var dialog := SaDialog.for_filter(_filter)
    var host := VBoxContainer.new()
    dialog.realize(host)

    var middle := PAINTED * SaChunk.SIZE + Vector2i((SaChunk.SIZE >> 1) + 2, SaChunk.SIZE >> 1)
    var before := _layer_texel(middle.x, middle.y)
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
    _filter.run(ctx)
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "apply wrote")

    var after := _layer_texel(middle.x, middle.y)
    assert_true(after.r > before.r, "the layer beside the column is brighter than it was")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_layer_texel(middle.x, middle.y).r, before.r, 0.002, "and undo puts it back")
    host.free()


## The reach follows the radius: the pass pads by what the slider holds, past
## the drag's 20 as far as the 200 a radius may be typed up to.
func test_the_pass_reads_as_far_as_the_radius_says() -> void:
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    for radius: int in [1, 7, 150]:
        _filter.set_parameters({"radius": radius})
        var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
        _filter.run(ctx)
        var recorded := ctx.point as SaNeighbourhoodPass
        assert_not_null(recorded, "radius %d records a neighbourhood pass" % radius)
        if recorded != null:
            assert_eq(recorded.radius, radius, "which pads by the radius, %d" % radius)


## The three steps lay the pixels the square kernel laid, kept beside this
## suite as `old_blur.gmacs`, on a soft dab over transparency at radii 1, 3
## and 20, the alpha ramp being where a mean taken without premultiplying would
## part from the old one. To half precision's step, since the steps store
## their means between them where the square stored once.
func test_the_three_steps_lay_what_the_square_kernel_laid() -> void:
    ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    for radius: int in [1, 3, 20]:
        _paint_a_soft_dab()
        var old := SaFilterContext.new(_doc, _layer, OWNER, "Old Box Blur")
        old.neighbourhood_pass("old_blur", "blur", {"radius": radius}, radius)
        assert_true(SaFilterApply.apply(old, "Old Box Blur"), "the old kernel applied at radius %d" % radius)
        var was := SaExportScript.get_texture_image_float(_layer.get_field(PAINTED))
        _paint_a_soft_dab()
        _filter.set_parameters({"radius": radius})
        var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title())
        _filter.run(ctx)
        assert_true(SaFilterApply.apply(ctx, _filter.title()), "and the three steps at radius %d" % radius)
        var now := SaExportScript.get_texture_image_float(_layer.get_field(PAINTED))
        var most := _largest_difference(was, now)
        assert_true(most < HALF_STEP, "and at radius %d the two lay the same pixels, %s apart at most" % [radius, most])


## A dab of orange whose alpha falls from one at its centre to nought forty
## texels out, in the middle of chunk (1,1) on an otherwise empty layer.
func _paint_a_soft_dab() -> void:
    var chunk := _layer.get_or_create_chunk(PAINTED)
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    var middle := Vector2(SaChunk.SIZE >> 1, SaChunk.SIZE >> 1)
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var fall := 1.0 - Vector2(x, y).distance_to(middle) / 40.0
            if fall > 0.0:
                image.set_pixel(x, y, Color(0.9, 0.35, 0.1, smoothstep(0.0, 1.0, fall)))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())


## The largest difference of any channel of any texel between *a* and *b*.
static func _largest_difference(a: Image, b: Image) -> float:
    var most := 0.0
    for y in a.get_height():
        for x in a.get_width():
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            most = maxf(most, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return most


func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
