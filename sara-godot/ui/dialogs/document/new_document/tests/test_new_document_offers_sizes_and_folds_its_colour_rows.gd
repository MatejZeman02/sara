## New Document offers sizes and folds its colour rows.
##
## The dialog once had no size presets, no px and no portrait and landscape
## swap, and seven expert colour rows with the focus starting on the Gamma
## slider. The Size row fills the numbers, the swap trades them, and
## five of the colour rows and the chooser's picture sit behind a switch that is
## off, so the focus starts on Width.
##
## The dialog is built detached for the rows, and embedded for the focus and
## the window's size, since a Window added to the tree without embedding maps a
## real OS window and hangs the run.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

## The seven colour rows, every one behind the fold.
const COLOUR_ROWS: Array[StringName] = [&"space", &"gamut", &"white", &"transfer", &"gamma", &"coordinates", &"depth"]


## Whether the row of *key* is on the page, as the page's own dump reads it.
static func _shown(dialog: NewDocumentDialog, key: StringName) -> bool:
    return bool(dialog.page.row(key).describe()["shown"])


func test_a4_fills_its_size_and_its_resolution() -> void:
    var dialog := NewDocumentDialog.new()
    assert_eq(dialog.row_option(&"size"), null, "the Size row is not one of the colour grid's")
    var sizes := dialog.page.row(&"size").control as SaChoiceButton
    assert_eq(sizes.text, "Screen, 1920 × 1080 px", "the dialog opens on the screen size it opens with")
    assert_eq(
        sizes.choice_labels(),
        ["Screen, 1920 × 1080 px", "A4 portrait, 300 dpi", "Square, 2048 × 2048 px", "Custom"],
        "four sizes"
    )
    dialog.page.row(&"size").drive(1)
    assert_eq(dialog.selected_size(), Vector2i(2480, 3508), "A4 fills 2480 by 3508")
    assert_eq(dialog.selected_dpi(), 300.0, "at the 300 dpi its name says")
    assert_eq((dialog.find_child("WidthSpin", true, false) as SpinBox).value, 2480.0, "and the width field shows it")
    dialog.page.row(&"size").drive(2)
    assert_eq(dialog.selected_size(), Vector2i(2048, 2048), "Square fills 2048 by 2048")
    assert_eq(dialog.selected_dpi(), 300.0, "and leaves a resolution it does not name")
    dialog.free()


func test_an_edited_number_reads_custom_and_a_matching_one_the_size() -> void:
    var dialog := NewDocumentDialog.new()
    var sizes := dialog.page.row(&"size").control as SaChoiceButton
    dialog.page.row(&"width").drive(1000)
    assert_eq(sizes.text, "Custom", "a width typed over a size reads Custom")
    dialog.page.row(&"width").drive(2048)
    dialog.page.row(&"height").drive(2048)
    assert_eq(sizes.text, "Square, 2048 × 2048 px", "numbers that are a size read as it")
    dialog.page.row(&"size").drive(1)
    dialog.page.row(&"dpi").drive(150)
    assert_eq(sizes.text, "Custom", "A4 at another resolution is not A4 at 300 dpi")
    dialog.free()


func test_the_swap_swaps_and_both_numbers_are_pixels() -> void:
    var dialog := NewDocumentDialog.new()
    dialog.page.row(&"size").drive(1)
    var swap := dialog.find_child("SwapButton", true, false) as Button
    assert_not_null(swap, "the swap is a button")
    var order := dialog.page.rows().map(func(entry: SaPageRow) -> StringName: return entry.key)
    var at := order.find(&"width")
    assert_eq(order.slice(at - 1, at + 3), [&"size", &"width", &"swap", &"height"], "between Width and Height")
    swap.pressed.emit()
    assert_eq(dialog.selected_size(), Vector2i(3508, 2480), "the swap swaps")
    assert_eq((dialog.find_child("HeightSpin", true, false) as SpinBox).value, 2480.0, "and the height field shows it")
    assert_eq((dialog.page.row(&"size").control as SaChoiceButton).text, "Custom", "and A4 on its side is no entry")
    for spin: String in ["WidthSpin", "HeightSpin"]:
        assert_eq((dialog.find_child(spin, true, false) as SpinBox).suffix, "px", "%s says px" % spin)
    dialog.free()


func test_the_details_are_hidden_at_first_and_opening_them_shows_the_seven_rows() -> void:
    var dialog := NewDocumentDialog.new()
    assert_false(dialog.details_open, "the details are closed")
    for key: StringName in NewDocumentDialog.DETAIL_ROWS:
        assert_false(_shown(dialog, key), "%s is behind the switch" % key)
    assert_true(_shown(dialog, &"details"), "the switch is not")
    var order := dialog.page.rows().map(func(entry: SaPageRow) -> StringName: return entry.key)
    assert_eq(order.find(&"depth"), order.find(&"space") + 1, "Bit depth sits under Colour space")
    var view := dialog.browser.get_parent() as Control
    assert_false(view.visible, "and the chooser's picture is with the five")

    dialog.page.row(&"details").drive(true)
    for key: StringName in COLOUR_ROWS:
        assert_true(_shown(dialog, key), "open, %s is shown" % key)
    assert_true(view.visible, "and so is the picture")
    dialog.page.row(&"details").drive(false)
    assert_false(_shown(dialog, &"gamut"), "closed again, they go")
    dialog.free()


func test_the_focus_opens_on_width_and_the_window_follows_the_fold() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree")
    if tree == null:
        return
    var kept: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var dialog := NewDocumentDialog.new()
    EventBus.add_child(dialog)
    dialog.show()
    # The app focuses a frame after the show, and a test cannot await one.
    dialog.focus_first_control()
    var width := (dialog.find_child("WidthSpin", true, false) as SpinBox).get_line_edit()
    assert_eq(dialog.gui_get_focus_owner(), width, "the focus opens on Width")
    assert_eq(dialog.logical_size, NewDocumentDialog.CLOSED_SIZE, "closed, the window is 640 wide")
    dialog.page.row(&"details").drive(true)
    assert_eq(dialog.logical_size, NewDocumentDialog.OPEN_SIZE, "open, it takes the size that holds the picture")
    dialog.page.row(&"details").drive(false)
    assert_eq(dialog.logical_size, NewDocumentDialog.CLOSED_SIZE, "and closed again, its own")
    # The open floor held a closing window at 760 wide while its rows had gone.
    var closed := SaUI.window_size_for(dialog, NewDocumentDialog.CLOSED_SIZE)
    assert_eq(dialog.size, closed, "which the window takes, not the floor it had open")
    dialog.free()
    tree.root.gui_embed_subwindows = kept
