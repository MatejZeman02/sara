## A stamp brush preset carries a gradient.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note's first Done clause, as two tests through the real preset store and
## a real file: "A new suite saves a preset with a three-stop gradient, loads it,
## and reads the three stops back, and loads a version 11 preset and reads the
## colour-to-background default with every other field as it was." The third
## clause, the settings file's length, is read here too, so a later row that
## grows it past the line is told by this suite rather than by a reviewer.
##
## The rest is what the field's default promises: an old preset saved again
## still carries no ramp of its own, and the Colour page's row builds the base
## module's ramp editor through the role without this module naming it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The module that brings the ramp editor, loaded by path the way the module
## loader and `Fixtures.make_tool_registry` load it, so this suite plays the
## loader and the row under test still names nothing of it.
const BASE_MODULE: String = "res://modules/sara-base-modules/base/module.gd"

## The painter's pair as the module would write it onto the live settings. A
## preset carries no colour of its own, `SaPresetStore.EXCLUDED_KEYS` says so,
## so a loaded preset is handed the pair and the default reads it.
const PAINTING: Color = Color(0.8, 0.3, 0.1, 1.0)
const BACKGROUND: Color = Color(0.1, 0.15, 0.3, 1.0)

## The settings file whose length the third clause bounds.
const SETTINGS_PATH: String = "res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd"

## The bound itself, "stands under 900 lines".
const LINE_LIMIT: int = 900

## Never the real `user://brush_presets`, for the reason `test_brush_presets.gd`
## gives.
static var scratch_dir: String = SaDataRoot.path("test_a_stamp_brush_preset_carries_a_gradient")

## Three stops at three positions in three colours, with an alpha that is not
## one, so a reader that dropped a channel or a stop is caught.
const THREE_STOPS: Array = [
    {"position": 0.0, "color": [0.9, 0.1, 0.1, 1.0]},
    {"position": 0.4, "color": [0.1, 0.8, 0.2, 0.5]},
    {"position": 1.0, "color": [0.1, 0.2, 0.9, 1.0]},
]

## Fields a load is allowed to change: the stamp, which the migration moves to
## the current version, and the field this row added, which an old file never
## wrote and reads as its default.
const MOVED_ON_LOAD: Array[String] = ["format_version", "gradient", "resource_path", "resource_name"]


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _file_text(preset_name: String) -> String:
    return FileAccess.get_file_as_string(scratch_dir.path_join(preset_name + ".tres"))


## A brush unlike the default in the fields a stroke reads first, so "every
## other field as it was" is a claim about values a default would not hide.
##
## Build-up, which is also what a version 11 preset painted in: the migration
## step that reads a file carrying no painting mode as build-up would otherwise
## move this fixture's own default, wash, and the round-trip these
## cases read would report it as a field that changed.
func _unusual_brush() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = 0.037
    settings.opacity = 0.62
    settings.spacing = 0.21
    settings.rotation_option.enabled = true
    settings.painting_mode = SaStampBrushSettings.PaintingMode.BUILD_UP
    return settings


## Whether *a* and *b* hold the same stored values, walking into a resource the
## way the saver does, by its storage properties. Floats to a tolerance, since a
## file is text.
func _differences(a: Variant, b: Variant, path: String, out: Array[String]) -> void:
    if a is Resource and b is Resource:
        for property: Dictionary in (a as Resource).get_property_list():
            var key := String(property["name"])
            if (int(property["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or MOVED_ON_LOAD.has(key):
                continue
            _differences((a as Resource).get(key), (b as Resource).get(key), path + "." + key, out)
        return
    if a is Array and b is Array:
        if (a as Array).size() != (b as Array).size():
            out.append(path)
            return
        for index: int in (a as Array).size():
            _differences(a[index], b[index], "%s[%d]" % [path, index], out)
        return
    if a is Dictionary and b is Dictionary:
        if (a as Dictionary).keys() != (b as Dictionary).keys():
            out.append(path)
            return
        for key: Variant in a:
            _differences(a[key], b[key], "%s[%s]" % [path, key], out)
        return
    if a is float and b is float:
        if not is_equal_approx(a, b):
            out.append(path)
        return
    if a is Color and b is Color:
        if not (a as Color).is_equal_approx(b):
            out.append(path)
        return
    if typeof(a) != typeof(b) or a != b:
        out.append(path)


# --- The three stops ---------------------------------------------------------


func test_a_preset_saved_with_three_stops_loads_with_the_three() -> void:
    var store := _store()
    var settings := _unusual_brush()
    settings.gradient = THREE_STOPS.duplicate(true)

    store.save_preset("Three", settings)
    var loaded := store.load_preset("Three") as SaStampBrushSettings

    assert_not_null(loaded, "The preset loads as the brush's settings")
    var ramp := SaColorRamp.from_array(loaded.gradient)
    assert_eq(ramp.size(), 3, "and its gradient holds three stops")
    for index: int in 3:
        var wanted: Dictionary = THREE_STOPS[index]
        var channels: Array = wanted["color"]
        assert_almost_eq(ramp.position_of(index), float(wanted["position"]), 0.0001, "stop %d at its position" % index)
        assert_true(
            ramp.color_of(index).is_equal_approx(Color(channels[0], channels[1], channels[2], channels[3])),
            "stop %d in its colour, alpha included, read %s" % [index, ramp.color_of(index)]
        )
    assert_eq(loaded.gradient_ramp().to_array(), ramp.to_array(), "and the ramp a reader asks for is those three, not the pair")


func test_the_field_is_written_as_the_door_s_array() -> void:
    var store := _store()
    var settings := SaStampBrushSettings.new()
    settings.gradient = THREE_STOPS.duplicate(true)

    store.save_preset("Written", settings)

    assert_true(_file_text("Written").contains("gradient = ["), "The file carries the field as an array")
    assert_false(
        _file_text("Written").contains("SaColorRamp"), "and not a ramp object, which is a RefCounted the saver cannot write"
    )


# --- The version 11 file ------------------------------------------------------


func test_a_version_11_preset_reads_the_colour_to_the_background() -> void:
    var store := _store()
    var older := _unusual_brush()
    older.format_version = 11
    store.save_preset("Eleven", older)

    assert_false(_file_text("Eleven").contains("gradient"), "A file at 11 has no gradient in it, as 11 wrote none")
    assert_true(_file_text("Eleven").contains("format_version = 11"), "and says it is at 11")

    var loaded := store.load_preset("Eleven") as SaStampBrushSettings

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "The load stamps it at the version of today")
    assert_true(loaded.gradient.is_empty(), "with no ramp of its own, because the step writes nothing")
    loaded.color = PAINTING
    loaded.background_color = BACKGROUND
    var pair := SaColorRamp.from_pair(PAINTING, BACKGROUND)
    assert_eq(loaded.gradient_ramp().to_array(), pair.to_array(), "so the ramp is the colour to the background colour")
    assert_eq(loaded.gradient_ramp().size(), 2, "two stops")
    assert_true(loaded.gradient_ramp().color_of(0).is_equal_approx(PAINTING), "starting at the painting colour")
    assert_true(loaded.gradient_ramp().color_of(1).is_equal_approx(BACKGROUND), "and ending at the background colour")
    loaded.color = BACKGROUND
    assert_true(
        loaded.gradient_ramp().color_of(0).is_equal_approx(BACKGROUND),
        "and it follows the pair when it moves, as the brush always did"
    )


func test_a_version_11_preset_loads_with_every_other_field_as_it_was() -> void:
    var store := _store()
    var older := _unusual_brush()
    older.format_version = 11
    store.save_preset("Eleven", older)

    var loaded := store.load_preset("Eleven")
    var differ: Array[String] = []
    _differences(older, loaded, "settings", differ)

    assert_eq(differ, [] as Array[String], "Every stored field but the stamp and the gradient reads as it was saved")


func test_the_step_to_12_writes_nothing() -> void:
    var at_eleven := _unusual_brush()
    at_eleven.format_version = 11
    var untouched := _unusual_brush()
    untouched.format_version = 11

    assert_true(at_eleven.migrate(), "A resource at 11 migrates when asked")
    assert_eq(at_eleven.format_version, SaStampBrushSettings.FORMAT_VERSION, "to the current version")
    var differ: Array[String] = []
    _differences(untouched, at_eleven, "settings", differ)
    assert_eq(differ, [] as Array[String], "and nothing else on it moved")
    assert_true(at_eleven.gradient.is_empty(), "the gradient included")


func test_an_old_preset_saved_again_still_carries_no_ramp_of_its_own() -> void:
    var store := _store()
    var older := _unusual_brush()
    older.format_version = 11
    store.save_preset("Eleven", older)
    var first := store.load_preset("Eleven")

    store.save_preset("Eleven", first)
    var again := store.load_preset("Eleven") as SaStampBrushSettings

    assert_false(_file_text("Eleven").contains("gradient"), "Saving it again writes no gradient")
    assert_true(again.gradient.is_empty(), "so it still follows the pair")
    var differ: Array[String] = []
    _differences(first, again, "settings", differ)
    assert_eq(differ, [] as Array[String], "and nothing a stroke reads changed between the two loads")


func test_the_gradient_arrived_at_version_12() -> void:
    assert_true(SaStampBrushSettings.FORMAT_VERSION >= 12, "The gradient arrived at version 12")
    assert_true(SaStampBrushSettings.new().gradient.is_empty(), "and a new brush starts with no ramp of its own")


func test_the_ramp_a_reader_is_handed_is_its_own() -> void:
    var settings := SaStampBrushSettings.new()
    settings.gradient = THREE_STOPS.duplicate(true)

    settings.gradient_ramp().add_stop(0.7)

    assert_eq(settings.gradient.size(), 3, "Editing the ramp a reader asked for leaves the preset's three stops")


# --- The settings file --------------------------------------------------------


func test_the_settings_file_stands_under_900_lines() -> void:
    var text := FileAccess.get_file_as_string(SETTINGS_PATH)
    var lines := text.split("\n").size()

    assert_true(not text.is_empty(), "The settings file is read")
    assert_true(lines < LINE_LIMIT, "and stands under %d lines, at %d" % [LINE_LIMIT, lines])


# --- The Colour page's row ----------------------------------------------------


func test_the_gradient_row_builds_the_ramp_editor_through_the_role() -> void:
    var roles := SaRoleRegistry.new()
    var context := SaContext.create(
        SaToolRegistry.new(),
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        roles
    )
    var base: SaModule = load(BASE_MODULE).new()
    base.register(context.for_module(base.get_id()))
    var machine := ToolMachine.new(false)
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(null, Fixtures.make_tool_registry(), roles)
    var brush := machine.get_tool("brush")
    var settings := brush.get("settings") as SaStampBrushSettings
    var was: Array = settings.gradient.duplicate(true)
    settings.gradient = []
    var spec: SaOptionSpec = null
    for each: SaOptionSpec in machine.get_descriptor(&"brush").options:
        if each.key == &"gradient":
            spec = each
    assert_not_null(spec, "The brush declares a Gradient row")
    if spec != null:
        _drive_the_row(spec, brush, settings)
    settings.gradient = was
    base.unregister(context)
    Fixtures.teardown(null, machine)


func _drive_the_row(spec: SaOptionSpec, brush: ToolState, settings: SaStampBrushSettings) -> void:
    assert_eq(spec.page, SaColorPage.PAGE, "on the Colour Dynamics page")
    assert_eq(spec.kind, SaOptionSpec.Kind.CUSTOM, "drawn by the module's own control")
    assert_false(spec.in_docker, "and kept off the docker")

    var writes: Array = []
    var row := spec.build_control.call(spec, func(value: Variant) -> void: writes.append(value)) as SaGradientRow
    spec.bind_value.call(row, brush.get_indexed(spec.property_path()))

    assert_not_null(row.editor, "The row built a ramp editor")
    if row.editor == null:
        row.free()
        return
    assert_eq(
        row.editor.get_script(),
        brush.roles.script_for(SaColorPage.RAMP_ROLE),
        "and it is the script the role names, which this module never names"
    )
    assert_eq(
        row.capture_option_report()["ramp"]["stops"],
        settings.gradient_ramp().to_array(),
        "showing the colour to the background colour while the preset has no ramp"
    )
    assert_true(settings.gradient.is_empty(), "which showing it writes nothing for")

    row.capture_option_edit({"add": 0.5, "color": "#20c040"})

    assert_eq(settings.gradient.size(), 3, "An added stop lands on the settings as three stops")
    assert_eq(writes.size(), 2, "through a write per edit, the stop and then its colour, which is what marks the preset dirty")
    assert_true(
        SaColorRamp.from_array(settings.gradient).color_of(1).is_equal_approx(Color.html("#20c040")),
        "and the middle stop is the colour the edit picked"
    )
    spec.bind_value.call(row, brush.get_indexed(spec.property_path()))
    assert_eq(row.capture_option_report()["ramp"]["selected"], 1, "and a sync after it keeps the stop under the hand")
    row.free()
