## A randomise row under the noise brush says what it rolls.
##
## Loading Grain Round once gave a Tool Options docker that led
## with two rows reading "Random: 0 %" beside "Per dab", no name on either and a
## blank above each. The noise brush puts a randomise row under every slider it
## randomises, the bar shows Radius and Opacity, and the docker leaves a slider
## out when the bar shows it, so those two sliders left and their rows stayed with
## nothing above to name them. A row whose slider the bar holds now reads the
## slider's name, and a row under its slider reads as it always did.
##
## Built the way the app builds it: the three modules through the door, a machine
## on the noise engine, the real bar in the tree, and the docker joined to the
## bar's `refitted` as Main joins them.
## `scenarios/a-randomise-row-under-the-noise-brush-says-what-it-rolls.json`
## is the same claim on the running app.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

## Wide enough that the bar's first row holds everything, at any theme scale.
const ROOMY := 4000.0

## A fresh profile, so the bar holds what a fresh bar holds.
static var scratch_profile: String = SaDataRoot.path("test_d94_the_randomise_rows.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _bar_host: Node = null
var _bar: TopMenuBar = null
var _host: Node = null
var _docker: ToolOptionsDocker = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_scratch_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    _bar = TopMenuBar.new()
    _bar.add_tool_options(options)
    _bar_host = Node.new()
    _bar_host.name = "D94BarHost"
    EventBus.add_child(_bar_host)
    _bar_host.add_child(_bar)
    # A bar outside a container keeps the width written to it only with its
    # anchors pinned together.
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.peer_bar = options
    _bar.rows.refitted.connect(_docker.sync_from_tool)
    _docker.target_tool_machine = _machine
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _lay_out(ROOMY)


func after_each() -> void:
    _host.free()
    _bar_host.free()
    _docker = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _remove_scratch_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


## The docker names a randomise row by the key the noise brush gives it, so the
## brush's spelling is held here: every row of its page that is a randomise one
## is known for one by the docker and finds its slider, and there are some.
func test_every_randomise_row_of_the_noise_page_finds_its_slider() -> void:
    var descriptor := _machine.get_descriptor(NoiseModuleScript.TOOL_ID)
    assert_not_null(descriptor, "The noise engine registered a descriptor")
    var rolls := 0
    for spec: SaOptionSpec in descriptor.options:
        if not String(spec.key).ends_with("_random"):
            continue
        rolls += 1
        assert_true(ToolOptionsRolls.is_roll(spec), "'%s' is known for a randomise row" % spec.key)
        var slider := ToolOptionsRolls.slider_of(spec, descriptor.options)
        assert_not_null(slider, "and finds the slider it rolls")
        if slider != null:
            assert_false(slider.label.is_empty(), "which has a name to give it: '%s'" % slider.key)
    assert_true(rolls >= 3, "The page has a randomise row under several sliders, %d found" % rolls)


## The first clause. With Radius and Opacity on the bar their
## sliders are not in the docker, their randomise rows are, and each reads the
## name of what it rolls with a label that is not blank above it.
func test_a_randomise_row_whose_slider_is_on_the_bar_names_what_it_rolls() -> void:
    for key: StringName in [&"radius", &"opacity"]:
        assert_true(_docker.bar_shows(key), "The roomy bar shows '%s'" % key)
        assert_false(_docker.shown_keys().has(key), "so the docker leaves its slider out")
    var shown := _docker.shown_keys()
    assert_eq(
        shown.slice(0, 2),
        [&"radius_random", &"opacity_random"] as Array[StringName],
        "and its first rows are the two randomise ones"
    )
    assert_eq(_text_of(&"radius_random"), "Radius jitter", "The first names Radius")
    assert_eq(_text_of(&"opacity_random"), "Opacity jitter", "and the second Opacity")
    for key: StringName in [&"radius_random", &"opacity_random"]:
        var label := _label_of(key)
        assert_true(label != null and label.visible, "'%s' draws its label" % key)
        assert_false(_text_of(key).strip_edges().is_empty(), "so there is no blank row above it")
    assert_true(
        _docker._foot_line.text.contains("Radius"),
        "and the foot line still says where the sliders are: '%s'" % _docker._foot_line.text
    )


## A randomise row under its slider reads as it did, so Hardness, which a fresh
## bar does not show, keeps its row right under it and no name on the row.
func test_a_randomise_row_under_its_slider_reads_as_it_did() -> void:
    var shown := _docker.shown_keys()
    var at := shown.find(&"hardness")
    assert_true(at >= 0, "Hardness is a docker row")
    assert_eq(shown[at + 1], &"hardness_random", "with its randomise row right under it")
    assert_eq(_text_of(&"hardness_random"), "", "which carries no name of its own, the slider above is it")


## The second clause. Radius sent back to the docker by a bar too
## narrow to hold it is a slider in the docker again, its randomise row sits
## under it unnamed, and the row of the slider the bar still holds keeps its
## name. Then the bar widens and the row takes the name again.
func test_with_radius_sent_back_to_the_docker_its_row_sits_under_its_slider() -> void:
    var pinned := ROOMY - _bar.rows.row_budget(1, ROOMY)
    _lay_out(pinned + 120.0)
    assert_false(_docker.bar_shows(&"radius"), "The narrow bar no longer shows Radius")
    var shown := _docker.shown_keys()
    var at := shown.find(&"radius")
    assert_true(at >= 0, "so the docker draws its slider")
    assert_eq(shown[at + 1], &"radius_random", "with its randomise row right under it")
    assert_eq(_text_of(&"radius_random"), "", "unnamed, as a row under its slider reads")
    for key: StringName in [&"opacity"]:
        var expected := "Opacity jitter" if _docker.bar_shows(key) else ""
        assert_eq(_text_of(&"opacity_random"), expected, "and Opacity's row says what its slider's place says")

    _lay_out(ROOMY)
    assert_false(_docker.shown_keys().has(&"radius"), "A roomy bar takes Radius back")
    assert_eq(_text_of(&"radius_random"), "Radius jitter", "and its row takes the name again")


func _row_of(key: StringName) -> Control:
    return _docker._rows.get(key, null) as Control


func _label_of(key: StringName) -> Label:
    var row := _row_of(key)
    assert_not_null(row, "The docker built a row for '%s'" % key)
    var label := row.get_node_or_null("Label") as Label if row != null else null
    assert_not_null(label, "and it has a label column")
    return label


## What the row's label reads, or a word no label reads when there is none.
func _text_of(key: StringName) -> String:
    var label := _label_of(key)
    return label.text if label != null else "(no label)"


func _lay_out(width: float) -> void:
    _bar.size.x = width
    _bar.apply_layout_settings()


func _remove_scratch_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
