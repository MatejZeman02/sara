## The settings page base and the binding for a setting that is a call.
##
## Every page here is built and freed off the tree, which is how the search and
## `test_settings_pages.gd` meet a Preferences page, so a base that drew only in
## `_ready` would fail every case below.
extends "res://tests/test_framework.gd"


## What the plain page binds to. A member of the page rather than a static,
## because the page holds it and nothing holds the page back.
class Knobs:
    extends RefCounted

    var enabled: bool = true
    var amount: float = 0.25


## A page with no constructor of its own, a toggle and a slider.
class PlainPage:
    extends SaSettingsPage

    var knobs := Knobs.new()

    func build(ui: SaPage) -> void:
        var rows := ui.section("Plain")
        rows.toggle("Enabled", knobs, ^"enabled")
        rows.slider("Amount", 0.0, 1.0, knobs, ^"amount")


## A page that takes a constructor argument, which `build` has to see: the
## shape of the layout page and the brush slots page.
class ArgPage:
    extends SaSettingsPage

    var store: Knobs = null
    var seen: Knobs = null

    func _init(given: Knobs) -> void:
        store = given
        super()

    func build(ui: SaPage) -> void:
        seen = store
        var rows := ui.section("With an argument")
        rows.toggle("Enabled", store, ^"enabled")
        rows.number("Amount", 0.0, 10.0, store, ^"amount")


## A setting that is a call: statics over a dictionary, standing in for
## `SaSettings.get_docker_option` so no case writes the person's preferences.
class Calls:
    static var values: Dictionary = {}
    static var reads: int = 0
    static var writes: int = 0

    static func read(key: StringName) -> Variant:
        reads += 1
        if key == &"folder":
            # The settings folder answers "" with the default, which is why a
            # row that wrote has to read again.
            var stored := String(values.get(key, ""))
            return "/default" if stored.is_empty() else stored
        return values.get(key, null)

    static func write(key: StringName, value: Variant) -> void:
        writes += 1
        values[key] = value


class CallPage:
    extends SaSettingsPage

    func build(ui: SaPage) -> void:
        var binding := SaPageBinding.new(Calls.read, Calls.write)
        var rows := ui.section("Calls")
        rows.toggle("Thumbnails", binding, ^"thumbnails")
        rows.text("Folder", binding, ^"folder")


func before_each() -> void:
    Calls.values = {&"thumbnails": true, &"folder": "/somewhere"}
    Calls.reads = 0
    Calls.writes = 0


func _row_lines(page: Node) -> Array[Node]:
    var out: Array[Node] = []
    for line in page.find_children("*", "HBoxContainer", true, false):
        if line.has_meta(SaSettingsRows.ROW_META):
            out.append(line)
    return out


func test_the_rows_exist_when_new_returns() -> void:
    var page := PlainPage.new()
    assert_false(page.is_inside_tree(), "built off the tree")
    assert_not_null(page.page, "the base declared a page")
    assert_eq(page.page.rows().size(), 2, "both rows declared")
    assert_eq(_row_lines(page).size(), page.page.rows().size(), "one ROW_META line per declared row")
    assert_eq(page.name, String(SaSettingsPage.NODE_NAME), "the page answers the name the dump keys it by")
    assert_true(page.has_meta(SaPage.PAGE_META), "the dump's pages block finds it")
    assert_eq((page.page.row(&"enabled").control as CheckButton).button_pressed, true, "the toggle read its binding")
    assert_almost_eq((page.page.row(&"amount").control as Range).value, 0.25, 0.0001, "the slider read its binding")
    page.free()


func test_the_shape_rules_of_the_settings_pages_hold() -> void:
    var page := ArgPage.new(Knobs.new())
    for check in page.find_children("*", "CheckButton", true, false):
        assert_eq((check as CheckButton).text, "", "a switch carries no label of its own")
    for spin in page.find_children("*", "SpinBox", true, false):
        assert_eq((spin as SpinBox).prefix, "", "a spin box carries no label of its own")
    var lines := _row_lines(page)
    assert_eq(lines.size(), 2, "both rows drawn")
    for line in lines:
        var labels := line.get_child(0) as VBoxContainer
        assert_not_null(labels, "a row starts with its label column")
        if labels != null:
            assert_eq(int(labels.custom_minimum_size.x), SaUI.px(SaSettingsRows.LABEL_WIDTH), "and it is LABEL_WIDTH")
    page.free()


func test_a_constructor_argument_is_visible_inside_build() -> void:
    var given := Knobs.new()
    given.amount = 7.0
    var page := ArgPage.new(given)
    assert_true(page.seen == given, "build ran after the field was set")
    assert_almost_eq((page.page.row(&"amount").control as Range).value, 7.0, 0.0001, "and bound its row to it")
    page.free()


func test_a_row_bound_through_a_binding_reads_and_writes_through_the_calls() -> void:
    var page := CallPage.new()
    assert_true(Calls.reads > 0, "realizing read through the reader")
    assert_eq(
        (page.page.row(&"thumbnails").control as CheckButton).button_pressed, true, "the toggle shows what the reader answered"
    )
    assert_eq((page.page.row(&"folder").control as LineEdit).text, "/somewhere", "the text row too")

    page.page.row(&"thumbnails").write(false)
    assert_eq(Calls.writes, 1, "a write reached the writer")
    assert_eq(Calls.values[&"thumbnails"], false, "with the value")

    Calls.values[&"thumbnails"] = true
    page.page.refresh()
    assert_eq(
        (page.page.row(&"thumbnails").control as CheckButton).button_pressed, true, "a change behind the page is read on refresh"
    )
    page.free()


func test_a_write_re_reads_what_the_target_made_of_the_value() -> void:
    var page := CallPage.new()
    page.page.row(&"folder").write("")
    assert_eq(Calls.values[&"folder"], "", "the empty folder was stored")
    assert_eq(
        (page.page.row(&"folder").control as LineEdit).text,
        "/default",
        "the binding's changed signal made the page show the default"
    )
    page.free()


func test_an_unknown_name_is_left_to_the_engine() -> void:
    var binding := SaPageBinding.new(Calls.read, Calls.write)
    assert_null(binding.get(&"nothing_here"), "a name the reader does not know reads as null")
    assert_not_null(binding.get_script(), "the object's own script is still its own")
    assert_true(binding.has_signal("changed"), "and so is its signal")


func test_fifty_builds_leave_the_object_count_where_it_was() -> void:
    # One build first, so a cache the first page fills is not read as a leak.
    # No row here carries an explanation: every hint label files a WeakRef with
    # `SaTheme.bind_font` that stays until the next theme switch, one object a
    # row, which is not this base's to free.
    PlainPage.new().free()
    CallPage.new().free()
    var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
    for i in 50:
        PlainPage.new().free()
        ArgPage.new(Knobs.new()).free()
        CallPage.new().free()
    var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
    assert_eq(after, before, "every page, row and binding went with its node")
