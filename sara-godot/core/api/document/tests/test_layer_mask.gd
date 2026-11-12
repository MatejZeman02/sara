## A mask is a field of the layer's schema.
##
## What the rest of the mask and filter rows stand on: where the field comes
## from, what a fresh texture of it holds, what leaves it alone, and what a
## `.sad` says about it. Every texel is read back, because a mask that was
## cleared to zero with its chunk returns a plausible picture, an empty one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Three texels of the first chunk and what a painted mask holds there.
const PAINTED: Dictionary = {
    Vector2i(3, 5): 0.0,
    Vector2i(128, 128): 0.25,
    Vector2i(255, 255): 0.5,
}

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## Writes PAINTED into *texture*, which is one everywhere else.
func _paint(texture: SaTexture) -> void:
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y)
    values.fill(1.0)
    for at: Vector2i in PAINTED:
        values[at.y * texture.size.x + at.x] = PAINTED[at]
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _assert_painted(texture: SaTexture, what: String) -> void:
    assert_not_null(texture, "%s holds the mask's texture" % what)
    if texture == null:
        return
    for at: Vector2i in PAINTED:
        assert_almost_eq(_texel(texture, at).r, float(PAINTED[at]), 0.0001, "%s keeps the texel at %s" % [what, at])


func _version_of(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    var version := file.get_32()
    file.close()
    return version


func _first_layer(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        if child is SaLayer:
            return child
    return null


func test_the_mask_spec_is_the_selections_format_and_never_colour() -> void:
    var spec := SaFieldSpec.mask()
    assert_eq(spec.id, SaSelection.FIELD, "A mask and a selection spell the field the same way")
    assert_eq(spec.format, SaSelection.FORMAT, "and store it at the same format")
    assert_false(spec.is_color, "A mask is coverage, never colour")
    assert_eq(spec.blank, Color(1, 1, 1, 1), "A fresh mask texture shows everything")
    assert_eq(SaFieldSpec.albedo().blank, Color(0, 0, 0, 0), "while fresh paint is no paint")


func test_a_layer_with_no_mask_answers_null() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    assert_null(layer.mask, "A layer nobody masked has no mask")
    assert_null(layer.get_field(Vector2i(0, 0), SaFieldSpec.MASK), "and no texture for the field")


func test_a_layer_that_gained_a_mask_has_it_at_every_chunk_it_held() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    layer.get_or_create_chunk(Vector2i(1, 1))
    var mask := layer.add_mask()
    assert_not_null(mask, "add_mask answers the mask")
    assert_eq(layer.mask, mask, "which is the layer's")
    assert_true(mask.enabled, "A new mask is on")
    assert_not_null(SaFieldSpec.find(layer.schema, SaFieldSpec.MASK), "The schema carries the field")
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 1)]:
        var texture := mask.texture_for(grid_pos)
        assert_not_null(texture, "The chunk at %s gained a mask texture" % grid_pos)
        if texture != null:
            assert_eq(texture.format, SaSelection.FORMAT, "at the selection's format")
            assert_almost_eq(_texel(texture, Vector2i(128, 128)).r, 1.0, 0.0001, "holding one")
    assert_null(mask.texture_for(Vector2i(5, 5)), "Where the layer holds nothing the mask is absent, which reads as one")
    assert_eq(mask.grid_positions().size(), 2, "and it lists the two chunks it has")
    assert_eq(layer.add_mask(), mask, "Asking twice answers the same mask")


func test_a_mask_added_hidden_holds_zero() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    var mask := layer.add_mask(0.0)
    var held := _texel(mask.texture_for(Vector2i(0, 0)), Vector2i(128, 128))
    assert_almost_eq(held.r, 0.0, 0.0001, "A hide-all mask holds zero")


func test_a_chunk_allocated_after_the_mask_reads_one() -> void:
    var layer := _doc.active_layer
    layer.add_mask()
    var chunk := layer.get_or_create_chunk(Vector2i(1, 0))
    var texture := chunk.field(SaFieldSpec.MASK)
    assert_not_null(texture, "A chunk allocated under the brush carries the mask")
    if texture == null:
        return
    assert_almost_eq(_texel(texture, Vector2i(128, 128)).r, 1.0, 0.0001, "and it opens fully shown, not fully hidden")
    assert_almost_eq(_texel(chunk.albedo(), Vector2i(128, 128)).a, 0.0, 0.0001, "while its paint opens empty")


func test_a_fill_of_colour_leaves_the_mask_untouched() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    var mask := layer.add_mask()
    _paint(mask.texture_for(Vector2i(0, 0)))
    layer.fill(RED)
    _assert_painted(mask.texture_for(Vector2i(0, 0)), "A filled layer")
    assert_almost_eq(
        _texel(layer.get_field(Vector2i(0, 0)), Vector2i(128, 128)).r, 1.0, 0.0001, "and the fill landed in the paint"
    )
    # The kernel path, which an alpha lock takes.
    layer.alpha_locked = true
    layer.fill(Color(0.0, 1.0, 0.0, 1.0))
    layer.alpha_locked = false
    _assert_painted(mask.texture_for(Vector2i(0, 0)), "A layer filled under alpha lock")


func test_an_undo_copy_of_a_mask_holds_the_mask_alone() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    var mask := layer.add_mask()
    _paint(mask.texture_for(Vector2i(0, 0)))
    var before := mask.duplicate_chunk(Vector2i(0, 0))
    assert_not_null(before, "A held chunk copies")
    assert_false(before.has_field(SaFieldSpec.ALBEDO), "The copy pays for no paint")
    assert_null(mask.duplicate_chunk(Vector2i(4, 4)), "An absent chunk copies as null")
    mask.texture_for(Vector2i(0, 0)).clear(Color(0, 0, 0, 0))
    mask.set_chunk(Vector2i(0, 0), before)
    _assert_painted(mask.texture_for(Vector2i(0, 0)), "A mask put back")
    mask.set_chunk(Vector2i(0, 0), null)
    var reset := _texel(mask.texture_for(Vector2i(0, 0)), Vector2i(3, 5))
    assert_almost_eq(reset.r, 1.0, 0.0001, "Null puts back a mask that reads as one")
    assert_not_null(layer.get_field(Vector2i(0, 0)), "and leaves the layer's paint where it was")


func test_dropping_the_mask_takes_the_field_and_its_textures() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    layer.add_mask()
    layer.drop_mask()
    assert_null(layer.mask, "The mask is gone")
    assert_null(SaFieldSpec.find(layer.schema, SaFieldSpec.MASK), "with its spec")
    assert_null(layer.get_field(Vector2i(0, 0), SaFieldSpec.MASK), "and its texture")
    assert_not_null(layer.get_field(Vector2i(0, 0)), "The paint stays")


func test_a_mask_of_its_own_allocates_where_it_is_written() -> void:
    var mask := SaMask.own()
    assert_null(mask.texture_for(Vector2i(0, 0)), "An own mask starts with nothing, which reads as one")
    var texture := mask.get_or_create(Vector2i(2, 3))
    assert_almost_eq(_texel(texture, Vector2i(128, 128)).r, 1.0, 0.0001, "A chunk it allocates opens at one")
    assert_eq(mask.grid_positions(), [Vector2i(2, 3)] as Array[Vector2i], "and is the only one it holds")
    assert_almost_eq(_texel(mask.absent(), Vector2i(0, 0)).r, 1.0, 0.0001, "The stand-in reads one")
    mask.set_chunk(Vector2i(2, 3), null)
    assert_null(mask.texture_for(Vector2i(2, 3)), "Null takes an own chunk away")


func test_a_painted_mask_survives_a_save_and_the_file_says_five() -> void:
    var layer := _doc.active_layer
    var name_was := str(layer.name)
    layer.get_or_create_chunk(Vector2i(0, 0))
    var mask := layer.add_mask()
    _paint(mask.texture_for(Vector2i(0, 0)))
    mask.enabled = false

    var path := SaDataRoot.path("test_layer_mask.sad")
    assert_eq(SaSadFile.version_for(_doc), 5, "A masked document is version 5")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "A masked document saves")
    assert_eq(_version_of(path), SaSadFile.SAD_VERSION_PLANES, "and its header says 14, for its planes")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")
    var back: SaLayer = loaded.get_node_or_null(name_was)
    assert_not_null(back, "The masked layer is back")
    if back != null:
        assert_not_null(back.mask, "with its mask")
        if back.mask != null:
            assert_false(back.mask.enabled, "switched off as it was saved")
            _assert_painted(back.mask.texture_for(Vector2i(0, 0)), "A loaded mask")
            var spec := SaFieldSpec.find(back.schema, SaFieldSpec.MASK)
            assert_eq(spec.blank, Color(1, 1, 1, 1), "and a chunk allocated after the load would open at one")
    DirAccess.remove_absolute(path)
    loaded.free()


func test_a_document_with_no_mask_is_still_version_four() -> void:
    _doc.active_layer.fill(RED)
    var path := SaDataRoot.path("test_layer_mask_plain.sad")
    assert_eq(SaSadFile.version_for(_doc), 4, "A plain document is version 4")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "A plain document saves")
    assert_eq(_version_of(path), SaSadFile.SAD_VERSION_PLANES, "and its planes stamp it 14")
    DirAccess.remove_absolute(path)


func test_a_mask_of_its_own_goes_through_the_two_doors() -> void:
    var group := SaLayer.new()
    group.name = "Group"
    group.is_group = true
    group.mask = SaMask.own()
    _paint(group.mask.get_or_create(Vector2i(0, 0)))
    _doc.add_child(group)

    var path := SaDataRoot.path("test_layer_mask_own.sad")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "A document whose group carries a mask saves")
    assert_eq(_version_of(path), SaSadFile.SAD_VERSION_PLANES, "as 14, for its planes")
    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")
    var back: SaLayer = loaded.get_node_or_null("Group")
    assert_not_null(back, "The group is back")
    if back != null and back.mask != null:
        assert_true(back.mask.is_own(), "holding chunks of its own")
        _assert_painted(back.mask.texture_for(Vector2i(0, 0)), "A group's loaded mask")
    else:
        assert_true(false, "The group came back with its mask")
    DirAccess.remove_absolute(path)
    loaded.free()


func test_a_hand_written_v4_file_with_a_mask_spec_reads_as_one() -> void:
    var schema := [
        {"id": "albedo", "format": RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "is_color": true, "derived_from": []},
        {"id": "mask", "format": SaSelection.FORMAT, "is_color": false, "derived_from": []},
    ]
    var header := {
        "format": "sad",
        "version": 4,
        "width": 64,
        "height": 64,
        "layers": [{"name": "Layer 1", "visible": true, "opacity": 1.0, "blend_mode": "normal", "schema": schema, "chunks": []}],
    }
    var header_raw := JSON.stringify(header).to_utf8_buffer()
    var header_packed := header_raw.compress(FileAccess.COMPRESSION_ZSTD)
    var path := SaDataRoot.path("test_layer_mask_v4.sad")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer("SAD2".to_ascii_buffer())
    file.store_32(4)
    file.store_32(header_packed.size())
    file.store_32(header_raw.size())
    file.store_buffer(header_packed)
    file.close()

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "A v4 file with a mask spec opens")
    var layer := _first_layer(loaded)
    assert_not_null(layer.mask, "The spec gave the layer a mask")
    if layer.mask != null:
        assert_true(layer.mask.enabled, "An absent flag reads as on")
        assert_null(layer.mask.texture_for(Vector2i(0, 0)), "No chunk, so the mask reads as one")
        var fresh := layer.get_or_create_chunk(Vector2i(0, 0)).field(SaFieldSpec.MASK)
        assert_almost_eq(_texel(fresh, Vector2i(10, 10)).r, 1.0, 0.0001, "and a chunk allocated into it opens at one")
    DirAccess.remove_absolute(path)
    loaded.free()


func test_a_duplicated_schema_is_not_grown_under_its_source() -> void:
    var source := _doc.active_layer
    var twin := SaLayer.new()
    twin.schema = source.schema
    twin.add_mask()
    var grown := SaFieldSpec.find(source.schema, SaFieldSpec.MASK)
    assert_null(grown, "A mask on one layer adds no field to the layer sharing its schema")
    assert_null(source.mask, "and gives it no mask")
    twin.free()
