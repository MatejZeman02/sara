## A dump says which gamut browser it is about, and picks the one in front.
##
## `SaColorSpaceBrowser` is built more than once: the full control on
## Preferences > Colour Spaces, a preview in the Colour Space dialog and another
## preview in the New Document dialog. The dump's finder walked the whole tree
## and returned the first node that answered `capture_state` and `show_space`,
## so the block was whichever of them Godot listed first, and it named neither.
##
## Preferences hides rather than frees, so the first run that opened it made
## every later dump its browser. The colour spaces scenario only read the page correctly
## because it dumped before any dialog existed.
##
## The choice is split into `_front_browser_row` because a `Window` outside the
## scene tree cannot be given the focus, and a suite has no scene tree. The
## running app proves the wiring, in `scenarios/dump-picks-the-wrong-gamut-browser.json`.
extends "res://tests/test_framework.gd"


## A row the way the walk builds one, without a browser, for the choice alone.
func _row(title: String, focused: bool) -> Dictionary:
    return {"title": title, "focused": focused, "browser": null}


## The defect itself. Preferences is built first and stays built, so tree order
## alone hands every later dump to it.
func test_the_focused_window_wins_however_early_it_was_built() -> void:
    var rows: Array = [_row("Preferences", false), _row("Document Colour Space", true)]
    assert_eq(
        String(SaColorSpaceBrowser._front_browser_row(rows)["title"]),
        "Document Colour Space",
        "A dialog in front of Preferences wins"
    )

    rows = [_row("Preferences", true), _row("Document Colour Space", false)]
    assert_eq(
        String(SaColorSpaceBrowser._front_browser_row(rows)["title"]),
        "Preferences",
        "and Preferences wins back when the focus returns to it, though it is the earlier window"
    )


## The fallback, for a run where nothing reports the focus. Build order is then
## all there is, and the later window is the one opened more recently.
func test_with_no_focus_anywhere_the_last_window_answers() -> void:
    var rows: Array = [_row("Preferences", false), _row("New Document", false)]
    assert_eq(
        String(SaColorSpaceBrowser._front_browser_row(rows)["title"]),
        "New Document",
        "The later of two unfocused windows answers"
    )
    assert_true(
        SaColorSpaceBrowser._front_browser_row([]).is_empty(), "and no window showing a browser is an empty block, not a guess"
    )


## A hidden window is not on screen, whatever it still holds. This is the half
## that makes escape enough: Preferences hides, and its browser stops answering.
func test_a_hidden_window_and_everything_under_it_is_skipped() -> void:
    var root := Window.new()
    root.visible = true
    var shown := Window.new()
    shown.title = "Document Colour Space"
    shown.visible = true
    var hidden := Window.new()
    hidden.title = "Preferences"
    hidden.visible = false
    root.add_child(shown)
    root.add_child(hidden)

    var titles: Array[String] = []
    for window: Window in SaColorSpaceBrowser._visible_windows(root):
        titles.append(window.title)
    assert_eq(titles, ["", "Document Colour Space"], "The hidden window is not walked and neither are its children")

    root.free()


## The finder, against the two real controls, in two real windows. A browser
## belongs to the window that shows it and not to every ancestor of it, or the
## outermost window would answer for all of them.
func test_the_finder_reads_the_browser_of_the_window_it_is_asked_about() -> void:
    var root := Window.new()
    root.visible = true
    var page_window := Window.new()
    page_window.title = "Preferences"
    page_window.visible = true
    var page := SaColorSpaceBrowser.new()
    page.show_space(SaColorSpace.srgb())
    page_window.add_child(page)
    var dialog_window := Window.new()
    dialog_window.title = "Document Colour Space"
    dialog_window.visible = true
    var preview := SaColorSpaceBrowser.new(true)
    preview.show_space(SaColorSpace.srgb())
    dialog_window.add_child(preview)
    root.add_child(page_window)
    root.add_child(dialog_window)

    assert_null(SaColorSpaceBrowser._browser_in(root), "The window holding both finds neither, because it draws neither")
    assert_false(
        bool(SaColorSpaceBrowser._browser_in(page_window).capture_state()["preview"]), "Preferences holds the full control"
    )
    assert_true(
        bool(SaColorSpaceBrowser._browser_in(dialog_window).capture_state()["preview"]), "and the dialog holds the preview"
    )

    root.free()


## The block a dump carries, end to end, over the tree the two windows make.
## Nothing here has the focus, so this is the build-order half, and it is the
## reading that says the two dumps are of two different controls.
func test_the_block_names_its_window_and_says_which_control_answered() -> void:
    var root := Window.new()
    root.visible = true
    var page_window := Window.new()
    page_window.title = "Preferences"
    page_window.visible = true
    var page := SaColorSpaceBrowser.new()
    page.show_space(SaColorSpace.srgb())
    page_window.add_child(page)
    var dialog_window := Window.new()
    dialog_window.title = "Document Colour Space"
    dialog_window.visible = true
    var preview := SaColorSpaceBrowser.new(true)
    preview.show_space(SaColorSpace.srgb())
    dialog_window.add_child(preview)
    root.add_child(page_window)
    root.add_child(dialog_window)

    var state: Dictionary = SaColorSpaceBrowser.capture_front_state(root)
    assert_eq(String(state["window"]), "Document Colour Space", "The later window answers while neither holds the focus")
    assert_true(bool(state["preview"]), "and the control it holds is the preview")
    assert_false(bool(state["focused"]), "with the block saying the choice was not made by the focus")

    dialog_window.visible = false
    state = SaColorSpaceBrowser.capture_front_state(root)
    assert_eq(String(state["window"]), "Preferences", "Hiding the dialog hands the block back to the page")
    assert_false(bool(state["preview"]), "which is the full control")

    page_window.visible = false
    assert_true(
        SaColorSpaceBrowser.capture_front_state(root).is_empty(), "and with both hidden the block is empty rather than stale"
    )

    root.free()
