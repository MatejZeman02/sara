## Liquify's Twirl takes a
## Clockwise or Anticlockwise choice from a Direction row, live under Twirl and
## dimmed under the other modes, and Alt still turns the twirl the other way
## from whichever the row says.
##
## Every case paints a level stroke through the brush's centre, holds a twirl
## over it through the tool the way a held button does, and reads where the
## stroke's right half went. It lies inside the brush's flat core, where a
## turn at full strength is exactly the angle the held time asks for.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const LiquifyScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

const CANVAS := Vector2i(1024, 512)
const RED := Color(0.9, 0.1, 0.1, 1.0)
## The stroke's centre, its half length and its half width.
const CENTRE := Vector2(128.0, 128.0)
const HALF_LENGTH: float = 80.0
const HALF_WIDTH: float = 3.0
## The radius along the stroke's right half where the turn is read.
const READ_AT: float = 60.0
## A sixth of a second held at half a turn a second is thirty degrees.
const HELD: float = 1.0 / 6.0
const TURN: float = 30.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document whose active layer holds the level stroke in chunk (0, 0),
## and the liquify tool in hand on Twirl at full strength, wide enough that the
## stroke lies in its flat core.
func _open() -> Variant:
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
            var off := (Vector2(x, y) + Vector2(0.5, 0.5) - CENTRE).abs()
            image.set_pixel(x, y, RED if off.x < HALF_LENGTH and off.y < HALF_WIDTH else Color(0.0, 0.0, 0.0, 0.0))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.mode = StateScript.TWIRL
    tool.settings.size = 400.0
    tool.settings.strength = 1.0
    return tool


## Alt pressed or let go, through the tool's own input, as the key reaches it.
static func _alt(tool: Variant, down: bool) -> void:
    var key := InputEventKey.new()
    key.keycode = KEY_ALT
    key.alt_pressed = down
    key.pressed = down
    tool.handle_input(key)


## A held twirl at the centre for `HELD` seconds, through the tool.
static func _twirl(tool: Variant) -> void:
    tool.press(CENTRE)
    tool.hold(HELD)
    tool.release()


## The angle, in degrees clockwise on screen, where the paint on a circle of
## `READ_AT` around the centre is thickest within 45 degrees of the stroke's
## right half, read every tenth of a degree.
func _angle() -> float:
    var texture := _surface.get_document().active_layer.chunks[Vector2i.ZERO].albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texels := Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)
    var weight := 0.0
    var moment := 0.0
    for tenth in range(-450, 451):
        var degrees := tenth / 10.0
        var at := CENTRE + Vector2.from_angle(deg_to_rad(degrees)) * READ_AT
        var alpha := texels.get_pixelv(Vector2i(at.floor())).a
        weight += alpha
        moment += alpha * degrees
    return moment / weight if weight > 0.0 else 999.0


static func _spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in LiquifyScript.options():
        if spec.key == key:
            return spec
    return null


func test_the_direction_row_offers_both_ways_and_starts_clockwise() -> void:
    var direction := _spec(&"liquify_direction")
    assert_not_null(direction, "Liquify declares a Direction row")
    if direction == null:
        return
    assert_eq(direction.label, "Direction", "Named Direction")
    assert_eq(direction.kind, SaOptionSpec.Kind.ENUM, "A choice of two")
    var labels := direction.choices.map(func(choice: Dictionary) -> String: return choice["label"])
    assert_eq(labels, ["Clockwise", "Anticlockwise"], "Clockwise, then Anticlockwise")
    assert_false(direction.on_tool, "Held on the engine's settings, as the other three rows are, so a preset keeps it")
    assert_eq(String(direction.property), "direction", "Written to the settings' own direction")
    var tool: Variant = _open()
    assert_eq(tool.settings.direction, StateScript.CLOCKWISE, "Clockwise by default")


func test_the_direction_row_is_live_under_twirl_alone() -> void:
    var direction := _spec(&"liquify_direction")
    assert_not_null(direction, "Liquify declares a Direction row")
    if direction == null:
        return
    assert_eq(direction.enabled_when, &"liquify_mode", "Gated on the Mode row")
    assert_true(_spec(&"liquify_mode") != null, "Which Liquify declares")
    var modes := {
        StateScript.PUSH: "Push",
        StateScript.RECONSTRUCT: "Reconstruct",
        StateScript.SMOOTH: "Smooth",
        StateScript.TWIRL: "Twirl",
        StateScript.SHRINK: "Shrink",
        StateScript.GROW: "Grow",
    }
    for mode: int in modes:
        var live := SaOptionSpec.row_is_enabled(direction, mode)
        assert_eq(live, mode == StateScript.TWIRL, "Direction under %s is %s" % [modes[mode], "live" if live else "dimmed"])


func test_clockwise_and_anticlockwise_turn_the_stroke_opposite_ways() -> void:
    var tool: Variant = _open()
    assert_almost_eq(_angle(), 0.0, 0.5, "The stroke starts level")
    tool.settings.direction = StateScript.CLOCKWISE
    _twirl(tool)
    assert_almost_eq(_angle(), TURN, 1.0, "Clockwise turns the stroke thirty degrees clockwise on screen")
    tool.cancel_session()
    assert_almost_eq(_angle(), 0.0, 0.5, "Escape puts it level again")
    tool.settings.direction = StateScript.ANTICLOCKWISE
    _twirl(tool)
    assert_almost_eq(_angle(), -TURN, 1.0, "Anticlockwise turns it thirty the other way")
    assert_true(tool.commit_session(), "And the turn is a session that commits")


func test_alt_turns_each_direction_the_other_way() -> void:
    var tool: Variant = _open()
    tool.settings.direction = StateScript.CLOCKWISE
    _alt(tool, true)
    _twirl(tool)
    assert_almost_eq(_angle(), -TURN, 1.0, "Clockwise with Alt held turns the stroke anticlockwise")
    tool.cancel_session()
    tool.settings.direction = StateScript.ANTICLOCKWISE
    _twirl(tool)
    assert_almost_eq(_angle(), TURN, 1.0, "Anticlockwise with Alt held turns it clockwise")
    tool.cancel_session()
    _alt(tool, false)
    _twirl(tool)
    assert_almost_eq(_angle(), -TURN, 1.0, "And Alt let go, Anticlockwise turns it anticlockwise again")
    assert_true(tool.commit_session(), "The turn is a session that commits")


func test_the_capture_report_names_the_direction() -> void:
    var tool: Variant = _open()
    assert_eq(tool.capture_report(&"liquify", true)["liquify"]["direction"], "clockwise", "The dump reads clockwise")
    tool.settings.direction = StateScript.ANTICLOCKWISE
    assert_eq(tool.capture_report(&"liquify", true)["liquify"]["direction"], "anticlockwise", "And anticlockwise once set")
