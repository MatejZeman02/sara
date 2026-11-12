## The eyedropper picks what the view shows, with the filters
## on, and the Sample row says what is picked.
##
## Sampling colour with an effect attached samples the final view, not unfiltered
## data, and the tool options choose what to sample. The view is the composite, every attached and group
## filter
## applied, and the layer is the active layer as painted. Both are held here at
## sample sizes 1 and 9 over a flat colour under the fixture's invert, whose
## change is plain, and the readback is held to the square in both.
##
## A press on the texel the last press picked must not answer the colour from
## before a filter was attached, as a cache that knew the position and not the
## picture would.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const SIZE := Vector2i(64, 64)
const AT := Vector2(32.5, 32.5)
## The colour painted, far enough from its inverse that a pick of either is
## told apart at a glance.
const PAINTED := Color(0.8, 0.3, 0.1, 1.0)
const BASE_MODULE_ID := &"sara-base-modules"

static var scratch_path: String = SaDataRoot.path("test_d31_eyedropper_sample_from.cfg")

var _saved_path: String = ""
var _surface: SaSurface = null


## The easel, answering the snapshot door as it always does and noting each
## rectangle it was asked for, so a suite can hold the readback to the square.
class SpyEasel:
    extends SaEasel

    var asked: Array[Rect2i] = []

    func snapshot_merged(rect: Rect2i) -> SaMergedSnapshot:
        asked.append(rect)
        return super.snapshot_merged(rect)


## The eyedropper with a pointer the suite places, the shape
## `test_a_pick_joins_the_recent_row.gd` uses: the tool samples where the pointer
## is rather than where an event says.
class ScriptedPointer:
    extends "res://modules/sara-base-modules/base/tools/state_eyedropper.gd"

    var at := Vector2(32.5, 32.5)

    func get_document_mouse_position() -> Vector2:
        return at


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    DirAccess.remove_absolute(_scratch())


func after_each() -> void:
    StateEyedropperScript.keep_choice_in(null)
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null
    SaSettings.settings_path = _saved_path
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    DirAccess.remove_absolute(_scratch())
    DirAccess.remove_absolute(_scratch() + SaSettings.BACKUP_SUFFIX)


func _scratch() -> String:
    return ProjectSettings.globalize_path(scratch_path)


## A surface over a spy easel whose compositor answers the fixture invert, with
## the active layer painted flat in [const PAINTED] and composited. With
## *on_group* the invert is attached to a group made around the layer rather than
## to the layer itself, and with *filtered* false nothing is attached.
func _painted(filtered: bool = true, on_group: bool = false) -> SaSurface:
    var easel := SpyEasel.new()
    easel.name = "SaEasel"
    easel.setup(SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(Bench.InvertFilter.new(), Bench.OWNER)
    easel.compositor.filter_chain.registry = filters
    var doc := easel.document
    var layer := doc.active_layer
    layer.fill(PAINTED)
    if filtered:
        var node := SaLayerOps.new(doc).group_active() if on_group else layer
        SaFilterOps.new(doc).attach(node, Bench.INVERT)
    Bench.composite(easel)
    _surface = SaSurface.create(&"test", easel, Fixtures.FakeView.new())
    return _surface


func _eyedropper(surface: SaSurface, from: StateEyedropperScript.SampleFrom, size: int) -> ScriptedPointer:
    var eyedropper := ScriptedPointer.new()
    eyedropper.surface = surface
    eyedropper.sample_from = from
    eyedropper.sample_size = size
    return eyedropper


func _assert_colour(picked: Color, expected: Color, what: String) -> void:
    assert_almost_eq(picked.r, expected.r, 0.01, "%s, red" % what)
    assert_almost_eq(picked.g, expected.g, 0.01, "%s, green" % what)
    assert_almost_eq(picked.b, expected.b, 0.01, "%s, blue" % what)
    assert_almost_eq(picked.a, expected.a, 0.01, "%s, alpha" % what)


## The largest per-channel distance between two colours.
func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


## The first half: in the view mode the pick is the filtered colour.
func test_the_view_picks_the_filtered_colour_at_one_and_nine() -> void:
    var surface := _painted()
    var shown := Bench.texel(surface.easel.output, Vector2i(AT))
    assert_true(_apart(shown, PAINTED) > 0.3, "The invert changes the painted colour plainly: %s" % shown)
    for size: int in [1, 9]:
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.VIEW, size)
        _assert_colour(
            eyedropper.pick_color_at_pos(AT), shown, "The view at a sample size of %d picks what the view shows" % size
        )


## And a filter attached to a group is in the view as much as one on the layer.
func test_the_view_picks_a_groups_filter_too() -> void:
    var surface := _painted(true, true)
    var shown := Bench.texel(surface.easel.output, Vector2i(AT))
    assert_true(_apart(shown, PAINTED) > 0.3, "The group's invert changes the painted colour plainly: %s" % shown)
    for size: int in [1, 9]:
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.VIEW, size)
        _assert_colour(eyedropper.pick_color_at_pos(AT), shown, "The view at a sample size of %d takes the group's filter" % size)


## The second half: in the layer mode the pick is the colour as painted.
func test_the_layer_picks_the_painted_colour_at_one_and_nine() -> void:
    var surface := _painted()
    for size: int in [1, 9]:
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, size)
        _assert_colour(
            eyedropper.pick_color_at_pos(AT), PAINTED, "The layer at a sample size of %d picks the painted colour" % size
        )


## The readback is still the square, the eyedropper's exception under hard rule
## 1: the view asks the snapshot door for the square alone and the layer copies
## into a texture the square's size, one texel at a sample size of one.
func test_the_readback_is_the_square() -> void:
    var surface := _painted()
    var spy := surface.easel as SpyEasel
    var centre := Vector2i(AT)
    for size: int in [1, 9]:
        spy.asked.clear()
        var view := _eyedropper(surface, StateEyedropperScript.SampleFrom.VIEW, size)
        view.pick_color_at_pos(AT)
        @warning_ignore("integer_division")
        var square := Rect2i(centre - Vector2i(size / 2, size / 2), Vector2i(size, size))
        assert_eq(spy.asked, [square] as Array[Rect2i], "The view at %d asks the door for the square once" % size)

        var layer := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, size)
        layer.pick_color_at_pos(AT)
        assert_eq(spy.asked.size(), 1, "and the layer at %d does not ask it at all" % size)
        assert_not_null(layer._pixel_readback, "The layer at %d read back through its own texture" % size)
        if layer._pixel_readback != null:
            assert_eq(layer._pixel_readback.size, Vector2i(size, size), "which is the square at %d" % size)


## A press on the texel the last press picked must not answer from the cache, or
## a filter attached in between would not be in the pick. A press is a new pick.
func test_a_press_after_a_filter_is_attached_picks_the_filtered_colour() -> void:
    var surface := _painted(false)
    var doc := surface.get_document()
    var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.VIEW, 1)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    eyedropper.handle_input(press)
    _assert_colour(eyedropper._picked, doc.color_space.to_display(PAINTED), "The first press picks the painted colour")

    SaFilterOps.new(doc).attach(doc.active_layer, Bench.INVERT)
    Bench.composite(surface.easel)
    var shown := Bench.texel(surface.easel.output, Vector2i(AT))
    assert_true(_apart(shown, PAINTED) > 0.3, "The invert is in the picture now: %s" % shown)
    eyedropper.handle_input(press)
    _assert_colour(
        eyedropper._picked, doc.color_space.to_display(shown), "and a press on the same texel picks the filtered colour"
    )


## The choice is kept in the base module's own preferences while the module is
## registered, so every eyedropper reads the one the painter made and a second
## launch opens on it.
func test_the_choice_outlives_the_session() -> void:
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = _scratch()
    SaSettings.load_settings()
    var registries := Fixtures.make_registries()
    var context := registries.context.for_module(BASE_MODULE_ID)
    StateEyedropperScript.keep_choice_in(context)

    var fresh := StateEyedropperScript.new()
    assert_eq(fresh.sample_from, StateEyedropperScript.SampleFrom.VIEW, "A profile that holds no choice picks the view")
    var first := StateEyedropperScript.new()
    first.sample_from = StateEyedropperScript.SampleFrom.LAYER
    var other := StateEyedropperScript.new()
    assert_eq(other.sample_from, StateEyedropperScript.SampleFrom.LAYER, "Another surface's eyedropper reads the choice")
    assert_eq(
        SaSettings.module_preference(BASE_MODULE_ID, StateEyedropperScript.SAMPLE_FROM_KEY),
        int(StateEyedropperScript.SampleFrom.LAYER),
        "which is in the module's own section"
    )

    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    assert_eq(StateEyedropperScript.new().sample_from, StateEyedropperScript.SampleFrom.LAYER, "and a second launch opens on it")

    StateEyedropperScript.keep_choice_in(null)
    assert_eq(
        StateEyedropperScript.new().sample_from,
        StateEyedropperScript.SampleFrom.VIEW,
        "With no module behind it a state remembers nothing"
    )


## A hand-edited profile is not a promise.
func test_a_stored_value_that_is_neither_reads_as_the_view() -> void:
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = _scratch()
    SaSettings.load_settings()
    var context := Fixtures.make_registries().context.for_module(BASE_MODULE_ID)
    StateEyedropperScript.keep_choice_in(context)
    for stored: Variant in [7, -1, "layer", 0.5]:
        context.set_preference(StateEyedropperScript.SAMPLE_FROM_KEY, stored)
        assert_eq(
            StateEyedropperScript.new().sample_from, StateEyedropperScript.SampleFrom.VIEW, "%s reads as the view" % str(stored)
        )


## The module hands its context over at `register` and takes it back at
## `unregister`, so a state built after the module is gone keeps nothing.
func test_the_module_hands_its_context_over_and_takes_it_back() -> void:
    # The context `Fixtures.make_tool_registry` builds, which holds a role
    # registry for the base module's engines and no filter registry.
    var context := (
        SaContext
        . create(
            SaToolRegistry.new(),
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
        . for_module(BASE_MODULE_ID)
    )
    var module := BaseModule.new()
    module.register(context)
    assert_eq(StateEyedropperScript._live_preferences(), context, "The registered module's context keeps the choice")
    module.unregister(context)
    assert_null(StateEyedropperScript._live_preferences(), "and an unregistered module leaves none behind")


## The Sample row takes the Merged switch's place on the eyedropper, a choice
## of the two, on the tool and on the bar, hidden on a fresh bar the way Merged
## was. The wand keeps its own Merged.
func test_the_sample_row_replaces_merged_on_the_eyedropper() -> void:
    var specs := BaseModule.eyedropper_options()
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in specs:
        keys.append(spec.key)
    assert_eq(keys, [&"sample_size", &"sample_from"] as Array[StringName], "The eyedropper declares its size and its Sample row")
    var from := specs[1]
    assert_eq(from.kind, SaOptionSpec.Kind.ENUM, "a choice")
    var ids: Array = []
    var labels: Array = []
    for choice: Dictionary in from.choices:
        ids.append(choice["id"])
        labels.append(choice["label"])
    assert_eq(ids, [StateEyedropperScript.SampleFrom.VIEW, StateEyedropperScript.SampleFrom.LAYER], "of the view and the layer")
    assert_eq(labels, ["View", "Layer"], "named for what they read")
    assert_true(from.on_tool and from.bar and from.bar_hidden, "on the tool, and on the bar a tick away")
    var wand_keys: Array[StringName] = []
    for spec: SaOptionSpec in BaseModule.wand_options():
        wand_keys.append(spec.key)
    assert_true(wand_keys.has(&"sample_merged"), "The wand keeps its Merged")
