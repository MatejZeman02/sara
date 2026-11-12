## The top bar and the Tablet page fit a 1280 pixel screen.
##
## At 1280 by 1024 on Windows: "Keep blend" drawn as
## `Keep blenc` with the slot's arrow over its last letter from the first frame
## on, the preset button reading `Soft Er` with no ellipsis, and the Tablet
## page's `0%` wrapped onto a line of its own. The first came back whole after
## a menu was opened and closed, which is a split made once against widths that
## grew afterwards.
##
## The bar is built detached the way `test_the_second_bar_overflows_rather_than_growing_a_row.gd`
## builds it, so its signals are sent by hand where Godot would send them a
## frame later. `scenarios/the-top-bar-and-the-tablet-page-fit-a-1280-pixel-screen.json`
## photographs the same in the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a machine, a
## surface and therefore a device.
const REQUIRES_GPU := true

## The screen widths the row names, the sweep's and two common ones.
const WIDTHS: Array[float] = [1280.0, 1366.0, 1920.0]

static var scratch_profile: String = SaDataRoot.path("test_bar_fits.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    # The one-row bar the sweep met at 1280. A fresh profile shows two rows,
    # and its first row then holds no option to cut.
    SaSettings.second_row = false


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    if _host != null:
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _bar() -> TopMenuBar:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    # A detached bar keeps the width written to it only with its anchors
    # pinned together.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    return bar


## The bar in the tree, under an autoload, because a detached control keeps the
## minimum width it first measured and a grown one would never read as grown.
## Not under the root, which the runner's own `_ready` is still filling
func _bar_in_tree() -> TopMenuBar:
    var bar := _bar()
    _host = Control.new()
    _host.name = "TestHost"
    EventBus.add_child(_host)
    _host.add_child(bar)
    return bar


func _lay_out(bar: TopMenuBar, width: float) -> void:
    bar.size.x = width
    bar.apply_layout_settings()


## Every shown control is on a row that holds it whole, or in the list. A row
## over its budget is one whose slot scrolls the end of a control under its
## arrow, which is the cut the sweep saw.
func _assert_whole(bar: TopMenuBar, tag: String) -> void:
    var rows := bar.rows
    var elements := rows.elements()
    for row: int in [1, 2]:
        if row == 2 and not rows.second_row.visible:
            continue
        assert_true(
            rows.row_spent(row) <= rows.row_budget(row) + 0.5,
            "%s: row %d holds what it shows whole, %d of %d" % [tag, row, int(rows.row_spent(row)), int(rows.row_budget(row))]
        )
    for element: String in elements:
        var node: Control = elements[element]
        if node == null or not node.visible:
            continue
        var parent := node.get_parent()
        assert_true(
            parent == rows.overflow.box or parent == rows.row_container(1) or parent == rows.row_container(2),
            "%s: %s is on a row or in the list, not somewhere else" % [tag, element]
        )
    if not rows.overflow.box.get_children().is_empty():
        assert_true(rows.overflow.visible, "%s: and a list holding a control has its button shown" % tag)


func test_every_control_is_whole_on_the_bar_or_in_the_list_at_three_widths() -> void:
    var bar := _bar()
    for width in WIDTHS:
        _lay_out(bar, width)
        _assert_whole(bar, "at %d" % int(width))
    bar.free()


## The sweep's case: the split made, and then a control on the row asks for
## more, the way a label does when its text is translated or its font settles.
## Godot says so with the options bar's `minimum_size_changed` a frame later,
## and the split is made again from it rather than waiting for a resize.
##
## At the width that just holds the whole row rather than at 1280, because Keep
## blend, the sweep's control, is the first a short row gives up and is in the
## list at 1280. A slider is not the control to grow either:
## a refit sets a slider's width itself, so its width is not what the split is
## told about. A label and not a custom width, because a control that moves
## between the rows has its custom width set again by the compact pass.
func test_a_control_that_grows_after_the_split_is_moved_whole() -> void:
    var bar := _bar_in_tree()
    const ROOMY := 4000.0
    _lay_out(bar, ROOMY)
    var rows := bar.rows
    # The row's need with its sliders at the width a short row gives them,
    # which is what the split measures against.
    rows._reset_sliders()
    var need := ROOMY - rows.row_budget(1, ROOMY) + rows.row_spent(1)
    _lay_out(bar, need + 1.0)
    var keep := rows._options.keep_blend_chk
    var held := rows.overflow.box.get_child_count()
    assert_eq(keep.get_parent(), rows.row_container(1), "Keep blend is on the first row at %d" % int(need + 1.0))
    keep.text += " when a preset is loaded"
    assert_true(rows.row_spent(1) > rows.row_budget(1), "The longer label puts the row over, which is the stale split")

    rows._options.minimum_size_changed.emit()

    _assert_whole(bar, "after Keep blend grew")
    assert_true(rows.overflow.box.get_child_count() > held, "and what no longer fits after it went into the list whole")


## Keep blend is a toggle button like
## the Stabilizer switch, not a check box with text. So it is a `Button` in
## toggle mode with its name on the button, nothing beside it, whole at 1280,
## and a press writes the same setting the box did. Whole in the list rather
## than on the row, because it is the first control a short
## row gives up.
func test_keep_blend_is_a_toggle_like_the_stabilizer_and_the_first_to_leave() -> void:
    var bar := _bar_in_tree()
    _lay_out(bar, WIDTHS[0])
    var rows := bar.rows
    var keep := rows._options.keep_blend_chk
    var stab := rows._options.stabilizer_btn
    assert_false(keep is CheckBox, "Keep blend is no longer a check box")
    assert_true(keep is Button and keep.toggle_mode, "but a toggle button")
    assert_eq(keep.get_class(), stab.get_class(), "of the Stabilizer's own class")
    assert_eq(keep.text, "Keep Blend Mode", "with its name on the button")
    assert_true(keep.tooltip_text.contains("preset"), "and a tooltip that says what it keeps")
    for child: Node in keep.get_parent().get_children():
        assert_false(child is Label and child.text.contains("Keep"), "and no label beside it")
    assert_eq(keep.get_parent(), rows.overflow.box, "In the list at 1280, the first control to leave the row")
    _assert_whole(bar, "with Keep blend a toggle")
    _lay_out(bar, 4000.0)
    assert_eq(keep.get_parent(), rows.row_container(1), "and back on the first row where the bar holds everything")
    var was := SaSettings.keep_blend_mode
    keep.button_pressed = not was
    assert_eq(SaSettings.keep_blend_mode, not was, "A press writes the same setting")
    assert_eq(rows._options.preset_store.keep_blend_mode, not was, "and the preset store hears it")
    keep.button_pressed = was


## The same for what is pinned beside the row: menus whose titles grow take the
## room from the row, and the split follows them.
func test_menus_that_grow_after_the_split_move_the_budget() -> void:
    var bar := _bar_in_tree()
    _lay_out(bar, WIDTHS[0])
    var rows := bar.rows
    var held := rows.overflow.box.get_child_count()
    var menus := rows.main_row.get_node(^"HBoxMenuBar") as Control
    menus.custom_minimum_size.x = menus.get_combined_minimum_size().x + 200.0
    assert_true(rows.row_spent(1) > rows.row_budget(1), "Wider menus put the row over")

    menus.minimum_size_changed.emit()

    _assert_whole(bar, "after the menus grew")
    assert_true(rows.overflow.box.get_child_count() > held, "and more went into the list")


## A long preset name takes none of the bar's width, because
## the word Presets is on the button and on the button and the name in the tooltip, and a label that
## did not fit would still end in an ellipsis.
func test_a_long_preset_name_stays_off_the_bar_and_hovers_whole() -> void:
    var presets := ToolOptionsPresets.new()
    assert_eq(
        presets.preset_menu.text_overrun_behavior,
        SaTheme.TEXT_CUT,
        "The preset button asks for the cut that always ends in an ellipsis, and the picture is drawn by the preset button suite"
    )
    presets.selected_preset = "Soft Eraser With A Long Name"
    presets.sync_menu()
    assert_eq(presets.preset_menu.text, ToolOptionsPresets.PRESET_LABEL, "The label is the word a press opens")
    assert_true(
        presets.preset_menu.tooltip_text.contains("Soft Eraser With A Long Name"),
        "and the tooltip reads the name whole: %s" % presets.preset_menu.tooltip_text
    )
    presets.free()


## The readout stays one line: at a page's width the whole form, narrower the
## shorter labels, and every figure still beside its label.
func test_the_readout_shortens_its_labels_rather_than_wrapping() -> void:
    SaSettings.tablet_max_pressure = 0.8
    var page := SaTabletCalibration.new()
    var readout := page.find_child("Readout", true, false) as Label
    assert_eq(readout.autowrap_mode, TextServer.AUTOWRAP_OFF, "The readout does not wrap")
    assert_true(
        readout.get_combined_minimum_size().x < 100.0,
        "and asks for little width, so the page is not pushed past its pane: %d" % int(readout.get_combined_minimum_size().x)
    )

    var font := readout.get_theme_font("font")
    var font_size := readout.get_theme_font_size("font_size")
    var margin := readout.get_theme_stylebox("normal").get_minimum_size().x
    var widths: Array[float] = []
    for form_text: String in SaTabletCalibration.Readout.FORMS:
        var written := tr(form_text) % [0.4, 0.4, 1, 50]
        widths.append(font.get_string_size(written, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + margin)
    for at in range(1, widths.size()):
        assert_true(widths[at] < widths[at - 1], "Form %d is shorter than the one before it" % at)

    for at in widths.size():
        var room := widths[at] + 1.0
        readout.size = Vector2(room, readout.size.y)
        page._readout.show_values([0.4, 0.4, 1, 50])
        assert_eq(page._readout.form(), at, "At %d wide the readout is written in form %d: %s" % [int(room), at, readout.text])
        var written := font.get_string_size(readout.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + margin
        assert_true(written <= room, "and fits the width, %d of %d" % [int(written), int(room)])
        assert_true(readout.text.ends_with("50%"), "with the figure the brush gets at its end: %s" % readout.text)
    page.free()
