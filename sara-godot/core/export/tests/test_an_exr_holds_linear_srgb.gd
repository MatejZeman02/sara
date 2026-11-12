## An EXR export holds linear sRGB.
##
## The `files` sweep's F1. The default document stores Oklab, and its EXR held
## L, a and b as red, green and blue, so the grey ground left as a dark red and
## Sara reopened the file flat red. A plain sRGB document's file held the
## curve's encoded numbers where every reader takes an EXR to be linear. Each
## document now leaves as linear sRGB, Rec. 709's primaries and no curve,
## whatever its gamut, and a P3 red stays outside sRGB's cube rather than being
## clipped onto its edge.
##
## The suite writes an Oklab document, an sRGB one and a P3 one, reads every
## file back through `SaImageImport` the way File > Open does, and holds the
## numbers to the colour's own linear sRGB, worked out by hand rather than by
## the converter under test. The relief branch is held to the same numbers
## where the surface is flat.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two cells wide, so one can hold a slope and the other none, and so the walk
## has more than one cell to visit.
const SIZE := Vector2i(512, 256)

## The sweep's orange, #E0A020, as the picker gives it.
const ORANGE := Color(224.0 / 255.0, 160.0 / 255.0, 32.0 / 255.0, 1.0)
## The same orange in linear sRGB, each channel through the sRGB curve's
## decode: 0.7454, 0.3515 and 0.0144.
const ORANGE_LINEAR := Vector3(0.74540, 0.35153, 0.01444)

## The picked red of a P3 document, which is P3's own red.
const RED := Color(1.0, 0.0, 0.0, 1.0)
## P3's red in linear sRGB, through the matrix built from the two sets of
## primaries and D65: past one in red and below nought in green and blue.
const P3_RED_LINEAR := Vector3(1.22494, -0.04206, -0.01964)

## What the spec holds the numbers to.
const EPSILON := 1e-3

## A ramp of height across the first cell, a tenth of a millimetre over four
## pixels, which is what the relief suite lights.
const RAMP_MM: float = 0.025

## A texel of the first cell, on the slope, and one of the second, flat.
const ON_THE_SLOPE := Vector2i(128, 128)
const FLAT := Vector2i(400, 128)

static var scratch_exr: String = SaDataRoot.path("s8-linear.exr")
static var scratch_exr_lit: String = SaDataRoot.path("s8-linear-lit.exr")

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    _registries = Fixtures.make_registries()


func after_each() -> void:
    for path: String in [scratch_exr, scratch_exr_lit]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _registries = null


## A document stored in *space*, its layer filled with the picked *color* and
## composited.
func _easel(space: SaColorSpace, color: Color) -> SaEasel:
    var easel := SaEasel.create_default(SIZE, null, space)
    _easels.append(easel)
    easel.compositor.set_registry(_registries.blend_modes)
    var doc := easel.document
    doc.active_layer.fill(doc.color_space.from_display(color))
    easel.process_pending_composite()
    return easel


## An empty document in *space*, for a file to be opened into.
func _blank(space: SaColorSpace) -> SaDocument:
    var easel := SaEasel.create_default(SIZE, null, space)
    _easels.append(easel)
    return easel.document


## The layer's texel at *at*, as it is stored.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(at.x % SaChunk.SIZE, at.y % SaChunk.SIZE)


func _assert_rgb(got: Color, want: Vector3, what: String) -> void:
    assert_almost_eq(got.r, want.x, EPSILON, "%s: red %.4f" % [what, got.r])
    assert_almost_eq(got.g, want.y, EPSILON, "%s: green %.4f" % [what, got.g])
    assert_almost_eq(got.b, want.z, EPSILON, "%s: blue %.4f" % [what, got.b])


## *space*'s document filled with *color* written as EXR, read back through
## `SaImageImport` and held to *linear*, then opened into a document of
## *space* and held to what the first one stored.
func _round_trip(space: SaColorSpace, color: Color, linear: Vector3, label: String) -> void:
    var easel := _easel(space, color)
    assert_eq(SaExport.export_exr(easel, scratch_exr), OK, "%s: the EXR writes" % label)
    assert_eq(SaExportGamut.cells_visited, SaExportGamut.cells_of(SIZE).size(), "%s: a cell at a time" % label)
    var file := SaImageImport.read(scratch_exr)
    assert_not_null(file, "%s: the reader opens it" % label)
    if file == null:
        return
    assert_eq(file.get_format(), Image.FORMAT_RGBAF, "%s: as 32-bit floats" % label)
    _assert_rgb(file.get_pixelv(FLAT), linear, "%s: the file holds linear sRGB" % label)
    assert_almost_eq(file.get_pixelv(FLAT).a, 1.0, EPSILON, "%s: and the alpha as it was" % label)
    assert_eq(SaImageImport.space_for(scratch_exr).id, SaColorSpace.linear_srgb().id, "%s: which the reader calls it" % label)

    var opened := SaImageImport.open_into(_blank(SaColorSpace.linear_srgb()), scratch_exr)
    assert_not_null(opened, "%s: File > Open's linear document takes it" % label)
    if opened != null:
        _assert_rgb(_texel(opened, FLAT), linear, "%s: and holds the same numbers" % label)

    var stored := space.from_display(color)
    var back := SaImageImport.open_into(_blank(space), scratch_exr)
    assert_not_null(back, "%s: a document of the first's space takes it" % label)
    if back != null:
        _assert_rgb(_texel(back, FLAT), Vector3(stored.r, stored.g, stored.b), "%s: and stores what the first stored" % label)


## The default document, Oklab over sRGB: the file held its L, a and b.
func test_an_oklab_document_leaves_as_linear_srgb() -> void:
    _round_trip(SaColorSpace.oklab(), ORANGE, ORANGE_LINEAR, "Oklab")


## The default document's own grey ground, Oklab's L of 0.598, which a reader
## should find near 0.21 in all three channels, L cubed.
func test_the_oklab_grey_leaves_as_a_grey() -> void:
    var grey := SaColorSpace.oklab().to_display(Color(0.598, 0.0, 0.0, 1.0))
    var cubed := 0.598 * 0.598 * 0.598
    _round_trip(SaColorSpace.oklab(), grey, Vector3(cubed, cubed, cubed), "Oklab grey")


## A plain sRGB document: the file held the curve's encoded numbers.
func test_an_srgb_document_leaves_decoded() -> void:
    _round_trip(SaColorSpace.srgb(), ORANGE, ORANGE_LINEAR, "sRGB")


## A P3 document's red is outside sRGB, and the file keeps it outside rather
## than clipping it onto the cube's edge.
func test_a_p3_red_lands_outside_srgb_s_cube() -> void:
    _round_trip(SaColorSpace.display_p3(), RED, P3_RED_LINEAR, "P3")


## A linear sRGB document is the file's own space, so nothing is converted and
## no cell is walked: the file is the stored numbers bit for bit.
func test_a_linear_srgb_document_is_written_as_it_stands() -> void:
    var easel := _easel(SaColorSpace.linear_srgb(), ORANGE)
    assert_eq(SaExport.export_exr(easel, scratch_exr), OK, "the EXR writes")
    assert_eq(SaExportGamut.cells_visited, 0, "with no cell walked")
    @warning_ignore("static_called_on_instance")
    var stored := SaExport.get_texture_image_float(easel.output).get_pixelv(FLAT)
    assert_eq(SaImageImport.read(scratch_exr).get_pixelv(FLAT), stored, "and the file is the stored texel exactly")


## The relief branch converts as well. Lit, the flat cell holds the same
## linear numbers as the flat export, and the slope is lit in linear sRGB too.
func test_the_relief_branch_holds_the_same_numbers() -> void:
    for space: SaColorSpace in [SaColorSpace.oklab(), SaColorSpace.srgb(), SaColorSpace.display_p3()]:
        var color := RED if space.id == SaColorSpace.display_p3().id else ORANGE
        var linear := P3_RED_LINEAR if space.id == SaColorSpace.display_p3().id else ORANGE_LINEAR
        var label := String(space.id)
        var easel := _easel(space, color)
        _raise_ramp(easel)
        assert_eq(SaExport.export_exr(easel, scratch_exr_lit, false, true), OK, "%s: the lit EXR writes" % label)
        assert_eq(SaExport.export_exr(easel, scratch_exr, false, false), OK, "%s: and the flat one" % label)
        var lit := SaImageImport.read(scratch_exr_lit)
        var flat := SaImageImport.read(scratch_exr)
        _assert_rgb(lit.get_pixelv(FLAT), linear, "%s: the lit file's flat cell is linear sRGB" % label)
        assert_eq(lit.get_pixelv(FLAT), flat.get_pixelv(FLAT), "%s: the same texel the flat file holds" % label)
        assert_true(lit.get_pixelv(ON_THE_SLOPE) != flat.get_pixelv(ON_THE_SLOPE), "%s: and the slope is lit" % label)


## A null space is the old write, the stored numbers unconverted, which is the
## bit-exact path `core/composite/tests/test_no_clamp.gd` holds.
func test_a_texture_with_no_space_is_written_unconverted() -> void:
    var easel := _easel(SaColorSpace.oklab(), ORANGE)
    assert_eq(SaExport.export_exr_texture(easel.output, scratch_exr), OK, "the EXR writes")
    @warning_ignore("static_called_on_instance")
    var stored := SaExport.get_texture_image_float(easel.output).get_pixelv(FLAT)
    assert_eq(SaImageImport.read(scratch_exr).get_pixelv(FLAT), stored, "as the Oklab numbers it stores")


## Height across the first cell of *easel*'s active layer, rising to the
## right, dirtied the way a dab dirties it, and composited.
func _raise_ramp(easel: SaEasel) -> void:
    var doc := easel.document
    var grid_pos := Vector2i.ZERO
    SaHeightOps.new(doc).gain(doc.active_layer)
    var texture := doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(x) * RAMP_MM)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    doc.invalidate_chunks([grid_pos])
    easel.process_pending_composite()
