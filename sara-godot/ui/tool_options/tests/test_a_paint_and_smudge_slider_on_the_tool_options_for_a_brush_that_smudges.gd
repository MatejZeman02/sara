## A Paint and Smudge slider on the Tool Options docker and the
## bar, for a brush that smudges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Mixing paint and smudge is awkward with the brush's Colour Rate on the
## editor's smudge page alone. The slider is that Colour Rate beside Opacity, smudge at the left and paint at the right, drawn
## for a brush whose Smudge Pickup is ticked and for no other.
##
## Built the way the app builds it: the modules through the door, a machine
## bound to a canvas of two bands of paint, the real bar over a scratch store
## holding the shipped presets, the docker detached, and the brush editor bound
## and never shown, for the reason `test_ticks_follow_a_loaded_preset.gd` gives.
## The drag is a press, a motion and a release handed to the root window through
## `Input.parse_input_event`, which the engine's own GUI pass gives the slider.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript := preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The canvas, the brush and the composite need a RenderingDevice.
const REQUIRES_GPU := true

const KEY := &"paint_and_smudge"

## Two chunks across, one band of paint each, and the stroke along the middle.
const CANVAS := Vector2i(512, 256)
const ROW: float = 128.0
const FROM_X: float = 60.0
const TO_X: float = 450.0
const STEPS: int = 60

const RED := Color(0.85, 0.15, 0.1, 1.0)
const YELLOW := Color(0.9, 0.8, 0.1, 1.0)
const INK := Color(0.1, 0.2, 0.8, 1.0)

## Where the slider is put on the root window for the drag, and the least size
## it is given there, more when its own minimum asks for more.
const SLIDER_AT := Vector2(40.0, 40.0)
const SLIDER_SIZE := Vector2(200.0, 24.0)

## How near the brush's colour a texel of the paint-only stroke reads, the
## largest channel apart. The stroke builds Oil Smudge's flow up over the red
## and the yellow, so a share of the ground under a texel the dabs left thin
## would read as tenths, and a carried red as more.
const NEAR_INK: float = 0.02

static var scratch_dir: String = SaDataRoot.path("test_presets")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _bar: ToolOptionsBar = null
var _docker: ToolOptionsDocker = null
var _foreground: Color = Color.BLACK


func before_each() -> void:
    _clear()
    _foreground = SaColors.foreground
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _host = Control.new()
    _host.name = "U85Host"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.install_shipped(_machine.get_tool(&"brush").get("settings"), ShippedPresetsScript)
    _bar._ready()
    _docker = ToolOptionsDocker.new()
    _docker.target_tool_machine = _machine


func after_each() -> void:
    SaColors.foreground = _foreground
    if _docker != null:
        _docker.free()
        _docker = null
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _clear()


func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


func _settings() -> SaStampBrushSettings:
    return _machine.get_tool(&"brush").get("settings") as SaStampBrushSettings


## *name* loaded through the bar, the way the preset button loads it, with the
## docker told as `EventBus.preset_loaded` tells it.
func _load(preset_name: String) -> void:
    assert_true(_bar.preset_box.load_preset(preset_name), "%s loads through the bar" % preset_name)
    _docker._on_preset_loaded(preset_name)
    # The surfaces sync in the frame after a load, and this reads them now.
    _bar.after.settle_all()
    _docker.after.settle_all()


## Whether the bar draws the slider for the brush in hand, the question its
## layout asks of every control before it shows one.
func _on_bar() -> bool:
    var slider := _bar.control_for(KEY)
    return slider != null and _bar.shows_for_active_tool(slider)


## Whether the docker draws a row for the slider, or names it on its foot line
## as one the bar is showing.
func _in_docker() -> bool:
    _docker.sync_from_tool()
    var row := _docker._rows.get(KEY, null) as Control
    return (row != null and row.visible) or _docker._foot_line.text.contains(tr("Paint and Smudge"))


## A left press at *at* on the root window, or its release.
func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    event.global_position = at
    return event


func _send(event: InputEvent) -> void:
    Input.parse_input_event(event)
    Input.flush_buffered_events()


## A hand's drag on the bar's slider from its middle to past its right end.
func _drag_to_the_paint_end() -> FactorSlider:
    var slider := _bar.control_for(KEY) as FactorSlider
    slider.visible = true
    slider.set_global_position(SLIDER_AT)
    slider.size = SLIDER_SIZE.max(slider.get_combined_minimum_size())
    var box := slider.get_global_rect()
    var middle := box.get_center()
    var past := Vector2(box.end.x + 30.0, middle.y)
    _send(_button(middle, true))
    _send(_motion(middle.lerp(past, 0.5)))
    _send(_motion(past))
    _send(_button(past, false))
    return slider


## The ask, Oil Smudge's half: the slider is drawn, a real drag takes it to the
## paint end, the editor's Colour Rate reads one and ticked, the preset reads
## changed, and the stroke lays the brush's colour and none of the red and the
## yellow it crosses.
func test_oil_smudge_dragged_to_paint_reads_colour_rate_one_and_lays_the_brush_alone() -> void:
    _load("Oil Smudge")
    var settings := _settings()
    assert_true(settings.smudge_pickup_option.enabled, "Oil Smudge smudges as it ships")
    assert_true(_on_bar(), "The bar draws Paint and Smudge for a brush that smudges")
    assert_true(_in_docker(), "and the docker draws it or names it as the bar's")
    var slider := _bar.control_for(KEY) as FactorSlider
    assert_almost_eq(slider.value, 0.5, 1e-6, "The slider reads Oil Smudge's Colour Rate")
    var editor := _editor()
    assert_false(editor.preset_bar.is_dirty(), "The editor reads Oil Smudge unchanged before the drag")

    _drag_to_the_paint_end()
    assert_almost_eq(slider.value, 1.0, 1e-6, "The drag puts the slider at the paint end")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 1.0, 1e-6, "and writes Colour Rate one")
    var page := _page(editor, "Colour Rate")
    assert_true(page >= 0, "The editor has a Colour Rate page")
    var option := editor.pages.curve_option_at(page) as SaCurveOption
    assert_true(option == settings.smudge_color_rate_option, "whose option is the brush's own")
    assert_true(option.enabled, "ticked")
    assert_almost_eq(option.strength, 1.0, 1e-6, "and at one in the editor")
    assert_true(editor.preset_bar.is_dirty(), "The preset reads changed, as after any edit")
    editor.free()

    var painted := _stroke()
    var most := 0.0
    for x in range(160, 420, 20):
        var texel := painted.get_pixel(x, int(ROW))
        most = maxf(most, maxf(maxf(absf(texel.r - INK.r), absf(texel.g - INK.g)), absf(texel.b - INK.b)))
    assert_true(most < NEAR_INK, "The stroke lays the brush's colour alone, %.4f from it at most" % most)
    # Not blind: the same stroke at Oil Smudge's own half carries the red.
    settings.smudge_color_rate_option.strength = 0.5
    var mixed := _stroke().get_pixel(200, int(ROW))
    assert_true(mixed.r > INK.r + 0.15, "At a half the stroke carries the red under it, red %.3f" % mixed.r)


## The ask, the other half: a brush that does not smudge draws no slider on
## either surface, and loading Oil Smudge after it draws it again.
func test_a_brush_that_does_not_smudge_reads_no_slider() -> void:
    _load("Oil Smudge")
    assert_true(_on_bar(), "Oil Smudge draws the slider")
    _load("Paint")
    assert_false(_settings().smudge_pickup_option.enabled, "Paint does not smudge")
    assert_false(_on_bar(), "The bar draws no slider for Paint")
    assert_false(_in_docker(), "and the docker neither draws it nor names it")
    _load("Oil Smudge")
    assert_true(_on_bar(), "Oil Smudge again draws it again")


## An unticked Colour Rate reads nought on the slider, which is the pure smudge
## it paints, and the slider's write ticks it, so a drag to paint paints. A rate
## with a sensor curve keeps the curve and has its strength moved.
func test_the_slider_ticks_the_rate_and_keeps_its_curve() -> void:
    _load("Oil Smudge")
    var option := _settings().smudge_color_rate_option
    option.enabled = false
    var pressure := SaSensor.create(SaSensor.Id.PRESSURE, true)
    option.set_sensor(pressure)
    _bar._sync_ui_from_settings()
    var slider := _bar.control_for(KEY) as FactorSlider
    assert_almost_eq(slider.value, 0.0, 1e-6, "Unticked, the slider reads nought, a pure smudge")
    _drag_to_the_paint_end()
    assert_true(option.enabled, "The drag ticks Colour Rate")
    assert_almost_eq(option.strength, 1.0, 1e-6, "and moves its strength")
    assert_true(option.sensor_for(SaSensor.Id.PRESSURE) != null, "and the pressure sensor stays on it")
    assert_eq(option.active_sensors().size(), 1, "still the one sensor it read")


## Smudge Pickup switched off in the brush editor takes the slider off the bar
## at once, the bar laid out again, and switched on brings it back.
func test_the_editors_smudge_pickup_switch_reaches_the_bar_at_once() -> void:
    _load("Oil Smudge")
    var editor := _editor()
    var page := _page(editor, "Smudge Pickup")
    assert_true(page >= 0, "The editor has a Smudge Pickup page")
    var laid_out := [0]
    var count := func() -> void: laid_out[0] += 1
    _bar.controls_changed.connect(count)
    editor.pages.set_page_enabled(page, false)
    assert_false(_settings().smudge_pickup_option.enabled, "The switch turns Smudge Pickup off")
    assert_false(_bar._rules_held.get(KEY, true), "and the bar's held answer for the slider is no")
    assert_eq(laid_out[0], 1, "The bar lays itself out again once, with no sync asked")
    editor.pages.set_page_enabled(page, true)
    assert_true(_bar._rules_held.get(KEY, false), "Switched on, the answer is yes again")
    assert_eq(laid_out[0], 2, "and the bar laid out again")
    _bar.controls_changed.disconnect(count)
    editor.free()


func _editor() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    window.bind_tool(_machine.get_tool(&"brush"), specs, _bar.preset_store, _bar.selected_preset_name())
    return window


func _page(editor: SaBrushEditorWindow, title: String) -> int:
    for i in editor.pages.count():
        if editor.pages.title_at(i) == title:
            return i
    return -1


## One stroke of the brush in hand over the two bands, through the tool's own
## input, and the composite it leaves.
func _stroke() -> Image:
    var document := _surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    document.active_layer.get_or_create_chunk(Vector2i(1, 0)).clear(YELLOW)
    document.invalidate_chunks([Vector2i.ZERO, Vector2i(1, 0)])
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var settings := _settings()
    settings.color = INK
    SaColors.foreground = INK
    var brush := _machine.get_tool(&"brush")
    var from := Vector2(FROM_X, ROW)
    var to := Vector2(TO_X, ROW)
    _surface.view.mouse_position = from
    var hover := InputEventMouseMotion.new()
    hover.pressure = 1.0
    brush.handle_input(hover)
    brush.handle_input(_pen(true))
    for i in range(1, STEPS + 1):
        _surface.view.mouse_position = from.lerp(to, float(i) / float(STEPS))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        brush.handle_input(motion)
    brush.handle_input(_pen(false))
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(_surface.easel)
    assert_not_null(image, "The canvas reads back")
    return image


func _pen(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
