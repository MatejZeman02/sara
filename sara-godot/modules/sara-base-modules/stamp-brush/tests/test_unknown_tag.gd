## A tag no preset carries is a failure the chooser says out loud.
##
## `capture_tag` read `_selected_tag = tag if _tag_rows.has(tag) else ""`, so a
## tag the store has never heard of became All and nothing was printed:
## `scenarios/preset-chooser-size.json` asked for `paint` and got two cells, asked for
## `Paint` and got six, and reported success both times. A scenario that
## mistypes a tag photographed the whole library and said it had filtered.
##
## The warning itself is proved by `scenarios/unknown-tag-clears-the-filter.json`,
## because `sara_shot.py` is what folds a run's problem lines and a suite cannot
## see them. What is asserted here is the half a suite can hold: the filter does
## not move, which is what made the old behaviour indistinguishable from All.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

## The shipped presets that carry the `paint` tag, sorted as the bar lists them.
const PAINT_WEARERS: Array[String] = [
    "Canvas Brush",
    "Fill",
    "Flat Brush",
    "Lost Edges",
    "Paint",
    "Paper Wash",
    "Shadow Edge",
    "Torn Gouache",
    "Wash",
]

static var scratch_dir: String = SaDataRoot.path("test_unknown_tag")

## The profile's tag filter as it stood, put back after each test, since a tag
## captured here is kept for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    ScratchFolder.clear(scratch_dir)


## A chooser over a store holding the three presets Sara ships.
func _chooser() -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


## The tags the shipped presets carry, which is what the message offers back.
func test_the_shipped_presets_are_tagged_in_lower_case() -> void:
    var chooser := _chooser()
    var tags := chooser.store.all_tags()
    assert_true(tags.has("paint"), "paint is one of them")
    assert_false(tags.has("Paint"), "and the capital is not, which is the whole of the defect")
    chooser.free()


## A tag nothing carries leaves the grid where it was rather than clearing it.
func test_an_unknown_tag_does_not_become_all() -> void:
    var chooser := _chooser()
    chooser.capture_tag("paint")
    var filtered := chooser.visible_names()
    assert_eq(filtered, ["Fill", "Paint"] as Array[String], "the filter is on")
    chooser.capture_tag("Paint")
    assert_eq(chooser.visible_names(), filtered, "and one capital does not undo it")
    assert_eq(String(chooser.chooser_report().get("tag", "")), "paint", "the report still names the tag that is on")
    chooser.free()


## And from All, an unknown tag leaves All rather than looking like a filter.
func test_an_unknown_tag_from_all_changes_nothing() -> void:
    var chooser := _chooser()
    assert_eq(chooser.visible_names().size(), 3, "All to begin with")
    chooser.capture_tag("watercolour")
    assert_eq(chooser.visible_names().size(), 3, "and All afterwards")
    assert_eq(String(chooser.chooser_report().get("tag", "")), "", "with no tag claimed")
    chooser.free()


## Clearing is a thing a painter does, so it never warns and always works.
func test_an_empty_tag_still_clears_without_complaint() -> void:
    var chooser := _chooser()
    chooser.capture_tag("lines")
    assert_eq(chooser.visible_names(), ["Sketch"] as Array[String], "a real tag narrows it")
    chooser.capture_tag("")
    assert_eq(chooser.visible_names().size(), 3, "and an empty one brings them all back")
    assert_eq(String(chooser.chooser_report().get("tag", "")), "", "with no tag left on the report")
    chooser.free()


## The tool options bar has the same fallback and the step goes through it first,
## so the chooser's guard alone left the filter cleared by the time the warning
## fired. Its own path is the one a painter's tag row takes, where every row
## exists, which is why the loud half stays in the chooser.
func test_the_bars_filter_holds_through_an_unknown_tag() -> void:
    var host := Node.new()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    # Installed by hand, because the recipes reach the bar through a role whose
    # registries live on a main scene a test host has none of.
    bar.preset_store.install_shipped(machine.get_tool("brush").settings, ShippedPresetsScript)
    bar._ready()

    bar.filter_by_tag("paint")
    assert_eq(bar.selected_tag(), "paint", "a real tag is picked")
    # Fourteen presets carry paint in the stock set, and this bar installs
    # from the live settings, so it sees all of them.
    assert_eq(bar.preset_names(), PAINT_WEARERS, "and narrows the list")

    bar.filter_by_tag("Paint")
    assert_eq(bar.selected_tag(), "paint", "one capital leaves the filter where it was")
    assert_eq(bar.preset_names(), PAINT_WEARERS, "and the list with it")

    bar.filter_by_tag("watercolour")
    assert_eq(bar.selected_tag(), "paint", "so does a tag nothing carries")

    bar.filter_by_tag("")
    assert_eq(bar.selected_tag(), "", "and clearing still clears")
    assert_eq(bar.preset_names().size(), ShippedPresetsScript.entries().size(), "with every preset back")

    host.free()
    Fixtures.teardown(surface, machine)
