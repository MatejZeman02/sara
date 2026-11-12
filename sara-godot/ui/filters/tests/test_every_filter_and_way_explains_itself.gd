## Every filter says what it does where the Add Adjustment Layer
## browser asks, and Bake, Attach and Layer each say what the way does.
##
## The fault: the
## browser's detail column read "This filter carries no description" for
## Brightness/Contrast, Hue/Saturation/Lightness and Levels, and the toggle's
## stops were not seen to explain themselves. The six adjustments declare an
## `action_name()`, so their command is not under the name their key spells,
## and the browser asked for that one and found nothing. It now reads the
## filter's own sentence, the string the Filter menu's row reads.
##
## Windowless for the browser, as `test_filter_browser.gd` is, and one dialog
## on a bench canvas for the way toggle's tips.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const FALLBACK := "This filter carries no description. Open it to see what it offers."


## A filter that says nothing, for the fallback to the command.
class SilentFilter:
    extends SaFilter

    func title() -> String:
        return "Silent"

    func run(_ctx: SaFilterContext) -> void:
        pass


var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## A context of its own with the whole base module registered, the way the
## loader does it, so a filter added later is counted without this suite
## naming it.
func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    return registries


func test_every_registered_filter_has_a_sentence_in_the_browser() -> void:
    var registries := _registries()
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    var keys := registries.filters.list_keys()
    assert_true(keys.size() >= 15, "the six adjustments and the usual set are registered: %d" % keys.size())
    for key: StringName in keys:
        var filter := registries.filters.get_filter(key)
        var said := docker.browser.sentence_for(key)
        assert_false(said.is_empty(), "%s says what it does through the browser's own lookup" % key)
        assert_eq(said, filter.sentence(), "and it is the filter's own string, the one the Filter menu reads: %s" % key)
    docker.free()


func test_the_adjustments_are_described_though_they_declare_an_action() -> void:
    var registries := _registries()
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    var declared := 0
    for key: StringName in registries.filters.list_keys():
        var filter := registries.filters.get_filter(key)
        if String(filter.action_name()).is_empty():
            continue
        declared += 1
        docker.browser.pick(key)
        var shown: String = docker.describe()["sentence"]
        assert_true(shown != FALLBACK, "%s declares an action, which hid its sentence, and no longer reads as undescribed" % key)
        assert_eq(shown, filter.sentence(), "the detail column says the filter's sentence: %s" % key)
    assert_true(declared >= 6, "the six adjustments declare an action: %d" % declared)
    docker.free()


func test_a_command_registered_by_hand_still_answers_when_the_filter_is_silent() -> void:
    var registries := _registries()
    var silent := SilentFilter.new()
    registries.filters.register(silent, &"alpha")
    var key := SaFilterRegistry.key_for(&"alpha", silent)
    var command := SaCommandDescriptor.create(SaFilterRegistry.command_for(key, silent), silent.title(), Callable())
    command.sentence = "Said by the command."
    registries.commands.register(command, &"alpha")
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    var said := docker.browser.sentence_for(key)
    assert_eq(said, "Said by the command.", "the command is the fallback for a filter that says nothing")
    assert_eq(docker.browser.sentence_for(&"alpha.no_such_filter"), "", "and a key nothing registered says nothing")
    docker.free()


func test_each_way_explains_itself_on_hover() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "S41TestHost"
    EventBus.add_child(host)
    var easel := Bench.easel(Vector2i(256, 256))
    easel.document.set_active_layer(easel.document.get_node("Layer 1") as SaLayer)
    var registry := easel.compositor.filter_chain.registry
    var hsl := SaHueSaturationLightnessFilter.new()
    registry.register(hsl, &"sara-base-modules")
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.layer_types = Fixtures.make_registries().layer_types
    window.watch(registry)
    host.add_child(window)

    assert_true(registry.invoke(SaFilterRegistry.key_for(&"sara-base-modules", hsl)), "the Filter menu's door opens the dialog")
    var toggle := window.way_toggle
    assert_not_null(toggle, "the dialog draws the way toggle")
    if toggle != null:
        if toggle.size.x <= 0.0:
            toggle.size = toggle.get_combined_minimum_size()
        var seen: Array[String] = []
        for index in SaFilterDialogWindow.WAYS.size():
            var way := SaFilterDialogWindow.WAYS[index]
            var tip := toggle._get_tooltip(Vector2(toggle.stop_x(index), 1.0))
            assert_false(tip.is_empty(), "resting on %s shows a tooltip" % way)
            assert_true(tip.contains(hsl.title()), "%s names the filter it applies: %s" % [way, tip])
            assert_false(seen.has(tip), "and %s does not repeat another way's" % way)
            seen.append(tip)
        toggle.dim(&"layer", "Said why.")
        assert_eq(toggle._get_tooltip(Vector2(toggle.stop_x(2), 1.0)), "Said why.", "a dimmed stop keeps saying why")

    window.free()
    canvas.free()
    easel.free()
    host.free()
