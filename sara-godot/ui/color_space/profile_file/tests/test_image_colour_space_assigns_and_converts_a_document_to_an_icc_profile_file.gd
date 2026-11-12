## Image > Colour Space takes an ICC profile file as its Target, so Assign and
## Convert work on the profile's primaries, white and curve as on a preset, the
## space is saved under the profile's description, and a lookup table profile
## is refused with the reason while the Target stays where it was.
##
## The profile is written here with known numbers, a version 2 matrix profile
## at D65 under a gamma of 2.5, which a `curv` tag holds exactly. The dialog is
## never added to the tree, because a suite that maps a window hangs the run.
## The file dialog's answer is handed to the picker as the dialog hands it.
extends "res://tests/test_framework.gd"

## The document is real chunks and Convert is a compute pass.
const REQUIRES_GPU := true

const PROFILE_NAME := "Suite's wide panel"
const PRIMARIES := [Vector2(0.7080, 0.2920), Vector2(0.1700, 0.7970), Vector2(0.1310, 0.0460)]
const GAMMA := 2.5
const TOLERANCE := 1e-4

var _written: Array[String] = []


func after_each() -> void:
    SaSadFile.finish_saves()
    for path: String in _written:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _written.clear()


func _known() -> SaColorSpace:
    return SaColorSpace.create(
        SaColorSpace.ID_CUSTOM, PackedVector2Array(PRIMARIES), SaColorSpace.WHITE_D65, SaTransferFunction.gamma(GAMMA)
    )


## A 32-bit sRGB document, so 1e-5 measures the conversion and not the storage.
func _document(fill: Color) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    doc.active_layer.fill(fill)
    return doc


func _image(doc: SaDocument) -> Image:
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(doc.active_layer.get_field(Vector2i(0, 0)))


## The dialog on *doc*, its two buttons wired as `main_dialogs.gd` wires them.
func _dialog_on(doc: SaDocument) -> ColorSpaceDialog:
    var dialog := ColorSpaceDialog.new()
    dialog.configure(doc.color_space, SaColorConversion.new(doc).blocked_reason)
    dialog.assign_requested.connect(func(space: SaColorSpace) -> void: SaColorConversion.new(doc).assign(space))
    dialog.convert_requested.connect(func(space: SaColorSpace) -> void: SaColorConversion.new(doc).convert_to(space))
    return dialog


## The Target's entries as the choice shows them.
func _labels(dialog: ColorSpaceDialog) -> Array:
    return (dialog.page.row(&"space").control as SaChoiceButton).choice_labels()


func _assert_known(space: SaColorSpace, what: String) -> void:
    var known := _known()
    for i in 3:
        assert_true(
            space.primaries[i].distance_to(known.primaries[i]) <= TOLERANCE,
            "%s: primary %d is the profile's, %s against %s" % [what, i, str(space.primaries[i]), str(known.primaries[i])]
        )
    assert_true(
        space.white.distance_to(known.white) <= TOLERANCE, "%s: the white is the profile's, %s" % [what, str(space.white)]
    )
    assert_almost_eq(space.transfer.exponent, GAMMA, TOLERANCE, "%s: the curve is the profile's gamma" % what)
    for value: float in [0.1, 0.5, 0.9]:
        assert_almost_eq(
            space.transfer.decode(value), known.transfer.decode(value), TOLERANCE, "%s: the curve at %s" % [what, value]
        )


func test_the_target_lists_the_profile_file_entry_and_takes_a_file_under_its_description() -> void:
    var dialog := ColorSpaceDialog.new()
    var labels := _labels(dialog)
    assert_eq(String(labels[-1]), SaColorSpacePicker.PROFILE_FILE_LABEL, "the Target's last entry opens a profile file")
    assert_eq(dialog.picker.profile_file_row(), labels.size() - 1, "and the picker knows it as that row")
    assert_true(dialog.picker.take_profile_file(_profile(_matrix_bytes())), "the matrix profile is read")
    labels = _labels(dialog)
    assert_eq(dialog.picker.space_row, labels.find(PROFILE_NAME), "the Target shows the profile's description")
    assert_eq(String(labels[-1]), SaColorSpacePicker.PROFILE_FILE_LABEL, "with Profile file still last")
    assert_eq(dialog.picker.capture_state()["space_name"], PROFILE_NAME, "and the space is named by it")
    dialog.free()


func test_assign_relabels_into_the_profile_and_leaves_every_texel() -> void:
    var doc := _document(Color(0.25, 0.5, 0.75, 1.0))
    var before := _image(doc).get_data()
    var dialog := _dialog_on(doc)
    assert_true(dialog.picker.take_profile_file(_profile(_matrix_bytes())), "the matrix profile is read")
    dialog.assign_button.pressed.emit()
    _assert_known(doc.color_space, "assigned")
    assert_eq(doc.color_space.profile_name, PROFILE_NAME, "the document's space carries the profile's description")
    assert_eq(_image(doc).get_data(), before, "and every texel of the chunk is as it was")
    dialog.free()
    doc.free()


func test_convert_moves_pure_red_by_the_matrix_to_the_profile() -> void:
    var doc := _document(Color(1.0, 0.0, 0.0, 1.0))
    var source := doc.color_space
    var dialog := _dialog_on(doc)
    assert_true(dialog.picker.take_profile_file(_profile(_matrix_bytes())), "the matrix profile is read")
    assert_false(dialog.convert_button.disabled, "Convert is offered into the profile")
    dialog.convert_button.pressed.emit()
    var wanted := doc.color_space
    _assert_known(wanted, "converted")
    var linear := Vector3(source.transfer.decode(1.0), source.transfer.decode(0.0), source.transfer.decode(0.0))
    var moved: Vector3 = source.to_space_matrix(wanted) * linear
    var expected := Vector3(wanted.transfer.encode(moved.x), wanted.transfer.encode(moved.y), wanted.transfer.encode(moved.z))
    var texel := _image(doc).get_pixel(0, 0)
    assert_almost_eq(texel.r, expected.x, 1e-5, "red is the matrix conversion's red")
    assert_almost_eq(texel.g, expected.y, 1e-5, "green is its green")
    assert_almost_eq(texel.b, expected.z, 1e-5, "and blue its blue")
    assert_true(expected.y > 1e-3 or expected.z > 1e-3, "and the conversion moved red off its own primary")
    dialog.free()
    doc.free()


func test_the_space_saves_and_opens_again_under_the_profile_s_description() -> void:
    var doc := _document(Color(0.25, 0.5, 0.75, 1.0))
    var dialog := _dialog_on(doc)
    assert_true(dialog.picker.take_profile_file(_profile(_matrix_bytes())), "the matrix profile is read")
    dialog.assign_button.pressed.emit()
    dialog.free()
    var saved := SaDataRoot.path("test_profile_file_saved.sad")
    _written.append(saved)
    SaSadFile.save_in_background(doc, saved, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "the document saves")
    var opened := SaDocument.new()
    assert_eq(SaExport.load_sad(opened, saved, SaCompositor.new()), OK, "and opens again")
    _assert_known(opened.color_space, "opened")
    assert_true(opened.color_space.matches(doc.color_space), "the same space it was saved in")
    assert_eq(opened.color_space.profile_name, PROFILE_NAME, "under the profile's description")
    var again := _dialog_on(opened)
    assert_eq(again.picker.name_of(opened.color_space), PROFILE_NAME, "which the dialog's Current line names it by")
    assert_eq(again.picker.space_row, _labels(again).find(PROFILE_NAME), "and its Target opens on")
    again.free()
    opened.free()
    doc.free()


func test_a_lookup_table_profile_leaves_the_target_and_says_why() -> void:
    var doc := _document(Color(0.25, 0.5, 0.75, 1.0))
    var dialog := _dialog_on(doc)
    var row_before := dialog.picker.space_row
    var space_before := dialog.selected_space()
    assert_false(dialog.picker.take_profile_file(_profile(_lut_bytes())), "the lookup table profile is refused")
    assert_eq(dialog.picker.space_row, row_before, "the Target stays where it was")
    assert_true(dialog.selected_space().matches(space_before), "and so does the space it adds up to")
    var status := (dialog.find_child("StatusLabel", true, false) as Label).text
    assert_true(status.contains("lookup table"), "the status line names the reason: %s" % status)
    dialog.free()
    doc.free()


func _profile(bytes: PackedByteArray) -> String:
    var path := SaDataRoot.path("profile_file_%d.icc" % _written.size())
    var out := FileAccess.open(path, FileAccess.WRITE)
    out.store_buffer(bytes)
    out.close()
    _written.append(path)
    return path


## A version 2 matrix profile of [method _known]: the colorants adapted from its
## white to D50 by Bradford, the white itself in `wtpt`, and one `curv` gamma.
func _matrix_bytes() -> PackedByteArray:
    var space := _known()
    var pcs := SaIccProfile.PCS_WHITE
    var chad := SaColorSpace.adaptation(space.white, Vector2(pcs.x, pcs.y) / (pcs.x + pcs.y + pcs.z))
    var colorants := chad * space.rgb_to_xyz()
    var curve := "curv".to_ascii_buffer()
    curve.append_array(PackedByteArray([0, 0, 0, 0]))
    curve.append_array(_u32(1))
    var fixed := int(roundf(GAMMA * 256.0))
    curve.append_array(PackedByteArray([(fixed >> 8) & 0xFF, fixed & 0xFF]))
    return _assemble(
        [
            ["desc", _desc(PROFILE_NAME)],
            ["rXYZ", _xyz_tag(colorants.x)],
            ["gXYZ", _xyz_tag(colorants.y)],
            ["bXYZ", _xyz_tag(colorants.z)],
            ["wtpt", _xyz_tag(SaColorSpace.xy_to_xyz(space.white))],
            ["rTRC", curve],
            ["gTRC", curve],
            ["bTRC", curve],
        ]
    )


## A profile with an `A2B0` tag and no colorants, as a lookup table profile is.
func _lut_bytes() -> PackedByteArray:
    var a2b0 := "mAB ".to_ascii_buffer()
    a2b0.resize(32)
    return _assemble([["desc", _desc("A LUT printer")], ["A2B0", a2b0], ["wtpt", _xyz_tag(SaIccProfile.PCS_WHITE)]])


func _assemble(tags: Array) -> PackedByteArray:
    var table := PackedByteArray()
    var body := PackedByteArray()
    var start := SaIccProfile.HEADER_SIZE + 4 + 12 * tags.size()
    for tag: Array in tags:
        var data: PackedByteArray = (tag[1] as PackedByteArray).duplicate()
        while data.size() % 4 != 0:
            data.append(0)
        table.append_array(String(tag[0]).to_ascii_buffer())
        table.append_array(_u32(start + body.size()))
        table.append_array(_u32(data.size()))
        body.append_array(data)
    var header := PackedByteArray()
    header.resize(SaIccProfile.HEADER_SIZE)
    header.encode_u8(8, 2)
    for i in 4:
        header[12 + i] = "mntr".unicode_at(i)
        header[16 + i] = "RGB ".unicode_at(i)
        header[20 + i] = "XYZ ".unicode_at(i)
        header[36 + i] = "acsp".unicode_at(i)
    var out := header
    out.append_array(_u32(tags.size()))
    out.append_array(table)
    out.append_array(body)
    var total := _u32(out.size())
    for i in 4:
        out[i] = total[i]
    return out


func _desc(text: String) -> PackedByteArray:
    var out := "desc".to_ascii_buffer()
    out.append_array(PackedByteArray([0, 0, 0, 0]))
    out.append_array(_u32(text.length() + 1))
    out.append_array(text.to_ascii_buffer())
    out.append(0)
    # The Unicode and ScriptCode parts a version 2 description carries after
    # its ASCII, empty.
    out.resize(out.size() + 4 + 4 + 2 + 1 + 67)
    return out


func _xyz_tag(value: Vector3) -> PackedByteArray:
    var out := "XYZ ".to_ascii_buffer()
    out.append_array(PackedByteArray([0, 0, 0, 0]))
    for component: float in [value.x, value.y, value.z]:
        var raw := int(roundf(component * 65536.0))
        if raw < 0:
            raw += 0x100000000
        out.append_array(_u32(raw))
    return out


func _u32(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])
