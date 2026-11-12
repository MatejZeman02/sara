## The brush step sets Wash, so one glaze stroke lays a glaze.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One Fill stroke 171 px tall at `opacity` 0.2,
## meant to glaze the crowns a fifth of the way, built its dabs on each other
## and laid near full strength. Here Fill as it ships is set by a real `brush`
## step on a canvas of the suite's own, once in each painting mode at that
## opacity, and each setting lays one stroke of black on a white
## layer through the brush tool's own input path, as
## `test_size_on_pressure_through_pen_settings_follows_the_pens_own_curve.gd`
## paints. A texel's cover is how far the stroke took it from white towards
## black, one less its red channel, and the stroke touched every texel whose
## cover is above [constant UNTOUCHED].
##
## A hard tip still antialiases its outline, so a texel the outline crosses is
## only partly inside the stroke and takes that part of the opacity. Those
## texels are the stroke's edge, the ones within [constant EDGE] texels of one
## the stroke left white. The suite holds them to no more than the opacity,
## every other texel to the opacity itself, and every texel the stroke touched
## to a fifth of what the same stroke at full opacity covers there.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The canvas, the brush and the readback need a RenderingDevice.
const REQUIRES_GPU := true

## Wider than it is tall, so the stroke has a length its dabs overlap along,
## and the shorter side the step turns `radius_px` against.
const CANVAS := Vector2i(512, 256)

## The reported opacity and the height of its stroke, as a radius.
const OPACITY: float = 0.2
const RADIUS_PX: float = 85.5
const HEIGHT: int = 171

## How far from the opacity a texel of the wash may lie, the row's 0.02.
const TOLERANCE: float = 0.02

## The cover below which a texel is white still, which the white ground does
## not reach by rounding.
const UNTOUCHED: float = 0.001

## How near, in texels either way, a white texel has to be for a touched one to
## be on the edge. The antialiased ramp measured a texel and a half wide, from
## 0.005 at 84.9 px from the stroke's line to 0.18 at 84.0.
const EDGE: int = 2

## The stroke, left to right in document pixels along the canvas's middle.
const FROM_X: float = 120.0
const TO_X: float = 392.0
const STROKE_Y: float = 128.0
const STEP: float = 4.0

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _foreground: Color = Color.BLACK

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _foreground = SaColors.foreground
    _host = Node.new()
    _host.name = "T3WashHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = CANVAS
    _host.add_child(_canvas)
    _canvas.size = Vector2(CANVAS)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(SaSurface.create(&"main", _canvas.easel, SaCanvasView.for_canvas(_canvas)), Fixtures.make_tool_registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    SaColors.foreground = _foreground
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


## Measured on 2026-10-08: wash laid 0.2000 at every texel off the edge and
## build-up up to 0.7379, over the same 171 rows.
func test_one_wash_stroke_at_a_fifth_lays_a_fifth_at_every_texel_it_touched() -> void:
    var washed := Cover.new(_paint(_fill_set_by_the_step("wash", "of the whole stroke")))
    assert_eq(washed.rows(), HEIGHT, "The stroke is the reported %d px tall" % HEIGHT)
    var touched := "It touched texels, %d inside and %d on the edge" % [washed.inside, washed.edge]
    assert_true(washed.inside > 0 and washed.edge > 0, touched)
    assert_eq(washed.inside_off, 0, "Every texel off the edge within %.2f of %.2f: %s" % [TOLERANCE, OPACITY, washed])
    assert_true(washed.highest <= OPACITY + TOLERANCE, "No texel past the opacity, the edge's included: %s" % washed)


## A texel the outline crosses is only partly inside the stroke, so a fifth of
## its cover is a fifth of what the stroke covers there, which the same stroke
## laid at full opacity reads. Every texel either stroke touched, the edge's
## included, lies within the row's 0.02 of that fifth. Measured on 2026-10-08:
## 64,887 texels, the worst 0.00000004 from it.
func test_every_texel_the_wash_touched_is_a_fifth_of_what_the_stroke_covers_there() -> void:
    var laid := _paint(_fill_set_by_the_step("wash", "of the whole stroke"))
    var full := _paint(_fill_set_by_the_step("wash", "of the whole stroke", 1.0))
    var touched := 0
    var worst := 0.0
    for index in laid.size():
        if laid[index] <= UNTOUCHED and full[index] <= UNTOUCHED:
            continue
        touched += 1
        worst = maxf(worst, absf(laid[index] - OPACITY * full[index]))
    assert_true(touched > 0, "The strokes touched texels")
    var said := "Every one of %d texels within %.2f of a fifth of the stroke's cover" % [touched, TOLERANCE]
    assert_true(worst <= TOLERANCE, "%s, the worst %.4f" % [said, worst])


func test_one_build_up_stroke_at_a_fifth_lays_past_it_where_its_dabs_overlap() -> void:
    var built := Cover.new(_paint(_fill_set_by_the_step("build-up", "of each dab")))
    assert_eq(built.rows(), HEIGHT, "The same %d px tall" % HEIGHT)
    var one_dab := "No texel off the edge under one dab's %.2f: %s" % [OPACITY, built]
    assert_true(built.lowest_inside >= OPACITY - TOLERANCE, one_dab)
    var overlap := "Most texels off the edge are past %.2f, where dabs overlap: %s" % [OPACITY, built]
    assert_true(built.past * 2 > built.inside, overlap)
    assert_true(built.highest > 3.0 * OPACITY, "and the stroke's middle near full strength: %s" % built)


## The reported step, which named no mode, leaves each preset its own: Fill
## builds up and Grainy Pencil washes, as they ship.
func test_a_step_without_the_key_keeps_the_presets_own_mode() -> void:
    var brush: Object = _machine.get_tool("brush")
    var shipped: Array = [
        ["Fill", "of the whole stroke, painting_mode wash"],
        ["Grainy Pencil", "of the whole stroke, painting_mode wash"],
    ]
    for pair: Array in shipped:
        brush.settings = _preset(pair[0])
        var answer := SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, {"opacity": OPACITY})
        assert_true(answer.contains("opacity 0.20 " + String(pair[1])), "%s keeps its mode: %s" % [pair[0], answer])
        assert_true(answer.ends_with(", unset {}"), "and the step set it all: %s" % answer)


func test_the_mode_is_taken_by_its_name_or_its_number_and_a_wrong_one_is_named() -> void:
    var brush: Object = _machine.get_tool("brush")
    brush.settings = _preset("Fill")
    for asked: Variant in ["Wash", "build_up", 1.0, "build up"]:
        var answer := SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, {"painting_mode": asked})
        var wanted := "wash" if asked is float or String(asked) == "Wash" else "build-up"
        assert_true(answer.contains("painting_mode " + wanted), "%s sets %s: %s" % [asked, wanted, answer])
    var refused := SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, {"painting_mode": "glaze"})
    assert_true(refused.ends_with(', unset {"painting_mode":null}'), "A mode of no name is named: %s" % refused)
    assert_true(refused.contains("painting_mode build-up"), "and leaves the mode as it was: %s" % refused)
    assert_false(SaBrushStepKeys.PaintingModeKey.hand(Resource.new(), "wash"), "Settings with no mode take none")


## Fill as it ships in black, put in the canvas machine's hand and set by a
## `brush` step of the reported radius in *mode* at *opacity*, the
## the reported one unless asked, whose answer has to say the opacity is *of*.
##
## The colour is written on the settings rather than sent as the step's
## `colour`, because that key goes out on the bus to the stamp brush module,
## and this suite keeps no module registered.
func _fill_set_by_the_step(mode: String, of: String, opacity: float = OPACITY) -> SaStampBrushSettings:
    var brush: Object = _machine.get_tool("brush")
    brush.settings = _preset("Fill")
    brush.settings.color = Color.BLACK
    var step := {"painting_mode": mode, "opacity": opacity, "radius_px": RADIUS_PX}
    var answer := SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, step)
    assert_true(answer.ends_with(", unset {}"), "The step set it all: %s" % answer)
    var said := "opacity %.2f %s, painting_mode %s" % [opacity, of, mode]
    assert_true(answer.contains(said), "The answer says '%s': %s" % [said, answer])
    return brush.settings as SaStampBrushSettings


static func _preset(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if entry["name"] == name:
            return SaShippedPresets.build(StampSettingsScript, entry) as SaStampBrushSettings
    return null


## One stroke of *settings* on a fresh white document, answered as the cover of
## every texel of the canvas, row by row.
func _paint(settings: SaStampBrushSettings) -> PackedFloat32Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var document := surface.easel.document
    document.fill_layer(Color.WHITE, document.active_layer)
    var brush: Object = machine.active_tool
    brush.settings = settings
    _send(brush, surface, _button(true), Vector2(FROM_X, STROKE_Y))
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        _send(brush, surface, motion, Vector2(x, STROKE_Y))
    _send(brush, surface, _button(false), Vector2(TO_X, STROKE_Y))
    var cover := _cover(document.active_layer)
    Fixtures.teardown(surface, machine)
    return cover


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _send(brush: Object, surface: SaSurface, event: InputEventMouse, at: Vector2) -> void:
    surface.view.mouse_position = at
    event.position = at
    brush.handle_input(event)


## The cover of every texel of *layer* on the canvas, read off each chunk at
## the size the chunk gives.
static func _cover(layer: SaLayer) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(CANVAS.x * CANVAS.y)
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image := Image.create_from_data(
            edge,
            edge,
            false,
            Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF,
            GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        )
        for y in range(edge):
            for x in range(edge):
                var at := grid_pos * edge + Vector2i(x, y)
                if at.x < CANVAS.x and at.y < CANVAS.y:
                    out[at.y * CANVAS.x + at.x] = 1.0 - image.get_pixel(x, y).r
    return out


## What one stroke's cover comes to: the texels it touched split into the edge
## and the inside, and the inside held against the opacity.
class Cover:
    extends RefCounted

    var top: int = CANVAS.y
    var bottom: int = -1
    var inside: int = 0
    var edge: int = 0
    ## Texels off the edge further from the opacity than the tolerance.
    var inside_off: int = 0
    ## Texels off the edge past the opacity and its tolerance.
    var past: int = 0
    var lowest_inside: float = 1.0
    var highest: float = 0.0

    func _init(cover: PackedFloat32Array) -> void:
        for y in range(CANVAS.y):
            for x in range(CANVAS.x):
                var value := cover[y * CANVAS.x + x]
                if value <= UNTOUCHED:
                    continue
                top = mini(top, y)
                bottom = maxi(bottom, y)
                highest = maxf(highest, value)
                if _near_white(cover, x, y):
                    edge += 1
                    continue
                inside += 1
                lowest_inside = minf(lowest_inside, value)
                if absf(value - OPACITY) > TOLERANCE:
                    inside_off += 1
                if value > OPACITY + TOLERANCE:
                    past += 1

    func rows() -> int:
        return bottom - top + 1

    func _to_string() -> String:
        return (
            "rows %d to %d, %d inside of which %d off and %d past, lowest %.4f, %d on the edge, highest %.4f"
            % [top, bottom, inside, inside_off, past, lowest_inside, edge, highest]
        )

    ## Whether a texel within [constant EDGE] of *x*, *y* is white or off the
    ## canvas.
    static func _near_white(cover: PackedFloat32Array, x: int, y: int) -> bool:
        for dy in range(-EDGE, EDGE + 1):
            for dx in range(-EDGE, EDGE + 1):
                var nx := x + dx
                var ny := y + dy
                if nx < 0 or ny < 0 or nx >= CANVAS.x or ny >= CANVAS.y:
                    return true
                if cover[ny * CANVAS.x + nx] <= UNTOUCHED:
                    return true
        return false
