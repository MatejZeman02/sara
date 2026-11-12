## A layer stored at twice the document's resolution composites
## into the document's picture at the document's resolution, each pixel the mean
## of the two by two texels under it.
##
## Most tests here build the same document twice. In one the layer holds chunks
## at 2.0 with a one-texel checker of two colours, in the other chunks at 1.0
## filled with the checker's mean, and the two canvases are compared texel for
## texel. The colours are sums of powers of two, so the mean is exact in half
## floats and equal means equal bytes. The chunks at 2.0 are made by hand with
## `SaChunk.create(schema, 2.0)`, so nothing here waits on the layer scale.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const ONE := Color(0.25, 0.5, 0.75, 1.0)
const TWO := Color(0.75, 0.25, 0.125, 1.0)
const MEAN := Color(0.5, 0.375, 0.4375, 1.0)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)


func _easel(size: Vector2i) -> SaEasel:
    var made := SaEasel.create_default(size)
    made.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return made


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


func _upload(texture: SaTexture, texel: Callable) -> void:
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var single := texture.format == RenderingDevice.DATA_FORMAT_R32_SFLOAT
    var image_format := Image.FORMAT_RF if single else (Image.FORMAT_RGBAF if wide else Image.FORMAT_RGBAH)
    var image := Image.create_empty(texture.size.x, texture.size.y, false, image_format)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


## A layer added above the background, holding the checker at 2.0 when *fine*
## and its mean at 1.0 when not, at every position in *positions*.
func _layer(doc: SaDocument, fine: bool, positions: Array) -> SaLayer:
    var layer := SaLayerOps.new(doc).add()
    for grid_pos: Vector2i in positions:
        if fine:
            layer.chunks[grid_pos] = SaChunk.create(layer.schema, 2.0)
            _upload(layer.get_field(grid_pos), _checker)
        else:
            layer.get_or_create_chunk(grid_pos).clear(MEAN)
    doc.invalidate_chunks(positions)
    return layer


func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## Every texel of the two canvases equal, and the first one that is not named.
func _same(fine: SaTexture, plain: SaTexture, what: String) -> void:
    var a := _bytes(fine)
    var b := _bytes(plain)
    if a == b:
        assert_true(true, what)
        return
    var count := fine.size.x * fine.size.y
    for i in count:
        var left := SaFieldSpec.decode_texel(a, fine.format, i)
        var right := SaFieldSpec.decode_texel(b, plain.format, i)
        if not left.is_equal_approx(right):
            assert_true(
                false,
                (
                    "%s: texel (%d, %d) is %s where the layer at 1.0 gives %s"
                    % [what, i % fine.size.x, floori(i / float(fine.size.x)), left, right]
                )
            )
            return
    assert_true(false, "%s: the bytes differ though every texel reads the same" % what)


## The two documents, the same *treatment* given to the layer in each, and
## their canvases compared.
func _pair(size: Vector2i, positions: Array, treatment: Callable, what: String) -> void:
    var fine := _easel(size)
    var plain := _easel(size)
    for easel: SaEasel in [fine, plain]:
        easel.document.fill_layer(UNDER, easel.document.get_node("Layer 1") as SaLayer)
        var layer := _layer(easel.document, easel == fine, positions)
        treatment.call(easel.document, layer, easel == fine)
        _composite(easel)
    _same(fine.output, plain.output, what)
    fine.free()
    plain.free()


func _nothing(_doc: SaDocument, _held: SaLayer, _fine: bool) -> void:
    pass


func test_a_checker_at_2_composites_as_its_mean() -> void:
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _nothing, "The checker at 2.0 on the active layer is its mean")
    var fine := _easel(Vector2i(256, 256))
    _layer(fine.document, true, [Vector2i.ZERO])
    _composite(fine)
    var bytes := _bytes(fine.output)
    var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(255, 0), Vector2i(0, 255), Vector2i(255, 255), Vector2i(97, 31)]
    for at in corners:
        var found := SaFieldSpec.decode_texel(bytes, fine.output.format, at.y * 256 + at.x)
        assert_true(found.is_equal_approx(MEAN), "Pixel %s is the mean of its four texels, %s" % [at, found])
    fine.free()


func _below_the_active(doc: SaDocument, _held: SaLayer, _fine: bool) -> void:
    doc.set_active_layer(doc.get_node("Layer 1") as SaLayer)


func test_a_checker_at_2_below_the_active_layer_composites_as_its_mean() -> void:
    _pair(
        Vector2i(256, 256),
        [Vector2i.ZERO],
        _below_the_active,
        "A layer at 2.0 above the active one is drawn by its tier as its mean"
    )


func test_a_solid_layer_at_2_equals_one_at_1() -> void:
    var fine := _easel(Vector2i(256, 256))
    var plain := _easel(Vector2i(256, 256))
    for easel: SaEasel in [fine, plain]:
        var layer := SaLayerOps.new(easel.document).add()
        if easel == fine:
            layer.chunks[Vector2i.ZERO] = SaChunk.create(layer.schema, 2.0)
            layer.get_field(Vector2i.ZERO).clear(Color(0.3, 0.6, 0.9, 0.7))
        else:
            layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.3, 0.6, 0.9, 0.7))
        easel.document.invalidate_chunks([Vector2i.ZERO])
        _composite(easel)
    assert_eq(
        fine.document.active_layer.chunks[Vector2i.ZERO].albedo().size,
        Vector2i(512, 512),
        "The layer's chunk holds 512 texels across"
    )
    _same(fine.output, plain.output, "A solid layer at 2.0 and one at 1.0 give the same canvas, alpha 0.7 included")
    fine.free()
    plain.free()


func _masked(_doc: SaDocument, layer: SaLayer, fine: bool) -> void:
    layer.add_mask(1.0)
    var coverage := layer.mask.texture_for(Vector2i.ZERO)
    var scale := 2 if fine else 1
    _upload(coverage, func(x: int, _y: int) -> Color: return Color(0.25 if x < 128 * scale else 1.0, 0, 0, 1))
    layer.mask.enabled = true


func test_under_a_mask() -> void:
    _pair(
        Vector2i(256, 256), [Vector2i.ZERO], _masked, "Under a mask held at 2.0 the layer is its mean, hidden as the 1.0 layer is"
    )


func _masked_below(doc: SaDocument, layer: SaLayer, fine: bool) -> void:
    _masked(doc, layer, fine)
    _below_the_active(doc, layer, fine)


func test_under_a_mask_below_the_active_layer() -> void:
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _masked_below, "Masked and drawn by its tier, the same")


func _grouped(doc: SaDocument, layer: SaLayer, _fine: bool) -> void:
    var ops := SaLayerOps.new(doc)
    ops.set_blend_mode(layer, &"multiply")
    var group := ops.group_layers([layer])
    ops.set_isolated(group, true)
    doc.set_active_layer(layer)


func test_inside_an_isolated_group() -> void:
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _grouped, "Inside an isolated group, active, the layer is its mean")


func _grouped_below(doc: SaDocument, layer: SaLayer, fine: bool) -> void:
    _grouped(doc, layer, fine)
    _below_the_active(doc, layer, fine)


func test_inside_an_isolated_group_folded() -> void:
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _grouped_below, "Inside an isolated group the fold caches, the same")


func _multiply(doc: SaDocument, layer: SaLayer, _fine: bool) -> void:
    SaLayerOps.new(doc).set_blend_mode(layer, &"multiply")


func _hue(doc: SaDocument, layer: SaLayer, _fine: bool) -> void:
    SaLayerOps.new(doc).set_blend_mode(layer, &"hue")


func test_in_multiply_and_in_hue() -> void:
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _multiply, "In multiply the mean is what multiplies")
    _pair(Vector2i(256, 256), [Vector2i.ZERO], _hue, "In hue the mean is whose hue is taken")


func test_across_a_chunk_seam() -> void:
    var positions := [Vector2i(0, 0), Vector2i(1, 0)]
    _pair(Vector2i(512, 256), positions, _nothing, "Two chunks at 2.0 side by side")
    var fine := _easel(Vector2i(512, 256))
    _layer(fine.document, true, positions)
    _composite(fine)
    var bytes := _bytes(fine.output)
    for y: int in [0, 100, 255]:
        var left := SaFieldSpec.decode_texel(bytes, fine.output.format, y * 512 + 255)
        var right := SaFieldSpec.decode_texel(bytes, fine.output.format, y * 512 + 256)
        assert_true(left.is_equal_approx(MEAN) and right.is_equal_approx(MEAN), "No seam at row %d: %s and %s" % [y, left, right])
    fine.free()


func _texture(size: int, texel: Callable) -> SaTexture:
    var made := SaTexture.new(Vector2i(size, size))
    _upload(made, texel)
    return made


func test_a_chunk_at_1_drawn_at_half_repeats_each_texel_over_two_by_two() -> void:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var source := _texture(256, func(x: int, y: int) -> Color: return Color(x / 256.0, y / 256.0, 0.5, 1.0))
    var target := SaTexture.new(Vector2i(512, 512))
    target.clear(Color(0, 0, 0, 0))
    compositor.composite_chunk(
        target, source, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, null, 1.0, Rect2i(0, 0, 512, 512), 0.5
    )
    var read := _bytes(source)
    var drawn := _bytes(target)
    var wrong := 0
    for y in 512:
        for x in 512:
            var want := SaFieldSpec.decode_texel(read, source.format, (y >> 1) * 256 + (x >> 1))
            if SaFieldSpec.decode_texel(drawn, target.format, y * 512 + x) != want:
                wrong += 1
    assert_eq(wrong, 0, "Every texel of the chunk at 1.0 covers its two by two block at 0.5")


func test_a_chunk_at_2_drawn_at_1_is_copied_texel_for_texel() -> void:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var source := _texture(512, func(x: int, y: int) -> Color: return Color(x / 512.0, y / 512.0, 0.25, 1.0))
    var target := SaTexture.new(Vector2i(512, 512))
    target.clear(Color(0, 0, 0, 0))
    compositor.composite_chunk(target, source, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, null, 1.0, Rect2i(), 1.0)
    assert_eq(_bytes(target), _bytes(source), "A density of 1 copies a 512 chunk into a 512 texture")


func test_a_zero_density_is_read_as_one_and_the_block_keeps_its_size() -> void:
    var packed := SaCompute.pack_composite_params(Vector2.ZERO, 1.0)
    assert_eq(packed.size() * 4, 128, "The block is 128 bytes")
    assert_eq(packed[SaCompute.COMPOSITE_DENSITY_INDEX], 0.0, "A caller that names no density packs 0.0, which reads as 1")
    packed = SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 2.0)
    assert_eq(packed[SaCompute.COMPOSITE_DENSITY_INDEX], 2.0, "and a density rides in the float that padded the block")
    assert_eq(SaDocumentTexels.density_of(SaTexture.new(Vector2i(512, 512))), 2.0, "A 512 chunk reads as 2")
    assert_eq(SaDocumentTexels.density_of(SaTexture.new(Vector2i(256, 256))), 1.0, "and a 256 one as 1")


func test_the_png_export_matches_the_layer_at_1() -> void:
    var fine := _easel(Vector2i(512, 256))
    var plain := _easel(Vector2i(512, 256))
    for easel: SaEasel in [fine, plain]:
        _layer(easel.document, easel == fine, [Vector2i(0, 0), Vector2i(1, 0)])
        _composite(easel)
    var space := fine.document.color_space
    var a := SaExport.png_bytes(fine.output, space, 16)
    var b := SaExport.png_bytes(plain.output, space, 16)
    assert_false(a.is_empty(), "The PNG is written")
    assert_eq(_picture_of(a), _picture_of(b), "and its header and pixel bytes are the layer at 1.0's")
    fine.free()
    plain.free()


## The IHDR and IDAT chunks of a PNG, which hold its size, depth and pixels.
## The text chunks carry the time the file was written, so two exports a
## second apart differ there whatever their pictures are.
func _picture_of(png: PackedByteArray) -> PackedByteArray:
    var kept := PackedByteArray()
    var at := 8
    while at + 8 <= png.size():
        var length := (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3]
        var kind := png.slice(at + 4, at + 8).get_string_from_ascii()
        if kind == "IHDR" or kind == "IDAT":
            kept.append_array(png.slice(at + 8, at + 8 + length))
        at += 12 + length
    return kept


func test_the_thumbnail_matches_the_layer_at_1() -> void:
    var pictures: Array[PackedByteArray] = []
    for fine: bool in [true, false]:
        var easel := _easel(Vector2i(512, 256))
        var layer := SaLayerOps.new(easel.document).add()
        if fine:
            layer.chunks[Vector2i.ZERO] = SaChunk.create(layer.schema, 2.0)
            layer.get_field(Vector2i.ZERO).clear(MEAN)
        else:
            layer.get_or_create_chunk(Vector2i.ZERO).clear(MEAN)
        easel.document.invalidate_chunks([Vector2i.ZERO])
        var thumb := SaLayerThumbnail.new()
        thumb.bind_layer(layer, easel.document)
        thumb.refresh()
        pictures.append(_bytes(thumb._texture) if thumb._texture != null else PackedByteArray())
        thumb.free()
        easel.free()
    assert_false(pictures[0].is_empty(), "The thumbnail of a layer at 2.0 is drawn")
    assert_eq(pictures[0], pictures[1], "over the chunk's own 256 document pixels, as the layer at 1.0's is, not over twice them")
