## The brush editor opens with the tip's curve in sight, its dynamics in their
## own group and its buttons in one row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At 900 by 560 the Brush Tip page's falloff curve must not be cut off at the
## bottom of the page scroll while the pad beside it takes a third of the width
## empty. The list mixes a fold, plain pages and dots rather than checkboxes, so
## a painter who clicks to open a page does not turn a dynamic on without seeing
## it. And Rename, Save and Save As are not as tall as the dashboard, with Save
## As against the right edge.
##
## **On a screen, for the first claim.** Whether a graph ends inside the page
## scroll is a question about a laid-out window, and a `Window` added to a
## headless tree hangs unless something embeds it. The screen is a
## `SubViewport` that embeds its subwindows, the way
## `test_every_dialog_opens_inside_the_window_at_every_size_and_scale.gd` opens
## every dialog, in the app's own theme, and laid out by hand because no frame
## passes inside a test. The other claims hold of a window built and never
## shown, the way `test_ticks_follow_a_loaded_preset.gd` builds one.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a pad with a canvas in it.
const REQUIRES_GPU := true

## The screen the row names, at an interface scale of 1.
const SCREEN := Vector2i(1920, 1080)

## The first row below a one-row bar, the number the dialog sweep uses.
const BAR := 65

## The page whose curve is checked, and the row the curve is.
const TIP_PAGE := "Brush Tip"
const FALLOFF := &"tip_falloff"

static var scratch_dir: String = SaDataRoot.path("test_n101_editor")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null
var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _kept_page: String = ""
var _kept_pad_width: int = 0


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaUI.user_scale = 1.0
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A dialog added outside the screen below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _kept_page = SaSettings.brush_editor_page
    _kept_pad_width = SaSettings.brush_editor_pad_width
    # The page the editor opens on, so the one page built is the one measured:
    # a page shown after another leaves the first one's rows queued for a free
    # that no frame here ever runs.
    SaSettings.brush_editor_page = TIP_PAGE
    SaSettings.brush_editor_pad_width = 0
    _host = Node.new()
    _host.name = "N101EditorHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    SaSettings.brush_editor_page = _kept_page
    SaSettings.brush_editor_pad_width = _kept_pad_width
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    SaDialogWindow.top_inset = _kept_inset
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _specs() -> Array[SaOptionSpec]:
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    return specs


## A window bound to the brush and never shown.
func _window() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_machine.get_tool("brush"), _specs(), _store())
    return window


## A window bound to the brush, opened on a screen of *logical* units the way
## the app opens it, fitted, and laid out. The screen is freed with the host.
func _opened(logical: Vector2i) -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    var screen := SubViewport.new()
    screen.size = logical
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    window.bind_tool(_machine.get_tool("brush"), _specs(), _store())
    window.popup_centered()
    _settle(window)
    window.fit_opening_size()
    _settle(window)
    return window


## Lays *window* out the way a drawn frame would, the dialog sweep's own walk:
## every container sorted outside in, every control asked for its minimum again,
## twice, and a pixel on the window and back so an anchored control takes its
## new size.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


# --- The curve in sight ---------------------------------------------------------


## The row's first claim: at 1920 by 1080 the Brush Tip page's curve ends inside
## what the page scroll shows, so a painter meets it without scrolling.
func test_at_1920_the_tip_pages_curve_ends_inside_the_page_scroll() -> void:
    var window := _opened(SCREEN)
    assert_eq(window.page_list.title_at(window.page_list.selected), TIP_PAGE, "The editor opened on the Brush Tip page")
    assert_eq(window.size, SaBrushEditorWindow.DEFAULT_LOGICAL_SIZE, "at the size it asks for, which the screen has room for")

    var curve := window.pages.page_controls.control(FALLOFF) if window.pages.page_controls != null else null
    assert_not_null(curve, "The page draws the falloff curve")
    if curve == null:
        return
    var view := window.page_scroll.get_global_rect()
    var rect := curve.get_global_rect()
    assert_true(rect.size.y > 0.0, "laid out with a height, %s" % rect)
    assert_true(
        rect.end.y <= view.end.y,
        "The curve ends at %d, inside a page scroll showing down to %d" % [int(rect.end.y), int(view.end.y)]
    )
    assert_eq(window.page_scroll.scroll_vertical, 0, "with the page scrolled nowhere")

    var graphs: Array = window.graphs_in_sight()
    assert_false(graphs.is_empty(), "The dump names the graph")
    if not graphs.is_empty():
        assert_true(bool((graphs[0] as Dictionary)["inside"]), "and says it is in sight")


## The pad takes the page column's height rather than a third of the width: its
## width is half the column's height, so it is a tall column and the page keeps
## the rest.
func test_at_1920_the_pad_is_a_tall_column_and_the_page_keeps_the_rest() -> void:
    var window := _opened(SCREEN)
    var pad := window.scratchpad
    var report := pad.pad_report()
    var height := int(report["page_height"])
    assert_true(height > 0, "The window measured its page column, %d tall" % height)
    assert_eq(
        int(report["share"]),
        maxi(SaEditorScratchpad.MIN_WIDTH, int(round(height * SaEditorScratchpad.HEIGHT_SHARE))),
        "The share is half the page column's height"
    )
    assert_true(pad.snap.open_width <= height, "so the pad is no wider than the page is tall")
    assert_true(
        pad.snap.open_width < int(round(SaBrushEditorWindow.DEFAULT_LOGICAL_SIZE.x * SaEditorScratchpad.WIDTH_SHARE)),
        "and narrower than the width's old share"
    )
    assert_true(
        window.page_scroll.size.x > float(pad.snap.open_width),
        "The page is wider than the pad, %d" % int(window.page_scroll.size.x)
    )


# --- The list -------------------------------------------------------------------


## No row of the list carries anything a press can tick, and the dynamics that
## are on are the ones with a dot.
func test_the_list_has_no_checkable_row_and_marks_the_dynamics_that_are_on() -> void:
    var window := _window()
    var rows: Array = window.page_list.row_report()
    var marked := 0
    for i in rows.size():
        var row := rows[i] as Dictionary
        assert_false(row.has("checkable"), "%s reports no checkable" % row["title"])
        var on: Variant = window.pages.tick_at(i)
        assert_eq(bool(row["switch"]), on != null, "%s has a switch exactly when its page does" % row["title"])
        assert_eq(bool(row["on"]), on != null and bool(on), "%s is marked exactly when it is on" % row["title"])
        if bool(row["on"]):
            marked += 1
    assert_true(marked > 0, "The brush has a dynamic that is on to mark")
    window.free()


## No row of the list draws a checkbox, which is what a dump field could lie
## about and a node cannot.
func test_no_row_of_the_list_draws_a_checkbox() -> void:
    var window := _window()
    var boxes := window.page_list.rows_box.find_children("*", "CheckBox", true, false)
    assert_true(boxes.is_empty(), "The rows hold %d checkboxes" % boxes.size())
    window.free()


## Brush over the tip and the general rows, Dynamics over the rest, and the
## colour page among the dynamics though it has no switch of its own.
func test_the_list_draws_two_headings() -> void:
    var window := _window()
    var groups: Dictionary = {}
    for row: Dictionary in window.page_list.row_report():
        groups[String(row["title"])] = String(row["group"])
    assert_eq(groups.get(TIP_PAGE), "Brush", "Brush Tip is under Brush")
    assert_eq(groups.get("General"), "Brush", "and so is General")
    for title: String in ["Size", "Opacity", "Texture", "Masking Brush", "Colour Dynamics"]:
        assert_eq(groups.get(title), "Dynamics", "%s is under Dynamics" % title)
    var headings: Array[String] = []
    for child: Node in window.page_list.rows_box.get_children():
        if child is Label and not child.is_queued_for_deletion():
            headings.append((child as Label).text)
    assert_eq(headings, ["Brush", "Dynamics"] as Array[String], "Two headings, in that order")
    window.free()


# --- The switch -----------------------------------------------------------------


## A page's switch sits at its top and writes the same `enabled` the checkbox
## did, and the dot in the list follows it.
func test_a_pages_switch_writes_enabled() -> void:
    var window := _window()
    var at := window.pages.index_of("Size")
    window.show_page(at)
    var option := window.pages.curve_option_at(at)
    assert_not_null(window.pages.page_switch, "The Size page has a switch at its top")
    assert_not_null(option, "over the Size option")
    if window.pages.page_switch == null or option == null:
        window.free()
        return
    var was := bool(option.enabled)
    assert_eq(window.pages.page_switch.button_pressed, was, "reading what the option holds")

    window.pages.page_switch.button_pressed = not was
    assert_eq(bool(option.enabled), not was, "Pressing the switch writes the option's enabled")
    assert_eq(bool((window.page_list.row_report()[at] as Dictionary)["on"]), not was, "and the dot follows")

    window.pages.page_switch.button_pressed = was
    assert_eq(bool(option.enabled), was, "and pressing it again puts it back")
    window.free()


## A switch moved from somewhere else, a preset or the bar, is shown on the open
## page as well as in the list.
func test_the_open_pages_switch_follows_the_option() -> void:
    var window := _window()
    var at := window.pages.index_of("Size")
    window.show_page(at)
    var option := window.pages.curve_option_at(at)
    var was := bool(option.enabled)
    option.set("enabled", not was)
    window.sync_ticks()
    assert_eq(window.pages.page_switch.button_pressed, not was, "The switch at the top reads the option again")
    option.set("enabled", was)
    window.free()


## A plain page has nothing at its top to switch.
func test_a_plain_page_has_no_switch() -> void:
    var window := _window()
    window.show_page(window.pages.index_of("General"))
    assert_null(window.pages.page_switch, "General has no switch")
    window.free()


# --- The buttons ----------------------------------------------------------------


## One row, the way out first and the default last, and the dashboard keeps the
## name and the dirty mark.
func test_the_buttons_sit_in_one_row_the_way_out_first() -> void:
    var window := _window()
    assert_eq(
        window.button_row(),
        PackedStringArray(["Close", "Reset", "Rename", "Save As", "Save"]),
        "Close, Reset, Rename, Save As, Save"
    )
    var bar := window.preset_bar
    var row := bar.save_button.get_parent()
    for button: Button in [bar.close_button_bottom, bar.reset_button, bar.rename_button, bar.save_as_button]:
        assert_eq(button.get_parent(), row, "%s is in the row" % button.name)
    assert_eq(window.default_button, bar.save_button, "Save is the button Enter presses")
    var dashboard := window.thumbnail.get_parent()
    assert_true(dashboard.is_ancestor_of(bar.preset_label), "The dashboard keeps the name")
    assert_true(dashboard.is_ancestor_of(bar.dirty_label), "and the dirty mark")
    assert_false(dashboard.is_ancestor_of(bar.save_button), "and no button")
    window.free()


## At the normal button height rather than the dashboard's.
func test_the_buttons_are_the_normal_height() -> void:
    var window := _opened(SCREEN)
    var bar := window.preset_bar
    var dashboard := window.thumbnail.get_parent() as Control
    for button: Button in [bar.close_button_bottom, bar.save_button]:
        assert_true(
            button.size.y < dashboard.size.y,
            "%s is %d tall under a dashboard %d tall" % [button.name, int(button.size.y), int(dashboard.size.y)]
        )
        assert_almost_eq(button.size.y, button.get_combined_minimum_size().y, 0.5, "%s is as tall as it asks" % button.name)
