## Import Fit's Read the picture as ends in "Custom...", which opens the colour
## space picker, and a picture read as the space it gives becomes a document in
## that space.
##
## The window's own row is picked as a hand picks it, the picker answered
## through its Use button and the window through Open, and the answer goes to
## `SaDocumentFiles.open_image_into`, the document half of the open that
## `test_an_opened_picture_chooses_its_depth.gd` uses for its reason: the open's
## `_document()` asks Sara's main scene for its canvas and no suite builds that.
extends "res://tests/test_framework.gd"

## Chunk allocation is what the open does, so this needs a real device.
const REQUIRES_GPU := true

const PNG := "res://tests/data/import_gradient.png"
const RED := Vector2(0.6812, 0.3105)
const GREEN := Vector2(0.2034, 0.7341)
const BLUE := Vector2(0.1427, 0.0518)
const WHITE := Vector2(0.3301, 0.3412)
const GAMMA := 2.7
const CLOSE := 1e-6

var _host: Control = null
var _embedded: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Control.new()
    _host.size = Vector2(1280, 900)
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded


## The clause "imports a picture into a custom space chosen through Custom… and
## finds the document's space equal to it".
func test_a_picture_read_as_a_custom_space_opens_in_it() -> void:
    var custom := SaColorSpace.create(
        SaColorSpace.ID_CUSTOM, PackedVector2Array([RED, GREEN, BLUE]), WHITE, SaTransferFunction.gamma(GAMMA)
    )
    var image := SaImageImport.read(PNG)
    assert_not_null(image, "the picture reads")
    var dialog := SaImportFitDialog.new()
    _host.add_child(dialog)
    var answers: Array[SaColorSpace] = []
    dialog.depth_chosen.connect(func(space: SaColorSpace) -> void: answers.append(space))
    dialog.configure_open(image.get_size(), SaColorSpace.srgb(), -1)

    var row := dialog.page.row(&"space")
    var option := row.control as SaChoiceButton
    assert_eq(option.choice_values()[-1], SaColorSpaceRow.ASK_ID, "Read the picture as ends in Custom...")
    row.drive(option.choice_values().find(SaColorSpaceRow.ASK_ID))
    var picker := option.find_child("ColorSpacePickerDialog", true, false) as SaColorSpacePickerDialog
    assert_not_null(picker, "which opens the colour space picker")
    if picker == null:
        return
    assert_false(
        picker.find_child("NoteLabel", true, false).visible, "with no word about the curve, as an import takes all of it"
    )
    picker.picker.show_space(custom)
    picker.use_button.pressed.emit()
    assert_eq(option.selected_value(), SaColorSpaceRow.PICKED_ID, "the row is on the space the picker gave")
    assert_true(option.choice_values().has(SaColorSpaceRow.ASK_ID), "and still offers Custom... after it")

    (dialog.find_child("PlaceButton", true, false) as Button).pressed.emit()
    assert_eq(answers.size(), 1, "Open answers once")
    if answers.is_empty():
        return
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var layer := SaDocumentFiles.open_image_into(easel.document, PNG, answers[0])
    assert_not_null(layer, "the picture is placed")
    var held := easel.document.color_space
    assert_eq(held.id, SaColorSpace.ID_CUSTOM, "in a custom space")
    for i in 3:
        assert_true(held.primaries[i].distance_to(custom.primaries[i]) < CLOSE, "primary %d is the picker's" % i)
    assert_true(held.white.distance_to(custom.white) < CLOSE, "so is the white")
    assert_true(absf(held.transfer.exponent - GAMMA) < CLOSE, "and so is the curve, %s" % held.transfer.exponent)
    easel.free()
