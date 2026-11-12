## Every stock brush preset, one stroke at a full press over a busy picture,
## changes a tenth of its footprint or more by more than two levels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A preset that leaves no mark a painter can see is a row of the shelf that
## costs a pick and a stroke to learn nothing. The hunt over two real paintings,
## `scripts/presets_on_paintings.py`, found Sparse Specks, Scattered Dots and
## Dust laying a few hundredths of their width, Halftone a solid wash at a
## light touch, and Liquify's Reconstruct and Smooth nothing at all. This holds
## the mended shelf where it is, with no window and no painting: the seven
## tables installed as a fresh profile installs them, each preset loaded onto
## the engine its file names, and one stroke across a picture of small blocks
## of every colour.
##
## **The matching layer.** A preset that lays colour paints on a fresh layer
## over the picture, in a deep blue no block of the picture is, and the change
## is the layer laid over the picture as Normal lays it. A preset that acts on
## paint already laid, a filter, an eraser, a smudge or liquify, paints on the
## picture's own layer, and the change is that layer's.
##
## **The footprint** is every texel within the stroke's radius of its line, the
## radius the tool's own ring shows, so a preset that scatters wide is not held
## to texels it never reached.
extends "res://tests/test_framework.gd"

## Every engine paints on the GPU.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const FilterModuleScript = preload("res://modules/sara-base-modules/filter-brush/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const FilterPresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")
const LiquifyPresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(1024, 512)
## The stroke, left to right through the middle, far enough from the edges that
## the widest stock preset keeps its footprint on the canvas.
const FROM := Vector2(300.0, 256.0)
const TO := Vector2(724.0, 256.0)
## Motions between the press and the release, each followed by a frame.
const MOVES: int = 48
## A frame of a held pen, which an airbrush and liquify paint on.
const FRAME: float = 1.0 / 60.0
## The most frames a release waits for the brush to lay what it carried.
const LIFT_FRAMES: int = 600
## The side of a block of the busy picture, in pixels.
const BLOCK: int = 6
## The colour a preset that lays colour paints in, darker and bluer than any
## block of the picture.
const INK := Color(0.07, 0.14, 0.35, 1.0)
## A texel changed by more than two levels of eight bits.
const LEVELS: float = 2.0 / 255.0
## The share of the footprint a full press changes, the note's floor.
const FLOOR: float = 0.10

## The presets that act on the paint already laid rather than laying colour,
## the same list the hunt paints on a painting's own layer.
const ACTS_ON_PAINT: Array[String] = [
    "Blender",
    "Blur Filter",
    "Desaturate Filter",
    "Eraser",
    "Grain Filter",
    "Layer Blender",
    "Lift",
    "Liquify Grow",
    "Liquify Push",
    "Liquify Shrink",
    "Liquify Twirl Anticlockwise",
    "Liquify Twirl Clockwise",
    "Oil Smudge",
    "Sharpen Filter",
    "Smeary Flat",
    "Soft Eraser",
    "Watery Lift",
    "Wet Into Wet",
]

static var scratch_dir: String = SaDataRoot.path("test_every_stock_preset_changes_a_tenth")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _store: SaPresetStore = null
## The time the pen's clock is held at for the event being handed, a frame
## further on for each, so a stabiliser and a speed sensor read a stroke drawn
## at a painter's pace rather than every event in the same microsecond.
var _clock_usec: int = 0


func before_each() -> void:
    _clear()
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, FilterModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _store = SaPresetStore.new()
    _store.dir = scratch_dir


func after_each() -> void:
    SaPenClock.let_go()
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    _store = null
    _clear()


static func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file))
    DirAccess.remove_absolute(scratch_dir)


## The tool that paints with *engine*, as the bar's engine switch picks it from
## the Brush.
func _tool_for(engine: StringName) -> StringName:
    return _registries.tools.engine_for(&"brush", engine)


## Every stock preset by name, installed as a fresh profile installs the seven
## tables, each shelf onto its own engine's settings.
func _install() -> Array[String]:
    var names: Array[String] = []
    var shelves: Array = [
        [&"", ShippedPresetsScript],
        [&"filter", FilterPresetsScript],
        [&"liquify", LiquifyPresetsScript],
        [&"noise", NoisePresetsScript],
    ]
    for shelf: Array in shelves:
        var id := _tool_for(shelf[0]) if not String(shelf[0]).is_empty() else &"brush"
        var template: Resource = _machine.get_tool(id).get("settings")
        _store.install_shipped(template, shelf[1])
        for entry: Dictionary in (shelf[1] as GDScript).entries():
            names.append(String(entry["name"]))
    return names


## A block's colour, a hash of its place, every channel between 0.2 and 0.9 so
## the ink is darker than all of them and a lift has paint to take.
@warning_ignore("integer_division")
static func _block(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var h := hash(Vector2i(x / BLOCK, y / BLOCK))
    return Color(
        0.2 + 0.7 * float(h & 255) / 255.0,
        0.2 + 0.7 * float((h >> 8) & 255) / 255.0,
        0.2 + 0.7 * float((h >> 16) & 255) / 255.0,
        1.0
    )


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh layer of the busy picture over the whole canvas, active.
func _picture() -> SaLayer:
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var grids: Array[Vector2i] = []
    for gy in ceili(float(CANVAS.y) / layer.CHUNK_SIZE):
        for gx in ceili(float(CANVAS.x) / layer.CHUNK_SIZE):
            var grid := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(grid)
            var texture := chunk.albedo()
            var side := chunk.pixel_size()
            var image := Image.create_empty(side, side, false, _image_format(texture))
            for y in side:
                for x in side:
                    image.set_pixel(x, y, _block(gx * side + x, gy * side + y))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(grid)
            grids.append(grid)
    doc.invalidate_chunks(grids)
    return layer


## The texels of *layer* in the rectangle the stroke can reach, read back as
## one image per chunk.
static func _texels(layer: SaLayer) -> Dictionary[Vector2i, Image]:
    var out: Dictionary[Vector2i, Image] = {}
    for grid: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid]
        var texture := chunk.albedo()
        var side := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        out[grid] = Image.create_from_data(side, side, false, _image_format(texture), bytes)
    return out


static func _texel(texels: Dictionary[Vector2i, Image], at: Vector2i, side: int) -> Color:
    var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var image: Image = texels.get(grid, null)
    if image == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    return image.get_pixel(at.x - grid.x * side, at.y - grid.y * side)


## The tool's own ring radius, in canvas pixels at the suite's view.
func _radius() -> float:
    var tool := _machine.active_tool
    if tool.has_method("get_cursor_radius"):
        return float(tool.call("get_cursor_radius"))
    return 0.0


func _event(at: Vector2, pressed: Variant) -> void:
    _clock_usec += roundi(FRAME * 1000000.0)
    SaPenClock.follow(_clock_usec)
    _surface.view.mouse_position = at
    var event: InputEvent = null
    if pressed == null:
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        motion.position = at
        motion.global_position = at
        event = motion
    else:
        var button := InputEventMouseButton.new()
        button.button_index = MOUSE_BUTTON_LEFT
        button.pressed = bool(pressed)
        button.position = at
        button.global_position = at
        event = button
    _machine.handle_input(event)


## One stroke at a full press from FROM to TO, a frame after every motion and
## frames after the release until the stroke is a step of the history.
##
## The frames are what the app gives a stroke. A brush walks a frame's share of
## its dabs and carries the rest, and a release waits for the walk, so a stroke
## of a slow smudge ended at its release lays its first dabs alone. Liquify's
## twirl, shrink and grow work only while the button is held, a frame at a
## time, and its session is a step once it is committed.
func _stroke() -> void:
    var tool := _machine.active_tool
    _clock_usec = Time.get_ticks_usec()
    _event(FROM, true)
    for i in range(1, MOVES + 1):
        _event(FROM.lerp(TO, float(i) / MOVES), null)
        _frame(tool)
    _event(TO, false)
    for i in LIFT_FRAMES:
        var budget: Variant = tool.get("_budget")
        if budget == null or not budget.lifting:
            break
        _frame(tool)
    if tool.has_method("commit_session"):
        tool.call("commit_session")


## A frame of the app for *tool*: the easel's composite, its tick, and a held
## liquify's hold, which the tick hands the frame's length only when the frame
## is the engine's own. The composite is what a smudge that reads every layer
## picks its paint up from, and without a frame's it picks up nothing past the
## first dab.
func _frame(tool: ToolState) -> void:
    _surface.easel.process_pending_composite(true)
    tool.tick(FRAME)
    if tool.has_method("hold"):
        tool.call("hold", FRAME)


## The share of the footprint changed by more than two levels: the texels of
## *after* against *picture* when the stroke was on the picture's layer, and
## *after* laid over *picture* as Normal lays it when it was on a fresh one.
func _share(
    picture: Dictionary[Vector2i, Image], after: Dictionary[Vector2i, Image], on_picture: bool, radius: float, side: int
) -> float:
    var reach := ceili(radius)
    var inside := 0
    var changed := 0
    for y in range(maxi(0, int(FROM.y) - reach), mini(CANVAS.y, int(FROM.y) + reach + 1)):
        for x in range(maxi(0, int(FROM.x) - reach), mini(CANVAS.x, int(TO.x) + reach + 1)):
            var at := Vector2(x + 0.5, y + 0.5)
            var along := clampf((at.x - FROM.x) / (TO.x - FROM.x), 0.0, 1.0)
            if at.distance_to(FROM.lerp(TO, along)) > radius:
                continue
            inside += 1
            var under := _texel(picture, Vector2i(x, y), side)
            var mark := _texel(after, Vector2i(x, y), side)
            var seen := mark if on_picture else under.lerp(Color(mark.r, mark.g, mark.b, 1.0), clampf(mark.a, 0.0, 1.0))
            var most := maxf(
                maxf(absf(seen.r - under.r), absf(seen.g - under.g)), maxf(absf(seen.b - under.b), absf(seen.a - under.a))
            )
            if most > LEVELS:
                changed += 1
    return float(changed) / float(maxi(inside, 1))


## The note's check: one full-press stroke with every stock preset over the busy
## picture, on the layer it belongs on, changes a tenth of its footprint or more.
func test_every_stock_preset_changes_a_tenth_of_its_footprint() -> void:
    var names := _install()
    assert_true(names.size() > 0, "The seven tables hold presets")
    var picture := _picture()
    var side: int = picture.chunks.values()[0].pixel_size()
    var held := _texels(picture)
    var doc := _surface.get_document()
    var lines := PackedStringArray()
    for preset_name: String in names:
        var engine := _store.engine_for(preset_name)
        var id := _tool_for(engine) if not String(engine).is_empty() else &"brush"
        _machine.set_active_tool(id)
        var settings: Resource = _machine.active_tool.get("settings")
        assert_true(_store.apply_preset(preset_name, settings), "%s loads onto the %s tool" % [preset_name, id])
        if "color" in settings:
            settings.set("color", INK)
        var on_picture := ACTS_ON_PAINT.has(preset_name)
        var mark := picture
        if not on_picture:
            mark = SaLayerOps.new(doc).add(&"", null, 1.0)
        doc.active_layer = mark
        _stroke()
        var share := _share(held, _texels(mark), on_picture, _radius(), side)
        lines.append("%s %.3f" % [preset_name, share])
        assert_true(share >= FLOOR, "%s changes %.3f of its footprint" % [preset_name, share])
        # The picture is laid again after every preset that changed it, so the
        # next one finds it as the first did.
        _machine.set_active_tool(&"brush")
        if on_picture:
            SaLayerOps.new(doc).remove(picture)
            picture = _picture()
            held = _texels(picture)
        else:
            SaLayerOps.new(doc).remove(mark)
            doc.active_layer = picture
    print("Stock presets over the busy picture: %s" % ", ".join(lines))
