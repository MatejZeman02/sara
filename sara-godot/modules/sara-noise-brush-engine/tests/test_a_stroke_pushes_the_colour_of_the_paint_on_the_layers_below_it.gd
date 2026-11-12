## A stroke pushes the colour of the paint on the layers below it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Grain Round band is painted down the document on one layer, a layer is
## added above it, and a Bristle Flat stroke of another colour is dragged
## across the band on the upper layer, at a pressure that leaves holes between
## its streaks. Two of the drag's radii past the band's far side the upper
## layer's colour has moved at least a quarter of the way from the drag's own
## towards the band's, in Oklab, against the same drag over nothing, and five
## radii past it is the bare drag's again. The colour is weighed by the band's
## height, so a band laid with no height is not pushed. Neither the Background
## nor a paper ground is pushed: a band painted into the Background itself and
## the tooth of a paper under the drag leave the upper layer as the drag with
## the setting off leaves it. With Push Colour Below off the upper layer is the
## bare drag's, so it holds none of the band's colour. The setting is one On
## and Off row on the page, on by default, and a preset keeps it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## Big enough that a preset's radius, a share of the smaller side, is a dozen
## pixels, and five of them past the band stay on the canvas.
const SIZE := Vector2i(1024, 512)
## The band, a stroke down x = 300, and the drag, a stroke along the middle row
## that crosses it and runs on well past five radii beyond it.
const BAND_X := 300.0
const BAND_FROM := Vector2(BAND_X, 120.0)
const BAND_TO := Vector2(BAND_X, 392.0)
const ROW := 256.0
const DRAG_FROM := Vector2(120.0, ROW)
const DRAG_TO := Vector2(760.0, ROW)
## The two colours in display terms, the band's an ochre and the drag's a blue.
const BAND_COLOUR := Color(0.69, 0.44, 0.24)
const DRAG_COLOUR := Color(0.24, 0.42, 0.69)
## Below a full press, so the Bristle Flat's cut leaves holes between its
## streaks, where a push laid only under the streaks would land nothing.
const DRAG_PRESSURE := 0.6
## How far across the stroke a window reads, as a share of the drag's radius,
## and how far along it, in pixels either side of its middle.
const ACROSS := 0.8
const ALONG := 2
## The alpha a texel counts as painted at.
const PAINTED := 0.05
## The share of the way to the band's colour two radii past it, at least.
const CARRIED := 0.25
## The thin band's thickness in millimetres, under a seventh of Grain
## Round's. Measured half a radius past the band, 0.02 is carried none of the
## way, 0.04 a third, 0.08 two thirds and the preset's 0.3 three quarters.
const THIN := 0.04
## How near two readings are to count as one, in Oklab.
const SAME := 0.001

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _registries: SaRegistries = null
## The upper layer the drag paints, and the layer the band lies on.
var _upper: SaLayer = null
var _lower: SaLayer = null
## Each layer's chunks read back, by layer and grid position, dropped whenever
## a stroke changes them.
var _read: Dictionary = {}
var _dir: String = SaDataRoot.path("test_p1_push_colour_below")


func before_each() -> void:
    _fresh()


func after_each() -> void:
    _brush = null
    _upper = null
    _lower = null
    Fixtures.teardown(_surface)
    _surface = null
    if DirAccess.dir_exists_absolute(_dir):
        for file_name: String in DirAccess.get_files_at(_dir):
            DirAccess.remove_absolute(_dir.path_join(file_name))
        DirAccess.remove_absolute(_dir)


## Two radii past the band the upper layer holds the band's colour carried a
## quarter of the way and more, and five radii past it holds the bare drag's.
func test_the_upper_layer_carries_the_bands_colour_past_its_edge() -> void:
    _band(-1.0)
    var band := _colour(_lower, Rect2i(int(BAND_X) - 2, int(ROW) - 40, 5, 81))
    var far := _far_side()
    var radius := _radius_of("Bristle Flat")
    var near_window := _window(far + 2.0 * radius, radius)
    var far_window := _window(far + 5.0 * radius, radius)
    _over(true)
    var pushed := [_colour(_upper, near_window), _painted(_upper, near_window), _colour(_upper, far_window)]
    _fresh()
    _over(true)
    var bare := [_colour(_upper, near_window), _painted(_upper, near_window), _colour(_upper, far_window)]

    var moved := _way(bare[0], band, pushed[0])
    var moved_far := _way(bare[2], band, pushed[2])
    print(
        (
            "  band far side %.1f, radius %.1f, way %.3f, painted %d against %d, five radii %.4f"
            % [far, radius, moved, pushed[1], bare[1], moved_far]
        )
    )
    assert_true(
        moved >= CARRIED,
        "Two radii past the band the upper layer has moved %.3f of the way towards the band's colour, at least a quarter" % moved
    )
    assert_true(pushed[1] > bare[1], "and paint lands in %d texels where the bare drag's holes leave %d" % [pushed[1], bare[1]])
    assert_true(absf(moved_far) < 0.01, "Five radii past the colour is the bare drag's, %.4f of the way" % moved_far)


## The colour below is weighed by its height: a band laid with none is paint
## with no body, and the drag above it lays its own colour past it.
func test_a_band_with_no_height_is_not_pushed() -> void:
    _band(0.0)
    assert_false(_lower.carries_height(), "A band laid at no thickness gives its layer no height")
    var radius := _radius_of("Bristle Flat")
    var window := _window(BAND_X + 3.0 * radius, radius)
    _over(true)
    var over_flat := _colour(_upper, window)
    _fresh()
    _over(true)
    var bare := _colour(_upper, window)
    assert_true(
        _distance(over_flat, bare) < SAME, "Past a band with no height the drag lays %s, over nothing %s" % [over_flat, bare]
    )


## A thinner band weighs less: half a radius past it, the same drag over a
## band under a seventh as thick as the preset's is carried a shorter way
## towards its colour than over the full one, and still some of it, since the
## height weighs the colour rather than gating it. A weak load runs out sooner,
## so the reading is taken where it has not yet.
func test_a_thinner_band_is_carried_less() -> void:
    var radius := _radius_of("Bristle Flat")
    _band(-1.0)
    var band := _colour(_lower, Rect2i(int(BAND_X) - 2, int(ROW) - 40, 5, 81))
    var window := _window(_far_side() + 0.5 * radius, radius)
    _over(true)
    var full := _colour(_upper, window)
    _fresh()
    _band(THIN)
    _over(true)
    var thin := _colour(_upper, window)
    _fresh()
    _over(true)
    var bare := _colour(_upper, window)
    var full_way := _way(bare, band, full)
    var thin_way := _way(bare, band, thin)
    print("  full band %.3f of the way, one of %.3f mm %.3f" % [full_way, THIN, thin_way])
    assert_true(
        thin_way < full_way - 0.2, "A band of %.3f mm is carried %.3f of the way, the full one %.3f" % [THIN, thin_way, full_way]
    )
    assert_true(thin_way > 0.1, "and still carried some of the way")


## With Push Colour Below off the upper layer is the bare drag's wherever the
## drag went, past the band and over it, so it holds none of the band's colour.
func test_with_the_setting_off_the_upper_layer_is_free_of_the_bands_colour() -> void:
    _band(-1.0)
    var band := _colour(_lower, Rect2i(int(BAND_X) - 2, int(ROW) - 40, 5, 81))
    var far := _far_side()
    var radius := _radius_of("Bristle Flat")
    var windows: Array[Rect2i] = []
    for past: float in [-1.0, 0.0, 1.0, 2.0, 3.0, 5.0]:
        windows.append(_window(far + past * radius, radius))
    _over(false)
    var off: Array = []
    for window: Rect2i in windows:
        off.append([_colour(_upper, window), _painted(_upper, window)])
    _fresh()
    _over(false)
    for at: int in windows.size():
        var bare := _colour(_upper, windows[at])
        var moved := _way(bare, band, off[at][0])
        assert_true(
            _distance(off[at][0], bare) < SAME,
            (
                "Off, the upper layer at %s is %s, the bare drag's %s, %.4f of the way to the band"
                % [windows[at].position, off[at][0], bare, moved]
            )
        )
        assert_eq(off[at][1], _painted(_upper, windows[at]), "and paints as many texels there")


## The Background is the sheet the paint lies on and never pushed: a band
## painted into it, with its height, leaves the upper layer as the drag with
## the setting off leaves it.
func test_paint_on_the_background_is_never_pushed() -> void:
    var background := _surface.easel.document.get_child(0) as SaLayer
    assert_eq(str(background.name), SaDocumentBackground.LAYER_NAME, "The bottom layer is the Background")
    assert_false(background.is_generated(), "and stores its paint")
    _surface.easel.document.set_active_layer(background)
    _band(-1.0)
    assert_true(background.carries_height(), "The band in it has a height")
    var radius := _radius_of("Bristle Flat")
    var window := _window(BAND_X + 3.0 * radius, radius)
    _surface.easel.document.set_active_layer(_upper)
    _over_upper(true)
    var on := _colour(_upper, window)
    var row := _colour(_upper, Rect2i(int(DRAG_FROM.x), int(ROW) - 4, int(DRAG_TO.x - DRAG_FROM.x), 9))
    _fresh()
    _surface.easel.document.set_active_layer(_surface.easel.document.get_child(0) as SaLayer)
    _band(-1.0)
    _surface.easel.document.set_active_layer(_upper)
    _over_upper(false)
    assert_true(
        _distance(on, _colour(_upper, window)) < SAME,
        "Past a band on the Background the drag lays its colour as with the setting off"
    )
    var off_row := _colour(_upper, Rect2i(int(DRAG_FROM.x), int(ROW) - 4, int(DRAG_TO.x - DRAG_FROM.x), 9))
    assert_true(_distance(row, off_row) < SAME, "and along the whole drag")


## A paper ground stands its tooth under the paint, which the drag pushes as
## height, but its colour is the sheet's and never pushed: the upper layer is
## the drag's own colour on and off alike.
func test_a_ground_is_never_pushed() -> void:
    _ground()
    _over(true)
    var rect := Rect2i(int(DRAG_FROM.x), int(ROW) - 4, int(DRAG_TO.x - DRAG_FROM.x), 9)
    var on := _colour(_upper, rect)
    _fresh()
    _ground()
    _over(false)
    var off := _colour(_upper, rect)
    assert_true(_distance(on, off) < SAME, "Over the paper the drag lays %s on and %s off" % [on, off])


## One On and Off row on the brush's page, on by default, and a preset saved
## with it off loads with it off.
func test_the_setting_is_one_row_and_a_preset_keeps_it() -> void:
    var found: SaOptionSpec = null
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.key == &"push_colour_below":
            assert_null(found, "The page has one row for it")
            found = spec
    assert_not_null(found, "The page has a row for Push Colour Below")
    assert_eq(found.kind, SaOptionSpec.Kind.BOOL, "an On and Off one, the way Size by Pressure reads")
    assert_eq(found.label, "Push Colour Below", "under its label")
    assert_eq(found.page, NoiseModuleScript.PAGE, "on the brush's page")
    assert_false(found.bar, "and kept off the bar")
    assert_true(NoiseSettingsScript.new().push_colour_below, "A brush pushes the colour below by default")
    for entry: Dictionary in NoisePresetsScript.entries():
        var built: Resource = NoisePresetsScript.build(NoiseSettingsScript, entry)
        assert_true(bool(built.get("push_colour_below")), "and so does the shipped %s" % entry["name"])
    DirAccess.make_dir_recursive_absolute(_dir)
    var store := SaPresetStore.new()
    store.dir = _dir
    var settings := NoiseSettingsScript.new()
    settings.push_colour_below = false
    var stored := store.save_preset("Dry Push", settings)
    assert_false(stored.is_empty(), "The preset saves")
    var loaded := store.load_preset(stored)
    assert_not_null(loaded, "and loads")
    assert_false(bool(loaded.get("push_colour_below")), "with Push Colour Below still off")


## A fresh document holding Oklab, its Background and Layer 1, with a layer
## added above Layer 1, a noise brush on it, and Layer 1 active for the band.
func _fresh() -> void:
    _read.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    var space := SaColorSpace.oklab().with_depth(SaColorSpace.Depth.F16)
    _surface = SaSurface.create(&"test", SaEasel.create_default(SIZE, null, space), Fixtures.FakeView.new())
    if _registries == null:
        _registries = Fixtures.make_registries()
    _surface.easel.compositor.set_registry(_registries.blend_modes)
    var doc := _surface.easel.document
    assert_eq(doc.color_space.coordinates, SaColorSpace.Coordinates.OKLAB, "The document stores Oklab")
    _lower = doc.active_layer
    SaLayerOps.new(doc).add()
    _upper = doc.active_layer
    assert_true(_upper != _lower and _upper.get_index() == _lower.get_index() + 1, "The new layer lies above the band's")
    doc.set_active_layer(_lower)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7


## A paper ground at the bottom of the stack, under the band's layer.
func _ground() -> void:
    var doc := _surface.easel.document
    doc.set_active_layer(doc.get_child(0) as SaLayer)
    SaLayerOps.new(doc).add(&"paper", _registries.layer_types)
    var paper := doc.active_layer
    assert_true(paper.is_generated() and paper.get_index() < _upper.get_index(), "A paper lies under the drag's layer")
    _read.clear()


## The settings of the preset called *name* on the brush, in *colour*, without
## the radius taper, so the tip is the radius
## [method _radius_of] reads.
func _preset(name: String, colour: Color) -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseSettingsScript, untapered)
    _brush.settings.color = colour


## The tip radius of the preset called *name* on this document, in pixels.
func _radius_of(name: String) -> float:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            return float(entry["settings"]["radius"]) * mini(SIZE.x, SIZE.y)
    return 0.0


## The band on the active layer, at *thickness* millimetres, or below nought
## at the 0.3 thickness the test gives Grain Round, which ships at 0.
func _band(thickness: float) -> void:
    _preset("Grain Round", BAND_COLOUR)
    _brush.settings.thickness = thickness if thickness >= 0.0 else 0.3
    _stroke(BAND_FROM, BAND_TO, 1.0)


## The drag on the upper layer, with Push Colour Below *on*.
func _over(on: bool) -> void:
    _surface.easel.document.set_active_layer(_upper)
    _over_upper(on)


func _over_upper(on: bool) -> void:
    _preset("Bristle Flat", DRAG_COLOUR)
    _brush.settings.thickness = 0.4  # the drag THIN was measured against, Bristle Flat at its old 0.4 mm
    _brush.settings.push_colour_below = on
    _stroke(DRAG_FROM, DRAG_TO, DRAG_PRESSURE)


## A stroke from *from* to *to* at *pressure*, sample by sample four pixels
## apart, as a pen would lay it.
func _stroke(from: Vector2, to: Vector2, pressure: float) -> void:
    _brush.begin_stroke(from, pressure)
    var steps := ceili(from.distance_to(to) / 4.0)
    for i in range(1, steps + 1):
        _brush.add_sample(from.lerp(to, float(i) / steps), pressure)
    _brush.end_stroke()
    _read.clear()


## The window a reading takes at *x* along the drag's row: a few pixels along
## and most of the stroke's width across, for a tip of *radius*.
func _window(x: float, radius: float) -> Rect2i:
    var half := int(radius * ACROSS)
    return Rect2i(int(x) - ALONG, int(ROW) - half, 2 * ALONG + 1, 2 * half + 1)


## How far right of the band's middle its paint reaches, near the drag's row.
func _far_side() -> float:
    var far := BAND_X
    for y in range(int(ROW) - 4, int(ROW) + 5):
        for x in range(int(BAND_X), int(BAND_X) + 64):
            if _texel(_lower, Vector2i(x, y)).a >= PAINTED:
                far = maxf(far, float(x))
    return far


## The colour *layer* holds over *rect*, each texel's weighed by its alpha.
func _colour(layer: SaLayer, rect: Rect2i) -> Vector3:
    var sum := Vector3.ZERO
    var weight := 0.0
    for y in rect.size.y:
        for x in rect.size.x:
            var texel := _texel(layer, rect.position + Vector2i(x, y))
            sum += Vector3(texel.r, texel.g, texel.b) * texel.a
            weight += texel.a
    return sum / weight if weight > 0.0 else Vector3.ZERO


## How many texels of *rect* *layer* holds paint in.
func _painted(layer: SaLayer, rect: Rect2i) -> int:
    var count := 0
    for y in rect.size.y:
        for x in rect.size.x:
            if _texel(layer, rect.position + Vector2i(x, y)).a >= PAINTED:
                count += 1
    return count


## How far *reading* has moved from *own* towards *towards*, along the line
## between them, nought at *own* and one at *towards*.
static func _way(own: Vector3, towards: Vector3, reading: Vector3) -> float:
    var line := towards - own
    return (reading - own).dot(line) / line.length_squared()


static func _distance(one: Vector3, other: Vector3) -> float:
    return (one - other).length()


## *layer*'s texel at *pixel*, transparent where it holds no chunk.
func _texel(layer: SaLayer, pixel: Vector2i) -> Color:
    for grid: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid] as SaChunk
        var side := chunk.pixel_size()
        if Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side)) != grid:
            continue
        var key := [layer.get_instance_id(), grid]
        if not _read.has(key):
            @warning_ignore("static_called_on_instance")
            _read[key] = SaExport.get_texture_image_float(layer.get_field(grid))
        return (_read[key] as Image).get_pixelv(pixel - grid * side)
    return Color.TRANSPARENT
