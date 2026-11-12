## Preferences fits its pane and opens each page at the top.
##
## Five findings, each pinned as a number: a number field holds its widest value, a page opens at its top while
## a searched row still scrolls into view, the Keyboard Shortcuts page is no
## wider than its pane, New Document's Transfer choice is not cut, and a folder
## path shows its end with the whole of it in the tooltip.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true


## What the number row writes, the one setting of a docker page's wait.
class Knobs:
    extends RefCounted

    var dwell_ms: int = 400


## A Preferences window in the tree, embedded, the way
## `test_preferences_search.gd` opens one and for its reasons.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "PreferencesFitsTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


func _text_width(control: Control, text: String) -> float:
    var font := control.get_theme_font(&"font")
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size(&"font_size")).x


## The widest a row's control column may be at 1920 by 1080: the window, less
## the sidebar, the content margins and room for the split's grabber, the
## vertical bar and the frame's borders.
func _pane_width(window: SaSettingsWindow) -> float:
    var sidebar := window._sidebar_panel.get_combined_minimum_size().x
    return float(window.size.x) - sidebar - 2.0 * SaUI.px(SaSettingsWindow.CONTENT_MARGIN) - SaUI.px(64)


func test_a_number_field_holds_its_widest_value_and_suffix() -> void:
    # In the tree, because a control off it keeps its minimum size cached and
    # never hears that its custom one moved.
    var host := SaMake.column(EventBus, "NumberHost")
    var knobs := Knobs.new()
    var page := SaPage.new(
        func(ui: SaPage) -> void:
            ui.section("Docker").number("Summoned docker waits", 0, 10000, knobs, ^"dwell_ms").step(100).with_suffix(" ms").named(
                &"wait"
            )
    )
    page.declare_rows()
    page.realize(host)
    var spin := page.row(&"wait").control as SpinBox
    var line := spin.get_line_edit()
    var room := line.get_combined_minimum_size().x - line.get_theme_stylebox(&"normal").get_minimum_size().x
    assert_true(room >= _text_width(line, "1000 ms"), "the field holds 1000 ms, where it read 000 m")
    assert_true(room >= _text_width(line, "10000 ms"), "and the widest value the row allows")
    var spin_wide := spin.get_combined_minimum_size().x
    assert_true(spin_wide >= line.get_combined_minimum_size().x, "and the spin box is as wide as its field")
    host.free()


func test_a_page_opened_after_a_scrolled_one_starts_at_the_top() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    # No frame passes in a suite, so the bar is given a range by hand and the
    # pane is scrolled the way a wheel leaves it.
    var bar := window.content_scroll.get_v_scroll_bar()
    bar.max_value = 5000.0
    bar.page = 500.0
    window.content_scroll.scroll_vertical = 900
    assert_eq(window.content_scroll.scroll_vertical, 900, "the Interface page is read far down")
    window.show_page("Canvas and colour")
    assert_eq(window.content_scroll.scroll_vertical, 0, "and Canvas and colour opens at its top, where it opened at 900")
    _close_window(opened)


func test_a_searched_row_is_still_the_one_brought_into_view() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var bar := window.content_scroll.get_v_scroll_bar()
    bar.max_value = 5000.0
    bar.page = 500.0
    window.content_scroll.scroll_vertical = 900
    window.search.apply("gamut")
    var pages := PackedStringArray(window.search.report()["categories"])
    assert_true(pages.size() > 0, "the search leaves a page holding the word")
    window.show_page(pages[0])
    var report: Dictionary = window.search.report()
    assert_true(not String(report["highlighted_row"]).is_empty(), "the page it opened has its row marked")
    assert_true(window.content_container.is_ancestor_of(window.search.highlighted), "on the page now open")
    # The mark is set after the reset, and `_scroll_to` brings that row into
    # view two frames later, which the scenario reads as `scrolled_to`.
    assert_eq(int(report["scrolled_to"]), 0, "the reset came first, so the scroll that follows is the search's own")
    _close_window(opened)


func test_the_shortcuts_page_is_no_wider_than_its_pane() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_true(window.show_page("Keyboard shortcuts"), "the page opens")
    # The rows arrive a slice a frame, and this reads them all.
    window.kept_pages.finish_arriving()
    for groups: Node in window.content_container.find_children("*", "SaShortcutGroups", true, false):
        (groups as SaShortcutGroups).fill_now()
    var sideways := window.content_scroll.horizontal_scroll_mode
    assert_eq(sideways, ScrollContainer.SCROLL_MODE_DISABLED, "the pane never scrolls sideways")
    var wide := window.content_container.get_combined_minimum_size().x
    assert_true(wide <= _pane_width(window), "the page asks for %d, no more than the pane's %d" % [wide, _pane_width(window)])
    var rows := window.content_container.find_children("*", "HFlowContainer", true, false)
    assert_true(rows.size() > 20, "every command's chords sit in a row that wraps")
    var gap := SaUI.px(6)
    for row: Node in rows:
        var widest := 0.0
        for button: Node in row.get_children():
            widest = maxf(widest, (button as Control).get_combined_minimum_size().x)
        if (row as Control).get_combined_minimum_size().x > widest + gap:
            assert_true(false, "%s asks for more than its widest chord" % row.get_parent().name)
            break
    _close_window(opened)


func test_the_transfer_choice_shows_a_short_name_and_the_full_one_in_its_tooltip() -> void:
    var dialog := NewDocumentDialog.new()
    var option := dialog.find_child("TransferOption", true, false) as SaChoiceButton
    assert_true(option != null, "the dialog has its Transfer choice")
    var curves := SaTransferFunction.presets()
    var widest_full := 0.0
    var widest_shown := 0.0
    for i in curves.size():
        dialog.page.row(&"transfer").drive(i)
        var full_name := curves[i].display_name
        assert_eq(option.text, SaColorSpacePicker.transfer_label(full_name), "%s shows its short name" % full_name)
        assert_false(option.text.contains("("), "with nothing in brackets")
        assert_eq(option.tooltip_text, curves[i].display_name, "and its full name as the tooltip")
        widest_full = maxf(widest_full, _text_width(option, curves[i].display_name))
        widest_shown = maxf(widest_shown, _text_width(option, option.text))
    assert_true(widest_shown < widest_full, "the widest label is narrower than the full name that was cut")
    var slider_row := _text_width(option, dialog.tr(SaColorSpacePicker.GAMMA_LABEL))
    assert_true(widest_shown <= slider_row, "and no wider than the slider's row, which fits")
    dialog.free()


func test_a_path_shows_its_end_and_the_whole_of_it_in_the_tooltip() -> void:
    # In the tree, because a control off it never hears that it was resized.
    var label := SaPathRow.PathLabel.new()
    EventBus.add_child(label)
    var path := "/home/somebody/a/folder/nested/deeply/enough/to/be/cut/Sara Library"
    label.size = Vector2(_text_width(label, path) + 10.0, 20.0)
    label.show_path(path)
    assert_eq(label.text, path, "a label wide enough shows the path whole")
    assert_eq(label.tooltip_text, path, "and carries it as its tooltip")
    label.size = Vector2(_text_width(label, path) / 2.0, 20.0)
    assert_true(label.text.begins_with("…"), "a narrow label trims the start, with an ellipsis")
    assert_true(label.text.ends_with("Sara Library"), "and keeps the folder's own name at its end")
    assert_true(_text_width(label, label.text) <= label.size.x, "and what is left fits")
    assert_eq(label.tooltip_text, path, "the tooltip keeps the whole path")
    label.free()
