## The crop tool's Ratio row says what a locked rectangle does.
##
## `state_crop.gd` has no clamps, so a locked rectangle reaches past the canvas
## like a free one and the crop grows the document to it. The row's tooltip in
## `base/module.gd` must not say "a locked rectangle stays inside the canvas",
## which would tell a painter hovering the row about a limit the tool does not
## have.
##
## Three cases: the sentence on the spec, the sentence on the built row read the
## way the capture dump reads it and through `tr`, and the tool doing what the
## sentence now says, so the words and the drag cannot drift apart. The box is a live crop of the active
## layer, so the third case
## reads the square on the layer and the document's size left alone.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A locale nobody runs Sara in, so the lookup below can only be this suite's.
const LOCALE := "eo"


func _ratio_spec() -> SaOptionSpec:
    for spec: SaOptionSpec in BaseModule.crop_options():
        if spec.key == &"crop_ratio":
            return spec
    return null


## The fault the claim names, and the half of the fix a painter reads: the
## sentence no longer promises the canvas holds the rectangle, and it says what
## happens past the edge instead.
func test_the_ratio_tooltip_does_not_promise_the_clamp() -> void:
    var spec := _ratio_spec()
    assert_not_null(spec, "the crop tool declares its Ratio row")
    if spec == null:
        return
    assert_false(
        spec.tooltip.contains("inside the canvas"), "the tooltip no longer says the rectangle stays inside: %s" % spec.tooltip
    )
    assert_true(spec.tooltip.contains("past the canvas edge"), "it says a locked rectangle reaches past the edge")
    assert_true(spec.tooltip.begins_with("Lock the rectangle's shape."), "and it still says what the row is for")


## The built row carries the sentence through `tr`, and the dump's own reader
## finds it there. A translation is loaded for the one string, so an untranslated
## tooltip would read back in English and fail.
func test_the_row_reads_the_tooltip_through_tr() -> void:
    var spec := _ratio_spec()
    assert_not_null(spec, "the crop tool declares its Ratio row")
    if spec == null:
        return
    var translated := "Ŝlosu la formon de la rektangulo."
    var translation := Translation.new()
    translation.locale = LOCALE
    translation.add_message(spec.tooltip, translated)
    TranslationServer.add_translation(translation)
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LOCALE)

    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    machine.set_active_tool(&"crop")
    docker.sync_from_tool()

    var row := docker.find_child("CropRatioRow", true, false) as Control
    assert_not_null(row, "the crop tool has its Ratio row")
    if row != null:
        assert_eq(ToolOptionsDocker.row_tooltip(row), translated, "and the row's tooltip is the translated sentence")

    host.free()
    Fixtures.teardown(surface, machine)
    TranslationServer.set_locale(locale)
    TranslationServer.remove_translation(translation)


## What the sentence says, done by the tool: a square drawn over the right edge
## keeps its shape, and the layer's crop is that square, the columns past the
## old edge included, while the document stays the size it was.
func test_a_locked_crop_past_the_edge_keeps_the_whole_square() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    # A layer that carries a transform is smart and keeps its crop live, which
    # is the rectangle read below. An ordinary layer has its crop written in.
    SaLiveTransform.put(surface.get_document(), surface.get_document().active_layer, Basis.IDENTITY)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    # The crop is the skeleton's live transform, which a tool reaches through
    # the role registry a bare machine does not hand it.
    tool.roles = Fixtures.make_registries().roles
    tool.ratio = StateCropScript.Ratio.SQUARE
    # The Layer choice, since Canvas is the default.
    tool.mode = StateCropScript.Mode.LAYER

    surface.view.mouse_position = Vector2(400, 100)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(500, 300)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    var rect: Rect2i = tool.pending_rect()
    assert_eq(rect, Rect2i(400, 100, 200, 200), "the locked square reaches 88 columns past the 512 edge")

    assert_true(tool.crop_now(), "the crop happens")
    assert_eq(tool._layer_crop(), Rect2i(400, 100, 200, 200), "and the layer's crop is the whole square, not the part inside")
    assert_eq(tool.surface.get_document().canvas_size, Vector2i(512, 512), "while the document keeps its size")
    Fixtures.teardown(surface, machine)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
