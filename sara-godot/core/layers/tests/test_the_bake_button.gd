## The painter bakes a double
## resolution layer down to the document's resolution in one step that one undo
## takes back, and merge down, flatten and the ORA export treat such a layer the
## way the canvas shows it at 100% and below.
##
## The layer at 2.0 holds a one-texel checker in one chunk and a checker of a
## colour and nothing in the other, so a plain mean and the alpha weighted mean
## the canvas draws give different answers in the second. The colours are
## sums of powers of two, so every mean is exact in half floats and equal means
## equal bytes.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_x7_bake.ora")
const CANVAS := Vector2i(512, 256)

const ONE := Color(0.25, 0.5, 0.75, 1.0)
const TWO := Color(0.75, 0.25, 0.125, 1.0)
const MEAN := Color(0.5, 0.375, 0.4375, 1.0)
## ONE beside nothing: the colour stays ONE's and the alpha halves. A plain
## mean would read ONE at half its brightness.
const HALF := Color(0.25, 0.5, 0.75, 0.5)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)


func _easel() -> SaEasel:
    var made := SaEasel.create_default(CANVAS)
    made.compositor.set_registry(Fixtures.make_registries().blend_modes)
    made.document.fill_layer(UNDER, made.document.get_node("Layer 1") as SaLayer)
    return made


func _composite(easel: SaEasel) -> PackedByteArray:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return _bytes(easel.output)


func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func _upload(texture: SaTexture, texel: Callable) -> void:
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF if wide else Image.FORMAT_RGBAH)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


func _holed(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else Color(0, 0, 0, 0)


## A layer at 2.0 above the active one, the checker at (0, 0) and the holed
## checker at (1, 0), made the way the Layer menu makes it.
func _fine(doc: SaDocument) -> SaLayer:
    var layer := SaLayerOps.new(doc).add(&"", null, 2.0)
    _upload(layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _checker)
    _upload(layer.get_or_create_chunk(Vector2i(1, 0)).albedo(), _holed)
    doc.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    return layer


## Every texel of *texture* is *color*, or the first that is not is named.
func _every(texture: SaTexture, color: Color, what: String) -> void:
    var bytes := _bytes(texture)
    for i in texture.size.x * texture.size.y:
        var found := SaFieldSpec.decode_texel(bytes, texture.format, i)
        if not found.is_equal_approx(color):
            var at := Vector2i(i % texture.size.x, floori(i / float(texture.size.x)))
            assert_true(false, "%s: texel %s is %s, not %s" % [what, at, found, color])
            return
    assert_true(true, what)


func test_the_bake_writes_the_mean_the_canvas_shows_as_one_step() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := _fine(doc)
    var shown := _composite(easel)
    var kept := {}
    for grid_pos: Vector2i in layer.chunks:
        kept[grid_pos] = _bytes(layer.chunks[grid_pos].albedo())

    assert_true(SaLayerBake.new(doc).bake(layer), "The layer bakes")
    assert_eq(layer.resolution_scale, 1.0, "and is at the document's resolution")
    assert_eq(layer.chunks.size(), 2, "with the chunks it had")
    for grid_pos: Vector2i in layer.chunks:
        assert_eq(layer.chunks[grid_pos].pixel_size(), 256, "Chunk %s is 256 across" % grid_pos)
        assert_eq(layer.chunks[grid_pos].albedo().size, Vector2i(256, 256), "and so is its texture")
    _every(layer.chunks[Vector2i(0, 0)].albedo(), MEAN, "Every texel of the checker is the mean of its block")
    _every(layer.chunks[Vector2i(1, 0)].albedo(), HALF, "and of the holed one the alpha weighted mean")
    assert_true(_composite(easel) == shown, "The canvas is the canvas before the bake, texel for texel")

    assert_true(doc.undo(), "Undo takes it back")
    assert_eq(layer.resolution_scale, 2.0, "The layer is at 2.0 again")
    for grid_pos: Vector2i in kept:
        assert_eq(layer.chunks[grid_pos].pixel_size(), 512, "Chunk %s is 512 across again" % grid_pos)
        assert_true(_bytes(layer.chunks[grid_pos].albedo()) == kept[grid_pos], "with its texels as they were")
    assert_true(_composite(easel) == shown, "and the canvas is unchanged")

    assert_true(doc.redo(), "Redo bakes it again")
    assert_eq(layer.resolution_scale, 1.0, "at 1.0")
    _every(layer.chunks[Vector2i(0, 0)].albedo(), MEAN, "with the mean in it")
    easel.free()


func test_a_mask_bakes_with_the_layer() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := _fine(doc)
    assert_true(SaMaskOps.new(doc).run(&"layer_mask_add", layer), "A mask goes on the layer")
    var mask := layer.chunks[Vector2i(0, 0)].field(SaFieldSpec.MASK)
    if mask != null:
        assert_eq(mask.size, Vector2i(512, 512), "at the layer's resolution")
    var shown := _composite(easel)
    assert_true(SaLayerBake.new(doc).bake(layer), "The masked layer bakes")
    for grid_pos: Vector2i in layer.chunks:
        for field_id: StringName in layer.chunks[grid_pos].fields:
            var size: Vector2i = layer.chunks[grid_pos].fields[field_id].size
            assert_eq(size, Vector2i(256, 256), "Field %s of chunk %s is 256 across" % [field_id, grid_pos])
    assert_true(_composite(easel) == shown, "and the canvas is unchanged")
    easel.free()


func test_only_a_double_resolution_layer_bakes() -> void:
    var easel := _easel()
    var doc := easel.document
    var plain := doc.get_node("Layer 1") as SaLayer
    assert_false(SaLayerBake.can_bake(plain), "A plain layer has nothing to bake")
    assert_false(SaLayerBake.new(doc).bake(plain), "and the bake refuses it")
    assert_true(SaLayerBake.can_bake(_fine(doc)), "A double resolution layer can bake")
    easel.free()


func test_the_command_is_dimmed_unless_the_active_layer_is_at_2() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    assert_true(registries.commands.has(&"layer_bake"), "The command is registered")
    var command := registries.commands.get_descriptor(&"layer_bake")
    assert_eq(command.label, "Resample to Document Resolution", "with the menu's words")
    assert_false(command.enabled.call(), "and is dimmed on a plain layer")
    assert_true(registries.commands.execute(&"layer_new_double"), "A double resolution layer is made")
    assert_true(command.enabled.call(), "and the command lights")
    assert_true(registries.commands.execute(&"layer_bake"), "It runs")
    assert_eq(doc.active_layer.resolution_scale, 1.0, "and bakes the active layer")
    assert_false(command.enabled.call(), "which dims it again")
    Fixtures.teardown(surface)


func test_merge_down_onto_a_plain_layer_keeps_the_canvas() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := _fine(doc)
    var shown := _composite(easel)
    var ops := SaLayerOps.new(doc)
    assert_true(ops.can_merge_down(layer), "A double resolution layer merges onto a plain one")
    assert_true(ops.merge_down(layer), "and does")
    assert_true(_composite(easel) == shown, "The canvas is unchanged")
    easel.free()


func test_merge_down_and_flatten_onto_a_double_resolution_layer_are_refused() -> void:
    var easel := _easel()
    var doc := easel.document
    var fine := _fine(doc)
    var ops := SaLayerOps.new(doc)
    var above := ops.add()
    above.get_or_create_chunk(Vector2i.ZERO).clear(TWO)
    SaProblems.announce = false
    SaProblems.pending_refusals = PackedStringArray()
    assert_false(ops.can_merge_down(above), "Merge down onto a double resolution layer is dimmed")
    assert_false(ops.merge_down(above), "and refused")
    assert_eq(SaProblems.pending_refusals.size(), 1, "with one line")
    if SaProblems.pending_refusals.size() > 0:
        assert_true("Resample it" in SaProblems.pending_refusals[0], "that says to resample it first")
    assert_true(ops.flatten(), "A flatten onto a plain bottom layer runs")

    var second := _easel()
    var bottom := _fine(second.document)
    var second_ops := SaLayerOps.new(second.document)
    var moves := 0
    while second_ops.can_move(bottom, -1) and moves < second_ops.layers().size():
        second_ops.move(bottom, -1)
        moves += 1
    assert_eq(second_ops.layers()[0], bottom, "The double resolution layer is at the bottom")
    SaProblems.pending_refusals = PackedStringArray()
    assert_false(second_ops.flatten(), "and a flatten into it is refused")
    assert_eq(SaProblems.pending_refusals.size(), 1, "with one line")
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true
    assert_eq(fine.resolution_scale, 2.0, "No refusal changed a layer")
    easel.free()
    second.free()


func test_the_ora_writes_a_double_resolution_layer_at_the_documents_size() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := _fine(doc)
    layer.name = "Fine"
    _composite(easel)
    # OpenRaster is the image formats module's, so its registries are held here.
    var formats := Fixtures.make_picture_registries()
    assert_eq(SaImageImport.formats(), formats.image_formats, "the formats asked are the ones these registries installed")
    assert_eq(Fixtures.export_through(&"ora", easel, scratch, 16), OK, "The export succeeds")
    var reader := ZIPReader.new()
    assert_eq(reader.open(scratch), OK, "and opens as a zip")
    var xml := reader.read_file("stack.xml").get_string_from_utf8()
    var found := RegEx.create_from_string('name="Fine"[^>]*src="([^"]+)"').search(xml)
    if found == null:
        found = RegEx.create_from_string('src="([^"]+)"[^>]*name="Fine"').search(xml)
    assert_true(found != null, "The stack names the layer's PNG")
    if found != null:
        var image := Image.new()
        assert_eq(image.load_png_from_buffer(reader.read_file(found.get_string(1))), OK, "which decodes")
        assert_eq(image.get_size(), CANVAS, "at the document's size")
        var at := image.get_pixel(97, 31)
        # Godot decodes a 16-bit PNG to eight bits, so within half a step of that.
        var off := maxf(maxf(absf(at.r - MEAN.r), absf(at.g - MEAN.g)), maxf(absf(at.b - MEAN.b), absf(at.a - MEAN.a)))
        assert_true(off <= 0.5 / 255.0 + 0.0001, "each pixel the mean of its block, %s" % at)
    reader.close()
    assert_eq(layer.resolution_scale, 2.0, "and the layer is left at 2.0")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
    easel.free()
