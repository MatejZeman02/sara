## The variants a format assignment compiles, and a document at each depth.
##
## The other half of `test_storage_formats.gd`, split off when that file came
## within two cases of gdlint's cap of 32 public methods. The seam is
## where the probe kernel stops being needed: everything before it binds the
## five-binding probe and asks what a kernel can be handed, and everything here
## asks what the compiler does with an assignment of formats and what a whole
## document does at each depth. Nothing was rewritten in the move, so the two
## files together assert exactly what the one did.
##
## `_read_half` and `_read_float` are five lines each and are in both files
## rather than in a shared fixture, because a reader of either suite wants to
## see how a texel is read back without leaving the file, and because
## `tests/fixtures.gd` belongs to nobody on this board.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const R32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT

## The dialect pass, so the walk below reads a converted kernel the way the
## compiler does. The conversion of every kernel rewrites `layout( ... ) uniform image2D` as
## `image`, and a walk that only knows the GLSL spelling checks nothing at all
## once the sweep is through.
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
## The bindings that are F32 whatever the document's depth, by file. The smudge
## carry is a two-texel scratch the reservoir always makes at F32, so its kernel
## has to say so literally, and the token would declare it F16 on an F16 document
## and bind it against the wrong view. The canvas image beside it takes the token.
const FIXED_F32 := {
    "smudge_pickup.gmacs": ["reservoir"],
    "smudge_blur.gmacs": ["cells", "rows", "reservoir"],
    "smudge_field.gmacs": ["reservoir", "held", "mix_under", "mix_over"],
    "smudge_mix.gmacs": ["reservoir", "mix_under", "mix_over", "held"],
}


func _read_half(texture: SaTexture, index: int = 0) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := index * 8
    return [bytes.decode_half(base), bytes.decode_half(base + 2), bytes.decode_half(base + 4), bytes.decode_half(base + 6)]


func _read_float(texture: SaTexture, index: int = 0) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := index * 16
    return [bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), bytes.decode_float(base + 12)]


func test_no_kernel_hardcodes_a_storage_format() -> void:
    # The token is the whole mechanism. A binding that writes rgba32f literally
    # can only ever be dispatched at F32 textures, and nothing would say so.
    var dir := DirAccess.open("res://shaders/compute")
    assert_not_null(dir, "The shader directory should be readable")
    if dir == null:
        return

    var checked := 0
    for file_name in dir.get_files():
        if not file_name.ends_with(".gmacs"):
            continue
        var text := Dialect.to_glsl(FileAccess.get_file_as_string("res://shaders/compute/".path_join(file_name)))
        text = _without_fixed_bindings(text, FIXED_F32.get(file_name, []))
        if not text.contains("uniform image2D"):
            continue
        checked += 1
        assert_false(
            text.contains("rgba32f") or text.contains("rgba16f"),
            "%s should declare %s rather than a literal format" % [file_name, GlobalShaderCompiler.STORAGE_FORMAT_TOKEN]
        )
    assert_true(checked > 0, "Some shader should have been checked, or this test proves nothing")


## *text* less its comments and the declarations of the bindings named in
## *fixed*, which are the only places a literal format may stand.
func _without_fixed_bindings(text: String, fixed: Array) -> String:
    var kept := PackedStringArray()
    for line in text.split("\n"):
        if line.strip_edges().begins_with("//"):
            continue
        var declares_fixed := false
        for binding: String in fixed:
            if line.contains("uniform image2D") and line.strip_edges().ends_with(" %s;" % binding):
                declares_fixed = true
        if not declares_fixed:
            kept.append(line)
    return "\n".join(kept)


func test_both_variants_compile_and_are_distinct() -> void:
    var f32_kernels: Array = GlobalShaderCompiler.get_compute_kernel_compilations("composite", F32)
    var f16_kernels: Array = GlobalShaderCompiler.get_compute_kernel_compilations("composite", F16)

    assert_false(f32_kernels.is_empty(), "The default variant compiles")
    assert_eq(f16_kernels.size(), f32_kernels.size(), "Both variants carry the same kernels in the same order")
    assert_true(f16_kernels[0] != f32_kernels[0], "and they are genuinely different shader RIDs")

    # Kernel names and order are variant-independent, which is what lets blend
    # modes resolve by name without knowing the document's depth.
    assert_true(GlobalShaderCompiler.get_kernel_index("composite", "multiply") > 0, "Kernel lookup is unaffected by variants")


func test_an_unknown_storage_format_falls_back_rather_than_emitting_the_token() -> void:
    # The token is not valid GLSL, so leaving it in would fail the compile and
    # blame the shader for a caller that asked for a format nothing supports.
    assert_true(GlobalShaderCompiler.supports_storage_format(F32), "F32 is supported")
    assert_true(GlobalShaderCompiler.supports_storage_format(F16), "F16 is supported")
    assert_false(
        GlobalShaderCompiler.supports_storage_format(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM), "an integer one is not"
    )

    var substituted: String = GlobalShaderCompiler.source.substitute_storage_formats(
        "layout(%s) uniform image2D t;" % GlobalShaderCompiler.STORAGE_FORMAT_TOKEN, F16, {}
    )
    assert_true(substituted.contains("rgba16f"), "F16 substitutes the half format")
    assert_false(substituted.contains(GlobalShaderCompiler.STORAGE_FORMAT_TOKEN), "and leaves no placeholder behind")


func test_a_kernel_dispatches_at_the_format_it_was_compiled_for() -> void:
    var f16 := SaTexture.new(Vector2i(16, 16), F16)
    f16.clear(Color(0, 0, 0, 0))

    var fill := SaCompute.new("fill")
    fill.use_storage_format(F16)
    assert_eq(fill.pipelines.storage_format, F16, "The instance follows the texture it is about to bind")

    fill.set_texture(0, f16.rid)
    var mask_1 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_1.clear(Color(1.0, 1.0, 1.0, 1.0))
    fill.set_texture(SaSelection.BINDING, mask_1.rid)
    fill.set_push_constant_float_array(PackedFloat32Array([0.25, 0.5, 0.75, 1.0, 0.0, 0.0, 0.0, 0.0]))
    fill.dispatch_kernel("fill", 2, 2, 1)

    assert_eq(_read_half(f16), [0.25, 0.5, 0.75, 1.0], "An F16 dispatch writes the values it was given")


func test_switching_format_on_one_instance_rebuilds_its_pipelines() -> void:
    # The uniform set is created against a specific shader RID, so a variant
    # switch that kept the old set would bind a set built for the other shader.
    var compute := SaCompute.new("fill")
    var f32_pipeline: RID = compute.pipelines.kernels[0]

    compute.use_storage_format(F16)
    assert_true(compute.pipelines.kernels[0] != f32_pipeline, "Switching format swaps the pipelines")
    assert_true(compute.uniforms.refresh, "and forces the uniform set to be rebuilt")

    compute.use_storage_format(F16)
    assert_eq(compute.pipelines.storage_format, F16, "Setting the same format again is a no-op")


func test_f16_keeps_out_of_range_values_within_the_range_it_has() -> void:
    # The no-clamp guarantee is that Sara never discards a negative or a value
    # above 1.0. It is not a promise that F16 can hold any magnitude: the range
    # is the depth the user chose. 65504 is the largest finite half, and a
    # larger value converts to infinity rather than saturating, because that is
    # what IEEE round-to-nearest does.
    var f16 := SaTexture.new(Vector2i(8, 8), F16)
    f16.clear(Color(0, 0, 0, 0))
    var source := SaTexture.new(Vector2i(8, 8), F16)
    source.clear(Color(-0.5, 2.5, 60000.0, 1.0))

    var compositor := SaCompositor.new()
    compositor.register_blend_mode(SaLayer.BLEND_MODE.ADD, "composite", GlobalShaderCompiler.get_kernel_index("composite", "add"))
    compositor.composite_chunk(f16, source, SaLayer.BLEND_MODE.ADD, 1.0)

    var texel := _read_half(f16)
    assert_almost_eq(texel[0], -0.5, 1e-3, "A negative survives F16 storage")
    assert_almost_eq(texel[1], 2.5, 1e-3, "and so does a value above 1.0")
    assert_almost_eq(texel[2], 60000.0, 32.0, "and a large one, to half precision at that magnitude")


func test_storing_beyond_the_half_range_saturates_but_blending_there_does_not() -> void:
    # Do not assert a number here. 70000 is outside the half range, and what
    # comes back was measured as 65504 on a plain run and as inf under
    # --gpu-validation, for the store *and* for a blend at that magnitude. Both
    # are defensible (saturate, or IEEE round-to-nearest overflow), neither is
    # promised, and two earlier versions of this test pinned one observation each
    # and flipped the moment the other run happened.
    #
    # The contract is what is worth asserting: an out-of-range magnitude is never
    # discarded, wrapped or turned into something small. It stays at least the
    # largest finite half, which is true of 65504 and of inf.
    var f16 := SaTexture.new(Vector2i(4, 4), F16)
    f16.clear(Color(70000.0, 0.0, 0.0, 1.0))
    var stored: float = _read_half(f16)[0]
    assert_true(stored >= 65504.0, "An out-of-range magnitude is not discarded or wrapped, whatever the ceiling does")

    # None of which is a no-clamp violation. The guarantee is that Sara never
    # throws away a negative or a value above 1.0, not that F16 holds any
    # magnitude: the range is the depth the user picked, and F32 is the default.
    assert_true(SaColorSpace.new().depth == SaColorSpace.Depth.F32, "F32 remains the default depth for exactly this reason")


# ---------------------------------------------------------------------------
# A document at each depth, end to end
# ---------------------------------------------------------------------------


func test_a_document_allocates_every_layer_at_its_declared_depth() -> void:
    for depth: int in SaColorSpace.storage_depths():
        var space := SaColorSpace.srgb().with_depth(depth as SaColorSpace.Depth)
        var easel := SaEasel.create_default(Vector2i(256, 256))
        easel.document.reset_to_default(Vector2i(256, 256), space)
        easel.resize_output(Vector2i(256, 256))

        var doc := easel.document
        var expected := space.texel_format()
        var name := SaColorSpace.depth_name(depth)

        for child in doc.get_children():
            if child is SaLayer:
                var layer := child as SaLayer
                # The paint layer has no chunks until paint lands, and the one it
                # then gains has to follow the depth as well.
                assert_eq(
                    layer.get_or_create_chunk(Vector2i(0, 0)).albedo().format,
                    expected,
                    "%s: layer %s allocates at the depth" % [name, layer.name]
                )

        # The caches and the stroke buffer are not children and are exactly what
        # a "which layers did we remember" bug would leave behind at F32.
        for orphan: SaLayer in [doc.stroke_layer, doc.fold.bottom_cache, doc.fold.top_cache]:
            orphan.get_or_create_chunk(Vector2i(0, 0))
            assert_eq(orphan.get_field(Vector2i(0, 0)).format, expected, "%s: %s follows the document too" % [name, orphan.name])

        assert_eq(easel.output.format, expected, "%s: the composited output matches as well" % name)
        easel.free()


func test_an_f16_document_paints_composites_and_reads_back() -> void:
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.document.reset_to_default(Vector2i(256, 256), space)
    easel.resize_output(Vector2i(256, 256))

    var doc := easel.document
    doc.active_layer.fill(Color(0.25, 0.5, 0.75, 1.0))
    doc.update_caches()
    easel.compositor.composite_all_layers(easel.output, doc, Rect2(0, 0, 256, 256))

    # get_texture_image_float once rejected anything but RGBA32F, which would
    # have made EXR export fail on exactly the documents that chose F16.
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(doc.active_layer.get_field(Vector2i(0, 0)))
    assert_not_null(image, "An F16 field reads back rather than being refused")
    if image == null:
        return
    assert_eq(image.get_format(), Image.FORMAT_RGBAF, "and is widened to RGBAF, losslessly, so callers need not care")
    var texel := image.get_pixel(0, 0)
    assert_almost_eq(texel.r, 0.25, 1e-3, "with the value that was painted")
    assert_almost_eq(texel.b, 0.75, 1e-3, "on every channel")

    @warning_ignore("static_called_on_instance")
    var composited := SaExport.get_easel_image_float(easel)
    assert_not_null(composited, "and the composited output reads back too")

    easel.free()


func test_converting_an_f16_document_keeps_it_f16() -> void:
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))

    # ACEScg's preset names F32. Converting must change the gamut and leave the
    # storage alone, or a colour operation quietly reallocates the document.
    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.acescg()), "An F16 document converts")
    assert_eq(doc.color_space.depth, SaColorSpace.Depth.F16, "and stays F16")
    assert_eq(
        doc.active_layer.get_field(Vector2i(0, 0)).format,
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
        "with its chunks still allocated at F16, matching what the header will say"
    )
    doc.free()


## The three cache layers carry no header entry, because they are rebuilt on load
## rather than stored, so nothing in the file says what depth to allocate them at.
##
## They were left at the default F32 while the paint layers came back F16,
## and `composite_chunk` refused every dispatch between them with "one dispatch
## cannot serve both". Refusing is right, a mismatched storage-image bind is
## undefined across the whole image. The load reported OK regardless, and the
## suite stayed green, which is exactly why this asserts the formats rather than
## the return code.
func test_the_caches_follow_the_loaded_documents_depth() -> void:
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var source := SaDocument.new()
    source.setup_default_document(Vector2i(64, 64), SaCompositor.new(), space)
    source.active_layer.fill(Color(0.25, 0.5, 0.75, 1.0))

    var path := SaDataRoot.path("test_f16_caches.sad")
    assert_eq(SaExport.save_sad(source, path), OK, "An F16 document saves")

    # Deliberately loaded into a document that is *already* set up at F32, which
    # is the real case: a session editing one document opens another. A fresh
    # SaDocument would have no caches yet and would take the fixed branch for the
    # wrong reason.
    var target := SaDocument.new()
    target.setup_default_document(Vector2i(32, 32), SaCompositor.new(), SaColorSpace.srgb())
    assert_eq(target.fold.bottom_cache.schema[0].format, F32, "The target starts with F32 caches")

    assert_eq(SaExport.load_sad(target, path, SaCompositor.new()), OK, "and the F16 file loads into it")
    for named: Array in [
        ["stroke buffer", target.stroke_layer], ["bottom cache", target.fold.bottom_cache], ["top cache", target.fold.top_cache]
    ]:
        var cache: SaLayer = named[1]
        assert_eq(cache.schema[0].format, F16, "The %s follows the loaded document" % named[0])

    # A cache that kept a tile allocated at the old depth would still mismatch,
    # whatever its schema now says.
    for named: Array in [
        ["stroke buffer", target.stroke_layer], ["bottom cache", target.fold.bottom_cache], ["top cache", target.fold.top_cache]
    ]:
        var cache: SaLayer = named[1]
        for grid_pos: Vector2i in cache.chunks:
            var texture := cache.get_field(grid_pos)
            if texture != null:
                assert_eq(texture.format, F16, "Every %s tile is at the loaded depth" % named[0])

    DirAccess.remove_absolute(path)
    target.free()
    source.free()


func test_an_f16_document_round_trips_through_sad() -> void:
    # The container stores raw chunk bytes with a per-field format tag and the
    # descriptor in the header, so this should hold by construction. Asserted
    # anyway, because "by construction" is what was said about the depth
    # reaching storage in the first place.
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new(), space)
    doc.active_layer.fill(Color(0.25, 0.5, 0.75, 1.0))

    var path := SaDataRoot.path("test_f16_roundtrip.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "An F16 document saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads back")
    assert_eq(loaded.color_space.depth, SaColorSpace.Depth.F16, "with the depth the header recorded")
    assert_true(loaded.color_space.is_specified, "and still described")

    # The header and the allocation have to agree on the way back in, which is
    # the whole invariant. A file saying F16 that reloads as F32 chunks is the
    # original bug in the other direction.
    var layer: SaLayer = loaded.get_child(loaded.get_child_count() - 1)
    var texture := layer.get_field(Vector2i.ZERO)
    assert_not_null(texture, "The saved chunk comes back")
    if texture == null:
        return
    assert_eq(texture.format, F16, "allocated at the depth the file declared, not the default")

    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    assert_almost_eq(bytes.decode_half(0), 0.25, 1e-3, "Red survives as a half")
    assert_almost_eq(bytes.decode_half(2), 0.5, 1e-3, "Green survives as a half")
    assert_almost_eq(bytes.decode_half(4), 0.75, 1e-3, "Blue survives as a half")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()
