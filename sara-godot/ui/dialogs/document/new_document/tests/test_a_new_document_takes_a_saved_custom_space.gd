## File > New makes a document in a colour space the painter saved, and the
## document's space is that space, value by value.
##
## The dialog is never added to the tree, because a suite that maps a window
## hangs the run. Create is pressed through its button and the document is made
## from what the signal carries, as `main_dialogs.gd` makes it.
extends "res://tests/test_framework.gd"

## The dialog draws the colour space browser, and the document is real chunks.
const REQUIRES_GPU := true

const SAVED_AS := "Suite's print space"

var _kept: Array = []


func before_each() -> void:
    _kept = SaSettings.saved_color_spaces.duplicate(true)
    SaSettings.saved_color_spaces = []


func after_each() -> void:
    SaSettings.saved_color_spaces = _kept


## Rec. 2020's lights at D50 under a gamma of 2.6, no preset's values.
func _custom() -> SaColorSpace:
    return SaColorSpace.create(
        SaColorSpace.ID_CUSTOM,
        PackedVector2Array([Vector2(0.708, 0.292), Vector2(0.170, 0.797), Vector2(0.131, 0.046)]),
        SaColorSpacePicker.WHITE_D50,
        SaTransferFunction.gamma(2.6)
    )


func test_a_document_made_in_a_saved_space_is_in_that_space() -> void:
    var wanted := _custom()
    assert_eq(SaColorSpacePicker.Saved.save(SAVED_AS, wanted), SAVED_AS, "the space is saved")

    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"space", SAVED_AS), "File > New lists it under the presets")
    assert_eq(dialog.row_option(&"space").text, SAVED_AS, "and its preset row shows it")

    var asked: Array = []
    dialog.document_requested.connect(
        func(size: Vector2i, space: SaColorSpace, dpi: float, background: Dictionary) -> void:
            asked.append([size, space, dpi, background])
    )
    dialog.create_button.pressed.emit()
    assert_eq(asked.size(), 1, "Create asks for one document")
    var request: Array = asked[0]
    var requested: SaColorSpace = request[1]
    # The depth is storage and stays the Bit depth row's, so the saved space is
    # compared at the depth the dialog asks for.
    wanted = wanted.with_depth(requested.depth)
    assert_true(requested.matches(wanted), "in the saved space")

    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb())
    doc.reset_to_default(request[0], requested, request[2], request[3])
    assert_true(doc.color_space.matches(wanted), "and the document made is in it")
    for i in 3:
        assert_almost_eq(doc.color_space.primaries[i].x, wanted.primaries[i].x, 1e-6, "primary %d's x" % i)
        assert_almost_eq(doc.color_space.primaries[i].y, wanted.primaries[i].y, 1e-6, "primary %d's y" % i)
    assert_true(doc.color_space.white.is_equal_approx(SaColorSpacePicker.WHITE_D50), "at D50")
    assert_almost_eq(doc.color_space.transfer.exponent, 2.6, 1e-6, "under a gamma of 2.6")
    assert_eq(doc.color_space.depth, dialog.selected_space().depth, "at the depth the Bit depth row reads")
    doc.free()
    dialog.free()
