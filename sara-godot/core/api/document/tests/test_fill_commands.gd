## Alt+Backspace fills the active layer
## with the foreground colour and Alt+Delete with the background, through the
## public command door like every other built-in.
##
## The scenario fill-chords proves the two chords on the running app. What
## is here is the part a screenshot cannot show: which colour landed to the
## bit, that the selection masked it, that it is one history step, and that a
## group and a locked layer decline the event rather than swallowing it.
##
## Adds the corner line: a fill
## with nothing selected covers the whole layer and says so, a fill inside a
## selection says nothing.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, because the proof is the pixels a fill wrote.
const REQUIRES_GPU := true

const CHORDS := {
    "fill_foreground": "Alt+Backspace",
    "fill_background": "Alt+Delete",
}


func test_both_fills_answer_to_the_chords_the_plan_named() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    for command_id: String in CHORDS:
        assert_true(registries.commands.has(StringName(command_id)), "%s is registered" % command_id)
        assert_eq(registries.commands.chord_text(StringName(command_id)), CHORDS[command_id], "%s answers to it" % command_id)
    Fixtures.teardown(surface)


func test_alt_backspace_lays_down_the_foreground_colour() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var was := _set_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))

    assert_true(registries.commands.execute(&"fill_foreground"), "The command runs")
    var pixel := _read_pixel(doc, Vector2i(0, 0))
    assert_almost_eq(pixel.r, 1.0, 0.01, "and the layer is the foreground red")
    assert_almost_eq(pixel.b, 0.0, 0.01, "with nothing of the background in it")
    assert_eq(doc.history.step_count(), 1, "as exactly one history step")

    _set_pair(was[0], was[1])
    Fixtures.teardown(surface)


func test_alt_delete_lays_down_the_background_colour() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var was := _set_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))

    assert_true(registries.commands.execute(&"fill_background"), "The command runs")
    var pixel := _read_pixel(doc, Vector2i(0, 0))
    assert_almost_eq(pixel.b, 1.0, 0.01, "and the layer is the background blue")
    assert_almost_eq(pixel.r, 0.0, 0.01, "with nothing of the foreground in it")
    assert_eq(doc.history.step_count(), 1, "as exactly one history step")

    _set_pair(was[0], was[1])
    Fixtures.teardown(surface)


## The mask belongs to `SaLayer.fill`, so this asks only that the command goes
## through it: a selection of the top left chunk leaves the one beside it alone.
func test_a_selection_holds_the_fill_inside_it() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var was := _set_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))
    doc.selection.select_rect(Rect2i(0, 0, 256, 256))

    assert_true(registries.commands.execute(&"fill_foreground"), "The command runs")
    assert_almost_eq(_read_pixel(doc, Vector2i(0, 0)).a, 1.0, 0.01, "the selected chunk is filled")
    assert_almost_eq(_read_pixel(doc, Vector2i(1, 0)).a, 0.0, 0.01, "and the one outside is untouched")

    _set_pair(was[0], was[1])
    Fixtures.teardown(surface)


func test_a_group_and_a_locked_layer_decline_the_chord() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var locked := doc.active_layer
    locked.is_locked = true

    assert_false(registries.commands.execute(&"fill_foreground"), "A locked layer declines the event")
    assert_eq(doc.history.step_count(), 0, "and nothing reached the history")

    locked.is_locked = false
    var group := SaLayerOps.new(doc).group_active()
    doc.set_active_layer(group)
    assert_false(registries.commands.execute(&"fill_foreground"), "A group declines it too")
    assert_eq(doc.history.step_count(), 1, "and only the grouping is on the history")

    Fixtures.teardown(surface)


## Krita fills the whole layer with nothing selected and so does Sara, and
## the fault was that it did so without a word. Both commands say so, on the
## route that is not a refusal, so a fill nobody turned away is not counted as
## one.
func test_a_fill_with_nothing_selected_says_it_filled_the_whole_layer() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var was := _set_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))
    assert_false(doc.selection.active, "Nothing is selected to begin with")

    for command_id: StringName in [&"fill_foreground", &"fill_background"]:
        var lines := _said(func() -> void: registries.commands.execute(command_id), EventBus.corner_notice)
        assert_eq(lines.size(), 1, "%s says one line" % command_id)
        assert_true(lines[0].contains("whole layer"), "%s says it took the whole layer" % command_id)
        assert_true(lines[0].contains("Nothing was selected"), "and why: %s" % lines[0])
        var refusals := _said(func() -> void: registries.commands.execute(command_id), EventBus.paint_refused)
        assert_eq(refusals, [], "%s is not a refusal, so the refusal route stays quiet" % command_id)

    _set_pair(was[0], was[1])
    Fixtures.teardown(surface)


func test_a_fill_inside_a_selection_says_nothing() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var was := _set_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))
    doc.selection.select_rect(Rect2i(0, 0, 256, 256))

    for command_id: StringName in [&"fill_foreground", &"fill_background"]:
        var lines := _said(func() -> void: registries.commands.execute(command_id), EventBus.corner_notice)
        assert_eq(lines, [], "%s says nothing while a selection holds it" % command_id)
    assert_almost_eq(_read_pixel(doc, Vector2i(1, 0)).a, 0.0, 0.01, "and the fill did stay inside the selection")

    _set_pair(was[0], was[1])
    Fixtures.teardown(surface)


## A fill that filled nothing has no whole layer to report, and it keeps the
## refusal it already had.
func test_a_refused_fill_reports_the_refusal_and_not_the_whole_layer() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    doc.active_layer.is_locked = true

    var notices := _said(func() -> void: registries.commands.execute(&"fill_foreground"), EventBus.corner_notice)
    assert_eq(notices, [], "A locked layer was not filled, so nothing is said about the whole layer")
    var refusals := _said(func() -> void: registries.commands.execute(&"fill_foreground"), EventBus.paint_refused)
    assert_eq(refusals.size(), 1, "and it still says the lock, once")

    doc.active_layer.is_locked = false
    Fixtures.teardown(surface)


## What *action* said on *bus_signal*, in order.
func _said(action: Callable, bus_signal: Signal) -> Array[String]:
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    bus_signal.connect(ear)
    action.call()
    bus_signal.disconnect(ear)
    return said


## The pair is an autoload the whole process shares, so a test that moves it
## puts it back. Returns what it was, as [foreground, background].
func _set_pair(foreground: Color, background: Color) -> Array:
    var was := [SaColors.foreground, SaColors.background]
    SaColors.foreground = foreground
    SaColors.background = background
    return was


## The first texel of one chunk of the active layer, straight off the GPU.
func _read_pixel(doc: SaDocument, grid_pos: Vector2i) -> Color:
    var chunk: SaTexture = doc.active_layer.get_or_create_field(grid_pos)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    if data.size() < 16:
        return Color(0, 0, 0, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))
