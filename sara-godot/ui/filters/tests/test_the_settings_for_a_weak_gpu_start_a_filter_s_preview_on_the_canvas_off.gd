## A filter's preview on the canvas starts as
## `SaSettings.filter_preview_on_canvas` says, which the settings for a weak GPU
## write off and Defaults writes back on. It is off by default only where
## toaster mode is on, so a fresh profile
## still opens it on, and the switch stays live when it opens off.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false
var _was_preview: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _was_preview = SaSettings.filter_preview_on_canvas
    _host = Node.new()
    _host.name = "B10TestHost"
    EventBus.add_child(_host)
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _doc.fill_layer(Color(0.25, 0.5, 0.75, 1.0), _doc.active_layer)
    Bench.composite(_easel)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    _registry.register(Bench.threshold(), &"sara-base-modules")
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    SaSettings.filter_preview_on_canvas = _was_preview
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


func test_a_fresh_profile_starts_the_preview_on() -> void:
    var fresh := SaSettingsValues.new()
    assert_true(fresh.filter_preview_on_canvas, "a fresh profile has it on")
    fresh.free()
    SaSettings.filter_preview_on_canvas = true
    _window.open_filter(&"sara-base-modules.threshold")
    assert_true(_window.dialog.canvas_box.button_pressed, "the switch opens pressed")
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "and the canvas shows the pass")


func test_off_starts_the_switch_unpressed_and_live_and_the_canvas_clear() -> void:
    SaSettings.filter_preview_on_canvas = false
    _window.open_filter(&"sara-base-modules.threshold")
    var box := _window.dialog.canvas_box
    assert_false(box.button_pressed, "the switch opens unpressed")
    assert_false(box.disabled, "and is not dimmed")
    assert_not_null(_window.context.point, "the filter still ran its first preview")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "the canvas shows nothing of it")
    box.button_pressed = true
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "ticking the switch turns the preview on")


func test_the_light_mode_writes_it_off_and_defaults_writes_it_on() -> void:
    var settings := SaSettingsValues.new()
    assert_true(SaSettingsPerformance.light_values().has("filter_preview_on_canvas"), "it is a value of the light mode")
    assert_eq(SaSettingsPerformance.light_values().size(), 5, "the fifth")
    var moved := SaSettingsPerformance.apply_light(settings)
    assert_true(moved.has("filter_preview_on_canvas"), "the light mode moved it")
    assert_false(settings.filter_preview_on_canvas, "to off")
    settings.filter_preview_on_canvas = true
    assert_true(settings.filter_preview_on_canvas, "a painter may move it alone, nothing remembers the mode")
    SaSettingsPerformance.apply_light(settings)
    var back := SaSettingsPerformance.apply_defaults(settings)
    assert_true(back.has("filter_preview_on_canvas"), "Defaults moved it back")
    assert_true(settings.filter_preview_on_canvas, "to on")
    settings.free()


func test_the_page_and_the_offer_name_it() -> void:
    var moved: Array[String] = ["filter_preview_on_canvas"]
    var said := SaPerformancePage.summary(moved, SaPerformancePage.WEAK_GPU_SET, "nothing")
    SaSettings.filter_preview_on_canvas = false
    said = SaPerformancePage.summary(moved, SaPerformancePage.WEAK_GPU_SET, "nothing")
    assert_true(said.contains("Start a filter's preview on the canvas: Off."), said)
    var offer := SaLightModeOffer.new()
    var on := offer.find_child("LightModeOfferOn", true, false) as Button
    assert_true(on != null and on.tooltip_text.contains("filter preview"), "the offer's tooltip lists it")
    offer.free()
