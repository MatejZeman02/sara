## A soft edge exported over transparency carries straight alpha.
##
## Godot reads a PNG's alpha as straight, so a soft edge written premultiplied
## composites in a game as `255a*a + ground*(1 - a)`, which dips below the ground
## around the stroke and reads as a dark fringe. The dip is widest at half cover:
## white over a 191 ground would be 159 there, 32 steps under the ground it is
## laid on. [method SaExport.export_png] at eight bits must leave the colour
## channels alone whatever the alpha beside them is, and it must cut the file at
## the page's edge however far the paint runs past it.
##
## `scripts/check_godot_sprite.py` holds the other half, that Godot itself draws
## the file this suite describes with no fringe over a light or a dark ground.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## A page that is a multiple of [constant SaChunk.SIZE] on neither axis, so the
## export's last cell on each axis is a part cell and any confusion between the
## page and the chunks it is stored in widens the file.
const PAGE := Vector2i(300, 140)
## The grid position of the chunk the ramp is written into, and of the one
## painted whole beyond the page's right and bottom edges.
const HOME := Vector2i(0, 0)
const PAST_THE_EDGE := Vector2i(1, 0)
## Alphas on a byte's own steps, so a half's rounding cannot move the byte, with
## nought and whole at the ends. The byte each one is written as is `255a`.
const RAMP: Array[float] = [0.0, 32.0 / 255.0, 64.0 / 255.0, 128.0 / 255.0, 192.0 / 255.0, 224.0 / 255.0, 1.0]
## The row the ramp is read on, well inside the page on both axes.
const READ_ROW := 70

var _canvas: SaCanvas = null
var _path := SaDataRoot.path("test_soft_edge.png")


func after_each() -> void:
    if _canvas != null:
        _canvas.free()
        _canvas = null
    if FileAccess.file_exists(_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


## A transparent page carrying the ramp and a whole chunk of white laid past its
## right and bottom edges, exported as an eight-bit PNG and read back.
func _exported() -> Image:
    _canvas = SaCanvas.new()
    _canvas.canvas_size = PAGE
    _canvas.easel = SaEasel.create_default(PAGE)
    _canvas.add_child(_canvas.easel)
    var document := _canvas.document
    document.reset_to_default(PAGE, null, document.dpi, {SaDocumentBackground.KIND: SaDocumentBackground.TRANSPARENT})
    var layer := document.active_layer
    assert_not_null(layer, "the transparent document opens on a paint layer")
    for i in RAMP.size():
        _lay(layer, HOME, Rect2i(i, 0, 1, PAGE.y), Color(1.0, 1.0, 1.0, RAMP[i]))
    _lay(layer, PAST_THE_EDGE, Rect2i(PAST_THE_EDGE * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE)), Color.WHITE)
    document.update_caches()
    _canvas.easel.request_full_composite()
    _canvas.easel.process_pending_composite()
    assert_eq(SaExport.export_png(_canvas.easel, _path), OK, "the PNG is written")
    var image := Image.load_from_file(_path)
    assert_not_null(image, "and reads back")
    return image


## Writes *colour* over *area*, in document pixels, into the chunk of *layer* at
## *grid_pos*, asking the chunk how many texels it holds rather than taking 256.
static func _lay(layer: SaLayer, grid_pos: Vector2i, area: Rect2i, colour: Color) -> void:
    var chunk := layer.get_or_create_chunk(grid_pos)
    var across := chunk.pixel_size()
    var scale := float(across) / float(SaChunk.SIZE)
    var corner := Vector2(area.position - grid_pos * SaChunk.SIZE) * scale
    var local := Rect2i(Vector2i(corner.floor()), Vector2i((Vector2(area.size) * scale).ceil()))
    local = local.intersection(Rect2i(0, 0, across, across))
    layer.mark_unresolved(grid_pos)
    if local.size == Vector2i(across, across):
        chunk.clear(colour)
        return
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var width := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(colour)
    var paint := rd.texture_get_data(one.rid, 0)
    for y in range(local.position.y, local.end.y):
        for x in range(local.position.x, local.end.x):
            var at := (y * texture.size.x + x) * width
            for i in width:
                bytes[at + i] = paint[i]
    rd.texture_update(texture.rid, 0, bytes)


func test_the_file_is_the_pages_size_however_far_the_paint_runs_past_it() -> void:
    var image := _exported()
    assert_eq(image.get_size(), PAGE, "the PNG is the page, not the chunks it was stored in")


func test_an_edge_texels_colour_channels_are_unchanged_by_its_alpha() -> void:
    var image := _exported()
    for i in RAMP.size():
        var texel := image.get_pixel(i, READ_ROW)
        var alpha := roundi(texel.a * 255.0)
        assert_eq(alpha, roundi(RAMP[i] * 255.0), "column %d carries its alpha %d" % [i, roundi(RAMP[i] * 255.0)])
        if alpha == 0:
            continue
        for channel: float in [texel.r, texel.g, texel.b]:
            assert_eq(roundi(channel * 255.0), 255, "and its white is 255 at alpha %d, not multiplied down by it" % alpha)
