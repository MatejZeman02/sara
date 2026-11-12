## The paper and canvas grounds look like a real sheet and a real canvas.
##
## A paper was three octaves of value noise, which reads as a soft cloud, and
## a canvas had threads with no slubs, fuzz or priming. The paper now lays
## fibres, a felt's cells and laid lines over its pulp, the canvas slubs, fuzz,
## crimp and priming over its weave, each by an amount, and both have presets
## and an edge beyond the page. This suite measures the presets against the
## reference scans, whose numbers were read by `measure_references.py` from the scans
## and are written below because the scans are never committed. It holds that
## the view past the page does not shimmer as the zoom crosses 100 percent,
## that no edge covers a pixel of the page, and that a file saved before the
## row opens on the texels it drew then.
extends "res://tests/test_framework.gd"

## Kernels and view shaders run on the GPU.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const PAPER_VIEW := "res://shaders/canvas/paper.gdshader"
const CANVAS_VIEW := "res://shaders/canvas/canvas.gdshader"

## The two files the base of this row saved, a paper and a canvas each with
## the settings a new one had then, and the texels its kernel drew at
## `SAMPLES` of the chunk at (256, 0), recorded from the same tree.
const SAVED_PAPER := "res://core/layers/generated/tests/data/paper_saved_before_its_parts.sad"
const SAVED_CANVAS := "res://core/layers/generated/tests/data/canvas_saved_before_its_parts.sad"
const SAMPLES: Array[Vector2i] = [
    Vector2i(0, 0),
    Vector2i(3, 7),
    Vector2i(17, 40),
    Vector2i(64, 64),
    Vector2i(100, 13),
    Vector2i(129, 200),
    Vector2i(255, 255),
    Vector2i(77, 191),
]
const PAPER_BEFORE: Array = [
    [0.899605, 0.876842, 0.821315],
    [0.891553, 0.868058, 0.811068],
    [0.867587, 0.841913, 0.780565],
    [0.897816, 0.87489, 0.819039],
    [0.887349, 0.863472, 0.805718],
    [0.85549, 0.828716, 0.765169],
    [0.879746, 0.855178, 0.796041],
    [0.888162, 0.864358, 0.806751],
]
const CANVAS_BEFORE: Array = [
    [0.817621, 0.779745, 0.71187],
    [0.66, 0.61, 0.53],
    [0.761168, 0.71895, 0.646732],
    [0.664219, 0.614544, 0.534868],
    [0.742317, 0.698649, 0.624981],
    [0.743977, 0.700437, 0.626897],
    [0.66, 0.61, 0.53],
    [0.66, 0.61, 0.53],
]

## Each reference crop's mean luminance and its spread over its mean, read
## from the middle 2048 square of the Poly Haven scans at 4K and the middle
## 1024 square of the ambientCG papers at 2K, and the thread spacing of each
## Poly Haven scan in millimetres, the mean of its two axes.
const REFERENCES: Dictionary = {
    "Paper001": {"mean": 0.955, "spread": 0.0134},
    "Paper003": {"mean": 0.874, "spread": 0.0150},
    "rough_linen": {"mean": 0.656, "spread": 0.093, "spacing_mm": 0.638},
    "hessian_380": {"mean": 0.585, "spread": 0.117, "spacing_mm": 1.491},
    "hessian_230": {"mean": 0.481, "spread": 0.224, "spacing_mm": 3.201},
}

## Which reference each preset is measured against.
const PAPER_AGAINST: Dictionary = {
    "Cartridge": "Paper003",
    "Hot Pressed": "Paper001",
    "Cold Pressed": "Paper003",
    "Rough": "Paper003",
}
const CANVAS_AGAINST: Dictionary = {
    "Medium Linen": "rough_linen",
    "Coarse Linen": "hessian_380",
    "Hessian": "hessian_230",
}

## The stated range: a preset's mean luminance within this of its
## reference's, and its spread over its mean within this factor either way.
const MEAN_WITHIN := 0.12
const SPREAD_FACTOR := 2.0
## The presets' pixels to the millimetre.
const PIXELS_PER_MM := 10.0
## A patch's mean may move this share between 97 and 103 percent.
const SHIMMER := 0.01

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _add_ground(kind: StringName) -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(kind, _registries.layer_types)
    SaLayerOps.new(_doc).move(ground, -1)
    _doc.set_active_layer(paint)
    _doc.update_caches()
    return ground


func _preset(kind: StringName, named: String) -> Dictionary:
    for preset: Dictionary in _registries.layer_types.get_descriptor(kind).generator_presets:
        if preset["name"] == named:
            return preset
    return {}


## The colours *ground*'s kernel draws over a square *side* texels wide at
## *corner*, as rows of floats, four to a texel.
func _kernel(ground: SaLayer, corner: Vector2i, side: int) -> PackedFloat32Array:
    var texture := _easel.compositor.generate_chunk(
        ground, Vector2(corner), Rect2i(0, 0, side, side), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    )
    var floats := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
    var width: int = texture.size.x
    assert_true(side <= width and side <= texture.size.y, "A kernel's square fits its chunk")
    var out := PackedFloat32Array()
    out.resize(side * side * 4)
    for y in side:
        for x in side:
            for c in 4:
                out[(y * side + x) * 4 + c] = floats[(y * width + x) * 4 + c]
    return out


static func _luminance(floats: PackedFloat32Array, at: int) -> float:
    return 0.2126 * floats[at * 4] + 0.7152 * floats[at * 4 + 1] + 0.0722 * floats[at * 4 + 2]


## The mean luminance of *floats* and its spread over its mean.
static func _grain(floats: PackedFloat32Array) -> Vector2:
    @warning_ignore("integer_division")
    var count := floats.size() / 4
    var total := 0.0
    for i in count:
        total += _luminance(floats, i)
    var mean := total / count
    var squares := 0.0
    for i in count:
        var apart := _luminance(floats, i) - mean
        squares += apart * apart
    return Vector2(mean, sqrt(squares / count) / mean)


## The period in texels at which *ground*'s kernel varies most along x, as
## the scans were read: the luminance of a strip four chunks wide and one high
## averaged down its columns, and the strongest whole number of cycles of a
## discrete Fourier sum over them, a period longer than an eighth of the strip
## left out as the scans' were.
func _strongest_period(ground: SaLayer) -> float:
    var side := 256
    var chunks := 4
    var width := side * chunks
    var columns := PackedFloat32Array()
    columns.resize(width)
    for chunk in chunks:
        var floats := _kernel(ground, Vector2i(chunk * side, 0), side)
        for x in side:
            var total := 0.0
            for y in side:
                total += _luminance(floats, y * side + x)
            columns[chunk * side + x] = total / side
    var best := 0.0
    var best_cycles := 0
    @warning_ignore("integer_division")
    for cycles in range(8, width / 2):
        var re := 0.0
        var im := 0.0
        for x in width:
            var phase := TAU * cycles * x / width
            re += columns[x] * cos(phase)
            im += columns[x] * sin(phase)
        var power := re * re + im * im
        if power > best:
            best = power
            best_cycles = cycles
    return float(width) / maxi(best_cycles, 1)


## What *shader* draws over a viewport *size* wide whose rect covers
## *texels* document pixels from *origin*, with *params* and *page*, as
## eight-bit colours.
func _view(shader: String, params: Dictionary, origin: Vector2, texels: Vector2, size: Vector2i, page: Vector2) -> Image:
    var material := ShaderMaterial.new()
    material.shader = load(shader)
    for key: String in params:
        material.set_shader_parameter(key, params[key])
    material.set_shader_parameter("color_a", params.get("color", Color.WHITE))
    material.set_shader_parameter("color_b", params.get("second", Color.BLACK))
    material.set_shader_parameter("rect_origin", origin)
    material.set_shader_parameter("rect_size", texels)
    material.set_shader_parameter("texels_per_pixel", texels.x / size.x)
    material.set_shader_parameter("page_size", page)
    material.set_shader_parameter("relief_enabled", false)
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, Vector2(size)), Color.WHITE)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    image.convert(Image.FORMAT_RGBA8)
    return image


static func _image_mean(image: Image) -> float:
    var total := 0.0
    for y in image.get_height():
        for x in image.get_width():
            var c := image.get_pixel(x, y)
            total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return total / (image.get_width() * image.get_height())


func _check_grain(kind: StringName, against: Dictionary) -> void:
    for named: String in against:
        var ground := _add_ground(kind)
        SaGeneratedLayer.apply_preset(_doc, ground, _preset(kind, named))
        var grain := _grain(_kernel(ground, Vector2i(256, 256), 256))
        var scan: Dictionary = REFERENCES[against[named]]
        var ratio := grain.y / float(scan["spread"])
        print(
            (
                "%s: mean %.3f spread %.4f against %s %.3f %.4f"
                % [named, grain.x, grain.y, against[named], scan["mean"], scan["spread"]]
            )
        )
        assert_true(
            absf(grain.x - float(scan["mean"])) <= MEAN_WITHIN,
            "%s's mean %.3f is within %.2f of %s's %.3f" % [named, grain.x, MEAN_WITHIN, against[named], scan["mean"]]
        )
        assert_true(
            ratio >= 1.0 / SPREAD_FACTOR and ratio <= SPREAD_FACTOR,
            "%s's spread %.4f is within twice %s's %.4f either way" % [named, grain.y, against[named], scan["spread"]]
        )
        SaLayerOps.new(_doc).remove(ground)


func test_every_paper_preset_has_the_grain_of_its_reference_sheet() -> void:
    _check_grain(&"paper", PAPER_AGAINST)


func test_every_canvas_preset_has_the_grain_of_its_reference_cloth() -> void:
    _check_grain(&"canvas", CANVAS_AGAINST)


## The threads' spacing read off the kernel's texels, not off the parameter,
## at the presets' ten pixels to the millimetre.
func test_the_canvas_presets_threads_are_spaced_as_the_scans_are() -> void:
    for named: String in CANVAS_AGAINST:
        var ground := _add_ground(&"canvas")
        SaGeneratedLayer.apply_preset(_doc, ground, _preset(&"canvas", named))
        var period := _strongest_period(ground)
        var scan: float = REFERENCES[CANVAS_AGAINST[named]]["spacing_mm"]
        var measured := period / PIXELS_PER_MM
        print("%s: threads %.3f mm apart against %.3f" % [named, measured, scan])
        assert_true(
            absf(measured - scan) <= 0.1 * scan,
            "%s's threads stand %.3f mm apart, within a tenth of %s's %.3f" % [named, measured, CANVAS_AGAINST[named], scan]
        )
        SaLayerOps.new(_doc).remove(ground)


## A 64 pixel patch past the page at 97 and at 103 percent, the place a
## screen pixel falls on texels moving under it, keeps its mean.
func test_no_preset_shimmers_as_the_zoom_crosses_100_percent() -> void:
    for kind: StringName in [&"paper", &"canvas"]:
        var shader := PAPER_VIEW if kind == &"paper" else CANVAS_VIEW
        for preset: Dictionary in _registries.layer_types.get_descriptor(kind).generator_presets:
            var params: Dictionary = preset["params"]
            var means: Array[float] = []
            for zoom: float in [0.97, 1.03]:
                var texels := Vector2(64.0, 64.0) / zoom
                means.append(_image_mean(_view(shader, params, Vector2(-400.0, -300.0), texels, Vector2i(64, 64), Vector2.ZERO)))
            var moved := absf(means[1] - means[0]) / means[0]
            print("shimmer %s: %.4f" % [preset["name"], moved])
            assert_true(moved < SHIMMER, "%s's patch moves %.4f of its mean between 97 and 103 percent" % [preset["name"], moved])


## Every edge leaves the page's pixels as the ground without an edge draws
## them, and draws something past the page.
func test_no_edge_covers_a_pixel_of_the_page() -> void:
    var page := Vector2(96.0, 96.0)
    for kind: StringName in [&"paper", &"canvas"]:
        var shader := PAPER_VIEW if kind == &"paper" else CANVAS_VIEW
        var params: Dictionary = _registries.layer_types.get_descriptor(kind).generator_defaults.duplicate()
        var bare := _view(shader, params, Vector2(-64.0, -64.0), Vector2(256.0, 256.0), Vector2i(256, 256), page)
        var edges: Array[int] = [1, 4]
        if kind == &"paper":
            edges = [1, 2, 3]
        for edge: int in edges:
            params["edge"] = float(edge)
            var edged := _view(shader, params, Vector2(-64.0, -64.0), Vector2(256.0, 256.0), Vector2i(256, 256), page)
            var inside_changed := 0
            var outside_changed := 0
            for y in 256:
                for x in 256:
                    var same := bare.get_pixel(x, y).is_equal_approx(edged.get_pixel(x, y))
                    var in_page := x >= 64 and x < 160 and y >= 64 and y < 160
                    if in_page and not same:
                        inside_changed += 1
                    elif not in_page and not same:
                        outside_changed += 1
            assert_eq(inside_changed, 0, "The %s's edge %d changes no pixel of the page" % [kind, edge])
            assert_true(outside_changed > 1000, "and ends the sheet past it, %d pixels changed" % outside_changed)
            var far := edged.get_pixel(2, 2)
            assert_true(far.a < 0.05, "Far past the %s's edge %d the view shows what is behind, alpha %.3f" % [kind, edge, far.a])


## A file saved before the row, with no fibre, felt, laid, slub, fuzz, crimp,
## priming or edge, opens on the texels its kernel drew then.
func test_a_file_saved_before_the_row_opens_on_the_same_look() -> void:
    for pair: Array in [[SAVED_PAPER, PAPER_BEFORE, &"paper"], [SAVED_CANVAS, CANVAS_BEFORE, &"canvas"]]:
        var easel := SaEasel.create_default(Vector2i(512, 512))
        easel.compositor.set_registry(_registries.blend_modes)
        assert_eq(SaExport.load_sad(easel.document, ProjectSettings.globalize_path(pair[0])), OK, "%s loads" % pair[2])
        # A load keeps each layer's type id, and the registry gives it back
        # its kernel, as the app does after every open.
        _registries.layer_types.rebind(SaLayerOps.new(easel.document).layers())
        var ground: SaLayer = null
        for layer: SaLayer in SaLayerOps.new(easel.document).layers():
            if layer.is_generated() and layer.generator == String(pair[2]):
                ground = layer
        assert_not_null(ground, "with its %s" % pair[2])
        if ground != null:
            for key: String in ["fibre", "felt", "laid", "slub", "fuzz", "crimp", "priming", "edge"]:
                assert_false(ground.generator_params.has(key), "which never had a %s" % key)
            var texture := easel.compositor.generate_chunk(
                ground, Vector2(256, 0), Rect2i(0, 0, 256, 256), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
            )
            var floats := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
            var expected: Array = pair[1]
            var largest := 0.0
            for index in SAMPLES.size():
                var at := (SAMPLES[index].y * texture.size.x + SAMPLES[index].x) * 4
                for c in 3:
                    largest = maxf(largest, absf(floats[at + c] - float(expected[index][c])))
            assert_true(largest < 0.0001, "and draws the texels it drew, %.6f apart at most" % largest)
        easel.free()


## A preset is one history step that writes its sheet whole, and the undo
## takes back every number, a key the layer never had included.
func test_a_preset_is_one_step_and_its_undo_takes_it_back() -> void:
    var ground := _add_ground(&"paper")
    ground.generator_params.erase("felt")
    var before := ground.generator_params.duplicate()
    SaGeneratedLayer.apply_preset(_doc, ground, _preset(&"paper", "Rough"))
    assert_almost_eq(SaTyped.float_at(ground.generator_params, "felt", 0.0), 1.0, 0.0001, "Rough lays the felt whole")
    assert_almost_eq(SaTyped.float_at(ground.generator_params, "felt_size", 0.0), 28.0, 0.0001, "at its cell")
    _doc.undo()
    assert_eq(ground.generator_params, before, "and one undo puts back the sheet it was")
