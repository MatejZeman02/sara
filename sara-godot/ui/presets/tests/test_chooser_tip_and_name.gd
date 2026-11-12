## The preset chooser can show the tip, and its names can be read.
##
## Two halves of one control. Showing the brush
## tip instead of the strokes was already built underneath, in
## `SaPresetThumbs.render`'s `one_dab` flag, and had no door: the chooser cached
## one PNG per preset and there was no room in the name for a second picture. A
## name showing only 7 letters came from `_build_cell`, where the name was given the picture's
## width and clipped, which stops the grid ratcheting its
## own host wider.
##
## So the two clauses pull against each other, and the third thing this file
## asserts is that they no longer do: a wrapping `Label` asks for one pixel of
## width, so the name gets two lines without the cell getting one column more.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a real dab through the real paint path, which is the whole
## point of showing the tip rather than a drawing of one.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_chooser_tip_and_name")

## Names that seven letters do not reach, so a clipped label is visible as
## a failure rather than as a shorter word.
const LONG_NAMES: Array[String] = ["Hard Round Pressure", "Soft Airbrush Large", "Watercolour Bleed"]

var _saved_icon_size: int = 48
var _saved_tip: bool = false


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    _saved_tip = SaSettings.preset_thumb_tip
    SaSettings.preset_thumb_tip = false
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    SaSettings.preset_thumb_tip = _saved_tip
    ScratchFolder.clear(scratch_dir)


## A store holding the three shipped presets under names of a painter's length.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    for long_name: String in LONG_NAMES:
        store.save_preset(long_name, BrushSettingsScript.new())
    return store


## A chooser inside a host of a declared width, the shape both real hosts have.
func _hosted(host_width: int = 300) -> Array:
    var host := VBoxContainer.new()
    host.custom_minimum_size = Vector2(float(SaUI.px(host_width)), 0.0)
    host.size = Vector2(float(SaUI.px(host_width)), 400.0)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(_store(), StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return [host, chooser]


# --- The tip ------------------------------------------------------------------


## Two files for one preset, so switching back and
## forth is two reads rather than two renders.
func test_the_tip_and_the_stroke_are_two_files() -> void:
    var store := _store()
    var settings := store.load_preset("Paint")
    var stroke := SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, false)
    var tip := SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, true)
    assert_true(not stroke.is_empty() and not tip.is_empty(), "Both pictures were drawn")
    assert_true(stroke != tip, "under two names, %s and %s" % [stroke.get_file(), tip.get_file()])
    assert_true(FileAccess.file_exists(stroke), "and both are on disk")
    assert_true(FileAccess.file_exists(tip), "the tip beside the stroke")
    assert_true(tip.get_file().contains(SaPresetThumbs.TIP_SUFFIX), "The tip carries the suffix")


## The second open renders nothing, which is what a cache of its own is for. A
## flip to the tip costs one render per preset and a flip back costs none.
func test_a_flip_back_reads_the_cache() -> void:
    var store := _store()
    var settings := store.load_preset("Paint")
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, false)
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, true)
    var renders := SaPresetThumbs.renders
    var hits := SaPresetThumbs.cache_hits
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, false)
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, true)
    assert_eq(SaPresetThumbs.renders, renders, "Neither picture was drawn again")
    assert_eq(SaPresetThumbs.cache_hits, hits + 2, "and both came off the cache")


## The tip is the shape and not the size, which is what the brush editor's own
## preview settled and what four invisible dots on the running app asked for.
func test_the_tip_is_drawn_at_the_fixed_radius() -> void:
    var store := _store()
    var settings := store.load_preset("Sketch")
    var hairline: float = settings.get("radius")
    assert_true(hairline < 0.01, "Sketch is a hairline, %.5f of the smaller side" % hairline)
    var shown := SaPresetThumbs._drawn_from(settings, true)
    assert_true(shown != settings, "A tip is drawn from a copy")
    assert_almost_eq(float(shown.get("radius")), SaPresetThumbs.TIP_RADIUS, 0.0001, "at the fixed radius")
    assert_almost_eq(float(settings.get("radius")), hairline, 0.0001, "and the preset is left where it was")
    assert_eq(SaPresetThumbs._drawn_from(settings, false), settings, "A stroke is drawn from the preset itself")


## The picture a cell gets is the fixed radius, not the hairline, which is the
## whole of what the cache is drawn through.
func test_two_hairline_presets_show_a_tip_that_can_be_seen() -> void:
    var store := _store()
    var tip := SaPresetThumbs.ensure(store.dir, "Sketch", StateBrushScript, store.load_preset("Sketch"), true)
    assert_true(FileAccess.file_exists(tip), "The tip was drawn")
    var image := Image.load_from_file(tip)
    assert_not_null(image, "and reads back")
    var inked := 0
    for y in image.get_height():
        for x in image.get_width():
            if image.get_pixel(x, y).r < 0.5:
                inked += 1
    assert_true(inked > 200, "with a dab a painter can see, %d of %d texels" % [inked, 64 * 64])


## A deleted preset takes both its pictures, or the next one saved under the same
## name inherits a tip that is not its own.
func test_forget_takes_both_pictures() -> void:
    var store := _store()
    var settings := store.load_preset("Paint")
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, false)
    SaPresetThumbs.ensure(store.dir, "Paint", StateBrushScript, settings, true)
    SaPresetThumbs.forget(store.dir, "Paint")
    assert_false(FileAccess.file_exists(SaPresetThumbs.path_for(store.dir, "Paint", false)), "The stroke is gone")
    assert_false(FileAccess.file_exists(SaPresetThumbs.path_for(store.dir, "Paint", true)), "and the tip with it")


## A dab is square, so the cell that frames one is. The stroke keeps its strip.
func test_the_tip_cell_is_square_and_the_stroke_is_a_strip() -> void:
    SaSettings.preset_icon_size = 60
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    var strip: Button = chooser.grid.get_child(0).get_node("Icon")
    assert_eq(strip.custom_minimum_size, Vector2(60.0, 30.0), "The stroke is two to one")
    ControlWalker.move(chooser.thumb_option, "tip")
    var square: Button = chooser.grid.get_child(0).get_node("Icon")
    assert_eq(square.custom_minimum_size, Vector2(60.0, 60.0), "and the tip is square")
    assert_eq(SaPresetThumbs.TIP_SIZE.x, SaPresetThumbs.TIP_SIZE.y, "which is the shape it is rendered at")
    (pair[0] as Node).free()


## The choice is remembered where the icon size is, so it survives a restart and
## the other host opens on it.
func test_the_choice_lands_in_the_profile() -> void:
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    assert_false(chooser.showing_tip(), "A chooser opens on the strokes")
    ControlWalker.move(chooser.thumb_option, "tip")
    assert_true(SaSettings.preset_thumb_tip, "The row wrote the profile")
    assert_eq(chooser.chooser_report()["thumb"], "tip", "and the report says so")
    assert_eq(SaSettingsKeys.place_of(&"preset_thumb_tip"), ["tools", "preset_thumb_tip"], "under a stored key")
    (pair[0] as Node).free()

    var second := _hosted()
    var other: SaBrushPresetsChooser = second[1]
    assert_true(other.showing_tip(), "A chooser built after it opens on the tip")
    assert_eq(other.thumb_option.selected_value(), SaBrushPresetsChooser.THUMB_TIP, "with the row on it")
    (second[0] as Node).free()


## A word that is neither is a loud failure and not a quiet Strokes, which is the
## rule a tag follows.
func test_an_unknown_choice_changes_nothing() -> void:
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    assert_false(ControlWalker.move(chooser.thumb_option, "dab"), "The row refuses a word it does not offer")
    assert_false(chooser.showing_tip(), "The chooser is where it was")
    (pair[0] as Node).free()


# --- The name -----------------------------------------------------------------


## The half that counted in letters. A name of nineteen characters is drawn
## over two lines rather than trimmed after seven.
func test_a_long_name_gets_two_lines() -> void:
    SaSettings.preset_icon_size = 30
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    for cell: Node in chooser.grid.get_children():
        var label := cell.get_node("Name") as Label
        assert_false(label.clip_text, "The name is wrapped rather than clipped")
        assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD, "between words and never inside one")
        assert_eq(label.max_lines_visible, SaBrushPresetsChooser.NAME_LINES, "over two lines")
        assert_true(
            label.custom_minimum_size.y >= float(SaBrushPresetsChooser.NAME_LINES),
            "with room declared for both, %.1f" % label.custom_minimum_size.y
        )
    (pair[0] as Node).free()


## A name of any length asks for the name
## column and no more, which keeps the column from ratcheting: the column is the
## picture or the widest word, whichever is wider, and it is the
## same in a host of any width.
func test_a_name_never_widens_its_cell() -> void:
    for icon: int in [30, 48, 80]:
        SaSettings.preset_icon_size = icon
        var pair := _hosted()
        var chooser: SaBrushPresetsChooser = pair[1]
        var column := chooser.name_width()
        assert_true(column >= float(SaUI.px(icon)), "At %d the column is at least the picture, %.1f" % [icon, column])
        var wide := _hosted(900)
        assert_almost_eq((wide[1] as SaBrushPresetsChooser).name_width(), column, 0.5, "and a wider host does not move it")
        (wide[0] as Node).free()
        for cell: Node in chooser.grid.get_children():
            var box := cell as Control
            var label := cell.get_node("Name") as Label
            assert_true(
                label.get_combined_minimum_size().x <= column + 0.5,
                "At %d the name '%s' asks %.1f" % [icon, label.text, label.get_combined_minimum_size().x]
            )
            assert_true(
                box.get_combined_minimum_size().x <= column + 0.5,
                "and the cell around it asks %.1f" % box.get_combined_minimum_size().x
            )
        (pair[0] as Node).free()


## The slack a docker has over the pictures goes to the names, which is what
## turned three letters a line at the slider's floor into eleven. A flag is not a
## minimum size, so the grid still asks for what the columns were counted
## against, which is the property that keeps the grid from ratcheting.
func test_the_cell_takes_the_slack_and_the_picture_does_not() -> void:
    SaSettings.preset_icon_size = 30
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    for cell: Node in chooser.grid.get_children():
        var box := cell as Control
        var button := cell.get_node("Icon") as Button
        assert_eq(box.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "The cell asks for the spare width")
        assert_eq(button.size_flags_horizontal, Control.SIZE_SHRINK_CENTER, "and the picture stays its own size")
    var given: float = chooser._host_width()
    var asked: float = chooser.grid.get_combined_minimum_size().x
    assert_true(asked <= given + 0.5, "The grid still asks %.1f of %.1f" % [asked, given])
    (pair[0] as Node).free()


## The column count is held at both ends of the slider, unchanged for
## a given width, with the long names in the library. This is that reading in a
## test, and the scenario shoots the same two on the running app.
func test_the_column_count_survives_the_drag_with_long_names() -> void:
    var ends: Dictionary = {}
    for icon: int in [80, 30]:
        SaSettings.preset_icon_size = icon
        var fresh := _hosted()
        ends[icon] = (fresh[1] as SaBrushPresetsChooser).grid.columns
        (fresh[0] as Node).free()

    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    for icon: int in [80, 70, 60, 50, 40, 30, 40, 50, 60, 70, 80]:
        SaSettings.preset_icon_size = icon
        chooser.refresh()
        if ends.has(icon):
            assert_eq(chooser.grid.columns, ends[icon], "At %d the drag counts what a fresh chooser counts" % icon)
    (pair[0] as Node).free()


## The whole name is still somewhere to be read, which is what the tooltip the
## button already carried is for.
func test_the_whole_name_stays_on_the_tooltip() -> void:
    SaSettings.preset_icon_size = 30
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    for stored_name: String in chooser.visible_names():
        var cell := chooser.grid.get_node("Cell_" + stored_name.validate_node_name())
        assert_eq((cell.get_node("Icon") as Button).tooltip_text, stored_name, "The tooltip is the whole name")
    (pair[0] as Node).free()
