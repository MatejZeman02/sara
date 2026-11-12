## Image > Colour Space's Target is the colour space picker, so Assign and
## Convert take a space no preset names, saved by the painter.
##
## The dialog is never added to the tree, because a suite that maps a window
## hangs the run. Its buttons are pressed and what they ask for is applied as
## `main_dialogs.gd` applies it.
extends "res://tests/test_framework.gd"

## The document is real chunks and Convert is a compute pass.
const REQUIRES_GPU := true

const SAVED_AS := "Suite's wide space"

var _kept: Array = []


func before_each() -> void:
    _kept = SaSettings.saved_color_spaces.duplicate(true)
    SaSettings.saved_color_spaces = []


func after_each() -> void:
    SaSettings.saved_color_spaces = _kept


## Wider lights than Rec. 2020's at D50 under a gamma of 2.6, so sRGB red lands
## inside it on all three channels and every channel of the answer is tested.
func _custom() -> SaColorSpace:
    return SaColorSpace.create(
        SaColorSpace.ID_CUSTOM,
        PackedVector2Array([Vector2(0.7347, 0.2653), Vector2(0.1152, 0.8264), Vector2(0.1566, 0.0177)]),
        SaColorSpacePicker.WHITE_D50,
        SaTransferFunction.gamma(2.6)
    )


## A 32-bit sRGB document, so 1e-5 measures the conversion and not the storage.
func _document(fill: Color) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    doc.active_layer.fill(fill)
    return doc


func _texel(doc: SaDocument) -> Color:
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(doc.active_layer.get_field(Vector2i(0, 0)))
    return image.get_pixel(0, 0)


## Opens the dialog on *doc* with the saved space picked as the Target, and
## wires its two buttons to the document.
func _dialog_on(doc: SaDocument) -> ColorSpaceDialog:
    var dialog := ColorSpaceDialog.new()
    var conversion := SaColorConversion.new(doc)
    dialog.configure(doc.color_space, conversion.blocked_reason)
    dialog.assign_requested.connect(func(space: SaColorSpace) -> void: SaColorConversion.new(doc).assign(space))
    dialog.convert_requested.connect(func(space: SaColorSpace) -> void: SaColorConversion.new(doc).convert_to(space))
    var labels := (dialog.page.row(&"space").control as SaChoiceButton).choice_labels()
    var at := labels.find(SAVED_AS)
    assert_true(at >= 0, "the Target lists the saved space")
    dialog.page.row(&"space").drive(at)
    assert_eq(dialog.picker.saved_name(), SAVED_AS, "and takes it")
    return dialog


func test_assign_relabels_into_the_custom_space_and_leaves_every_texel() -> void:
    var wanted := _custom()
    SaColorSpacePicker.Saved.save(SAVED_AS, wanted)
    var doc := _document(Color(0.25, 0.5, 0.75, 1.0))
    var before := _texel(doc)
    var image_before: Image = SaExport.get_texture_image_float(doc.active_layer.get_field(Vector2i(0, 0)))

    var dialog := _dialog_on(doc)
    dialog.assign_button.pressed.emit()
    assert_true(doc.color_space.matches(wanted.with_depth(SaColorSpace.Depth.F32)), "the document is in the custom space")
    var image_after: Image = SaExport.get_texture_image_float(doc.active_layer.get_field(Vector2i(0, 0)))
    assert_eq(image_after.get_data(), image_before.get_data(), "and every texel of the chunk is as it was")
    var after := _texel(doc)
    assert_eq(after, before, "the first one too, read as a colour")
    dialog.free()
    doc.free()


func test_convert_moves_pure_red_by_the_matrix_and_the_curves() -> void:
    var wanted := _custom()
    SaColorSpacePicker.Saved.save(SAVED_AS, wanted)
    var doc := _document(Color(1.0, 0.0, 0.0, 1.0))
    var source := doc.color_space
    var dialog := _dialog_on(doc)
    assert_false(dialog.convert_button.disabled, "Convert is offered into the custom space")
    dialog.convert_button.pressed.emit()
    assert_true(doc.color_space.matches(wanted.with_depth(SaColorSpace.Depth.F32)), "the document is in the custom space")

    var linear := Vector3(source.transfer.decode(1.0), source.transfer.decode(0.0), source.transfer.decode(0.0))
    var moved: Vector3 = source.to_space_matrix(wanted) * linear
    var expected := Vector3(wanted.transfer.encode(moved.x), wanted.transfer.encode(moved.y), wanted.transfer.encode(moved.z))
    var texel := _texel(doc)
    assert_almost_eq(texel.r, expected.x, 1e-5, "red is the matrix conversion's red")
    assert_almost_eq(texel.g, expected.y, 1e-5, "green is its green")
    assert_almost_eq(texel.b, expected.z, 1e-5, "and blue its blue")
    assert_true(expected.y > 1e-3 and expected.z > 1e-3, "and the space is wide enough that neither is zero")
    assert_almost_eq(texel.a, 1.0, 0.0, "while alpha is coverage and is never converted")
    dialog.free()
    doc.free()
