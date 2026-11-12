## A preset given a grey lays a grey, or its brush answer says what changes it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The painting of the laundry basket asked Oil Smudge and Dry Marker for greys
## and whites, jittered by twelve a channel, over the recess's yellow wash and
## the wall's cream, and the painter saw lavender and teal. The painting's own
## texels put every tint inside the script's jitter, and these give the two
## shipped presets the script's greys over that ground through the same `brush`
## step, stroke them, and read each laid texel as a mix of the asked colour and
## the ground under it. Building them found the fault the note asked for: Oil
## Smudge's dilution and length were switched off, which read one, so its carry
## replaced the asked colour in full and it laid only the ground. The dilution
## is Colour Rate, its complement. The last tests
## read the brush answer, which now names what changes the colour and the key
## that switches it off.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const ShippedPresetsScript := preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const NoisePresetsScript := preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

## The canvas, the bar, the machine and the strokes need a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_known: String = SaDataRoot.path("c3-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("c3-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("c3-door-run")
static var scratch_presets: String = SaDataRoot.path("test_c3_presets")

const ROUNDS: int = 600
const DOCUMENT := Vector2i(512, 512)
const FRAME := 1.0 / 60.0

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-noise-brush-engine/module.gd",
]

## The two presets the note names.
const PRESETS: Array[String] = ["Oil Smudge", "Dry Marker"]

## The four grey heaps of `p_wall` in `paint_bin.py`, in 0 to 255.
const HEAPS: Array[Vector3] = [
    Vector3(222.0, 222.0, 214.0), Vector3(150.0, 150.0, 146.0), Vector3(204.0, 200.0, 186.0), Vector3(96.0, 96.0, 92.0)
]

## The script's `jit(c, 12)`, a channel at a time, before every dash.
const JITTER := 12.0

## The recess's Wash, the wall's cream, and the paper's fill, as the script laid
## them: `{"fill": [0.9, 0.84, 0.62]}` and the cream half way from the wall
## colour to its highlight.
const YELLOW := Color(196.0 / 255.0, 176.0 / 255.0, 112.0 / 255.0, 1.0)
const CREAM := Color(238.0 / 255.0, 223.0 / 255.0, 169.0 / 255.0, 1.0)
const PAPER := Color(0.9, 0.84, 0.62, 1.0)

## The thin wash, the share of yellow a Wash at 0.7 leaves on a layer by itself.
const THIN := 0.35

## One dash a cell: yellow, cream, thin yellow, and the bare layer over the paper.
const CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## How far a texel may sit outside the mix, in stored channels: a tenth of a
## step of eight bits, since an sRGB document at F32 mixes in floats.
const SLACK := 0.0004

## The least share of the asked colour the middle of a dash holds, where the
## asked colour and the ground are far enough apart to measure it.
const LEAST_SHARE := 0.3

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
var _ctx: SaContext = null
var _modules: Array[SaModule] = []
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _client: StreamPeerTCP = null
var _view: Fixtures.FakeView = null
var _foreground: Color = Color.BLACK

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    ScratchFolder.clear(scratch_presets)
    _foreground = SaColors.foreground
    _host = Node.new()
    _host.name = "C3Host"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = DOCUMENT
    _host.add_child(_canvas)
    _canvas.size = Vector2(DOCUMENT)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    # A view the suite moves, so a dash reaches the brush the way a hand does.
    _view = Fixtures.FakeView.new()
    _machine.bind(SaSurface.create(&"main", _canvas.easel, _view), _registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_presets
    _bar.preset_store.install_shipped(_machine.get_tool(&"brush").get("settings"), ShippedPresetsScript)
    _bar.preset_store.install_shipped(_machine.get_tool(&"noise_brush").get("settings"), NoisePresetsScript)
    _bar._ready()
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _client = _runner.connect_client()


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    if _client != null:
        _client.disconnect_from_host()
        _client = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    SaColors.foreground = _foreground
    for module: SaModule in _modules:
        module.unregister(_ctx)
    _modules.clear()
    _ctx = null
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null
    _bar = null
    ScratchFolder.clear(scratch_presets)


func test_the_two_presets_lay_a_mix_of_the_asked_grey_and_the_ground() -> void:
    _open_srgb()
    var random := RandomNumberGenerator.new()
    random.seed = 6
    for preset: String in PRESETS:
        for heap: Vector3 in HEAPS:
            # The wall was painted in build-up, which is not the default.
            var asks := {"preset": preset, "radius_px": 12, "colour": _hex(heap), "opacity": 0.8, "painting_mode": "build-up"}
            var answer := _brush(asks)
            assert_true(answer.contains("preset '%s'" % preset), "%s loads through the brush step: %s" % [preset, answer])
            var clothes := _ground()
            var brush: Object = _machine.active_tool
            var asked: Array[Color] = []
            for cell: Vector2i in CELLS:
                var jittered := Vector3(
                    heap.x + random.randf_range(-JITTER, JITTER),
                    heap.y + random.randf_range(-JITTER, JITTER),
                    heap.z + random.randf_range(-JITTER, JITTER)
                )
                _brush({"colour": _hex(jittered)})
                asked.append(_canvas.easel.document.color_space.from_display(Color.html(_hex(jittered))))
                _dash(brush, Vector2(cell * 256) + Vector2(128.0, 128.0), 30.0, 0.7)
            for i in CELLS.size():
                _read_cell(preset, clothes, CELLS[i], asked[i])
            SaLayerOps.new(_canvas.easel.document).remove(clothes)


func test_oil_smudges_answer_names_its_smudge_stage_and_the_key_that_turns_it_off() -> void:
    var answer := _brush({"preset": "Oil Smudge", "colour": "#969692"})
    assert_true(answer.contains("the smudge stage"), "The answer names the smudge stage: %s" % answer)
    assert_true(answer.contains("pickup 0.60, colour rate 0.50, length 0.75"), "as the dab reads it: %s" % answer)
    assert_true(answer.contains('(off: "smudge_pickup_option:enabled": false)'), "and the key that turns it off: %s" % answer)
    var off := _brush({"smudge_pickup_option:enabled": false})
    assert_true(off.contains("nothing changes the colour"), "The key sent through the same step turns it off: %s" % off)


func test_living_colours_answer_names_its_colour_variation() -> void:
    var answer := _brush({"preset": "Living Colour", "colour": "#969692"})
    assert_true(answer.contains("tool in hand noise_brush"), "Living Colour is the noise brush's: %s" % answer)
    assert_true(answer.contains("colour variation 0.70"), "The answer names its colour variation: %s" % answer)
    assert_true(answer.contains('(off: "chroma_variation": 0)'), "and the key that turns it off: %s" % answer)
    var off := _brush({"tool": "noise_brush", "chroma_variation": 0})
    assert_false(off.contains("colour variation"), "The key sent through the same step turns it off: %s" % off)


func test_dry_marker_says_nothing_changes_its_colour_until_an_option_does() -> void:
    var answer := _brush({"preset": "Dry Marker", "colour": "#969692"})
    assert_true(answer.contains("nothing changes the colour"), "Dry Marker lays the colour asked: %s" % answer)
    var bare := _brush({"hue_option:enabled": true})
    assert_true(
        bare.contains("nothing changes the colour"), "An option on with no sensor reads nothing, as in the dab: %s" % bare
    )
    var hue := _brush({"pen_settings": {"hue": {"enabled": true, "sensors": ["pressure"]}}})
    assert_true(
        hue.contains('hue_option turns the hue by pressure (off: "hue_option:enabled": false)'),
        "An option switched on with its sensor is named with its key: %s" % hue
    )
    # No exposure to name: the paint exposure is the
    # foreground's own stops, and the dab multiplies the colour by nothing.
    var plain := _brush({"hue_option:enabled": false})
    assert_true(plain.contains("nothing changes the colour"), "Each key it names puts the colour back: %s" % plain)


## Every laid texel of *cell* against the mix of *asked* and the ground, and
## the middle of the dash against a share of *asked*.
##
## The mix is the triangle of the asked colour, the picture under the dab and
## the layer's own texel, which differ only on the thin wash: the smudge stage
## carries the picture, and a dab laid over a half covered texel mixes with the
## layer's own. A texel holds no hue neither holds when its chroma sits inside
## that triangle and its lightness between the triangle's lightest and darkest.
func _read_cell(preset: String, clothes: SaLayer, cell: Vector2i, asked: Color) -> void:
    var under := _under(cell)
    var own := _own(cell)
    var corners: Array[Color] = [asked, under, own if own.a > 0.01 else under]
    var image := _image(clothes, cell)
    var worst := 0.0
    var worst_at := Vector2i(-1, -1)
    var laid := 0
    for y in range(64, 192):
        for x in range(40, 216):
            var texel := image.get_pixel(x, y)
            if texel.a < 0.01 or _distance(texel, own) < SLACK:
                continue
            laid += 1
            var off := _outside(texel, corners)
            if off > worst:
                worst = off
                worst_at = Vector2i(x, y)
    var label := "%s asked %s, cell %s" % [preset, asked, cell]
    assert_true(laid > 100, "%s: the dash lays paint, %d texels" % [label, laid])
    var worst_texel := image.get_pixel(worst_at.x, worst_at.y) if worst_at.x >= 0 else Color()
    var mixed := "every laid texel is a mix of the asked colour and the ground"
    assert_true(worst < SLACK, "%s: %s, the worst %s at %s, %.5f out" % [label, mixed, worst_texel, worst_at, worst])
    var middle := image.get_pixel(128, 128)
    var span := Vector3(asked.r - under.r, asked.g - under.g, asked.b - under.b)
    if span.length() < 0.05:
        return
    var share := Vector3(middle.r - under.r, middle.g - under.g, middle.b - under.b).dot(span) / span.dot(span)
    var held := "the middle %s holds %.2f of the asked colour, not only the ground %s" % [middle, share, under]
    assert_true(share > LEAST_SHARE, "%s: %s" % [label, held])


## How far *texel* sits outside the mix of *corners*: its chroma's distance from
## their triangle, or its lightness's from their range, whichever is further.
static func _outside(texel: Color, corners: Array[Color]) -> float:
    var lightest := -INF
    var darkest := INF
    var flat: Array[Vector2] = []
    for corner: Color in corners:
        lightest = maxf(lightest, _lightness(corner))
        darkest = minf(darkest, _lightness(corner))
        flat.append(_chroma(corner))
    var lightness := _lightness(texel)
    var beyond := maxf(lightness - lightest, darkest - lightness)
    return maxf(beyond, _off_triangle(_chroma(texel), flat[0], flat[1], flat[2]))


## The mean of the three channels, which a mix in stored channels keeps between
## the lightnesses of what it mixes.
static func _lightness(c: Color) -> float:
    return (c.r + c.g + c.b) / 3.0


## The plane across the grey axis, in two coordinates, so a grey is the origin
## and a hue is a direction.
static func _chroma(c: Color) -> Vector2:
    return Vector2((c.r - c.g) / sqrt(2.0), (c.r + c.g - 2.0 * c.b) / sqrt(6.0))


## Nought for *p* inside the triangle *a*, *b*, *c*, and its distance from the
## nearest edge otherwise. A triangle with no area is its longest edge.
static func _off_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
    var area := (b - a).cross(c - a)
    if absf(area) > 1e-9:
        var u := (b - p).cross(c - p) / area
        var v := (c - p).cross(a - p) / area
        var w := (a - p).cross(b - p) / area
        if u >= 0.0 and v >= 0.0 and w >= 0.0:
            return 0.0
    return minf(minf(_off_segment(p, a, b), _off_segment(p, b, c)), _off_segment(p, c, a))


static func _off_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var along := b - a
    var t := 0.0 if along.length_squared() < 1e-12 else clampf((p - a).dot(along) / along.length_squared(), 0.0, 1.0)
    return p.distance_to(a + along * t)


static func _distance(a: Color, b: Color) -> float:
    return Vector4(a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a).length()


## The picture under *cell* before the dash: the clothes layer over the paper.
func _under(cell: Vector2i) -> Color:
    var space := _canvas.easel.document.color_space
    var paper := space.from_display(PAPER)
    var own := _own(cell)
    return Color(lerpf(paper.r, own.r, own.a), lerpf(paper.g, own.g, own.a), lerpf(paper.b, own.b, own.a), 1.0)


## The clothes layer's own texel in *cell* before the dash.
func _own(cell: Vector2i) -> Color:
    var space := _canvas.easel.document.color_space
    match CELLS.find(cell):
        0:
            return space.from_display(YELLOW)
        1:
            return space.from_display(CREAM)
        2:
            var thin := space.from_display(YELLOW)
            thin.a = THIN
            return thin
    return Color(0.0, 0.0, 0.0, 0.0)


## The script's document, `{"document": "srgb"}`, made the way that step makes
## it.
func _open_srgb() -> void:
    for space: SaColorSpace in SaColorSpace.presets():
        if String(space.id) == "srgb":
            _canvas.document.reset_to_default(DOCUMENT, space, SaDocument.DEFAULT_DPI, {}, null)
    _canvas.resize_canvas(DOCUMENT)
    assert_eq(String(_canvas.easel.document.color_space.id), "srgb", "The document is the script's sRGB")


## The paper filled with the script's fill, and the clothes layer above it
## holding the ground of the four cells. Returned, so a round removes it.
func _ground() -> SaLayer:
    var document := _canvas.easel.document
    var paper := document.active_layer
    for cell: Vector2i in CELLS:
        paper.get_or_create_chunk(cell).clear(document.color_space.from_display(PAPER))
    var clothes := SaLayerOps.new(document).add()
    for cell: Vector2i in CELLS:
        var own := _own(cell)
        if own.a > 0.0:
            clothes.get_or_create_chunk(cell).clear(own)
    document.invalidate_chunks(CELLS)
    _canvas.easel.request_full_composite()
    _canvas.easel.process_pending_composite()
    return clothes


static func _hex(c: Vector3) -> String:
    return "#%02x%02x%02x" % [clampi(roundi(c.x), 0, 255), clampi(roundi(c.y), 0, 255), clampi(roundi(c.z), 0, 255)]


func _registry() -> SaToolRegistry:
    var registry := SaToolRegistry.new()
    _ctx = SaContext.create(
        registry,
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        SaRoleRegistry.new()
    )
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_ctx.for_module(module.get_id()))
        _modules.append(module)
    return registry


## The `brush` step sent over the door, and its answer line.
func _brush(spec: Dictionary) -> String:
    var answer := _runner.ask(_client, {"brush": spec})
    for line: Variant in answer.get("verdicts", []):
        if String(line).begins_with("SaCapture: brush"):
            return String(line)
    return JSON.stringify(answer)


## A straight dash of *length* through *middle* at *pressure*, six motions from
## a press to a release, then frames until the brush has laid its last dab.
func _dash(brush: Object, middle: Vector2, length: float, pressure: float) -> void:
    var points: Array[Vector2] = []
    for i in 6:
        points.append(middle + Vector2(-length * 0.5 + length * float(i) / 5.0, 0.0))
    _motion(brush, points[0], pressure, 0)
    brush.tick(FRAME)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = points[0]
    brush.handle_input(press)
    brush.tick(FRAME)
    for i in range(1, points.size()):
        _motion(brush, points[i], pressure, MOUSE_BUTTON_MASK_LEFT)
        brush.tick(FRAME)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = points[-1]
    brush.handle_input(release)
    var frames := 0
    while brush.is_drawing and frames < 600:
        brush.tick(FRAME)
        frames += 1


func _motion(brush: Object, at: Vector2, pressure: float, mask: int) -> void:
    _view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.button_mask = mask
    motion.pressure = pressure
    brush.handle_input(motion)


## *cell* of *layer* read back from VRAM, at the chunk's own format.
func _image(layer: SaLayer, cell: Vector2i) -> Image:
    var chunk: SaChunk = layer.chunks[cell]
    var texture := chunk.albedo()
    var format := Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var edge := chunk.pixel_size()
    return Image.create_from_data(edge, edge, false, format, bytes)
