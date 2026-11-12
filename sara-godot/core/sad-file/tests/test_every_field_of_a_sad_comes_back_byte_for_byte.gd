## A `.sad` from version 14 stores each field as byte planes
## of deltas before Zstd, and gives back every byte of every field, colour at
## full and at half precision, a height field and a mask. A file stamped 13,
## whose blobs are the texture's bytes as they lie, opens as before.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Saved by the build before the byte planes, at version 13, by [method write_fixture]
## run there: one layer of one chunk holding colour at full precision, a height
## field and a mask, each filled with [method pattern].
const FIXTURE_V13 := "res://tests/data/every_field_v13.sad"

const FIELDS: Array[StringName] = [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT, SaFieldSpec.MASK]

static var scratch: String = SaDataRoot.path("test_planes.sad")


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## The bytes a texture of *format*, *side* texels square, is filled with: a
## ramp at steps of a sixty-fourth that goes below zero and above white, a
## value under a half float's smallest normal every seventeenth texel, under a
## float's every 211th, and a busy mantissa every 97th, so the planes meet a
## denormal and noise as well as the smooth paint they are for. A step of a
## sixty-fourth keeps the fixture small.
static func pattern(format: int, side: int) -> PackedByteArray:
    var channels: int = (
        {
            RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: 4,
            RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: 4,
        }
        . get(format, 1)
    )
    var half := format in [RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.DATA_FORMAT_R16_SFLOAT]
    var width := 2 if half else 4
    var rng := RandomNumberGenerator.new()
    rng.seed = 102
    var bytes := PackedByteArray()
    bytes.resize(side * side * channels * width)
    var at := 0
    for y in side:
        for x in side:
            var index := y * side + x
            for channel in channels:
                var value := floorf((sin(x * 0.05 + channel) + cos(y * 0.03 - channel)) * 96.0) / 64.0
                if index % 17 == 3:
                    value = 0.000001 * (channel + 1)
                elif index % 211 == 7:
                    value = 1e-40
                elif index % 97 == 5:
                    value = rng.randf_range(-4.0, 4.0)
                if half:
                    bytes.encode_half(at, value)
                else:
                    bytes.encode_float(at, value)
                at += width
    return bytes


## A document of one chunk whose layer holds colour at *depth*, a height field
## and a mask, each filled with [method pattern], or null with no device.
static func painted(depth: SaColorSpace.Depth) -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(depth))
    var layer := _first_layer(doc)
    var fields: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(doc.color_space.texel_format()), SaFieldSpec.height(), SaFieldSpec.mask()
    ]
    layer.schema = fields
    layer.chunks.clear()
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    for field_id in FIELDS:
        var texture := layer.get_or_create_field(Vector2i.ZERO, field_id)
        rd.texture_update(texture.rid, 0, pattern(texture.format, chunk.pixel_size()))
    return doc


## Writes [constant FIXTURE_V13]. Run by hand in the build before the byte planes, never
## by the gate: this build would stamp it 14. A second layer carries Spread,
## unstepped, because a simulation is what the build before stamped 13, and
## without one the same file is a 6.
static func write_fixture() -> Error:
    var doc := painted(SaColorSpace.Depth.F32)
    var registries := Fixtures.make_registries()
    var base := BaseModule.new()
    base.register(registries.context.for_module(base.get_id()))
    SaSimulation.put_on(SaLayerOps.new(doc).add(), registries.simulation_rules.find(&"spread"))
    var error := SaExport.save_sad(doc, ProjectSettings.globalize_path(FIXTURE_V13), 0)
    doc.free()
    return error


static func _first_layer(doc: SaDocument) -> SaLayer:
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            return child as SaLayer
    return null


static func _bytes_of(layer: SaLayer) -> Dictionary[StringName, PackedByteArray]:
    var found: Dictionary[StringName, PackedByteArray] = {}
    for field_id in FIELDS:
        var texture := layer.get_field(Vector2i.ZERO, field_id)
        if texture != null:
            found[field_id] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return found


func test_colour_at_full_and_half_a_height_and_a_mask_come_back_byte_for_byte() -> void:
    for depth: SaColorSpace.Depth in [SaColorSpace.Depth.F32, SaColorSpace.Depth.F16]:
        var named := "F32" if depth == SaColorSpace.Depth.F32 else "F16"
        var source := painted(depth)
        var saved := _bytes_of(_first_layer(source))
        assert_eq(saved.size(), 3, "%s: the layer holds colour, height and a mask" % named)
        assert_eq(SaExport.save_sad(source, scratch, 0), OK, "%s: the save lands" % named)
        assert_eq(SaSadFile.version_at(scratch), SaSadFile.SAD_VERSION_PLANES, "%s: stamped 14, for its planes" % named)

        var reopened := SaDocument.new()
        assert_eq(SaExport.load_sad(reopened, scratch, SaCompositor.new()), OK, "%s: and opens" % named)
        var back := _bytes_of(_first_layer(reopened))
        for field_id in FIELDS:
            var texture := _first_layer(reopened).get_field(Vector2i.ZERO, field_id)
            var format := texture.format if texture != null else -1
            assert_true(SaSadBlob.LAYOUT.has(format), "%s: the %s field opens in a format the planes take" % [named, field_id])
            assert_eq(
                back.get(field_id, PackedByteArray()),
                saved[field_id],
                "%s: every byte of the %s field comes back" % [named, field_id]
            )
        source.free()
        reopened.free()


func test_every_format_the_kernels_take_goes_through_the_planes_and_back() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    for format: int in SaSadBlob.LAYOUT:
        var texture := SaTexture.new(Vector2i(256, 256), format)
        rd.texture_update(texture.rid, 0, pattern(format, 256))
        var before := rd.texture_get_data(texture.rid, 0)
        var blobs := PackedByteArray()
        var slot := SaSadBlob.write(texture, blobs, rd)
        assert_true(SaSadBlob.is_planes(slot), "Format %d is stored as planes" % format)
        assert_true(int(slot.get("size", 0)) < before.size(), "and smaller than its bytes")
        var copy := SaTexture.new(Vector2i(256, 256), format)
        assert_true(SaSadBlob.upload(copy, SaSadBlob.read(slot, blobs), true), "The planes fit the texture")
        assert_eq(rd.texture_get_data(copy.rid, 0), before, "and give back every byte of format %d" % format)


func test_a_mask_of_its_own_comes_back_byte_for_byte() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var mask := SaMask.own()
    var texture := mask.get_or_create(Vector2i(1, 2))
    rd.texture_update(texture.rid, 0, pattern(texture.format, texture.size.x))
    var before := rd.texture_get_data(texture.rid, 0)
    var blobs := PackedByteArray()
    var entry := SaSadFile.write_mask(mask, blobs, rd)
    var chunks: Array = entry.get("chunks", [])
    assert_eq(chunks.size(), 1, "The mask writes its one chunk")
    assert_false(
        SaSadBlob.is_planes(SaTyped.strings(chunks[0])), "stored plain since the mask format that weighs no planes for a mask"
    )
    var back := SaSadFile.read_mask(entry, blobs)
    var opened := back.texture_for(Vector2i(1, 2))
    assert_not_null(opened, "The chunk opens where it was")
    if opened != null:
        assert_eq(rd.texture_get_data(opened.rid, 0), before, "with every byte it held")


func test_a_version_13_file_opens_as_before() -> void:
    assert_eq(SaSadFile.version_at(FIXTURE_V13), 13, "The fixture is a version 13 file")
    var doc := SaDocument.new()
    assert_eq(SaExport.load_sad(doc, FIXTURE_V13, SaCompositor.new()), OK, "and opens")
    var layer := _first_layer(doc)
    var back := _bytes_of(layer)
    for field_id in FIELDS:
        var texture := layer.get_field(Vector2i.ZERO, field_id)
        var format := texture.format if texture != null else -1
        assert_eq(
            back.get(field_id, PackedByteArray()), pattern(format, 256), "with every byte of its %s field as written" % field_id
        )
    doc.free()
