## The Brush Tip page has an Angle row, the tip's fixed turn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tip holds the angle and every dab turns by it, so a row on the Brush Tip
## page has to show it. Here the row is typed into on the brush editor's Brush
## Tip page as a painter types, a tap is laid through the brush's own input,
## and the turn is read off the layer from the second moments of its alpha. A
## Krita preset whose tip is turned 30 degrees is imported and the row reads 30.
##
## **Detached, and the window is never shown**, for the reason
## `test_editor_size_in_pixels.gd` gives: a `Window` in the tree maps a real OS
## window and the headless run waits on it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const StampModule = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseTipRow = preload("res://modules/sara-noise-brush-engine/tip/tip_row.gd")

## The tap's radius as the settings hold it, a share of the canvas's 256.
const RADIUS: float = 20.0 / 256.0
## Flat enough that the long axis is the tip's own and not the texel grid's.
const RATIO: float = 0.3
## Half the side of the square a tap's coverage is read over.
const WINDOW: int = 36
## Where the fuzzy taps land, a grid far enough apart that no two touch.
const TAPS: Array[Vector2] = [
    Vector2(48, 48),
    Vector2(128, 48),
    Vector2(208, 48),
    Vector2(48, 128),
    Vector2(128, 128),
    Vector2(208, 128),
    Vector2(48, 208),
    Vector2(128, 208),
    Vector2(208, 208),
]
## The Rotation option's strength for the fuzzy taps, a tenth of a half turn
## either way, so the spread is around the tip's own angle and not all round.
const FUZZY_STRENGTH: float = 0.1
## A Krita preset of its own name, so the store holds nothing else.
const ANGLED_NAME := "Sara fixture angled"

static var scratch_dir: String = SaDataRoot.path("test_tip_angle")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _window: SaBrushEditorWindow = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: Resource = _brush().settings
    settings.radius = RADIUS
    settings.stabilizer_mode = 0
    settings.tip.ratio = RATIO
    settings.tip.angle = 0.0


func after_each() -> void:
    if _window != null:
        _window.free()
        _window = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    ScratchFolder.clear(scratch_dir)


func _brush() -> ToolState:
    return _machine.active_tool


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The brush editor bound to the brush, walked to the Brush Tip page.
func _tip_page() -> SaBrushEditorWindow:
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), specs, _store(), "", 256.0)
    window.show_page(window.pages.index_of(StampModule.TIP_PAGE))
    return window


func _angle_slider() -> FactorSlider:
    return _window.pages.page_controls.control(&"tip_angle") as FactorSlider


## *text* typed into the row's field and Enter pressed, as a painter does it.
## The field is shown by hand rather than through `_start_editing`, whose focus
## grab a detached window cannot take, and the rest is the field's own path.
func _type(slider: FactorSlider, text: String) -> void:
    slider._line_edit.visible = true
    slider._line_edit.text = text
    slider._on_line_edit_submitted(text)


func _tap(at: Vector2) -> void:
    _brush().is_tablet = false
    _surface.view.mouse_position = at
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        _brush().handle_input(event)


## The row exists on the Brush Tip page beside Ratio, 0 to 360 degrees, and
## writes the tip's angle, which the tip holds in radians.
func test_the_row_sits_beside_ratio_and_reads_degrees() -> void:
    var keys: Array[StringName] = []
    var angle: SaOptionSpec = null
    for spec: SaOptionSpec in StampModule.tip_options():
        keys.append(spec.key)
        if spec.key == &"tip_angle":
            angle = spec
    assert_not_null(angle, "The stamp brush declares an Angle row")
    assert_eq(keys.find(&"tip_angle"), keys.find(&"tip_ratio") + 1, "straight after Ratio")
    assert_eq(angle.page, StampModule.TIP_PAGE, "on the Brush Tip page")
    assert_eq(angle.property, ^"tip:angle", "writing the tip's own angle")
    assert_almost_eq(angle.max_value * angle.display_scale, 360.0, 1e-6, "up to 360 degrees")
    assert_eq(angle.suffix, "°", "shown in degrees")
    assert_true(angle.shown_when.is_empty(), "and drawn for a picture as well as a generated tip")


## The noise engine's tip turns by the same number, so it declares the row too,
## the stamp's word for word under the same key.
func test_the_noise_brush_has_the_same_row() -> void:
    var stamp: SaOptionSpec = null
    for spec: SaOptionSpec in StampModule.tip_options():
        if spec.key == &"tip_angle":
            stamp = spec
    var noise: SaOptionSpec = null
    for spec: SaOptionSpec in NoiseTipRow.rows():
        if spec.key == &"tip_angle":
            noise = spec
    assert_not_null(noise, "The noise brush declares an Angle row")
    for field: String in ["label", "property", "min_value", "max_value", "step", "display_scale", "suffix", "tooltip"]:
        assert_eq(noise.get(field), stamp.get(field), "its %s is the stamp's" % field)


## 45 typed on a Ratio 0.3 tip, one dab, its long
## axis at 45 degrees.
func test_a_typed_45_lays_the_dab_at_45_degrees() -> void:
    _window = _tip_page()
    var slider := _angle_slider()
    assert_not_null(slider, "The Brush Tip page draws an Angle row")
    var preview := _window.pages.page_controls.control(&"tip_preview") as SaTipPreview
    assert_not_null(preview, "beside the tip preview")
    preview.render_now()
    var level: Array = preview.preview_report()["bounds"]
    _type(slider, "45")
    preview.render_now()
    var turned: Array = preview.preview_report()["bounds"]
    assert_eq(level.size(), 4, "The level tip draws, %s" % str(level))
    assert_eq(turned.size(), 4, "and so does the turned one, %s" % str(turned))
    if level.size() == 4 and turned.size() == 4:
        var level_shape := float(level[3]) / float(level[2])
        var turned_shape := float(turned[3]) / float(turned[2])
        assert_true(level_shape < 0.5, "The preview draws the level tip flat, %.2f as tall as wide" % level_shape)
        assert_true(turned_shape > 0.8, "and turns it with the row, %.2f as tall as wide at 45" % turned_shape)
    assert_almost_eq(rad_to_deg(_brush().settings.tip.angle), 45.0, 1e-4, "Typing 45 writes a quarter of PI on the tip")
    assert_eq(slider._label.text, "Angle: 45 °", "and the row reads it back in degrees")
    _tap(Vector2(128, 128))
    var painted := _painted_degrees(Vector2(128, 128))
    assert_true(_axial_gap(painted, 45.0) < 2.0, "The dab's long axis lies at %.2f degrees" % painted)
    assert_true(_axial_gap(painted, 0.0) > 40.0, "and not level")


## The first clause's second half: with Fuzzy per dab on the Rotation page the
## taps spread around 45 rather than all lying at it.
func test_fuzzy_per_dab_spreads_the_dabs_around_45() -> void:
    _window = _tip_page()
    _type(_angle_slider(), "45")
    var option: SaCurveOption = _brush().settings.rotation_option
    option.enabled = true
    option.strength = FUZZY_STRENGTH
    option.sensors.clear()
    option.set_sensor(SaSensor.create(SaSensor.Id.FUZZY_PER_DAB, true))
    var read: Array[float] = []
    for at: Vector2 in TAPS:
        _tap(at)
        read.append(_painted_degrees(at))
    var mean := 0.0
    var low := INF
    var high := -INF
    for degrees: float in read:
        var off := _signed_gap(degrees, 45.0)
        mean += off
        low = minf(low, off)
        high = maxf(high, off)
    mean /= read.size()
    var reach := rad_to_deg(PI * FUZZY_STRENGTH) + 2.0
    assert_true(high - low > 5.0, "The taps lie at different angles, %.1f to %.1f degrees off 45: %s" % [low, high, str(read)])
    assert_true(low > -reach and high < reach, "every one within the option's reach of 45, %.1f degrees" % reach)
    assert_true(absf(mean) < 0.6 * reach, "and spread around it, a mean of %.1f degrees off" % mean)


## A Krita preset whose tip is turned 30 degrees,
## in the radians Krita writes, imports onto the row as 30.
func test_a_krita_tip_turned_30_degrees_reads_30_on_the_row() -> void:
    var store := _store()
    var params := KppFixtures._common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="%.7f">' % deg_to_rad(30.0)
            + ' <MaskGenerator ratio="0.5" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    var bytes := KppFixtures._kpp(KppFixtures._preset_xml(ANGLED_NAME, params, []), "zTXt")
    var result := SaKppImport.import_preset(SaKppReader.read_bytes(bytes, "angled.kpp"), store)
    assert_eq(String(result["error"]), "", "The preset imports")
    SaPresetStore.copy_settings(store.load_preset(String(result["name"])), _brush().settings)
    assert_almost_eq(rad_to_deg(_brush().settings.tip.angle), 30.0, 1e-4, "Its tip holds the 30 degrees")
    _window = _tip_page()
    assert_eq(_angle_slider()._label.text, "Angle: 30 °", "and the Angle row reads 30")


## How far apart two axes are in degrees, an axis and its reverse being one.
func _axial_gap(a: float, b: float) -> float:
    return absf(_signed_gap(a, b))


func _signed_gap(a: float, b: float) -> float:
    return fposmod(a - b + 90.0, 180.0) - 90.0


## The axis the tap's paint about *at* lies along, in degrees, turning the way
## the tip's angle does on screen.
func _painted_degrees(at: Vector2) -> float:
    var layer := _surface.easel.document.active_layer
    var images := {}
    var total := 0.0
    var mean := Vector2.ZERO
    var samples: Array[Vector3] = []
    for y in range(int(at.y) - WINDOW, int(at.y) + WINDOW):
        for x in range(int(at.x) - WINDOW, int(at.x) + WINDOW):
            var a := _alpha_at(layer, Vector2i(x, y), images)
            if a <= 0.0:
                continue
            samples.append(Vector3(x + 0.5, y + 0.5, a))
            total += a
            mean += a * Vector2(x + 0.5, y + 0.5)
    if total <= 0.0:
        return NAN
    mean /= total
    var sxx := 0.0
    var syy := 0.0
    var sxy := 0.0
    for sample: Vector3 in samples:
        var dx := sample.x - mean.x
        var dy := sample.y - mean.y
        sxx += sample.z * dx * dx
        syy += sample.z * dy * dy
        sxy += sample.z * dx * dy
    return rad_to_deg(0.5 * atan2(2.0 * sxy, sxx - syy))


## The layer's alpha at a document pixel, each chunk read back once into
## *images*.
func _alpha_at(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return 0.0
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    if not images.has(grid):
        @warning_ignore("static_called_on_instance")
        images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (images[grid] as Image).get_pixelv(pixel - grid * side).a
