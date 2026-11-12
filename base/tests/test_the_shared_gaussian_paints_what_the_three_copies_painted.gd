## The Gaussian blur, the High Pass and the Unsharp Mask take
## their Gaussian from one library, `base/shaders/gaussian.gmacs`, and paint
## what their three copies of it painted. Each filter runs over one painted
## chunk through its kernel as it is and, after an undo, through the copy of
## its kernel as it stood before the fold, kept in
## `tests/fixtures/one-gaussian/modules/gaussian-before-fold/`, and the
## two runs read equal byte for byte in every chunk the layer holds.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The bell is lowered.** The library lowers the bell by its own height one
## texel past the reach, so a wide blur stops stepping down at its edge, and the
## change is in the library alone. The three Gaussian filters paint apart
## from their copies, every one of them at every radius here, which is
## the fold doing what it was for: one place for a fix to the bell, and the fix
## reached all three. So their cases read the run against the copy and find it
## moved, and what the lowered bell paints is pinned where the bell is read,
## in the suites `test_gaussian_blur.gd` and `test_sharpen.gd`. The five-tap
## sharpen holds no Gaussian and still reads equal to its copy byte for byte in
## colour. Its alpha is the copy's held between nought and one, or the texel's
## own alpha where that lies outside them, since a sharpened edge overshot its
## coverage past one and below nought and now keeps it as coverage.
##
## The chunk is noise rather than a shape: every texel its own colour, some
## channels above one and below nought, some texels transparent and many half
## covered, so a weight, a normalisation, a premultiplication or a sum taken in
## another order that moved one bit anywhere shows. It sits in the middle of a
## canvas three chunks across, so the halo reads empty paint on all four sides
## and the run spills into all eight chunks round it, which are read too.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## The owner the shader index files the copies under, the fixture's folder. A
## context with this id and no ModuleLoader behind it qualifies a bare kernel
## name to the copies, so the Sharpen's own `run` records them.
const BEFORE: StringName = &"gaussian-before-fold"
## The painted chunk, with a chunk of canvas on every side of it.
const MIDDLE := Vector2i(1, 1)
const CHUNKS_ACROSS := 3
## So every run paints the same noise.
const SEED := 43005
## The radii each Gaussian runs at: the least the dialog offers, the Sharpen's
## default, one whose walk ends partway through a block of eight, and one
## broader than a group by five times.
const RADII: Array[int] = [1, 3, 11, 40]
## The unsharp mask's amount and threshold, in the dialog's per cent, the
## threshold high enough that the gate's smoothstep decides some texels.
const AMOUNT := 150.0
const THRESHOLD := 10.0
## The library and the three kernels that import it.
const LIBRARY := "res://modules/sara-base-modules/base/shaders/gaussian.gmacs"
const KERNELS: Array[String] = [
    "res://modules/sara-base-modules/base/shaders/gaussian_blur.gmacs",
    "res://modules/sara-base-modules/base/shaders/high_pass.gmacs",
    "res://modules/sara-base-modules/base/shaders/sharpen.gmacs",
]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i.ONE * CHUNKS_ACROSS * SaChunk.SIZE)
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _paint_noise()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The middle chunk, uploaded whole, since the brush is not what this suite is
## about. Each texel's alpha is nought, one or anything between, a third of the
## time each, and its colour anywhere from just below nought to three.
func _paint_noise() -> void:
    var texture := _layer.get_or_create_chunk(MIDDLE).albedo()
    var rng := RandomNumberGenerator.new()
    rng.seed = SEED
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y * 4)
    for texel in texture.size.x * texture.size.y:
        for channel in 3:
            values[texel * 4 + channel] = rng.randf_range(-0.25, 3.0)
        var coverage := rng.randi_range(0, 2)
        values[texel * 4 + 3] = rng.randf() if coverage == 2 else float(coverage)
    var image := Image.create_from_data(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF, values.to_byte_array())
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    _layer.mark_unresolved(MIDDLE)


## Every chunk the layer holds, as its stored bytes.
func _picture() -> Dictionary[Vector2i, PackedByteArray]:
    var out: Dictionary[Vector2i, PackedByteArray] = {}
    for grid_pos: Vector2i in _layer.chunks.keys():
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(_layer.get_field(grid_pos).rid, 0)
    return out


## How many texels of chunk *grid_pos* differ between *found* and *wanted*,
## and the first of them, for the message, to nine places, since a difference
## this suite exists to catch is in the last bit.
func _difference(found: PackedByteArray, wanted: PackedByteArray, grid_pos: Vector2i) -> String:
    var field := _layer.get_field(grid_pos)
    var format := field.format
    var stride: int = SaFieldSpec.BYTES_PER_TEXEL.get(format, 0)
    @warning_ignore("integer_division")
    var texels := mini(found.size(), wanted.size()) / stride
    var count := 0
    var first := -1
    for texel in texels:
        if found.slice(texel * stride, (texel + 1) * stride) != wanted.slice(texel * stride, (texel + 1) * stride):
            count += 1
            first = texel if first < 0 else first
    if first < 0:
        return "%d bytes against %d" % [found.size(), wanted.size()]
    @warning_ignore("integer_division")
    var at := Vector2i(first % field.size.x, first / field.size.x)
    return (
        "%d texels differ, the first at %s reading %s against %s"
        % [
            count,
            at,
            _exact(SaFieldSpec.decode_texel(found, format, first)),
            _exact(SaFieldSpec.decode_texel(wanted, format, first))
        ]
    )


func _exact(colour: Color) -> String:
    return "(%.9f, %.9f, %.9f, %.9f)" % [colour.r, colour.g, colour.b, colour.a]


func _assert_same(
    found: Dictionary[Vector2i, PackedByteArray], wanted: Dictionary[Vector2i, PackedByteArray], what: String
) -> void:
    var found_keys := found.keys()
    var wanted_keys := wanted.keys()
    found_keys.sort()
    wanted_keys.sort()
    assert_eq(found_keys, wanted_keys, "%s holds the same chunks" % what)
    for grid_pos: Vector2i in wanted_keys:
        if not found.has(grid_pos):
            continue
        var same: bool = found[grid_pos] == wanted[grid_pos]
        assert_true(
            same,
            (
                "%s reads the same in chunk %s%s"
                % [what, grid_pos, "" if same else ", " + _difference(found[grid_pos], wanted[grid_pos], grid_pos)]
            )
        )


## *filter* over the layer through its own `run` and the kernel as it is.
func _run_now(filter: SaFilter) -> bool:
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    return SaFilterApply.call_run(filter, ctx) and SaFilterApply.apply(ctx, filter.title())


## The pass *record* writes into a context, applied over the layer: the same
## pass as the filter's `run`, at the copy of the kernel.
func _run_before(record: Callable, title: String) -> bool:
    var ctx := SaFilterContext.new(_doc, _layer, BEFORE, title)
    record.call(ctx)
    return ctx.point != null and SaFilterApply.apply(ctx, title)


## *filter* under *values* now, the undo, and the same pass through the copy,
## answering the two pictures, now's first. The copy's run is left on the layer
## for the caller to undo.
func _now_and_before(filter: SaFilter, values: Dictionary, record: Callable, what: String) -> Array[Dictionary]:
    filter.set_parameters(values)
    var painted := _picture()
    assert_true(_run_now(filter), "%s runs through the kernel as it is" % what)
    var now := _picture()
    assert_false(now == painted, "and changes the painted chunk")
    assert_true(_doc.undo(), "which undoes")
    _assert_same(_picture(), painted, "The undone layer of %s" % what)
    assert_true(_run_before(record, filter.title()), "%s runs through the copy of the kernel before the fold" % what)
    return [now, _picture()]


## The two runs of [method _now_and_before] read against each other and then
## undone, so the next case starts from the painted chunk again.
func _assert_paints_as_before(filter: SaFilter, values: Dictionary, record: Callable, what: String) -> void:
    var both := _now_and_before(filter, values, record, what)
    _assert_same(both[0], both[1], "%s through the shared Gaussian" % what)
    assert_true(_doc.undo(), "and the copy's run undoes as well")


## The two runs of [method _now_and_before] holding the same chunks and reading
## apart, because the copy weighs its taps with the bell as it stood before the
## bell was lowered, and then undone.
func _assert_moved_from_before(filter: SaFilter, values: Dictionary, record: Callable, what: String) -> void:
    var both := _now_and_before(filter, values, record, what)
    var held := both[0].keys()
    var held_before := both[1].keys()
    held.sort()
    held_before.sort()
    assert_eq(held, held_before, "%s holds the same chunks as the copy's run" % what)
    assert_false(both[0] == both[1], "%s paints apart from the copy, under the lowered bell" % what)
    assert_true(_doc.undo(), "and the copy's run undoes as well")


func test_the_gaussian_blur_moved_from_its_copy_with_the_bell() -> void:
    var filter := SaGaussianBlurFilter.new()
    for radius in RADII:
        var record := func(ctx: SaFilterContext) -> void:
            ctx.neighbourhood_pass("%s/gaussian_blur" % BEFORE, "gaussian_blur", {"radius": radius}, radius)
        _assert_moved_from_before(filter, {"radius": radius}, record, "The Gaussian blur at radius %d" % radius)


func test_the_high_pass_moved_from_its_copy_with_the_bell() -> void:
    var filter := SaHighPassFilter.new()
    for radius in RADII:
        var params := SaHighPassFilter.params_for(radius, _doc.color_space)
        var record := func(ctx: SaFilterContext) -> void:
            ctx.neighbourhood_pass("%s/high_pass" % BEFORE, "high_pass", params, radius)
        _assert_moved_from_before(filter, {"radius": radius, "raw": true}, record, "The High Pass at radius %d" % radius)


## The Sharpen's own `run` records both, the bare `sharpen` it names qualified
## to the copy by the context's id.
func test_the_unsharp_mask_moved_from_its_copy_with_the_bell() -> void:
    var filter := SaSharpenFilter.new()
    for radius in RADII:
        var values := {"kind": SaSharpenFilter.UNSHARP_MASK, "radius": radius, "amount": AMOUNT, "threshold": THRESHOLD}
        _assert_moved_from_before(filter, values, filter.run, "The unsharp mask at radius %d" % radius)
    var plain := {"kind": SaSharpenFilter.UNSHARP_MASK, "radius": RADII[1], "amount": AMOUNT, "threshold": 0.0}
    _assert_moved_from_before(filter, plain, filter.run, "The unsharp mask with no threshold")


## The fold itself, read off the text: each of the three imports the library
## and none defines a weight of its own, so a fix to the bell has one place to
## go.
func test_no_kernel_of_the_three_defines_its_own_weight() -> void:
    var own_weight := RegEx.create_from_string("(?m)^def\\s+weight\\s*\\(")
    var imports := RegEx.create_from_string("(?m)^import\\s+gaussian\\s*$")
    for path: String in KERNELS:
        var text := FileAccess.get_file_as_string(path)
        assert_false(text.is_empty(), "%s is read" % path)
        assert_null(own_weight.search(text), "%s defines no weight of its own" % path)
        assert_not_null(imports.search(text), "and imports the gaussian library")
    assert_true(FileAccess.file_exists(LIBRARY), "The library is %s" % LIBRARY)


## The five taps share no Gaussian, and they are in the file that imports it.
func test_the_five_tap_sharpen_paints_what_its_copy_painted() -> void:
    var filter := SaSharpenFilter.new()
    var values := {"kind": SaSharpenFilter.SHARPEN, "amount": AMOUNT, "threshold": THRESHOLD}
    var painted := _picture()
    var both := _now_and_before(filter, values, filter.run, "The five-tap sharpen")
    _assert_same_with_alpha_held(both[0], both[1], painted, "The five-tap sharpen through the shared Gaussian")
    assert_true(_doc.undo(), "and the copy's run undoes as well")


## A chunk's stored bytes as straight floats, whichever float format it holds.
func _floats(bytes: PackedByteArray, grid_pos: Vector2i) -> PackedFloat32Array:
    var field := _layer.get_field(grid_pos)
    var half := field.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_from_data(
        field.size.x, field.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF, bytes
    )
    image.convert(Image.FORMAT_RGBAF)
    return image.get_data().to_float32_array()


## *found* against *wanted* with every colour channel equal and every alpha the
## wanted one held between nought and one, or at the texel's alpha in *painted*
## where that lies outside them, the bound the sharpen's `finish` keeps.
func _assert_same_with_alpha_held(
    found: Dictionary[Vector2i, PackedByteArray],
    wanted: Dictionary[Vector2i, PackedByteArray],
    painted: Dictionary[Vector2i, PackedByteArray],
    what: String
) -> void:
    var found_keys := found.keys()
    var wanted_keys := wanted.keys()
    found_keys.sort()
    wanted_keys.sort()
    assert_eq(found_keys, wanted_keys, "%s holds the same chunks" % what)
    var held := 0
    for grid_pos: Vector2i in wanted_keys:
        if not found.has(grid_pos):
            continue
        var now := _floats(found[grid_pos], grid_pos)
        var copy := _floats(wanted[grid_pos], grid_pos)
        var was := _floats(painted[grid_pos], grid_pos) if painted.has(grid_pos) else PackedFloat32Array()
        var first := -1
        for index in copy.size():
            var expected := copy[index]
            if index % 4 == 3:
                var own := was[index] if not was.is_empty() else 0.0
                expected = clampf(expected, minf(0.0, own), maxf(1.0, own))
                held += 1 if expected != copy[index] else 0
            if now[index] != expected and first < 0:
                first = index
        assert_eq(first, -1, "%s reads the copy with its alpha held in chunk %s" % [what, grid_pos])
    assert_true(held > 0, "%s held the copy's alpha in %d texels" % [what, held])
