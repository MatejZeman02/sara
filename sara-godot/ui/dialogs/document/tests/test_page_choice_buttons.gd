## The dropdowns of Preferences and the dialogs.
##
## `SaChoiceButton` stands in for the engine's dropdown on every page and dialog,
## so what is held here is the claim that no page and no dialog opens the
## engine's list any more, plus the two pieces of machinery the move needed: the
## page layer's `CHOICE` row and the `choice` capture step.
extends "res://tests/test_framework.gd"

## The files that must not build the engine's dropdown. Named one by
## one rather than scanned for, because a file that grows a dropdown is a file
## that has to be added here on purpose.
##
## The whole tree is scanned as well, by the case below this one. The list stays
## because a name here says which file was changed, and a bare scan says only
## that nobody has written one lately.
const OWNED := [
    "res://ui/page/sa_page.gd",
    "res://ui/dialogs/document/new_document/new_document_dialog.gd",
    "res://ui/dialogs/document/import_fit_dialog.gd",
    "res://ui/color_space/color_space_browser.gd",
    "res://ui/dockers/graph/graph_docker.gd",
    "res://ui/settings/arrange/workspace_page.gd",
    "res://ui/settings/look/display_page.gd",
    "res://ui/settings/arrange/top_bar_page.gd",
    "res://ui/settings/keyboard/shortcuts_page.gd",
    "res://ui/settings/arrange/layout_docker_options.gd",
    "res://ui/settings/look/color_themes_page.gd",
    "res://ui/dialogs/document/image_size_dialog.gd",
    "res://ui/dialogs/document/export_dialog.gd",
    # The two dialogs' channel rows, which are the Curves and Levels filters'
    # panels in the base module.
    "res://modules/sara-base-modules/base/filters/sa_curves_panel.gd",
    "res://modules/sara-base-modules/base/filters/levels/sa_levels_panel.gd",
    "res://ui/color_space/color_space_dialog.gd",
    "res://ui/dockers/minimap/minimap_docker.gd",
    "res://ui/presets/brush_presets_chooser.gd",
    "res://ui/widgets/curve_option/sa_curve_option_control.gd",
]


class Knobs:
    extends RefCounted

    var mode: int = 4


var _knobs: Knobs = null
var _host: VBoxContainer = null
var _page: SaPage = null


func before_each() -> void:
    _knobs = Knobs.new()


func after_each() -> void:
    # The host owns every control the page realized, and `SaPage` is RefCounted,
    # so the one `free` here is the container's.
    if _host != null:
        _host.free()
        _host = null
    _page = null
    _knobs = null


func _build() -> SaChoiceButton:
    _host = VBoxContainer.new()
    _page = SaPage.new()
    var rows := _page.section("Choices")
    rows.choice("Mode", [{"id": 4, "label": "Normal"}, {"id": 9, "label": "Raw"}], _knobs, ^"mode")
    _page.realize(_host)
    var row := _page.row(&"mode")
    return (row.control if row != null else null) as SaChoiceButton


## The claim of the unit, held where a rebuild cannot quietly undo it: not one
## of the eleven files builds the engine's dropdown.
func test_no_page_or_dialog_of_this_unit_builds_the_engines_dropdown() -> void:
    var offenders: Array[String] = []
    for path: String in OWNED:
        var file := FileAccess.open(path, FileAccess.READ)
        assert_not_null(file, "%s is still in the tree" % path)
        if file == null:
            continue
        if file.get_as_text().contains("OptionButton.new()"):
            offenders.append(path)
    offenders.sort()
    assert_true(
        offenders.is_empty(),
        "A choice in a page or a dialog is SaChoiceButton, not the engine's dropdown: %s" % ", ".join(offenders)
    )


## The claim a list of names cannot make: not one
## script under the six source roots builds the engine's dropdown, whoever wrote
## it and whenever. `SaChoiceButton` reads `OptionButton`'s theme for its arrow
## and `SaUI` styles the type, so the words are looked for as the call.
func test_nothing_in_the_tree_builds_the_engines_dropdown() -> void:
    var offenders: Array[String] = []
    for root: String in [
        "res://core", "res://render", "res://tools", "res://ui", "res://utils", "res://harness", "res://modules"
    ]:
        for path: String in _scripts_under(root):
            var file := FileAccess.open(path, FileAccess.READ)
            if file != null and file.get_as_text().contains("OptionButton.new()"):
                offenders.append(path)
    offenders.sort()
    assert_true(offenders.is_empty(), "A dropdown anywhere in Sara is SaChoiceButton: %s" % ", ".join(offenders))


## Every `.gd` under *root*, at whatever depth. A walk rather than a glob,
## because a module puts its own ui/ two directories down. A `tests` folder is
## skipped, since a suite beside its feature is not Sara's code and may name
## the engine's dropdown to say it is gone.
func _scripts_under(root: String) -> Array[String]:
    var out: Array[String] = []
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        var path := "%s/%s" % [root, entry]
        if dir.current_is_dir():
            if entry != "tests":
                out.append_array(_scripts_under(path))
        elif entry.ends_with(".gd"):
            out.append(path)
        entry = dir.get_next()
    dir.list_dir_end()
    return out


## The page layer's own `CHOICE` row, which is the door thirteen of those
## dropdowns came through rather than being written out by hand.
func test_a_pages_choice_row_is_saras_own_button() -> void:
    var control := _build()
    assert_not_null(control, "A choice row draws Sara's own choice button")
    assert_eq(control.choice_labels(), ["Normal", "Raw"], "with the row's own words on it")
    assert_eq(control.choice_values(), [4, 9], "and the row's own ids behind them, never a position")


## The id and not the index, which is the whole reason the control exists: a
## list whose first row stands for 4 writes 4.
func test_a_press_writes_the_rows_id_into_the_binding() -> void:
    var control := _build()
    assert_true(control.pick_row("Raw"), "The second row takes a press")
    assert_eq(_knobs.mode, 9, "and the binding takes that row's id, not its position")
    assert_true(control.pick_row("Normal"), "and back again")
    assert_eq(_knobs.mode, 4, "for the id of the row pressed")


## A stored value no row stands for. The engine's dropdown drew `select(-1)`, an
## empty button, and `SaChoiceButton` has no such state: the button stays on
## what it showed, which is a readable answer rather than a blank one.
func test_a_value_no_row_stands_for_leaves_the_button_where_it_was() -> void:
    var control := _build()
    assert_eq(control.selected_value(), 4, "The page opened on the bound value")
    _knobs.mode = 77
    _page.refresh()
    assert_null(control.selected_value(), "and a value no row stands for holds no row's value behind it")
    assert_eq(control.text, "Normal", "with words on it rather than nothing")


## The `choice` capture step, which every scenario written before this unit
## opens its dropdowns with. It named an `OptionButton`, and the control under
## most of those names is an `SaChoiceButton` now, so the refusal cannot go on
## naming one of the two.
##
## Only the refusal is here. The open path adds a Window to the tree, which
## hangs the runner (the watchdog note at the top of `run_tests.sh`), so it is
## proved by `scenarios/label-buttons-finish.json` instead: its
## `{"choice": {"open": "ModeButton"}}` reads
## `SaCapture: ModeButton opened 6 rows` on both sides of this unit.
func test_the_choice_step_refuses_a_name_in_the_words_of_both_controls() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_eq(
        SaMenuChoice.capture_choice(tree, {"open": "NothingInTheTreeIsCalledThis"}),
        "SaCapture: no dropdown called \'NothingInTheTreeIsCalledThis\'",
        "A name nothing carries names neither control, because either one could have worn it"
    )
