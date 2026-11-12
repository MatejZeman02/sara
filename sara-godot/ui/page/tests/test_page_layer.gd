## The declarative page layer: declare, realize, update, and nothing else.
##
## Every claim the layer makes is here: a page
## of every kind built offscreen, each control changed and its binding read,
## a binding changed behind the page's back and its control read, dimming and
## hiding by value, a rebuild that keeps the values, and the description the
## dump prints. The scenario of the same name is the other half, because a
## suite that passes while the page is unreadable is a failure the gate must catch.
extends "res://tests/test_framework.gd"


## A binding target with no `changed` signal at all, which is the case the
## re-read on open exists for.
class Plain:
    extends RefCounted

    var amount: float = 1.0
    var label: String = ""


var _knobs: SaPageDemo.Knobs = null
var _plain: Plain = null
var _host: VBoxContainer = null
var _page: SaPage = null


func _declare(ui: SaPage) -> void:
    var kinds := ui.section("Every kind")
    kinds.toggle("Rolloff", _knobs, ^"rolloff").explain("Decides the two below.").dims(&"knee").hides(&"shoulder")
    kinds.slider("Exposure", -5.0, 5.0, _knobs, ^"exposure").step(0.1).decimals(1)
    kinds.number("Frames", 1.0, 120.0, _knobs, ^"frames")
    kinds.choice("Mode", ["Normal", "Raw", "Heatmap"], _knobs, ^"mode")
    kinds.text("Folder", _knobs, ^"folder")
    kinds.colour("Ink", _knobs, ^"ink")
    kinds.path("Library", _knobs, ^"library")
    kinds.action("Reset the knobs", _reset)
    kinds.note("A note has no binding and no value.")
    kinds.custom("Readout", Label.new())
    kinds.slider("Radius", 1.0, 20.0).step(1.0).decimals(0)
    kinds.slider("Amount", 0.0, 4.0, _plain, ^"amount")

    var under := ui.section("Under the toggle")
    under.slider("Knee", 0.0, 1.0, _knobs, ^"knee")
    under.number("Shoulder", 0.0, 8.0, _knobs, ^"shoulder")


func _reset() -> void:
    _knobs.exposure = 0.0


func _build() -> void:
    _knobs = SaPageDemo.Knobs.new()
    _plain = Plain.new()
    _host = VBoxContainer.new()
    _page = SaPage.new(_declare)
    _page.declare_rows()
    _page.realize(_host)


func _tear_down() -> void:
    if _host != null:
        _host.free()
    _host = null
    _page = null


func _control(key: StringName) -> Control:
    var row := _page.row(key)
    return row.control if row != null else null


## Moves a control the way a hand does, through `SaPageDemo.drive`, which is
## also what the scenario's step calls. Half the controls do not emit for a
## script: `OptionButton.select` never does and a `Range` assigned to by a
## script emits a frame later or not at all, so a suite that only assigns
## proves nothing about the wiring.
func _move(key: StringName, value: Variant) -> void:
    _page.row(key).drive(value)


func test_a_page_of_every_kind_builds_offscreen() -> void:
    _build()
    assert_eq(_page.sections.size(), 2, "two sections")
    assert_eq(_page.sections[0].title, "Every kind", "the first section keeps its title")
    assert_eq(_page.rows().size(), 14, "fourteen rows declared")

    var kinds := {}
    for row in _page.rows():
        kinds[SaPageRow.KIND_NAMES[row.kind]] = true
    for kind_name in SaPageRow.KIND_NAMES:
        assert_true(kinds.has(kind_name), "a %s row is on the page" % kind_name)

    assert_true(_control(&"rolloff") is CheckButton, "a toggle draws a CheckButton")
    assert_true(_control(&"exposure") is HSlider, "a slider draws an HSlider")
    assert_true(_control(&"frames") is SpinBox, "a number draws a SpinBox")
    assert_true(_control(&"mode") is SaChoiceButton, "a choice draws Sara's own choice button")
    assert_true(_control(&"folder") is LineEdit, "a text row draws a LineEdit")
    assert_true(_control(&"ink") is ColorPickerButton, "a colour row draws the colour button")
    assert_true(_control(&"reset_the_knobs") is Button, "an action draws a Button")
    assert_eq((_control(&"rolloff") as CheckButton).text, "", "and a switch carries no label of its own")
    assert_eq((_control(&"frames") as SpinBox).prefix, "", "nor does a spin box")
    _tear_down()


func test_every_row_reads_its_binding_when_the_page_is_realized() -> void:
    _build()
    assert_eq((_control(&"rolloff") as CheckButton).button_pressed, true, "the toggle read the knob")
    assert_almost_eq((_control(&"frames") as SpinBox).value, 24.0, 0.001, "the spin box read the knob")
    assert_eq((_control(&"folder") as LineEdit).text, "~/pictures", "the text row read the knob")
    assert_eq((_control(&"mode") as SaChoiceButton).selected_value(), 0, "the choice read the knob")
    assert_eq((_control(&"ink") as ColorPickerButton).color, _knobs.ink, "the colour row read the knob")
    _tear_down()


func test_each_control_writes_the_binding_the_row_declares() -> void:
    _build()
    _move(&"rolloff", false)
    assert_eq(_knobs.rolloff, false, "the toggle wrote the knob")

    _move(&"exposure", 2.5)
    assert_almost_eq(_knobs.exposure, 2.5, 0.001, "the slider wrote the knob")

    _move(&"frames", 48.0)
    assert_eq(_knobs.frames, 48, "the spin box wrote the knob, rounded to the int the property holds")

    _move(&"mode", 2)
    assert_eq(_knobs.mode, 2, "the choice wrote the id of the row it selected")

    _move(&"folder", "/tmp/frames")
    assert_eq(_knobs.folder, "/tmp/frames", "the text row wrote on submit")
    var edit := _control(&"folder") as LineEdit
    edit.text = "/tmp/other"
    edit.focus_exited.emit()
    assert_eq(_knobs.folder, "/tmp/other", "and on focus loss, which is the second commit path")

    _move(&"ink", "#ff0080ff")
    assert_eq(_knobs.ink, Color("#ff0080ff"), "the colour row wrote the knob")

    _move(&"reset_the_knobs", null)
    assert_almost_eq(_knobs.exposure, 0.0, 0.001, "the action row called what it was given")
    _tear_down()


func test_a_row_with_no_binding_holds_its_own_value() -> void:
    _build()
    var radius := _page.row(&"radius")
    assert_eq(radius.bound_to(), "itself", "an unbound row says so")
    _move(&"radius", 7.0)
    assert_almost_eq(float(radius.value), 7.0, 0.001, "and holds what the control wrote")
    _tear_down()


func test_a_binding_changed_behind_the_page_reaches_the_control() -> void:
    _build()
    _knobs.exposure = -3.0
    assert_almost_eq((_control(&"exposure") as HSlider).value, -3.0, 0.001, "a target that says it changed updates the control")
    assert_almost_eq(_knobs.exposure, -3.0, 0.001, "and the refresh did not write the value back")

    _plain.amount = 3.0
    assert_almost_eq((_control(&"amount") as HSlider).value, 1.0, 0.001, "a silent target is not noticed on its own")
    _page.refresh()
    assert_almost_eq((_control(&"amount") as HSlider).value, 3.0, 0.001, "and is re-read when the page opens")
    _tear_down()


func test_a_rule_dims_and_hides_by_value() -> void:
    _build()
    var knee := _page.row(&"knee")
    var shoulder := _page.row(&"shoulder")
    assert_true(SaOptionSpec.row_reads_enabled(knee.line), "Knee is live while Rolloff is on")
    assert_true(shoulder.line.visible, "Shoulder is on the page while Rolloff is on")

    _move(&"rolloff", false)
    assert_false(SaOptionSpec.row_reads_enabled(knee.line), "Rolloff off dims Knee and disables it")
    assert_almost_eq(knee.line.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "at the one dim alpha")
    assert_false((knee.control as HSlider).editable, "dimmed means disabled, the standing rule")
    assert_false(shoulder.line.visible, "and takes Shoulder off the page")

    _move(&"rolloff", true)
    assert_true(SaOptionSpec.row_reads_enabled(knee.line), "and both come back")
    assert_true(shoulder.line.visible, "Shoulder with them")
    _tear_down()


func test_the_layer_takes_one_dim_alpha() -> void:
    assert_almost_eq(SaPage.DIMMED_ALPHA, 0.4, 0.0001, "the dimmed alpha is 0.4")
    assert_almost_eq(SaPage.DIMMED_ALPHA, SaOptionSpec.DIMMED_ALPHA, 0.0001, "by taking the number the tool rows enforce")


func test_a_rebuild_keeps_the_values() -> void:
    _build()
    _move(&"exposure", 4.0)
    _move(&"radius", 12.0)
    var before := _page.describe()

    _page.rebuild()
    assert_eq(_page.rows().size(), 14, "the declaration ran again")
    assert_almost_eq((_control(&"exposure") as HSlider).value, 4.0, 0.001, "a bound row came back from its target")
    assert_almost_eq((_control(&"radius") as HSlider).value, 12.0, 0.001, "and an unbound one from what the page kept")
    assert_eq(JSON.stringify(_page.describe()), JSON.stringify(before), "so the page describes itself the same way")
    _tear_down()


func test_the_page_says_what_it_is() -> void:
    _build()
    _move(&"rolloff", false)
    var described := _page.describe()
    assert_eq(int(described["rows"]), 14, "the description counts the rows")
    var sections: Array = described["sections"]
    assert_eq(sections.size(), 2, "and holds both sections")

    var by_key := {}
    for block: Dictionary in sections:
        for row: Dictionary in block["rows"] as Array:
            by_key[String(row["key"])] = row
    assert_eq(String((by_key["exposure"] as Dictionary)["kind"]), "slider", "a row says its kind")
    assert_eq(String((by_key["exposure"] as Dictionary)["label"]), "Exposure", "and its label")
    assert_true(String((by_key["exposure"] as Dictionary)["bound_to"]).ends_with(".exposure"), "and what it is bound to")
    assert_eq(String((by_key["radius"] as Dictionary)["bound_to"]), "itself", "an unbound row says itself")
    assert_false(bool((by_key["knee"] as Dictionary)["live"]), "a dimmed row reads as dead")
    assert_false(bool((by_key["shoulder"] as Dictionary)["shown"]), "a hidden row reads as off the page")
    assert_eq(
        String(((by_key["rolloff"] as Dictionary)["dims"] as Array)[0]["row"]),
        "knee",
        "and the row that decides names what it decides"
    )
    assert_true(JSON.stringify(described).length() > 0, "the whole description is JSON a dump can carry")
    _tear_down()


func test_a_key_that_collides_is_renamed_rather_than_shadowed() -> void:
    var page := SaPage.new()
    var block := page.section("Twice")
    block.slider("Radius", 0.0, 1.0)
    block.slider("Radius", 0.0, 1.0)
    page.declare_rows()
    assert_not_null(page.row(&"radius"), "the first keeps the key its label gives it")
    assert_not_null(page.row(&"radius_2"), "the second is numbered rather than shadowing it")
    assert_eq(page.rows().size(), 2, "and both rows are on the page")


## What the Preferences pages need of the layer and the demo never asked for,
## one row per gap, on a page of its own so the fourteen rows
## above stay fourteen.
var _own_delete: Button = null
var _span: Control = null


func _declare_needs(ui: SaPage) -> void:
    var needs := ui.section("What the pages need")
    needs.toggle("Rolloff", _knobs, ^"rolloff").dims(&"knee")
    needs.slider("Knee", 0.0, 1.0, _knobs, ^"knee").node("KneeSlider")
    needs.action("Reset all preferences", _reset).button("Reset")
    needs.action("Start again", _reset)
    _own_delete = Button.new()
    _own_delete.disabled = true
    needs.custom("Delete theme", _own_delete).words("remove palette")
    _span = Control.new()
    _span.size_flags_vertical = Control.SIZE_EXPAND_FILL
    needs.custom("", _span)
    var wide := LineEdit.new()
    wide.size_flags_horizontal = Control.SIZE_SHRINK_END
    needs.custom("Kept width", wide)
    needs.text("Folder", _knobs, ^"folder").globalized()
    needs.path("Library", _knobs, ^"library").globalized()
    needs.note("Restart to see it.").named(&"restart").node("RestartNote")


func _build_needs(host: VBoxContainer = null) -> void:
    _knobs = SaPageDemo.Knobs.new()
    _knobs.folder = SaDataRoot.path("frames")
    _knobs.library = ""
    _host = host if host != null else VBoxContainer.new()
    _page = SaPage.new(_declare_needs)
    _page.declare_rows()
    _page.realize(_host)


func test_a_rule_pass_leaves_a_row_no_rule_names_alone() -> void:
    _build_needs()
    var note := _page.row(&"restart").line
    note.visible = false
    _move(&"rolloff", false)
    assert_true(_own_delete.disabled, "the page's own disabled button is still disabled after another row changed")
    assert_false(note.visible, "and the note the page hid is still hidden")
    assert_false(SaOptionSpec.row_reads_enabled(_page.row(&"knee").line), "while the row a rule names did dim")
    _move(&"rolloff", true)
    assert_true(_own_delete.disabled, "and the pass that brings Knee back does not enable it either")
    _tear_down()


func test_an_action_row_with_button_words_has_a_title_of_its_own() -> void:
    _build_needs()
    var titled := _page.row(&"reset_all_preferences")
    assert_eq(String(titled.line.get_meta(SaSettingsRows.TITLE_META)), "Reset all preferences", "the label is the row's title")
    assert_eq((titled.control as Button).text, "Reset", "and the button carries its own words")
    assert_true(SaSettingsSearch.row_haystack(titled.line).contains("reset all"), "so the search finds the row")
    var bare := _page.row(&"start_again")
    assert_eq(String(bare.line.get_meta(SaSettingsRows.TITLE_META)), "", "a row that declared none keeps an empty title")
    assert_eq((bare.control as Button).text, "Start again", "and its label on the button")
    _tear_down()


## The control sits in the rows container itself, which is what
## the Preferences pages asked for.
func test_a_custom_row_with_no_label_spans_the_page() -> void:
    _build_needs()
    var spanning: SaPageRow = null
    for entry in _page.rows():
        if entry.custom_control == _span:
            spanning = entry
    assert_not_null(spanning, "the page holds the spanning row")
    assert_eq(spanning.line, _span, "the row's line is the control itself")
    var rows_box := _page.row(&"rolloff").line.get_parent()
    assert_eq(_span.get_parent(), rows_box, "which stands in the rows container beside the other lines")
    assert_false(_span.has_meta(SaSettingsRows.ROW_META), "a spanning row is not a row to the search or the column check")
    assert_eq(_span.size_flags_horizontal, Control.SIZE_FILL, "the control keeps the default width flag it came with")
    assert_eq(_span.size_flags_vertical, Control.SIZE_EXPAND_FILL, "and the height flag it was handed over with")
    _tear_down()


func test_a_spanning_row_takes_the_width_of_the_rows() -> void:
    var host := VBoxContainer.new()
    EventBus.add_child(host)
    host.size = Vector2(600.0, 400.0)
    _build_needs(host)
    _sort(host)
    var rows_box := _span.get_parent() as Control
    assert_almost_eq(_span.position.x, 0.0, 0.5, "the spanning control starts at the rows' left edge")
    assert_almost_eq(_span.size.x, rows_box.size.x, 0.5, "and is as wide as they are")
    _tear_down()


## Top down, so every container sorts inside the size its parent just gave it,
## the way `test_filter_dialog_columns` lays a dialog out with no frame.
func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


func test_a_custom_control_keeps_the_width_flag_it_came_with() -> void:
    _build_needs()
    var wide := _page.row(&"kept_width").control
    assert_eq(wide.size_flags_horizontal, Control.SIZE_SHRINK_END, "a LineEdit handed over shrunk to the end stays there")
    assert_true(_page.row(&"kept_width").line.has_meta(SaSettingsRows.ROW_META), "and a labelled custom row is still a row")
    assert_eq(
        _own_delete.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, "one that asked for nothing sits at the column's left edge"
    )
    _tear_down()


func test_a_slider_row_draws_the_width_and_the_tooltip_the_pages_draw() -> void:
    _build_needs()
    var slider := _control(&"knee") as HSlider
    var readout := slider.get_parent().get_node(NodePath(SaPage.READOUT_NAME)) as Label
    assert_almost_eq(readout.custom_minimum_size.x, float(SaUI.px(44)), 0.001, "the readout is slider_row's 44 and not 64")
    assert_eq(slider.tooltip_text, "Knee", "and the slider carries its title as a tooltip")
    _tear_down()


func test_node_names_the_control_the_builder_makes() -> void:
    _build_needs()
    assert_eq(String(_control(&"knee").name), "KneeSlider", "the HSlider of a slider row")
    assert_true(_host.find_child("KneeSlider", true, false) is HSlider, "so a suite finds it by name")
    assert_eq(String(_page.row(&"restart").line.name), "RestartNote", "and the Label of a note")
    assert_not_null(_page.row(&"restart"), "a row named after it was declared answers to that name")
    assert_eq(String(_page.row(&"knee").describe()["node"]), "KneeSlider", "and the description says so")
    _tear_down()


func test_a_globalized_row_shows_a_real_path_and_stores_what_was_typed() -> void:
    _build_needs()
    var edit := _control(&"folder") as LineEdit
    assert_eq(edit.text, ProjectSettings.globalize_path(SaDataRoot.path("frames")), "the field shows the real folder")
    edit.focus_exited.emit()
    assert_eq(_knobs.folder, SaDataRoot.path("frames"), "leaving it untouched does not store the real path over user://")
    _move(&"folder", SaDataRoot.path("other"))
    assert_eq(_knobs.folder, SaDataRoot.path("other"), "what was typed is what is stored")
    assert_eq(edit.text, ProjectSettings.globalize_path(SaDataRoot.path("other")), "and the field re-reads it as a real path")
    _tear_down()


func test_words_are_words_the_search_finds_the_row_by() -> void:
    _build_needs()
    var line := _page.row(&"delete_theme").line
    assert_true(SaSettingsSearch.row_haystack(line).contains("remove palette"), "a word given only to words() is in the haystack")
    assert_false(SaSettingsSearch.row_haystack(_page.row(&"knee").line).contains("palette"), "and in no other row's")
    assert_eq(String(_page.row(&"delete_theme").describe()["words"]), "remove palette", "the description carries them")
    _tear_down()


func test_a_refresh_leaves_a_field_that_has_the_keyboard_alone() -> void:
    var host := VBoxContainer.new()
    EventBus.add_child(host)
    _build_needs(host)
    var edit := _control(&"folder") as LineEdit
    edit.grab_focus()
    assert_true(edit.has_focus(), "the field holds the keyboard")
    edit.text = "half a wor"
    _knobs.folder = SaDataRoot.path("behind")
    _page.refresh()
    assert_eq(edit.text, "half a wor", "a refresh does not write over what is being typed")
    edit.release_focus()
    assert_eq(_knobs.folder, "half a wor", "so leaving the field commits the words typed and not the ones a refresh put back")
    _tear_down()


func test_a_path_row_that_wrote_shows_what_the_binding_now_holds() -> void:
    _build_needs()
    var row := _page.row(&"library")
    var shown := row.control.find_child("PathLabel", true, false) as Label
    row.control.find_children("*", "Button", true, false)[1].pressed.emit()
    assert_eq(shown.text, "", "Use Default shows the empty default at once, with no refresh")
    SaPage._wrote(_page, row, SaDataRoot.path("library"))
    assert_eq(_knobs.library, SaDataRoot.path("library"), "a chosen folder is stored as handed over")
    assert_eq(
        shown.text,
        ProjectSettings.globalize_path(SaDataRoot.path("library")),
        "and shown as the real one, re-read from the binding"
    )
    _tear_down()
