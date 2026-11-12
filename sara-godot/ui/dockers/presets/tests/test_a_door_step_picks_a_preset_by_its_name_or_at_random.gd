## A door step picks a brush preset by its name, or one at random.
##
## A script selects a brush preset by name, and "Random" selects a random
## preset. The step is `pick_preset`, and
## its handler is `SaPresetPick.pick`, driven here against the real bar and the
## real docker in the tree, the way `test_a_tool_switch_builds_the_presets_grid_at_most_once`
## builds them, so a pick is the docker's `apply_preset` and a dimmed cell is
## the docker's own reading of one.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A stamp preset of a size nothing starts at, so a load of it is seen.
const INK_RADIUS := 0.31

static var scratch_dir: String = SaDataRoot.path("test_d9_presets")

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _bar = null
    _docker = null
    ScratchFolder.clear(scratch_dir)


## The bar and the docker in the tree over a store holding Ink, Second Ink, a
## preset of an engine no tool here takes, and whatever ships, with *tool* in hand.
func _build(tool: StringName) -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(tool)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    var ink: Resource = StampSettingsScript.new()
    ink.radius = INK_RADIUS
    _bar.preset_store.save_preset("Ink", ink)
    _bar.preset_store.save_preset("Second Ink", StampSettingsScript.new())
    _bar.preset_store.save_preset("Ghost", StampSettingsScript.new(), PackedStringArray(), {SaPresetMeta.ENGINE_META: &"ghost"})
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()


func _loaded() -> String:
    return _bar.preset_box.selected_preset


## The quoted name an answer says was picked.
func _picked(answer: String) -> String:
    var found := RegEx.create_from_string("picked '([^']*)'").search(answer)
    return found.get_string(1) if found != null else ""


func test_an_exact_name_loads_that_preset() -> void:
    _build(&"brush")
    var answer := SaPresetPick.pick(_docker, "Ink")
    assert_eq(_loaded(), "Ink", "The preset named is the one loaded: %s" % answer)
    assert_almost_eq(float(_machine.active_tool.get("settings").radius), INK_RADIUS, 1e-6, "with its size in the hand")
    assert_true(answer.contains("picked 'Ink' by name"), "and the answer names it: %s" % answer)
    assert_true(answer.contains("tool in hand brush"), "and the tool in hand: %s" % answer)


func test_the_same_name_in_other_case_and_spaces_loads_it_too() -> void:
    _build(&"brush")
    SaPresetPick.pick(_docker, "  second INK ")
    assert_eq(_loaded(), "Second Ink", "Case and the spaces around a name do not stop the match")


func test_an_unknown_name_changes_nothing_and_names_the_presets_on_offer() -> void:
    _build(&"brush")
    SaPresetPick.pick(_docker, "Ink")
    var answer := SaPresetPick.pick(_docker, "Inked Pencil")
    assert_eq(_loaded(), "Ink", "The loaded preset is the one it was")
    assert_true(answer.contains("found no preset named 'Inked Pencil'"), "and the answer says the name missed: %s" % answer)
    assert_true(answer.contains('"Second Ink"') and answer.contains('"Ghost"'), "and names the presets on offer: %s" % answer)


## The same through the step: a pick under the lasso leaves the brush in the hand.
func test_a_pick_under_the_lasso_leaves_the_brush_in_the_hand() -> void:
    _build(&"lasso")
    var answer := SaPresetPick.pick(_docker, "ink")
    assert_eq(_machine.active_tool_name, &"brush", "The brush is in the hand: %s" % answer)
    assert_true(answer.contains("tool in hand brush"), "and the answer says so: %s" % answer)


func test_random_with_a_seed_picks_the_same_lit_preset_twice() -> void:
    _build(&"brush")
    var lit := SaPresetPick.lit_names(_docker, _docker.chooser.visible_names())
    assert_false(lit.has("Ghost"), "The preset of an engine nobody takes is dimmed, so not lit")
    assert_true(lit.has("Ink"), "and a stamp preset is lit")
    var first := SaPresetPick.pick(_docker, {"name": "Random", "seed": 7})
    var second := SaPresetPick.pick(_docker, {"name": "rAnDoM", "seed": 7})
    assert_false(_picked(first).is_empty(), "Seed 7 picks a preset: %s" % first)
    assert_eq(_picked(second), _picked(first), "and the same one again, in any case of the word")
    assert_true(first.contains("at random with seed 7"), "with the seed in the answer: %s" % first)
    assert_eq(_loaded(), _picked(first), "which is the preset loaded")
    # Every seed of a run of them, so a dimmed pick cannot hide behind seed 7.
    for given in 64:
        var answer := SaPresetPick.pick(_docker, {"name": "Random", "seed": given})
        assert_true(lit.has(_picked(answer)), "Seed %d picks a lit preset: %s" % [given, answer])


func test_an_unseeded_pick_names_a_seed_that_picks_it_again() -> void:
    _build(&"brush")
    var answer := SaPresetPick.pick(_docker, "Random")
    var seed_found := RegEx.create_from_string("with seed (-?\\d+)").search(answer)
    assert_not_null(seed_found, "The answer names the seed it drew: %s" % answer)
    if seed_found == null:
        return
    var again := SaPresetPick.pick(_docker, {"name": "Random", "seed": int(seed_found.get_string(1))})
    assert_eq(_picked(again), _picked(answer), "and that seed picks the same preset: %s" % again)
