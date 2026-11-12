## The developer's rows sit together, in a Develop section at the end of the
## Modules menu.
##
## Rows for developers (Copy the kernel prompt, Local Server and Documentation,
## New Module and Open User Modules Folder, the two reloads) would otherwise
## spread over three menus. What this suite holds is the section, last and in
## order, that no other menu draws a row for any of its commands, that Reload
## Shaders is a row once and not an action under a heading as well, and that
## Edit keeps Preferences.
##
## Built detached and `_ready()`ed by hand, the way `test_menus.gd` builds its
## bar: a popup is a `Window`, and a bar in the tree hangs a headless run. The
## frame that draws the menus is
## `scenarios/preferences-sits-in-settings-and-the-developers-rows-sit-together.json`.
extends "res://tests/test_framework.gd"

## The section's rows, in their order, as `[label, command]`.
const DEVELOP := [
    ["Documentation", &"help_documentation"],
    ["New Module...", &"modules_new"],
    ["Open User Modules Folder...", &"modules_open_folder"],
    ["Reload Modules", &"modules_reload"],
    ["Reload Shaders", &"modules_reload_shaders"],
    ["Copy the kernel prompt", &"filter_copy_prompt"],
    ["Local Server", &"help_connect_agent"],
]

var _bar: TopMenuBar = null


func before_each() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null


## The labels and the command behind each row of *menu_name*, in order, with a
## heading as `[">", text]` and a line as `["---"]`.
func _column(menu_name: String) -> Array:
    var menu := _bar.menu(menu_name)
    var out := []
    var column := menu.popup.get_node_or_null(NodePath("ChoiceBody/ChoiceScroll/ChoiceColumn"))
    if column == null:
        return out
    for child in column.get_children():
        if child is HSeparator:
            out.append(["---"])
        elif child is Label:
            out.append([">", (child as Label).text])
        elif child is SaChoiceRow:
            var row_id: StringName = (child as SaChoiceRow).id
            var button := menu.popup.label_button(row_id)
            out.append([button.text if button != null else "", menu.command_at(SaMenu.id_of(row_id))])
    return out


func test_modules_ends_with_develop_holding_the_seven_rows_in_order() -> void:
    var column := _column("Modules")
    assert_eq(column[0], ["Active Modules", &""], "Modules opens on the row of the list of what loaded")
    var develop := column.find([">", "Develop"])
    assert_true(develop > 0, "Develop is under the list: %s" % [column])
    assert_eq(column.slice(develop + 1), DEVELOP, "and is the end of the menu, its rows in the order a module is written")
    var titles := (_bar.menus["Modules"] as SaChoicePopup).section_titles()
    assert_eq(titles[titles.size() - 1], "Develop", "no heading follows it")


## Every row of the section is a command row, so a press runs what the row
## says, and the ids are the Modules menu's own, 803 to 806 for the four that
## came from elsewhere.
func test_each_row_runs_its_command_under_an_id_of_the_modules_menu() -> void:
    var menu := _bar.menu("Modules")
    var ids := {
        SaModulesMenu.ID_DOCUMENTATION: &"help_documentation",
        SaModulesMenu.ID_RELOAD_SHADERS: &"modules_reload_shaders",
        SaModulesMenu.ID_COPY_PROMPT: &"filter_copy_prompt",
        SaModulesMenu.ID_LOCAL_SERVER: &"help_connect_agent",
    }
    for id: int in ids:
        assert_eq(menu.command_at(id), ids[id], "item %d runs %s" % [id, ids[id]])
    assert_eq(ids.keys(), [806, 803, 804, 805], "after the three ids the menu already had")


## None of the seven is drawn by another menu, which is the half of "sit
## together" a section alone does not prove.
func test_no_other_menu_draws_a_developer_row() -> void:
    var commands: Array[StringName] = []
    var labels: Array[String] = []
    for row: Array in DEVELOP:
        labels.append(row[0])
        commands.append(row[1])
    for menu_name: String in TopMenuBar.MENU_NAMES:
        if menu_name == "Modules" or _bar.menu(menu_name) == null:
            continue
        for row: Array in _column(menu_name):
            if row.size() < 2 or row[0] == ">":
                continue
            assert_false(commands.has(row[1]), "%s draws no row for %s" % [menu_name, row[1]])
            assert_false(labels.has(row[0]), "nor one called %s" % row[0])


## Help and Filter hold none of the developer's rows, and Help keeps every painter's row.
func test_help_and_filter_keep_only_the_painters_rows() -> void:
    var help: Array[String] = []
    for row: Array in _column("Help"):
        if row.size() == 2 and row[0] != ">":
            help.append(row[0])
    assert_eq(
        help,
        [
            "Manual",
            "Welcome",
            "Colour Spaces...",
            "Report a Problem",
            "Take a Note",
            "Display Settings...",
            "Tablet Settings...",
            "Keyboard Shortcuts",
            "About Sara",
        ],
        "Help is the welcome, the manual, the colour spaces, the report, the note, the three settings pages and About"
    )
    assert_eq(
        _column("Filter"),
        [["Apply Filter Again", &"filter_apply_again"], ["Browse Filters...", &"filter_browse"]],
        "Filter, with no module loaded, is Apply Again over its browser"
    )
    var filter: SaChoicePopup = _bar.menus["Filter"]
    assert_eq(filter.section_titles(), [], "and carries no Writing a filter heading")


## Reload Shaders is a command of the base app. As a row of Develop it would be
## drawn twice, so its command does not ask for an action row, and the
## menu has no heading but its two.
func test_reload_shaders_is_one_row_and_no_action_heading() -> void:
    var registry: SaCommandRegistry = _bar.menu("Modules").commands
    var descriptor := registry.get_descriptor(&"modules_reload_shaders")
    assert_not_null(descriptor, "Reload Shaders is registered")
    if descriptor == null:
        return
    assert_false(descriptor.show_in_modules_menu, "and asks for no row among the modules' actions")
    var rows := 0
    var popup: SaChoicePopup = _bar.menus["Modules"]
    for label: String in popup.row_labels():
        if label == "Reload Shaders":
            rows += 1
    assert_eq(rows, 1, "so the menu draws it once")
    assert_eq(popup.section_titles(), ["Develop"], "under Develop, with no heading for the skeleton")


## A module's own action still has its heading, between the list and Develop,
## so Develop stays the end of the menu with a module's rows in it.
func test_a_modules_action_sits_between_the_list_and_develop() -> void:
    var registry: SaCommandRegistry = _bar.menu("Modules").commands
    var action := SaCommandDescriptor.create(&"n49_probe_action", "Probe action", func() -> bool: return true)
    action.label = "Probe Action"
    action.show_in_modules_menu = true
    # No InputMap action, so the probe leaves nothing behind for the suites
    # that read every action the map holds.
    action.action = &""
    registry.register(action, &"n49-probe")
    _bar.menu("Modules").populate()
    var column := _column("Modules")
    var probe := column.find(["Probe Action", &"n49_probe_action"])
    var develop := column.find([">", "Develop"])
    assert_true(probe > 0, "the module's action is drawn: %s" % [column])
    assert_true(probe < develop, "above Develop")
    assert_eq(column.slice(develop + 1), DEVELOP, "which still ends the menu")
    registry.unregister_module(&"n49-probe")


## Edit keeps its Preferences row, because Settings has no menu of its own.
func test_edit_keeps_preferences() -> void:
    var found := false
    for row: Array in _column("Edit"):
        if row.size() == 2 and row[1] == &"edit_preferences":
            found = true
    assert_true(found, "Edit has a row for Preferences")


## The kernel prompt's file and the step that reads it moved with the row, so
## the Filter menu's file names neither.
func test_the_prompt_moved_with_its_row() -> void:
    var filter := FileAccess.get_file_as_string("res://ui/menus/filter_menu.gd")
    assert_false(filter.is_empty(), "the Filter menu's file is readable")
    assert_false(filter.contains("kernel_prompt.txt"), "and does not name the prompt's file")
    assert_false(filter.contains("filter_copy_prompt"), "or the row's command")
    assert_eq(SaModulesMenu.PROMPT_PATH, "res://core/custom-shader/kernel_prompt.txt", "Modules reads the committed prompt")
    var steps := FileAccess.get_file_as_string("res://harness/sa_step_table.gd")
    assert_true(steps.contains("SaModulesMenu.capture("), "and the kernel_prompt step asks Modules")
