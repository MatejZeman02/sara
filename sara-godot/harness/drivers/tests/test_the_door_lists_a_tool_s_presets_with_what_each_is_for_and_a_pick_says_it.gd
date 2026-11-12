## The door lists the presets a tool takes with what each says
## it is for, and a pick answers the description of the preset it picked.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A script picking through the door needs a description to know
## what it is picking. The `preset_list` step is `SaPresetListDriver`, and
## the pick is `SaPresetPick.pick`, both driven here against the real bar and the
## real docker in the tree, the way the pick's own suite builds them.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

const INK_SAYS: String = "A hard round for clean lines, solid at any press."

static var scratch_dir: String = SaDataRoot.path("test_door")

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


## The bar and the docker over a store holding Ink, which says what it is for,
## Plain, a stamp preset that says nothing, and Ghost, of an engine no tool here
## takes, which says something too.
func _build() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    var store := _bar.preset_store
    store.save_preset("Ink", StampSettingsScript.new(), PackedStringArray(["ink"]), {SaPresetMeta.DESCRIPTION_META: INK_SAYS})
    store.save_preset("Plain", StampSettingsScript.new())
    var ghost := {SaPresetMeta.ENGINE_META: &"ghost", SaPresetMeta.DESCRIPTION_META: "Not a brush."}
    store.save_preset("Ghost", StampSettingsScript.new(), PackedStringArray(), ghost)
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()


## The rows a `preset_list` answer carries, read back out of its JSON.
func _rows_of(answer: String) -> Array:
    var prefix := "SaCapture: preset_list "
    assert_true(answer.begins_with(prefix), "The answer is the step's line: %s" % answer)
    var parsed: Variant = JSON.parse_string(answer.trim_prefix(prefix))
    return parsed if parsed is Array else []


func _row(rows: Array, preset_name: String) -> Dictionary:
    for row: Variant in rows:
        if row is Dictionary and String((row as Dictionary).get("name", "")) == preset_name:
            return row
    return {}


## The stamp brush's presets through the door: each with its engine and tags,
## the one that says what it is for with its description, the one that says
## nothing with an empty one, and none of another engine.
func test_the_stamp_brush_s_presets_are_listed_with_their_descriptions() -> void:
    _build()
    var rows := _rows_of(SaPresetListDriver.capture_list(_host.get_tree(), "stamp"))
    var ink := _row(rows, "Ink")
    assert_eq(String(ink.get("description", "")), INK_SAYS, "Ink is listed with its description: %s" % ink)
    assert_eq(String(ink.get("engine", "")), "stamp", "and its engine")
    assert_true((ink.get("tags", []) as Array).has("ink"), "and its tags")
    var plain := _row(rows, "Plain")
    assert_false(plain.is_empty(), "A stamp preset that says nothing is listed too")
    assert_eq(String(plain.get("description", "-")), "", "with an empty description")
    assert_true(_row(rows, "Ghost").is_empty(), "and a preset of another engine is not")
    var every := _rows_of(SaPresetListDriver.capture_list(_host.get_tree(), ""))
    assert_eq(String(_row(every, "Ghost").get("description", "")), "Not a brush.", "Every preset, asked for none")


## A tool's word reaches the engines its presets are of: the Brush takes the
## stamp's, so the stamp's presets are the Brush's.
func test_a_tool_s_word_lists_the_engines_it_takes() -> void:
    var tools := Fixtures.make_tool_registry()
    var engines := SaPresetListDriver.engines_wanted(tools, "brush")
    assert_true(engines.has(&"stamp"), "The Brush takes the stamp engine's presets: %s" % [engines])
    assert_eq(SaPresetListDriver.engines_wanted(tools, "stamp"), [&"stamp"] as Array[StringName], "An engine's word is itself")
    assert_true(SaPresetListDriver.engines_wanted(tools, "").is_empty(), "and no word is every engine")


## A pick by name answers what the picked preset says it is for, and a pick of
## one that says nothing adds nothing.
func test_a_pick_answers_the_description_of_the_preset_it_picked() -> void:
    _build()
    var answer := SaPresetPick.pick(_docker, "ink")
    assert_true(answer.contains("picked 'Ink' by name"), "The pick lands: %s" % answer)
    assert_true(answer.contains(", description %s" % JSON.stringify(INK_SAYS)), "and says what Ink is for: %s" % answer)
    var plain := SaPresetPick.pick(_docker, "Plain")
    assert_false(plain.contains("description"), "A preset that says nothing is picked without one: %s" % plain)
