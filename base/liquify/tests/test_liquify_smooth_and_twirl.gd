## Liquify takes a pushed field back, in the mode named Reconstruct that takes
## each offset towards none, and twirls the paint under the brush, both ways.
##
## The twirl cases paint a cross centred on the brush and read where its
## right arm went. Its arms lie inside the brush's flat core, where a turn at
## full strength is exactly the angle asked for.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

const CANVAS := Vector2i(1024, 512)
const RED := Color(0.9, 0.1, 0.1, 1.0)
## The cross's centre, its arms' half length and their half width.
const CENTRE := Vector2(128.0, 128.0)
const ARM: float = 80.0
const HALF_WIDTH: float = 3.0
## The radius along the right arm where the turn is read.
const READ_AT: float = 60.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document with an active layer whose chunk (0, 0) is painted where
## *painted* says, a callable of a document pixel.
func _open(painted: Callable) -> SaLayer:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := chunk.pixel_size()
    var texture := chunk.albedo()
    var image := Image.create_empty(edge, edge, false, _image_format(texture))
    for y in edge:
        for x in edge:
            image.set_pixel(x, y, RED if painted.call(Vector2(x, y) + Vector2(0.5, 0.5)) else Color(0.0, 0.0, 0.0, 0.0))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    return layer


func _cross() -> SaLayer:
    return _open(
        func(at: Vector2) -> bool:
            var off := (at - CENTRE).abs()
            return (off.x < ARM and off.y < HALF_WIDTH) or (off.y < ARM and off.x < HALF_WIDTH)
    )


## A vertical stripe four pixels wide at x 100.
func _stripe() -> SaLayer:
    return _open(func(at: Vector2) -> bool: return at.x > 100.0 and at.x < 104.0)


static func _read(texture: SaTexture) -> Image:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


## The angle, in degrees clockwise on screen, where the paint on a circle of
## `READ_AT` around the centre is thickest within 45 degrees of the right arm,
## read every tenth of a degree. The window stops short of where a turn of
## thirty puts the arms beside it, at sixty.
static func _arm_angle(layer: SaLayer) -> float:
    var texels := _read(layer.chunks[Vector2i.ZERO].albedo())
    var weight := 0.0
    var moment := 0.0
    for tenth in range(-450, 451):
        var degrees := tenth / 10.0
        var at := CENTRE + Vector2.from_angle(deg_to_rad(degrees)) * READ_AT
        var alpha := texels.get_pixelv(Vector2i(at.floor())).a
        weight += alpha
        moment += alpha * degrees
    return moment / weight if weight > 0.0 else 999.0


## How long the x offsets of row *y* of a field chunk are, summed over *from*
## to *to*.
static func _offsets(field: SaTexture, y: int, from: int, to: int) -> float:
    var texels := _read(field)
    var total := 0.0
    for x in range(from, to):
        total += absf(texels.get_pixel(x, y).r)
    return total


## Where the paint on row *y* of the chunk sits, alpha weighted.
static func _centre_of_row(layer: SaLayer, y: int) -> float:
    var texels := _read(layer.chunks[Vector2i.ZERO].albedo())
    var weight := 0.0
    var moment := 0.0
    for x in texels.get_width():
        var alpha := texels.get_pixel(x, y).a
        weight += alpha
        moment += alpha * (x + 0.5)
    return moment / weight if weight > 0.0 else -1.0


func test_a_twirl_turns_the_cross_clockwise() -> void:
    var layer := _cross()
    assert_almost_eq(_arm_angle(layer), 0.0, 0.5, "The right arm starts level")
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.twirl(CENTRE, 400.0, 1.0, deg_to_rad(30.0))
    assert_almost_eq(_arm_angle(layer), 30.0, 1.0, "A turn of thirty degrees turns the arm thirty, clockwise on screen")


func test_a_twirl_with_a_negative_angle_turns_it_back() -> void:
    var layer := _cross()
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.twirl(CENTRE, 400.0, 1.0, deg_to_rad(-30.0))
    assert_almost_eq(_arm_angle(layer), -30.0, 1.0, "A negative turn goes anticlockwise")
    session.twirl(CENTRE, 400.0, 0.5, deg_to_rad(60.0))
    assert_almost_eq(_arm_angle(layer), 0.0, 1.0, "And half the strength of twice the turn brings it level again")


func test_alt_turns_the_tools_twirl_anticlockwise() -> void:
    var layer := _cross()
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.mode = StateScript.TWIRL
    tool.settings.size = 400.0
    tool.settings.strength = 1.0
    tool.press(CENTRE)
    # A sixth of a second held at half a turn a second is thirty degrees.
    tool.hold(1.0 / 6.0)
    tool.release()
    assert_almost_eq(_arm_angle(layer), 30.0, 1.0, "A held twirl turns clockwise")
    var alt := InputEventKey.new()
    alt.keycode = KEY_ALT
    alt.alt_pressed = true
    alt.pressed = true
    tool.handle_input(alt)
    tool.press(CENTRE)
    tool.hold(1.0 / 3.0)
    tool.release()
    assert_almost_eq(_arm_angle(layer), -30.0, 1.0, "And with Alt anticlockwise, twice as long taking it past level")
    assert_true(tool.commit_session(), "Both turns are one session")


func test_a_reconstruct_takes_the_field_back_and_leaves_the_brushs_edge() -> void:
    var layer := _stripe()
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.push(Vector2(102.0, 128.0), Vector2(112.0, 128.0), 120.0, 1.0)
    var field: SaTexture = session.fields[Vector2i.ZERO]
    var edge_before := _centre_of_row(layer, 128)
    assert_almost_eq(edge_before, 112.0, 0.05, "The push moved the stripe ten")
    # Centred right of the stripe, so the stripe sits where the reconstruct's
    # falloff has reached nought.
    var centre := Vector2(174.0, 128.0)
    var before := _offsets(field, 128, 130, 190)
    session.reconstruct(centre, 120.0, 1.0)
    var after := _offsets(field, 128, 130, 190)
    assert_true(before > 0.0, "The pushed field has offsets to take back")
    assert_true(after < before * 0.8, "A reconstruct takes the field towards no offset: %f from %f" % [after, before])
    assert_almost_eq(_centre_of_row(layer, 128), edge_before, 0.1, "The stripe at the brush's edge stays where the push left it")


func test_a_reconstruct_where_nothing_was_pushed_makes_no_field() -> void:
    var layer := _stripe()
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.reconstruct(Vector2(600.0, 300.0), 120.0, 1.0)
    assert_true(session.fields.is_empty(), "No field chunk where no push reached")
    session.push(Vector2(102.0, 128.0), Vector2(112.0, 128.0), 120.0, 1.0)
    # Across the seam into chunk (1, 0), where the push never reached.
    session.reconstruct(Vector2(250.0, 128.0), 120.0, 1.0)
    assert_eq(session.fields.size(), 1, "A reconstruct over the seam makes no field where there is nothing to take back")
