## An export of the live document equals an export of the same
## document saved and opened again. The save rounds full precision colour to 12
## significant bits in the file, so before an export reads the picture
## `SaSadSnapshot.round_live` rounds the live colour the same way. A document
## of random colour and a stroke, rounded live, holds bit for bit what the same
## document saved as the painter saves and opened again holds, the chunks it moved are
## marked to be composited again, and a second rounding, or one of a document
## opened from the file, moves nothing. Half precision colour and a mask are
## left as they lie, as a save leaves them.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the rounding and the hash run on the card.
const REQUIRES_GPU := true

## The chunk a stroke is painted over, and the chunk written with random colour.
const STROKED := Vector2i(0, 0)
const WRITTEN := Vector2i(1, 0)
const POSITIONS: Array[Vector2i] = [STROKED, WRITTEN]

static var saved: String = SaDataRoot.path("test_saved.sad")


func after_each() -> void:
    SaSadFile.finish_saves()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))


## A document of one layer in *space* at *depth*, with a colour and a mask over
## [constant POSITIONS], a stroke at part strength across [constant STROKED] and
## random colour and mask in [constant WRITTEN], written as the bench writes.
static func painted(space: SaColorSpace, depth: SaColorSpace.Depth) -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), space.with_depth(depth))
    var layer := doc.active_layer
    var fields: Array[SaFieldSpec] = [SaFieldSpec.albedo(doc.color_space.texel_format()), SaFieldSpec.mask()]
    layer.schema = fields
    layer.chunks.clear()
    for grid_pos in POSITIONS:
        layer.get_or_create_chunk(grid_pos)
    doc.begin_stroke(0.7071, &"normal")
    doc.stroke_layer.get_or_create_field(STROKED, SaFieldSpec.ALBEDO).clear(Color(0.4123457, 0.3141593, 0.7777777, 0.61803))
    doc.commit_stroke()
    var rng := RandomNumberGenerator.new()
    rng.seed = 231
    for field_id: StringName in [SaFieldSpec.ALBEDO, SaFieldSpec.MASK]:
        var texture := layer.get_or_create_field(WRITTEN, field_id)
        var layout: Vector2i = SaSadBlob.LAYOUT[texture.format]
        var bytes := PackedByteArray()
        bytes.resize(texture.size.x * texture.size.y * layout.x * layout.y)
        for at in range(0, bytes.size(), layout.y):
            if layout.y == 2:
                bytes.encode_half(at, rng.randf_range(0.0, 1.0))
            else:
                bytes.encode_float(at, rng.randf_range(0.0, 1.0))
        rd.texture_update(texture.rid, 0, bytes)
    return doc


## The colour and the mask of *doc*'s active layer at each of
## [constant POSITIONS], as the card holds them.
static func fields_of(doc: SaDocument) -> Dictionary[String, PackedByteArray]:
    var rd := GlobalShaderCompiler.get_rd()
    var found: Dictionary[String, PackedByteArray] = {}
    for field_id: StringName in [SaFieldSpec.ALBEDO, SaFieldSpec.MASK]:
        for grid_pos in POSITIONS:
            var texture := doc.active_layer.get_field(grid_pos, field_id)
            found["%s %s" % [field_id, grid_pos]] = rd.texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()
    return found


## *doc* saved as the painter's File > Save saves it and opened again, or null.
static func saved_and_opened(doc: SaDocument) -> SaDocument:
    SaSadFile.save_in_background(doc, saved, 0, null, true, Callable(), true)
    if not SaSadFile.finish_saves():
        return null
    var opened := SaDocument.new()
    if SaExport.load_sad(opened, saved, SaCompositor.new()) != OK:
        opened.free()
        return null
    return opened


func test_the_live_colour_rounds_to_what_the_saved_file_opens_to() -> void:
    var doc := painted(SaColorSpace.srgb(), SaColorSpace.Depth.F32)
    var painted_fields := fields_of(doc)
    var opened := saved_and_opened(doc)
    assert_not_null(opened, "The document saves as the painter saves and opens again")
    if opened == null:
        doc.free()
        return
    var from_file := fields_of(opened)
    var differs: bool = painted_fields["albedo (1, 0)"] != from_file["albedo (1, 0)"]
    assert_true(differs, "Before, the live colour is not what the file holds")
    doc.consume_dirty_chunks()
    assert_eq(SaSadSnapshot.round_live(doc), POSITIONS.size(), "Both colour chunks are rounded")
    var rounded := fields_of(doc)
    for key: String in rounded:
        assert_eq(rounded[key], from_file[key], "%s: the live document holds what the file opens to" % key)
    var dirty := doc.consume_dirty_chunks()
    for grid_pos in POSITIONS:
        assert_true(dirty.has(grid_pos), "%s is marked to be composited again" % grid_pos)
    assert_eq(SaSadSnapshot.round_live(doc), 0, "A second rounding moves nothing")
    assert_true(doc.consume_dirty_chunks().is_empty(), "and marks nothing")
    assert_eq(SaSadSnapshot.round_live(opened), 0, "A document opened from the file rounds nothing")
    opened.free()
    doc.free()


func test_half_precision_colour_and_the_mask_are_left_as_they_lie() -> void:
    var doc := painted(SaColorSpace.srgb(), SaColorSpace.Depth.F16)
    var before := fields_of(doc)
    assert_eq(SaSadSnapshot.round_live(doc), 0, "Half precision colour is never rounded")
    assert_eq(fields_of(doc), before, "and every field is as painted")
    doc.free()
