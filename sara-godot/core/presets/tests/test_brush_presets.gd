## The brush preset library: the store on disk, and the options bar over it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template can
## carry, which lives outside `core/`. A suite preloads the module's
## script by path rather than asking the registries, because a test machine is
## built without the loader and installs the recipes itself.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The bar's sliders come from the brush's descriptor now, and a
## machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

## Never the real `user://brush_presets`. A suite that wrote there would leave
## test rubbish in a painter's own preset list, and `run_all.gd` only sandboxes
## the settings file.
static var scratch_dir: String = SaDataRoot.path("test_brush_presets")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func test_a_preset_round_trips_through_disk() -> void:
    var store := _store()
    var settings := BrushSettingsScript.new()
    settings.radius = 0.077
    settings.opacity = 0.4
    settings.spacing = 0.05
    settings.hardness.value = 0.8
    settings.flow.value = 0.25
    settings.size_by_pressure = true
    settings.opacity_by_pressure = false
    settings.blend_mode = SaLayer.BLEND_MODE.MULTIPLY

    assert_eq(store.save_preset("Inky", settings), "Inky", "Saving reports the name it stored under")

    var restored := BrushSettingsScript.new()
    assert_true(store.apply_preset("Inky", restored), "The preset applies onto a fresh settings resource")
    assert_almost_eq(restored.radius, 0.077, 0.00001, "Radius survives")
    assert_almost_eq(restored.opacity, 0.4, 0.00001, "Opacity survives")
    assert_almost_eq(restored.spacing, 0.05, 0.00001, "Spacing survives")
    assert_almost_eq(restored.hardness.value, 0.8, 0.00001, "Hardness survives")
    assert_almost_eq(restored.flow.value, 0.25, 0.00001, "Flow survives")
    assert_almost_eq(restored.flow.gamma(), 2.4, 0.00001, "The gamma beside it survives too")
    assert_true(restored.size_by_pressure, "A pressure toggle turned on survives")
    assert_false(restored.opacity_by_pressure, "A pressure toggle turned off survives, rather than reverting to its default")
    # Exposure is not in the brush: it is the colour's stops now.
    assert_false("exposure" in restored, "Exposure is not part of the brush")
    assert_eq(restored.blend_mode, SaLayer.BLEND_MODE.MULTIPLY, "The blend mode is")


func test_a_preset_does_not_carry_the_colour() -> void:
    var store := _store()
    var saved := BrushSettingsScript.new()
    saved.color = Color(1.0, 0.0, 0.0, 1.0)
    saved.radius = 0.09
    store.save_preset("Red brush", saved)

    var target := BrushSettingsScript.new()
    target.color = Color(0.0, 0.0, 1.0, 1.0)
    store.apply_preset("Red brush", target)
    assert_eq(target.color, Color(0.0, 0.0, 1.0, 1.0), "Loading a preset leaves the painter's colour alone")
    assert_almost_eq(target.radius, 0.09, 0.00001, "The brush itself still comes across")

    # Excluded means absent from the file, not stored as a default. A default is
    # never written to a .tres, which is why there is no misleading white line.
    var text := FileAccess.get_file_as_string(scratch_dir.path_join("Red brush.tres"))
    assert_false(text.is_empty(), "The preset was written where the store says it was")
    assert_false(text.contains("color = "), "The saved file carries no colour at all")


## A preset carries its blend mode on purpose, and the switch says
## the one the painter picked is theirs.
func test_a_preset_leaves_the_blend_mode_alone_when_asked() -> void:
    var store := _store()
    var saved := BrushSettingsScript.new()
    saved.blend_mode = &"multiply"
    saved.radius = 0.07
    store.save_preset("Multiplier", saved)

    var target := BrushSettingsScript.new()
    target.blend_mode = &"screen"
    store.apply_preset("Multiplier", target)
    assert_eq(target.blend_mode, &"multiply", "By default the preset's mode comes across")

    target.blend_mode = &"screen"
    store.keep_blend_mode = true
    store.apply_preset("Multiplier", target)
    assert_eq(target.blend_mode, &"screen", "With the switch on, the painter's mode stays")
    assert_almost_eq(target.radius, 0.07, 0.00001, "and everything else still comes across")


func test_a_preset_and_the_live_brush_do_not_share_sub_resources() -> void:
    var store := _store()
    var live := BrushSettingsScript.new()
    live.hardness.value = 0.6
    store.save_preset("Shared", live)

    var target := BrushSettingsScript.new()
    store.apply_preset("Shared", target)
    assert_almost_eq(target.hardness.value, 0.6, 0.00001, "The gamma pair comes across")
    assert_false(target.hardness == live.hardness, "As a copy, rather than as the same object in two places")

    target.hardness.value = 0.1
    var second := BrushSettingsScript.new()
    store.apply_preset("Shared", second)
    assert_almost_eq(second.hardness.value, 0.6, 0.00001, "Dragging a slider after loading does not rewrite the stored preset")


func test_the_library_lists_deletes_and_survives_a_restart() -> void:
    var store := _store()
    var settings := BrushSettingsScript.new()
    settings.radius = 0.033
    store.save_preset("Zeta", settings)
    store.save_preset("Alpha", settings)

    assert_eq(Array(store.list_names()), ["Alpha", "Zeta"], "Presets are listed in name order")

    # A restart is exactly this: nothing in memory carries over and the library
    # is whatever the directory holds.
    var after_restart := _store()
    assert_true(after_restart.has_preset("Alpha"), "A preset written last run is there the next one")
    var restored := BrushSettingsScript.new()
    after_restart.apply_preset("Alpha", restored)
    assert_almost_eq(restored.radius, 0.033, 0.00001, "With its values intact")

    assert_true(after_restart.delete_preset("Alpha"), "Deleting a preset reports success")
    assert_false(after_restart.has_preset("Alpha"), "And it is gone")
    assert_false(after_restart.delete_preset("Alpha"), "Deleting it twice is a no-op rather than an error")
    assert_eq(Array(store.list_names()), ["Zeta"], "The other preset is untouched")
    assert_null(store.load_preset("Alpha"), "Loading a preset that is not there is null rather than a crash")


func test_a_name_the_file_system_would_refuse_is_reduced_to_one_it_takes() -> void:
    var store := _store()
    var settings := BrushSettingsScript.new()

    var stored := store.save_preset("  Round/Soft  ", settings)
    assert_eq(stored, "Round_Soft", "The name is trimmed and its path separator replaced")
    assert_true(store.has_preset(stored), "The preset is found under the name it was actually given")
    assert_eq(Array(store.list_names()), ["Round_Soft"], "And that is the name the dropdown will show")

    assert_eq(SaPresetStore.sanitize_name("..hidden"), "hidden", "A leading dot would hide the file, so it goes")
    assert_eq(SaPresetStore.sanitize_name("..."), "", "A name of nothing but dots is refused")
    assert_eq(store.save_preset("", settings), "", "So is an empty one")
    assert_eq(store.save_preset("Fine", null), "", "And so is a save with no settings behind it")


func test_the_options_bar_saves_lists_loads_and_deletes() -> void:
    var host := Node.new()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var brush := machine.get_tool("brush")
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    # The bar installs the shipped recipes on its first refresh, and the role
    # they come through is registered by a main scene a test machine has none of.
    # So the suite hands them over exactly as the app does, and
    # the refresh then finds the directory already there.
    bar.preset_store.install_shipped(brush.settings, ShippedPresetsScript)
    bar._ready()

    brush.settings.radius = 0.061
    brush.settings.opacity = 0.3
    brush.settings.color = Color(1.0, 0.0, 0.0, 1.0)

    assert_eq(bar.preset_menu.text, ToolOptionsBar.PRESET_LABEL, "The button says Presets while no preset is loaded")
    assert_true(_menu_row_disabled(bar, ToolOptionsBar.PRESET_ID_DELETE), "Delete is dead with nothing selected")

    bar._on_preset_menu_id(ToolOptionsBar.PRESET_ID_SAVE)
    assert_true(bar.preset_name_edit.visible, "Save as opens the name field")
    assert_false(bar.preset_menu.visible, "The field takes the button's place rather than widening the bar")
    bar.preset_name_edit.text_submitted.emit("Inker")
    assert_false(bar.preset_name_edit.visible, "Committing puts the field away again")
    assert_true(bar.preset_menu.visible, "And brings the button back")

    var expected: Array[String] = ["Inker"]
    for entry: Dictionary in ShippedPresetsScript.entries():
        expected.append(String(entry["name"]))
    expected.sort()
    assert_eq(bar.preset_names(), expected, "The saved preset joins the presets Sara ships, sorted")
    assert_eq(bar.selected_preset_name(), "Inker", "And it is what the button shows after the save")
    assert_eq(bar.preset_menu.text, ToolOptionsBar.PRESET_LABEL, "The button still says Presets")
    assert_eq(bar.preset_menu.tooltip_text, "Inker. Shows or hides Brush Presets.", "and names the loaded preset in its tooltip")
    assert_false(_menu_row_disabled(bar, ToolOptionsBar.PRESET_ID_DELETE), "Delete is live once a preset is loaded")

    # Move the brush somewhere else, then load the preset back over it.
    brush.settings.radius = 0.005
    brush.settings.opacity = 1.0
    brush.settings.color = Color(0.0, 1.0, 0.0, 1.0)
    bar._on_preset_menu_id(bar.preset_names().find("Inker"))

    assert_almost_eq(brush.settings.radius, 0.061, 0.0005, "Choosing a preset restores the radius")
    assert_almost_eq(brush.settings.opacity, 0.3, 0.0005, "And the opacity")
    assert_eq(brush.settings.color, Color(0.0, 1.0, 0.0, 1.0), "And leaves the colour where the painter put it")
    assert_almost_eq(bar.control_for(&"radius").value, 0.061, 0.0005, "The sliders follow the settings they now describe")
    assert_almost_eq(bar.control_for(&"opacity").value, 0.3, 0.0005, "All of them, not only the one that was checked")

    bar._on_preset_menu_id(ToolOptionsBar.PRESET_ID_DELETE)
    assert_false(bar.preset_names().has("Inker"), "Deleting takes the row away")
    assert_eq(bar.preset_names().size(), ShippedPresetsScript.entries().size(), "and leaves the presets Sara ships")
    assert_eq(bar.selected_preset_name(), "", "With nothing loaded")
    assert_eq(bar.preset_menu.text, ToolOptionsBar.PRESET_LABEL, "And the button saying Presets still")
    assert_almost_eq(brush.settings.radius, 0.061, 0.0005, "Throwing the recipe away does not undo the meal")

    host.free()
    Fixtures.teardown(surface, machine)


## Whether the popup row carrying *row_id* is greyed out.
## Three presets in a fresh profile, each carrying its own tags in
## its own file, and nothing to reinstall once the painter has thrown one away.
func test_the_shipped_presets_land_in_a_fresh_store() -> void:
    var store := _store()
    assert_eq(
        store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript), 3, "Three are written into a store that has none"
    )
    assert_eq(store.list_names(), PackedStringArray(["Fill", "Paint", "Sketch"]), "and they are the three named")

    var sketch := BrushSettingsScript.new()
    assert_true(store.apply_preset("Sketch", sketch), "Sketch applies")
    assert_almost_eq(sketch.radius * 1080.0, 5.0, 0.1, "at five pixels of a default document")
    assert_almost_eq(sketch.hardness.value, 1.0, 0.001, "hard")
    assert_eq(sketch.stabilizer_mode, 0, "and with no smoothing")

    var fill := BrushSettingsScript.new()
    store.apply_preset("Fill", fill)
    assert_almost_eq(fill.radius * 1080.0, 200.0, 0.5, "Fill is two hundred pixels across")

    var paint := BrushSettingsScript.new()
    store.apply_preset("Paint", paint)
    assert_almost_eq(paint.flow.value, 0.5, 0.001, "Paint is half flow")
    assert_almost_eq(paint.hardness.value, 0.0, 0.001, "and soft")

    assert_eq(store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript), 0, "A second run writes nothing")
    store.delete_preset("Sketch")
    assert_eq(
        store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript),
        0,
        "and a deleted one does not come back on the next launch"
    )


## The tags travel inside the preset rather than in an index file beside the
## directory, which is what stops the two falling out of step.
func test_tags_round_trip_and_group_the_presets() -> void:
    var store := _store()
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)

    assert_eq(store.tags_for("Sketch"), PackedStringArray(["lines"]), "Sketch carries its one tag")
    assert_eq(store.all_tags(), PackedStringArray(["lines", "paint"]), "and the union is sorted")
    assert_eq(store.names_tagged("paint"), PackedStringArray(["Fill", "Paint"]), "A tag names the presets carrying it")
    assert_eq(store.names_tagged(""), store.list_names(), "and no tag means all of them")

    # Read back through a second store, so this is the file talking and not the
    # cache the first one filled.
    var reopened := _store()
    assert_eq(reopened.tags_for("Fill"), PackedStringArray(["paint"]), "The tags are in the file, not in memory")

    var settings := BrushSettingsScript.new()
    store.save_preset("Sketch", settings)
    assert_eq(store.tags_for("Sketch"), PackedStringArray(["lines"]), "Saving over a preset keeps the tags it had")
    store.save_preset("Sketch", settings, PackedStringArray(["wet"]))
    assert_eq(store.tags_for("Sketch"), PackedStringArray(["wet"]), "and naming tags replaces them")


## Applying a preset must not push its tags onto the live brush, which is what
## `copy_settings` walking script variables only is for.
func test_applying_a_preset_leaves_no_tags_on_the_brush() -> void:
    var store := _store()
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var live := BrushSettingsScript.new()
    store.apply_preset("Sketch", live)
    assert_false(live.has_meta(SaPresetMeta.TAGS_META), "The brush is not tagged by the preset it was given")


# --- One engine ships as several presets of itself --------------

const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The five added, each built on one brush engine feature.
const E1_PRESETS: Array[String] = ["Dry Marker", "Grainy Pencil", "Lost Edges", "Inked Pen", "Flat Brush"]


## Every recipe names only fields the live settings have, down to each option's
## own fields and each sensor's, because `set_indexed` and the option door both
## step over a name they do not know without a word.
func test_every_shipped_recipe_names_only_fields_the_settings_have() -> void:
    var names: Array[String] = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry["name"])
        names.append(preset_name)
        var missing := SaPresetRecipe.missing_fields(StampSettingsScript.new(), entry)
        assert_true(missing.is_empty(), "%s names nothing the settings lack, %s" % [preset_name, missing])
        assert_false(String(entry.get("about", "")).is_empty(), "and %s says what it is for" % preset_name)
        var pen: Dictionary = entry.get("pen_settings", {})
        for key: String in pen:
            var asked_option: Dictionary = pen[key]
            for sensor: Variant in asked_option.get("sensors", []):
                var asked: Dictionary = sensor if sensor is Dictionary else {"id": sensor}
                var id := SaSensor.id_of(String(asked["id"]))
                assert_true(id >= 0, "%s's %s sensor '%s' is a sensor" % [preset_name, key, asked["id"]])
                var built := SaSensor.create(SaSensor.Id.PRESSURE)
                for field: String in asked:
                    assert_true(field == "id" or field in built, "and '%s' is a field a sensor has" % field)
    for preset_name: String in E1_PRESETS:
        assert_true(names.has(preset_name), "%s is one of the shipped presets" % preset_name)


## A fresh store on the live settings holds every recipe, each loading back as
## the script that wrote it, with its tags and its sentence in its own file.
func test_a_fresh_store_on_the_live_settings_holds_every_shipped_preset() -> void:
    var store := _store()
    assert_eq(
        store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript),
        ShippedPresetsScript.entries().size(),
        "Every recipe is written"
    )
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry["name"])
        var preset := store.load_preset(preset_name)
        assert_not_null(preset, "%s loads" % preset_name)
        if preset == null:
            continue
        assert_eq(preset.get_script(), StampSettingsScript, "as the stamp brush's settings")
        var tags := PackedStringArray(entry["tags"])
        tags.sort()
        assert_eq(store.tags_for(preset_name), tags, "with the tags a painter filters %s by" % preset_name)
        var about := store.about_for(preset_name)
        assert_eq(about, String(entry["about"]), "and the sentence saying what %s is for" % preset_name)
        var bundle := String(store.meta_for(preset_name, SaPresetMeta.BUNDLE_META, ""))
        assert_eq(bundle, String(entry["bundle"]), "and the bundle it was installed from (P3)")


## P3's deletion clause: a preset the painter throws away is in the bundle's
## marker, so no refresh after it writes it back.
func test_a_preset_the_painter_deleted_is_not_written_again() -> void:
    var store := _store()
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_true(store.delete_preset("Sketch"), "The painter deletes Sketch")

    assert_eq(store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript), 0, "and no refresh writes it back")
    assert_false(store.has_preset("Sketch"), "so it is still gone")

    # A restart is a second store that remembers nothing of the first, and the
    # marker on disk is what holds the deletion across it.
    var after_restart := _store()
    assert_eq(after_restart.install_shipped(StampSettingsScript.new(), ShippedPresetsScript), 0, "nor does the next launch")
    assert_false(after_restart.has_preset("Sketch"), "Sketch is still gone after a restart")


## P3's upgrade: a profile whose bundle has offered the eight is given the
## thirteen the table grew by, and a preset the painter holds is left alone.
##
## The eight and their marker are written by hand, the way the stale half below
## writes its stale preset: a profile of the eight is a state this build can no
## longer reach, now that the table holds twenty-one.
func test_a_profile_of_the_eight_is_given_the_thirteen_the_table_grew_by() -> void:
    var store := _store()
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var eight := PackedStringArray()
    for entry: Dictionary in ShippedPresetsScript.entries().slice(0, 8):
        eight.append(String(entry["name"]))
        store.save_preset(String(entry["name"]), StampSettingsScript.new())
    # The painter's own preset, under a name the bundle has never offered. It is
    # in the directory and in no marker, which is the half of the rule only the
    # directory can answer.
    var mine := StampSettingsScript.new()
    mine.radius = 0.123
    store.save_preset("Wash", mine)
    _write_marker(eight)

    var upgraded := _store()
    var written := upgraded.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    # The drawn bundle, a painting pass's and a painter's have a marker each and
    # this profile has none of them, so their whole sets arrive beside the twelve.
    var drawn := ShippedPresetsScript.SaDrawnTipPresetsScript.ENTRIES.size()
    drawn += ShippedPresetsScript.SaHabitPresetsScript.ENTRIES.size()
    drawn += ShippedPresetsScript.SaAuthorPresetsScript.ENTRIES.size()
    assert_eq(written, 12 + drawn, "The twelve the bundle has not offered are written, and the other three bundles whole")
    var keepsake := StampSettingsScript.new()
    upgraded.apply_preset("Wash", keepsake)
    assert_almost_eq(keepsake.radius, 0.123, 0.0001, "and the preset the painter saved under a shipped name is theirs")
    assert_eq(upgraded.list_names().size(), 21 + drawn, "so a profile of the eight holds the twenty-one, with a refresh for each")

    # The record is on the store, so a refresh after the first answers from
    # memory: with the marker gone from disk, that store still writes nothing.
    DirAccess.remove_absolute(_marker_path())
    var again := upgraded.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(again, 0, "A later refresh of the session writes nothing")


## The marker P3's upgrade starts from: the bundle has offered the eight and no
## more, which is every recipe the table held before the presets were split out.
func _write_marker(names: PackedStringArray) -> void:
    var file := FileAccess.open(_marker_path(), FileAccess.WRITE)
    file.store_string("\n".join(names) + "\n")


## Where the marker for the shipped bundle lives, spelled out rather than asked
## of the ledger, so a rename of the file is a failure here and not a silent one.
func _marker_path() -> String:
    return scratch_dir.path_join(ShippedPresetsScript.FORMERLY[0] + SaPresetLedger.SUFFIX)


## What each of the five is named for survives the file, read off the loaded
## preset rather than off the recipe that wrote it.
func test_each_of_the_five_carries_the_unit_it_is_built_on() -> void:
    var store := _store()
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)

    var marker := store.load_preset("Dry Marker") as SaStampBrushSettings
    assert_true(_reads(marker.opacity_option, SaSensor.Id.DEPLETION), "The Dry Marker's opacity runs on depletion")
    assert_true(marker.flow_option.enabled and _reads(marker.flow_option, SaSensor.Id.DEPLETION), "and so does its flow")
    assert_true(_reads(marker.opacity_option, SaSensor.Id.PRESSURE), "with the pressure a new brush has kept beside it")

    var pencil := store.load_preset("Grainy Pencil") as SaStampBrushSettings
    assert_eq(pencil.pattern_name, "Lit Grain", "The Grainy Pencil is textured with the lit grain")
    assert_true(pencil.texture_option.enabled, "with the texture switched on")
    assert_true(SaPatternStore.new().has(pencil.pattern_name), "and a pattern by that name is listed")
    assert_true(_reads(pencil.size_option, SaSensor.Id.PRESSURE), "and a line that thins under a light hand")

    var edges := store.load_preset("Lost Edges") as SaStampBrushSettings
    assert_true(edges.hardness_option.enabled, "Lost Edges has the Hardness option on")
    assert_true(_reads(edges.hardness_option, SaSensor.Id.FUZZY_PER_DAB), "drawn afresh per dab")
    assert_almost_eq(edges.hardness.value, 1.0, 0.0001, "under a Hardness row at its ceiling")

    var pen := store.load_preset("Inked Pen") as SaStampBrushSettings
    assert_almost_eq(pen.sharpness, 1.0, 0.0001, "The Inked Pen is at full sharpness")
    assert_true(pen.sharpness_option.enabled and _reads(pen.sharpness_option, SaSensor.Id.PRESSURE), "on the pressure")
    assert_false(pen.opacity_option.enabled, "and lays opaque ink")

    var flat_brush := store.load_preset("Flat Brush") as SaStampBrushSettings
    assert_eq(int(flat_brush.tip.get("shape")), 1, "The Flat Brush is a rectangle")
    assert_almost_eq(float(flat_brush.tip.get("ratio")), 0.2, 0.0001, "a fifth as thick as it is wide")
    var angle: SaSensor = flat_brush.rotation_option.sensors.get(int(SaSensor.Id.DRAWING_ANGLE), null)
    assert_true(flat_brush.rotation_option.enabled and angle != null and angle.active, "turned by the drawing angle")
    assert_true(angle != null and angle.fan_corners, "with the fan round its corners")


## The pre-C4 script cannot carry the five, so a store on it holds the three
## rather than five plain rounds wearing the names of the brushes.
func test_a_template_that_cannot_carry_a_recipe_does_not_ship_it() -> void:
    for preset_name: String in E1_PRESETS:
        var lacks := SaPresetRecipe.missing_fields(BrushSettingsScript.new(), _shipped(preset_name))
        assert_false(lacks.is_empty(), "The old script lacks what %s is built on, %s" % [preset_name, lacks])
    var store := _store()
    assert_eq(store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript), 3, "so a store on it holds three")
    for preset_name: String in E1_PRESETS:
        assert_false(store.has_preset(preset_name), "and no %s" % preset_name)


## Whether a preset's stroke picture is blank for a reason: an eraser lays no
## paint, which `SaPresetThumbs._paint` says is what an eraser does and is worth
## seeing empty. It was a list of two cases until d6, which drew a stroke too
## small for the picture again rather than leaving the spatter's cell blank.
func _lays_no_paint(settings: Resource) -> bool:
    if settings.get("blend_mode") == SaLayer.BLEND_MODE.ERASE:
        return true
    # A blurring brush that reads only its own layer and lays none of its own
    # colour has nothing to blur on a blank thumbnail. Its picture showed the
    # swatch's ink until the fix, and that ink was the blot a painter met on an
    # empty layer.
    if "smudge_mode" not in settings or int(settings.get("smudge_mode")) != 2 or settings.get("smudge_sample_merged"):
        return false
    var pickup := settings.get("smudge_pickup_option") as SaCurveOption
    var rate := settings.get("smudge_color_rate_option") as SaCurveOption
    return pickup != null and pickup.enabled and rate != null and rate.enabled and rate.strength <= 0.0


## Every shipped preset draws the two pictures a chooser cell shows.
##
## **Five lay no paint, and the test says which rather than skipping them.** The
## erasers, the Blender, the Layer Blender and the Lift change only what is under
## them, so over a bare document they draw nothing. Their picture is drawn over
## `SaThumbGround`'s bands, and the test checks it differs from the corner there,
## so a picture a painter is shown cannot go back to an empty square unseen.
func test_every_shipped_preset_draws_its_thumbnails() -> void:
    var store := _store()
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry["name"])
        var settings := store.load_preset(preset_name)
        var stroke := SaPresetThumbs.ensure(store.dir, preset_name, StateBrushScript, settings, false)
        var tip := SaPresetThumbs.ensure(store.dir, preset_name, StateBrushScript, settings, true)
        assert_true(FileAccess.file_exists(stroke), "%s draws its stroke" % preset_name)
        assert_true(FileAccess.file_exists(tip), "and its tip")
        if not FileAccess.file_exists(stroke):
            continue
        var ink := _ink(Image.load_from_file(stroke))
        if _lays_no_paint(settings):
            assert_true(
                ink > 0, "%s lays no paint and shows its work over the coloured ground, %d texels differ" % [preset_name, ink]
            )
        else:
            assert_true(ink > 0, "and %s's stroke is paint, %d texels of it" % [preset_name, ink])


## Whether *option* reads the sensor *id*, switched on.
func _reads(option: SaCurveOption, id: SaSensor.Id) -> bool:
    var sensor: SaSensor = option.sensors.get(int(id), null)
    return sensor != null and sensor.active


func _shipped(preset_name: String) -> Dictionary:
    for entry: Dictionary in ShippedPresetsScript.entries():
        if String(entry["name"]) == preset_name:
            return entry
    return {}


## The shipped presets carrying *tag*, sorted, as the stamp brush's tables say.
func _tagged(tag: String) -> Array[String]:
    var names: Array[String] = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        if (entry["tags"] as Array).has(tag):
            names.append(String(entry["name"]))
    names.sort()
    return names


## Every tag a shipped preset carries, sorted and once each, which is the tag row.
func _shipped_tags() -> Array[String]:
    var tags: Array[String] = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        for tag: String in entry["tags"]:
            if not tags.has(tag):
                tags.append(tag)
    tags.sort()
    return tags


## How many texels of *image* differ from its corner, which is the card.
func _ink(image: Image) -> int:
    var card := image.get_pixel(0, 0)
    var count := 0
    for y in image.get_height():
        for x in image.get_width():
            if absf(image.get_pixel(x, y).r - card.r) > 0.05:
                count += 1
    return count


## The tag row on the dropdown, which is the half the painter sees.
func test_the_tag_row_filters_the_dropdown() -> void:
    var host := Node.new()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    # Installed by hand for the reason the test above gives: no main scene, so
    # no role, so the recipes arrive the way the app's caller passes them.
    bar.preset_store.install_shipped(machine.get_tool("brush").settings, ShippedPresetsScript)
    bar._ready()

    assert_eq(bar.preset_tags(), _shipped_tags(), "Every tag has a row")
    assert_eq(bar.selected_tag(), "", "All to begin with")
    assert_eq(bar.preset_names().size(), ShippedPresetsScript.entries().size(), "so the list is every shipped preset")

    bar.filter_by_tag("lines")
    assert_eq(bar.preset_names(), _tagged("lines"), "A tag narrows the list to what carries it")
    assert_true(bar.preset_names().has("Sketch"), "Sketch among them")
    assert_eq(bar.selected_tag(), "lines", "and the row stays picked")

    bar.filter_by_tag("paint")
    assert_eq(bar.preset_names(), _tagged("paint"), "Another tag, another list, every stamp preset tagged paint")

    bar.filter_by_tag("")
    assert_eq(bar.preset_names().size(), ShippedPresetsScript.entries().size(), "and All brings them back")

    # A filter hides rows, it does not unload what is loaded.
    bar.load_preset("Sketch")
    bar.filter_by_tag("eraser")
    assert_false(bar.preset_names().has("Sketch"), "Sketch is filtered out")
    assert_eq(bar.selected_preset_name(), "Sketch", "and is still the loaded preset")

    host.free()
    Fixtures.teardown(surface, machine)


## Whether the action for *row_id* is dead.
##
## It read a `PopupMenu` row until the fix replaced the list with a grid of
## thumbnails in a `PopupPanel`, then that grid's own buttons, and now the
## rule those buttons follow: the grid and its two actions are the Brush Presets
## docker's, and this bar runs in three hosts that have no docker. The assertion
## is the same claim throughout, that Delete is dead with nothing selected, and
## only where it is drawn keeps moving. `test_presets_docker.gd` is where the
## buttons themselves are read.
func _menu_row_disabled(bar: ToolOptionsBar, row_id: int) -> bool:
    var box := bar.preset_box
    return box != null and not box.action_available(row_id)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


# --- A preset written before a script moved ------------------------------
#
# The gap this closes is not the paths, it is the shape of the test above them:
# the offscreen runner points `user://` at the checkout's own `scratch/`, so
# every assertion in this file writes the file it then reads and none of them
# ever opens one an earlier build wrote. That is the shape of every migration
# bug this program will have, so these four write the file by hand.


## The exact line the run log choked on, with the path `module-split` left
## behind, and the rest of a preset small enough to read.
func _stale_preset_text() -> String:
    return """[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://modules/sara-base-modules/tools/brush_settings.gd" id="1_stale"]

[resource]
script = ExtResource("1_stale")
radius = 0.05
"""


func _write_preset(store: SaPresetStore, preset_name: String, text: String) -> String:
    DirAccess.make_dir_recursive_absolute(store.dir)
    var path: String = store.dir.path_join(preset_name + SaPresetStore.EXTENSION)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file = null
    return path


## The repair itself, on the file rather than through a load, so a failure here
## says which of the two halves broke.
func test_a_stale_script_path_is_rewritten_to_where_the_script_is() -> void:
    var store := _store()
    var path := _write_preset(store, "Stale", _stale_preset_text())
    var changed := SaResourceFinder.repair_resource_paths(path)
    assert_eq(changed.size(), 1, "One line was repaired")
    var text := FileAccess.open(path, FileAccess.READ).get_as_text()
    assert_false(text.contains("sara-base-modules/tools/brush_settings.gd"), "The old path is gone from the file")
    assert_true(text.contains("stamp-brush/tools/brush_settings.gd"), "and the path the script is at now is in it")
    assert_true(text.contains('uid="uid://'), "and the line carries a uid, which is what a later move resolves by")
    ScratchFolder.clear(scratch_dir)


## The whole point: the preset the painter saved before the move opens.
func test_a_preset_written_before_the_move_still_loads() -> void:
    var store := _store()
    _write_preset(store, "Stale", _stale_preset_text())
    var preset := store.load_preset("Stale")
    assert_not_null(preset, "The preset comes back")
    if preset != null:
        assert_almost_eq(float(preset.get("radius")), 0.05, 0.0001, "with the value it was saved with")
    ScratchFolder.clear(scratch_dir)


## The repair is written to disk, so it happens once rather than on every load.
func test_the_repair_is_written_once_and_not_repeated() -> void:
    var store := _store()
    var path := _write_preset(store, "Stale", _stale_preset_text())
    store.load_preset("Stale")
    assert_true(SaResourceFinder.repair_resource_paths(path).is_empty(), "A second pass finds nothing left to repair")
    ScratchFolder.clear(scratch_dir)


## A path that resolves is left where it is, and only gains its uid. A repair
## that rewrote working paths would be a migration nobody could review.
func test_a_path_that_resolves_is_only_given_its_uid() -> void:
    var store := _store()
    var path := _write_preset(
        store,
        "Fresh",
        """[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://utils/sa_report_shapes.gd" id="1_ok"]

[resource]
script = ExtResource("1_ok")
"""
    )
    SaResourceFinder.repair_resource_paths(path)
    var text := FileAccess.open(path, FileAccess.READ).get_as_text()
    assert_true(text.contains('path="res://utils/sa_report_shapes.gd"'), "The path that resolved is untouched")
    assert_true(text.contains('uid="uid://'), "and it gained the uid it had no reason to be without")
    ScratchFolder.clear(scratch_dir)


## a preset the painter saved before GammaFloat followed the stamp brush,
## with no uid, still loads with the hardness it was saved with.
func test_a_preset_naming_gamma_floats_old_path_still_loads() -> void:
    var store := _store()
    _write_preset(
        store,
        "OldGamma",
        """[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd" id="1_bs"]
[ext_resource type="Script" path="res://utils/gamma_float.gd" id="2_gf"]

[sub_resource type="Resource" id="1"]
script = ExtResource("2_gf")
value = 0.75
gamma_val = 1.0

[resource]
script = ExtResource("1_bs")
hardness = SubResource("1")
"""
    )
    var preset := store.load_preset("OldGamma")
    assert_not_null(preset, "The preset comes back")
    if preset != null:
        var hardness: GammaFloat = preset.get("hardness")
        assert_not_null(hardness, "Hardness resolved to a GammaFloat")
        if hardness != null:
            assert_almost_eq(hardness.raw(), 0.75, 0.0001, "with the value it was saved with")
    ScratchFolder.clear(scratch_dir)
