## The stabiliser is named in full on every row of the bar, and its menu rows
## say what they do.
##
## The toggle reads "Stabilizer" on every row and in the overflow's list, never
## the cut "Stab", its tooltip says what it does, and each mode carries its
## sentence on its choice, which the Tools menu and the docker's list both
## show. The painting mode keeps the name Cross, so the suite holds that too.
## `scenarios/the-stabiliser-is-named-in-full.json` shows it in the app.
extends "res://tests/test_framework.gd"

## The bar's controls come from the tools' descriptors, which need a machine
## and a surface, and both need a device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModule = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

const PROFILE := "test_n124_stabiliser_named.cfg"

## The three sentences, by the mode they explain.
const SENTENCES := {
    0: "No smoothing at all.",
    1: "Follows a short distance behind the pen.",
    2: "Follows on a longer, springier line.",
}

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: TopMenuBar = null
## The node an in-tree bar hangs from, and the root's embedding before it did.
var _host: Node = null
var _kept_embedding: bool = true
## A detached control the docker's rows are built under.
var _rows: Control = null


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path(PROFILE))
    _remove_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    if _rows != null:
        _rows.free()
        _rows = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path(PROFILE)) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, readied by hand and
## then hung in the tree, because the toggle settles its word as it enters the
## tree and a bar that never does is not one a painter sees. The root embeds
## while it stands, since the bar's menus are windows.
func _bar_in_tree(width: float) -> TopMenuBar:
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    bar.set_anchor(SIDE_RIGHT, 0.0)
    bar.size.x = width
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N124TopBarTestHost"
    EventBus.add_child(_host)
    _host.add_child(bar)
    bar.rows.refit()
    return bar


## The toggle as the bar's own report says it, which is what a dump prints.
func _toggle_report() -> Dictionary:
    return _bar.rows._options.bar_report().get("stabilizer_toggle", {})


func test_the_toggle_reads_stabilizer_on_either_row() -> void:
    # Wide enough that nothing leaves the first row for the overflow, so the
    # toggle is on the row the order puts it on.
    _bar = _bar_in_tree(4000.0)
    var toggle: Button = _bar.rows._options.stabilizer_btn
    assert_eq(toggle.get_parent(), _bar.rows._options, "With one row the toggle sits on the first")
    assert_eq(toggle.text, "Stabilizer", "where it reads in full, with no cut word")
    assert_false(bool(_toggle_report().get("on_second_row", true)), "and the report says the first row")

    SaSettings.second_row = true
    assert_eq(toggle.get_parent(), _bar.rows.second_options_row, "The second row takes it")
    assert_eq(toggle.text, "Stabilizer", "and there it reads the same")
    assert_eq(String(_toggle_report().get("text", "")), "Stabilizer", "which the report prints")

    SaSettings.second_row = false
    assert_eq(toggle.get_parent(), _bar.rows._options, "Back on the first row")
    assert_eq(toggle.text, "Stabilizer", "it keeps its name")


func test_the_toggle_reads_in_full_in_the_overflows_list() -> void:
    _bar = _bar_in_tree(4000.0)
    assert_true(SaTopBarOverflow.enabled(), "The overflow is the default")
    var toggle: Button = _bar.rows._options.stabilizer_btn
    # The toggle is among the first to leave a short row, so a narrow bar sends
    # it to the list before Size and Opacity.
    _bar.size.x = 900.0
    _bar.rows.refit()
    assert_eq(toggle.get_parent(), _bar.rows.overflow.box, "A narrow first row sends the toggle to the overflow")
    assert_eq(toggle.text, "Stabilizer", "where the list shows its name")
    _bar.size.x = 4000.0
    _bar.rows.refit()
    assert_eq(toggle.get_parent(), _bar.rows._options, "Wide again, it is back on the first row")
    assert_eq(toggle.text, "Stabilizer", "under the same name")


## The button says Stabilizer itself, so its tooltip says what it does rather
## than the name again.
func test_the_toggles_tooltip_says_what_it_does() -> void:
    _bar = _bar_in_tree(4000.0)
    var toggle: Button = _bar.rows._options.stabilizer_btn
    assert_true(
        toggle.tooltip_text.begins_with("Steady the stroke."), "The tooltip says what it does: '%s'" % toggle.tooltip_text
    )
    assert_false(toggle.tooltip_text.begins_with("Stabilizer"), "and does not repeat the name")


func test_each_mode_carries_s2s_sentence() -> void:
    var spec := _stamp_spec(&"stabilizer_mode")
    assert_not_null(spec, "The brush declares a stabilizer")
    if spec == null:
        return
    assert_eq(spec.choices.size(), SENTENCES.size(), "three modes")
    for choice: Dictionary in spec.choices:
        assert_eq(String(choice.get("tooltip", "")), SENTENCES[int(choice["id"])], "%s explains itself" % choice["label"])


func test_the_tools_menu_shows_each_modes_sentence() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    var menu := _bar.menu("Tools") as SaToolsMenu
    assert_not_null(menu, "The bar has a Tools menu")
    if menu == null:
        return
    menu.machine = _machine
    menu.populate()
    var spec: SaOptionSpec = SaToolsMenu.stabilizer_owner(_machine).get("spec", null)
    assert_not_null(spec, "and a tool whose stabilizer it offers")
    if spec == null:
        return
    for index in spec.choices.size():
        var row := menu.popup.label_button(SaToolsMenu.key(SaToolsMenu.STABILIZER_ROW_BASE + index))
        assert_not_null(row, "row %d is in the menu" % index)
        if row == null:
            continue
        assert_eq(row.text, String(spec.choices[index]["label"]), "under its mode's name")
        assert_eq(row.tooltip_text, SENTENCES[int(spec.choices[index]["id"])], "%s says what it does" % row.text)


func test_the_dockers_list_and_the_bars_show_each_modes_sentence() -> void:
    _rows = Control.new()
    var docker := ToolOptionControls.new(_rows)
    docker.for_docker = true
    docker.build_for(_machine.get_descriptor(SaToolsMenu.stabilizer_owner(_machine).get("id", &"")))
    _assert_rows_explain(docker.control(&"stabilizer_mode") as SaChoiceButton, "The docker's")

    _bar = _bar_in_tree(4000.0)
    _assert_rows_explain(_bar.rows._options.control_for(&"stabilizer_mode") as SaChoiceButton, "The bar's")


func test_cross_is_still_the_painting_modes_name() -> void:
    var spec: SaOptionSpec = null
    for row: SaOptionSpec in StampModule.tip_options():
        if row.key == &"painting_mode":
            spec = row
    assert_not_null(spec, "The brush declares a painting mode")
    if spec != null:
        assert_eq(spec.label, "Cross", "and the maintainers' word for it stands")


func _assert_rows_explain(option: SaChoiceButton, surface: String) -> void:
    assert_not_null(option, "%s stabilizer is a choice" % surface)
    if option == null:
        return
    assert_eq(String(option.name), "StabilizerModeOpt", "%s keeps the name a scenario finds" % surface)
    for value: Variant in option.choice_values():
        var row := option.popup.label_button(SaChoiceButton.row_id_of(value))
        assert_not_null(row, "%s list holds mode %s" % [surface, value])
        if row != null:
            assert_eq(row.tooltip_text, SENTENCES[int(value)], "%s row %s says what it does" % [surface, row.text])


func _stamp_spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in StampModule.brush_options():
        if spec.key == key:
            return spec
    return null
