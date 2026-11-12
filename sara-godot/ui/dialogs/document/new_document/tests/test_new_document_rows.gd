## The New Document dialog's capture door for its colour grid.
##
## The gamut row has `select_gamut`, and without a door for the preset,
## transfer, coordinates and depth rows `scenarios/colour-space.json` would read
## the depth back as `16-bit float` in all five of its dialog dumps and nothing
## could move it. `select_row` is that door widened to the grid.
##
## The dialog is never added to the tree here: a test that maps a real window
## hangs the run, which is why `test_new_document_white_point.gd` says the same.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true


## The depth row, which no door once drove. The depth row moves, and `capture_state` is
## not asked here because it needs a visible dialog: what the row draws is what
## that block reads out of it.
func test_the_depth_row_moves() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"depth", "32-bit float"), "The depth row takes 32-bit float")
    assert_eq(dialog.selected_space().depth, SaColorSpace.Depth.F32, "and the space the dialog would build is F32")
    assert_true(dialog.select_row(&"depth", "16-bit float"), "and 16-bit float")
    assert_eq(dialog.selected_space().depth, SaColorSpace.Depth.F16, "and that space is F16")
    dialog.free()


## The other two rows, and the preset row above them.
func test_the_transfer_coordinates_and_preset_rows_move_too() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"coordinates", "Oklab"), "The coordinates row takes Oklab")
    assert_eq(dialog.selected_space().coordinates, SaColorSpace.Coordinates.OKLAB, "and the space is in Oklab")

    assert_true(dialog.select_row(&"transfer", "Linear"), "The transfer row takes Linear")
    assert_eq(dialog.selected_space().transfer.id, SaTransferFunction.ID_LINEAR, "and the space carries that curve")

    assert_true(dialog.select_row(&"space", "sRGB"), "The preset row takes sRGB")
    assert_eq(dialog.row_option(&"space").text, "sRGB", "and shows it")
    dialog.free()


## The preset row fills the two below it, so a scenario naming both means the
## named row to win. That is why `CAPTURE_ROWS` puts the preset first, after
## the Template row, which fills the preset in turn.
func test_the_preset_row_is_applied_before_the_rows_it_fills() -> void:
    assert_eq(NewDocumentDialog.CAPTURE_ROWS[0], "template", "The template row goes first")
    assert_eq(NewDocumentDialog.CAPTURE_ROWS[1], "space", "and the preset row after it")
    var dialog := NewDocumentDialog.new()
    dialog.select_row(&"space", "sRGB")
    var after_preset := dialog.selected_space().transfer.id
    dialog.select_row(&"transfer", "Linear")
    assert_eq(dialog.selected_space().transfer.id, SaTransferFunction.ID_LINEAR, "and the named row wins over what it filled")
    assert_true(after_preset != SaTransferFunction.ID_LINEAR, "which is only a claim because sRGB filled a different curve")
    dialog.free()


## The gamut row keeps the id form three committed scenarios already write, so
## `colour-space.json` can move to the one step without being rewritten.
func test_the_gamut_row_still_answers_to_an_id() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"gamut", "ap1"), "The gamut row takes a gamut id")
    assert_eq(dialog.row_option(&"gamut").text, "ACES AP1", "and shows the display name")
    assert_true(dialog.select_row(&"gamut", "Rec. 2020"), "and a display name")
    dialog.free()


## A number is the row's index, for an entry a translation moved out from under
## a scenario.
func test_a_number_is_the_row_index() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"depth", 1), "The depth row takes an index")
    assert_eq(int(dialog.row_option(&"depth").selected_value()), 1, "and lands on it")
    assert_false(dialog.select_row(&"depth", 99), "An index past the end is refused")
    dialog.free()


## A name nothing draws and a row the grid does not have are both refused, so
## `capture_row` can say which rather than reporting a move that did not happen.
func test_an_unknown_entry_or_row_is_refused() -> void:
    var dialog := NewDocumentDialog.new()
    assert_false(dialog.select_row(&"depth", "8-bit"), "No 8-bit row, and integer depths are decided against")
    # The white point is a row a painter picks, so the row refused here is one
    # the grid has never had.
    assert_false(dialog.select_row(&"white", "D93"), "The white point row has no D93")
    assert_false(dialog.select_row(&"lightness", "Bright"), "and a row the grid does not have is refused")
    assert_null(dialog.row_option(&"lightness"), "and has no dropdown behind it")
    dialog.free()


## Every row `capture_row` names has a dropdown, which is the check that stops
## the list and the grid drifting apart.
func test_every_capture_row_has_a_dropdown() -> void:
    var dialog := NewDocumentDialog.new()
    for row: String in NewDocumentDialog.CAPTURE_ROWS:
        assert_not_null(dialog.row_option(StringName(row)), "'%s' is a row of the grid" % row)
    dialog.free()
