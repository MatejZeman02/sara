## File > Open reads a Radiance `.hdr`.
##
## A panorama of a sky most often travels as a Radiance file, and Sara's list
## had no `.hdr` in it, so the one format the HDRI page's documents arrive in
## had no way into one. Godot's own loader read the file as `FORMAT_RGBE9995`,
## and the import made halves of it on the way in. `SaRadianceReader` replaces the
## loader and `SaRadianceReader`, which hands this fixture back as halves
## because every value in it is one a half keeps, and which reads the layouts
## the loader refused, so the case that read their refusal went with it.
##
## The fixture beside this suite, `sky.hdr`, is 256 by 128 texels of
## run-length-encoded `32-bit_rle_rgbe`, the layout Radiance writes: a sky from
## a deep blue at the top row to a pale one at row 95, a dark ground below it,
## and a sun of radius five centred on (192, 40) whose texels hold 4,000 in all
## three channels, the RGBE bytes 250, 250, 250 and 140, which the format holds
## exactly.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The texels are read back off the chunks a real document uploaded.
const REQUIRES_GPU := true

const FIXTURE := "res://modules/sara-base-modules/image-formats/radiance/tests/sky.hdr"
const FIXTURE_SIZE := Vector2i(256, 128)
const SUN := Vector2i(192, 40)
const SUN_VALUE := 4000.0
## F16's precision at the sun: eleven significant bits, so a value between 2,048
## and 4,096 is held to within a step of two.
const HALF_STEP_AT_SUN := 2.0

var _problems: Array[String] = []

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _problems.clear()
    # A refusal is a push_error while it announces, and a deliberate one fails
    # the run, so the lines come to the suite instead.
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true


## The list File > Open filters on, the bytes, and the import dialog's filter all
## know the format, by both of its magic lines and by nothing that only starts
## like one.
func test_the_import_knows_the_name_and_the_bytes() -> void:
    assert_true(SaImageImport.is_image_path("sky.hdr") and SaImageImport.is_image_path("SKY.HDR"), "An .hdr is a picture")
    assert_true(SaImageImport.dialog_filter().contains("*.hdr"), "File > Open and the import dialog list it")
    assert_eq(SaImageImport.sniff_format(FIXTURE), "hdr", "The fixture's #?RADIANCE line is sniffed as Radiance")
    assert_eq(SaImageImport.format_of_header("#?RGBE\nFORMAT=".to_ascii_buffer()), "hdr", "and so is the older #?RGBE line")
    assert_eq(SaImageImport.format_of_header("#?RADIANCEX\n".to_ascii_buffer()), "", "but a longer first word is not")
    assert_eq(SaImageImport.claimed_format("a/b/sky.hdr"), "hdr", "The name claims what the bytes say")


## The ask itself: the sun at 4,000 comes back at 4,000, the picture arrives as
## halves, and the document File > Open builds of it is linear sRGB at F16.
##
## The document is built the way `SaDocumentFiles.open_picture_into` builds one
## for a caller that has no answer from the depth question, the file's own width
## and its space, with the reset and the place it runs. The flow itself is under
## `ui`, which no `core` suite names, and the scenario of the same name walks it
## in the running app.
func test_the_sun_opens_at_four_thousand_in_a_linear_half_document() -> void:
    var image := SaImageImport.read(FIXTURE)
    assert_not_null(image, "The fixture is read")
    if image == null:
        return
    assert_eq(image.get_size(), FIXTURE_SIZE, "at its own size")
    assert_eq(image.get_format(), Image.FORMAT_RGBAH, "as halves, since a half keeps every value the fixture holds")
    assert_eq(SaImageImport.depth_for(image), SaColorSpace.Depth.F16, "so the file names F16 for itself")
    var sun := image.get_pixel(SUN.x, SUN.y)
    assert_true(
        absf(sun.r - SUN_VALUE) <= HALF_STEP_AT_SUN and absf(sun.b - SUN_VALUE) <= HALF_STEP_AT_SUN,
        "The sun is read at 4,000 with nothing clamped, read %s" % [sun]
    )

    var space := SaImageImport.space_for(FIXTURE).with_depth(SaImageImport.depth_for(image) as SaColorSpace.Depth)
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var document := easel.document
    document.reset_to_default(image.get_size(), space, document.dpi)
    var layer := SaImageImport.place(document, image, "sky", space)
    assert_not_null(layer, "The picture lands on a layer")
    assert_eq(document.color_space.id, SaColorSpace.ID_LINEAR_SRGB, "of a linear sRGB document")
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F16, "stored at F16, the depth the page asks for a panorama")
    if layer != null:
        var texel := _texel(layer, SUN)
        assert_true(
            absf(texel.r - SUN_VALUE) <= HALF_STEP_AT_SUN and absf(texel.g - SUN_VALUE) <= HALF_STEP_AT_SUN,
            "and its chunk holds the sun at 4,000, read %s" % [texel]
        )
        var sky := _texel(layer, Vector2i(10, 95))
        assert_true(
            absf(sky.r - 0.5977) < 0.002 and absf(sky.b - 0.9492) < 0.002 and is_equal_approx(sky.a, 1.0),
            "while the sky by the horizon is the pale blue the file holds, read %s" % [sky]
        )
    easel.free()
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## The texel under document point *at*, found in its chunk's own texels.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(at.x / float(SaLayer.CHUNK_SIZE)), floori(at.y / float(SaLayer.CHUNK_SIZE)))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var scale := chunk.pixel_size() / float(SaLayer.CHUNK_SIZE)
    var local := Vector2i(Vector2(at - grid * SaLayer.CHUNK_SIZE) * scale)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixel(local.x, local.y)
