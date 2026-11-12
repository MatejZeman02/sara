## A pure primary stored at F16 is shown as itself. A
## scenario imported pure red beside pure blue into the default F16 Oklab
## document and the view drew the blue as (0, 48, 229). F16 rounds pure blue's
## Oklab to a number whose green decodes to -4.6e-5, the gamut test allowed
## 1e-5, and at blue's hue the map's first exit is 85 per cent of the vertex's
## chroma, the fold under `find_cusp`.
##
## The eight vertices of the sRGB cube are put down as an 8-bit picture into an
## F16 Oklab document the way an import puts one down, drawn through the
## canvas's own material under Oklab mapping, read back, and exported to PNG.
## Each has to come back as itself. Pure magenta was drawn (255, 1, 255) here
##, because the conversion's store truncated its `a` to a
## half one step below the nearest, and the kernel now stores the nearest. A
## colour a hundredth outside a face has to be mapped still, by the view and by
## the export's kernel, and the three copies of the gamut test have to carry
## one slack, which the drift suite's comparison of their bodies does not read.
extends "res://tests/test_framework.gd"

## The picture is composited, drawn and exported on a real device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

const VIEW_SHADER := "res://shaders/canvas/tonemap.gdshader"
const ROLLOFF_KERNEL := "res://shaders/compute/tonemap_rolloff.gmacs"
const MAPPING_KERNEL := "res://shaders/compute/map_into_gamut.gmacs"

## The cube's eight vertices as 8-bit colours, one a column of the picture.
const VERTICES: Array[Vector3i] = [
    Vector3i(0, 0, 0),
    Vector3i(255, 0, 0),
    Vector3i(0, 255, 0),
    Vector3i(0, 0, 255),
    Vector3i(255, 255, 0),
    Vector3i(0, 255, 255),
    Vector3i(255, 0, 255),
    Vector3i(255, 255, 255),
]

## Each colour a block this many pixels square, read at its middle.
const BLOCK := 4

## The float slack the gamut test had alone, which pure blue's green is past.
const FLOAT_SLACK := 1e-5

## The share of the largest channel F16's rounding may put a texel outside,
## the shader's GAMUT_ROUNDING.
const F16_SLACK := 2e-3

## Linear sRGB a hundredth outside the low face and the high face.
const A_HUNDREDTH_OUTSIDE: Array[Vector3] = [Vector3(0.0, -0.01, 1.0), Vector3(1.01, 0.5, 0.2)]

## Float rounding through the export kernel's decode, map and encode.
const CUBE_SLACK := 1e-4

## Half an 8-bit level, and the float the device's encode may add to it.
const HALF_A_LEVEL := 0.51

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _canvases: Array[SaCanvas] = []
var _scratch := SaDataRoot.path("d24-vertices.png")
var _saved_tonemap := false
var _saved_mapping := ""


func before_each() -> void:
    _saved_tonemap = SaSettings.tonemap_highlights
    _saved_mapping = SaSettings.gamut_mapping
    SaSettings.tonemap_highlights = false
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    _registries = Fixtures.make_registries()


func after_each() -> void:
    for canvas: SaCanvas in _canvases:
        canvas.free()
    _canvases.clear()
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _registries = null
    SaSettings.tonemap_highlights = _saved_tonemap
    SaSettings.gamut_mapping = _saved_mapping
    if FileAccess.file_exists(_scratch):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_scratch))


## An empty picture of *count* blocks side by side, in *format*.
static func _picture(count: int, format: Image.Format) -> Image:
    return Image.create_empty(count * BLOCK, BLOCK, false, format)


static func _fill_block(image: Image, index: int, color: Color) -> void:
    image.fill_rect(Rect2i(index * BLOCK, 0, BLOCK, BLOCK), color)


## An easel in *space* holding *image* put down from *source* the way an
## import puts a picture down, composited.
func _easel(space: SaColorSpace, image: Image, source: SaColorSpace) -> SaEasel:
    var easel := SaEasel.create_default(image.get_size(), null, space)
    easel.compositor.set_registry(_registries.blend_modes)
    _easels.append(easel)
    var layer := SaImageImport.place(easel.document, image, "d24", source, SaImageImport.Fit.ORIGIN)
    assert_not_null(layer, "The picture is put down as a layer")
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The vertices as an import puts them into the default F16 Oklab document on
## an sRGB display, `SaColorSpace.oklab_srgb_gamma30` at F16.
func _vertices_easel() -> SaEasel:
    var image := _picture(VERTICES.size(), Image.FORMAT_RGB8)
    for i in VERTICES.size():
        var v := VERTICES[i]
        _fill_block(image, i, Color8(v.x, v.y, v.z))
    var space := SaColorSpace.oklab_srgb_gamma30().with_depth(SaColorSpace.Depth.F16)
    return _easel(space, image, SaColorSpace.srgb())


func _canvas(easel: SaEasel) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = easel.document.canvas_size
    canvas.easel = easel
    canvas.sync_tonemap()
    _canvases.append(canvas)
    return canvas


## *easel*'s output drawn one texel a pixel through *canvas*'s own material
## into a viewport and read back, the frame a painter sees.
func _frame(easel: SaEasel, canvas: SaCanvas) -> Image:
    canvas.sync_tonemap()
    var size := easel.document.canvas_size
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(size)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


static func _bytes_at(image: Image, index: int) -> Vector3i:
    var c := image.get_pixel(index * BLOCK + (BLOCK >> 1), BLOCK >> 1)
    return Vector3i(c.r8, c.g8, c.b8)


## The stored texel under the block of vertex *index*, decoded to linear sRGB.
func _stored(easel: SaEasel, canvas: SaCanvas, index: int) -> Vector3:
    var read := TexelProbe._read_point(easel.document, canvas, Vector2i(index * BLOCK + 1, 1))
    assert_not_null(read["composited"], "The stored %s is read" % VERTICES[index])
    if read["composited"] == null:
        return Vector3.ZERO
    var stored := read["composited"] as Dictionary
    return SaOklab.to_linear_srgb(Vector3(stored["r"], stored["g"], stored["b"]))


## Where *linear* lands on an 8-bit screen, in levels and unrounded: the stored
## number shown as itself, the nearest any view can come to the vertex it
## rounds from.
static func _levels(linear: Vector3) -> Vector3:
    var out := Vector3.ZERO
    for i in 3:
        out[i] = 255.0 * _encode(clampf(linear[i], 0.0, 1.0))
    return out


## Whether every channel of *shown* is within half a level of *levels*.
static func _within_half_a_level(shown: Vector3i, levels: Vector3) -> bool:
    for i in 3:
        if absf(float(shown[i]) - levels[i]) > HALF_A_LEVEL:
            return false
    return true


func test_pure_blue_stored_at_f16_is_past_the_float_slack_and_inside_f16s() -> void:
    var easel := _vertices_easel()
    var canvas := _canvas(easel)
    var linear := _stored(easel, canvas, VERTICES.find(Vector3i(0, 0, 255)))
    var low := minf(linear.x, minf(linear.y, linear.z))
    var peak := maxf(absf(linear.x), maxf(absf(linear.y), absf(linear.z)))
    assert_true(low < -FLOAT_SLACK, "F16 puts pure blue %s past the float slack alone, the fault's premise" % linear)
    assert_true(low >= -F16_SLACK * peak, "and inside F16's own, %f of %f" % [low, peak])


## Each vertex is stored within half a level of itself and shown as itself,
## magenta among them, and Oklab mapping shows every one as the clip does, so
## the map moves none.
func test_the_eight_vertices_come_out_of_the_views_mapping_as_themselves() -> void:
    var easel := _vertices_easel()
    var canvas := _canvas(easel)
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    var clipped := _frame(easel, canvas)
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    var mapped := _frame(easel, canvas)
    for i in VERTICES.size():
        var vertex := VERTICES[i]
        var stored := _stored(easel, canvas, i)
        var own := _levels(stored)
        var shown := _bytes_at(mapped, i)
        var what := "%s stored as %s, %s levels, is shown as %s" % [vertex, stored, own, shown]
        assert_eq(shown, _bytes_at(clipped, i), "%s, as the clip shows it" % what)
        assert_true(_within_half_a_level(vertex, own), "%s, and F16 stored it within half a level" % what)
        assert_eq(shown, vertex, "%s, which is itself" % what)


## An export to PNG under Oklab writes pure blue as (0, 0, 255), and every
## vertex as itself and as the view shows it.
func test_an_export_to_png_under_oklab_writes_the_vertices_as_themselves() -> void:
    var easel := _vertices_easel()
    var canvas := _canvas(easel)
    assert_eq(SaExport.export_png(easel, _scratch, 8, false, SaGamutMapping.OKLAB), OK, "The picture exports as PNG")
    var written := Image.load_from_file(ProjectSettings.globalize_path(_scratch))
    assert_not_null(written, "and the file reads back")
    if written == null:
        return
    assert_eq(_bytes_at(written, VERTICES.find(Vector3i(0, 0, 255))), Vector3i(0, 0, 255), "Pure blue is written as itself")
    var frame := _frame(easel, canvas)
    for i in VERTICES.size():
        assert_eq(_bytes_at(written, i), VERTICES[i], "%s is written as itself" % VERTICES[i])
        assert_eq(_bytes_at(written, i), _bytes_at(frame, i), "%s is written as the view shows it" % VERTICES[i])


## Through the view: a linear sRGB document holds the two colours exactly, and
## Oklab mapping has to show them otherwise than the per-channel clip does.
func test_a_colour_a_hundredth_outside_a_face_is_still_mapped_by_the_view() -> void:
    var image := _picture(A_HUNDREDTH_OUTSIDE.size(), Image.FORMAT_RGBAF)
    for i in A_HUNDREDTH_OUTSIDE.size():
        var c := A_HUNDREDTH_OUTSIDE[i]
        _fill_block(image, i, Color(c.x, c.y, c.z, 1.0))
    var space := SaColorSpace.linear_srgb()
    var easel := _easel(space, image, space)
    var canvas := _canvas(easel)
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    var clipped := _frame(easel, canvas)
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    var mapped := _frame(easel, canvas)
    for i in A_HUNDREDTH_OUTSIDE.size():
        var shown := _bytes_at(mapped, i)
        var clip := _bytes_at(clipped, i)
        assert_true(shown != clip, "%s is mapped, %s against the clip's %s" % [A_HUNDREDTH_OUTSIDE[i], shown, clip])


## Through the export's kernel, in floats: a texel F16 left just outside is not
## written, and a texel a hundredth outside is written back inside the cube.
func test_a_colour_a_hundredth_outside_a_face_is_still_mapped_by_the_export() -> void:
    var cases: Array[Vector3] = [Vector3(-8.0e-6, -4.6e-5, 0.99962)]
    cases.append_array(A_HUNDREDTH_OUTSIDE)
    var texture := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    var texels := PackedFloat32Array()
    texels.resize(SaChunk.SIZE * SaChunk.SIZE * 4)
    texels.fill(0.5)
    for i in cases.size():
        for channel in 3:
            texels[i * 4 + channel] = _encode(cases[i][channel])
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    var image := SaExportGamut.encoded_image(texture, SaColorSpace.srgb(), PackedFloat32Array(), SaGamutMapping.OKLAB)
    assert_not_null(image, "The export pass ran")
    if image == null:
        return
    for i in cases.size():
        var texel := image.get_pixel(i, 0)
        var read := Vector3(texel.r, texel.g, texel.b)
        var stored := Vector3(texels[i * 4], texels[i * 4 + 1], texels[i * 4 + 2])
        if i == 0:
            assert_eq(read, stored, "Pure blue as F16 leaves it is not written")
            continue
        assert_true(read != stored, "%s is written" % cases[i])
        var linear := Vector3(_decode(read.x), _decode(read.y), _decode(read.z))
        var low := minf(linear.x, minf(linear.y, linear.z))
        var high := maxf(linear.x, maxf(linear.y, linear.z))
        assert_true(low >= -CUBE_SLACK and high <= 1.0 + CUBE_SLACK, "%s is written inside the cube, %s" % [cases[i], linear])


func test_the_three_copies_carry_one_slack() -> void:
    var view := _constants(FileAccess.get_file_as_string(VIEW_SHADER))
    assert_eq(view.size(), 2, "The view declares both slacks, %s" % view)
    assert_almost_eq(float(view.get("GAMUT_ROUNDING", 0.0)), F16_SLACK, 0.0, "and F16's is the one this suite holds")
    for path: String in [ROLLOFF_KERNEL, MAPPING_KERNEL]:
        assert_eq(_constants(FileAccess.get_file_as_string(path)), view, "%s carries the view's slacks" % path.get_file())


## The sRGB curve's encode and decode with the sign carried, which is what the
## export kernel reads a stored number through and writes one back with.
static func _encode(linear: float) -> float:
    var magnitude := absf(linear)
    var encoded := 12.92 * magnitude if magnitude <= 0.0031308 else 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
    return signf(linear) * encoded


static func _decode(encoded: float) -> float:
    var magnitude := absf(encoded)
    var linear := magnitude / 12.92 if magnitude < 0.04045 else pow((magnitude + 0.055) / 1.055, 2.4)
    return signf(encoded) * linear


## The two slacks *source* declares, by name, as written.
static func _constants(source: String) -> Dictionary:
    var out := {}
    var pattern := RegEx.create_from_string("const float (GAMUT_EPSILON|GAMUT_ROUNDING) = ([0-9.e-]+)")
    for found: RegExMatch in pattern.search_all(source):
        out[found.get_string(1)] = found.get_string(2)
    return out
