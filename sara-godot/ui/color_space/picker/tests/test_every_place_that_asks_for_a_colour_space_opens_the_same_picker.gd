## Every single row that asks for a colour space ends in "Custom...", which opens
## the colour space picker as a dialog, and lists the spaces saved in it.
##
## The rows are the hosts' own, built as the hosts build them: Preferences >
## Display's Proof gamut and Display profile, the Minimap's proof and Import
## Fit's Read the picture as. "Custom..." is picked as a hand picks it, through
## the row, and the dialog it opens is answered through its Use button, so the
## call each host makes is what is tested. The dialog is a window, so the hosts
## sit in the tree with subwindows embedded, as the dialog sweep keeps them.
extends "res://tests/test_framework.gd"

## Six coordinates no preset gamut holds and a white no named one is.
const RED := Vector2(0.6812, 0.3105)
const GREEN := Vector2(0.2034, 0.7341)
const BLUE := Vector2(0.1427, 0.0518)
const WHITE := Vector2(0.3301, 0.3412)
const SAVED_AS := "Suite's wide space"
const CLOSE := 1e-6

var _host: Control = null
var _embedded: bool = true
var _kept: Dictionary = {}


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    for key: StringName in [
        &"saved_color_spaces", &"proof_profile", &"proof_custom_space", &"display_profile", &"display_custom_space"
    ]:
        var value: Variant = SaSettings.get(key)
        _kept[key] = value.duplicate(true) if value is Array or value is Dictionary else value
    SaSettings.saved_color_spaces = []
    SaSettings.proof_profile = "srgb"
    SaSettings.display_profile = "srgb"
    _host = Control.new()
    _host.size = Vector2(1280, 900)
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    for key: StringName in _kept:
        SaSettings.set(key, _kept[key])
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded


func _custom() -> SaColorSpace:
    return SaColorSpace.create(
        SaColorSpace.ID_CUSTOM, PackedVector2Array([RED, GREEN, BLUE]), WHITE, SaTransferFunction.gamma(2.7)
    )


## The Display page under the host, its rows realized.
func _display_page() -> SaDisplayPage:
    var page := SaDisplayPage.new()
    _host.add_child(page)
    return page


## Picks the entry *id* on the page row *row*, by its index as a hand does.
func _pick(row: SaPageRow, id: String) -> void:
    var control := row.control as SaChoiceButton
    row.drive(control.choice_values().find(id))


## The dialog "Custom..." opened under *control*, or null.
func _dialog_under(control: Node) -> SaColorSpacePickerDialog:
    return control.find_child("ColorSpacePickerDialog", true, false) as SaColorSpacePickerDialog


## Puts the dialog on *space* and presses Use.
func _answer(dialog: SaColorSpacePickerDialog, space: SaColorSpace) -> void:
    dialog.picker.show_space(space)
    dialog.use_button.pressed.emit()


func _assert_gamut(held: SaColorSpace, what: String) -> void:
    var wanted := _custom()
    assert_not_null(held, what)
    if held == null:
        return
    for i in 3:
        assert_true(
            held.primaries[i].distance_to(wanted.primaries[i]) < CLOSE,
            "%s holds primary %d within 1e-6: %s" % [what, i, held.primaries[i]]
        )
    assert_true(held.white.distance_to(wanted.white) < CLOSE, "%s holds the white within 1e-6: %s" % [what, held.white])


## The clause "sets the proof gamut to a custom gamut through Custom… and finds
## proof_profile_space() holding its primaries and white within 1e-6".
func test_the_proof_gamut_takes_a_custom_gamut_through_custom() -> void:
    var page := _display_page()
    var row := page.page.row(&"proof_profile")
    assert_true((row.control as SaChoiceButton).choice_values().has(SaColorSpaceRow.ASK_ID), "Proof gamut ends in Custom...")
    _pick(row, SaColorSpaceRow.ASK_ID)
    var dialog := _dialog_under(row.control)
    assert_not_null(dialog, "which opens the colour space picker as a dialog")
    if dialog == null:
        return
    assert_true(dialog.visible, "shown")
    assert_eq(SaSettings.proof_profile, "srgb", "and the setting waits for its answer")
    _answer(dialog, _custom())
    assert_eq(SaSettings.proof_profile, SaSettingsValues.DISPLAY_PROFILE_CUSTOM, "Use sets the proof to the custom space")
    _assert_gamut(SaSettings.proof_profile_space(), "proof_profile_space()")
    assert_eq(SaSettings.proof_profile_space().id, SaColorSpace.ID_CUSTOM, "under the custom id, as no preset is it")


## The same clause for the display profile and the display space, whose curve
## stays the display's own.
func test_the_display_profile_takes_a_custom_gamut_through_custom() -> void:
    var page := _display_page()
    var row := page.page.row(SaDisplayPage.PROFILE_ROW)
    _pick(row, SaColorSpaceRow.ASK_ID)
    var dialog := _dialog_under(row.control)
    assert_not_null(dialog, "Display profile's Custom... opens the picker")
    if dialog == null:
        return
    _answer(dialog, _custom())
    assert_eq(SaSettings.display_profile, SaSettingsValues.DISPLAY_PROFILE_CUSTOM, "Use sets the display profile")
    _assert_gamut(SaSettings.display_profile_space(), "display_profile_space()")
    assert_eq(
        SaSettings.display_profile_space().transfer.id,
        SaColorSpace.srgb().transfer.id,
        "and the curve is the display's, not the gamma the picker held"
    )


## Cancel leaves the setting as it was.
func test_cancel_leaves_the_proof_as_it_was() -> void:
    var page := _display_page()
    var row := page.page.row(&"proof_profile")
    SaSettings.proof_profile = "display_p3"
    _pick(row, SaColorSpaceRow.ASK_ID)
    var dialog := _dialog_under(row.control)
    if dialog == null:
        assert_not_null(dialog, "the picker opened")
        return
    dialog.picker.show_space(_custom())
    dialog.cancel_button.pressed.emit()
    assert_eq(SaSettings.proof_profile, "display_p3", "Cancel writes nothing")


## A space saved in the picker is listed in Import Fit's row, Preferences >
## Display's two rows and the Minimap's proof.
func test_a_saved_space_is_listed_in_every_row() -> void:
    var saved := SaColorSpacePicker.Saved.save(SAVED_AS, _custom())
    assert_eq(saved, SAVED_AS, "the picker saves the space")
    var entry := SaColorSpaceRow.SAVED_PREFIX + SAVED_AS

    var page := _display_page()
    for key: StringName in [&"proof_profile", SaDisplayPage.PROFILE_ROW]:
        var control := page.page.row(key).control as SaChoiceButton
        assert_true(control.choice_labels().has(SAVED_AS), "Display's %s lists the saved space" % key)
        assert_eq(control.choice_values()[-1], SaColorSpaceRow.ASK_ID, "and still ends in Custom...")

    var minimap := MinimapDocker.new()
    var proof := minimap.find_child("ProofGamut", true, false) as SaChoiceButton
    assert_not_null(proof, "the Minimap has its proof gamut")
    if proof != null:
        assert_true(proof.choice_values().has(entry), "which lists the saved space")
    minimap.free()

    var import_fit := SaImportFitDialog.new()
    import_fit.configure_open(Vector2i(64, 32), SaColorSpace.srgb(), -1)
    var space_row := import_fit.find_child("InputSpaceOption", true, false) as SaChoiceButton
    assert_true(space_row.choice_values().has(entry), "Import Fit's row lists the saved space")
    assert_eq(space_row.choice_values()[-1], SaColorSpaceRow.ASK_ID, "and ends in Custom...")
    assert_true(import_fit.select_space(StringName(entry)), "and takes it")
    _assert_gamut(import_fit.chosen_space(), "Import Fit's chosen space")
    import_fit.free()


## A saved space picked on Proof gamut is held by value, so deleting it later
## leaves the proof where it was.
func test_a_saved_space_picked_is_held_by_value() -> void:
    SaColorSpacePicker.Saved.save(SAVED_AS, _custom())
    var page := _display_page()
    var row := page.page.row(&"proof_profile")
    _pick(row, SaColorSpaceRow.SAVED_PREFIX + SAVED_AS)
    _assert_gamut(SaSettings.proof_profile_space(), "the proof on the saved space")
    page.page.refresh()
    assert_eq(
        (row.control as SaChoiceButton).selected_value(), SaColorSpaceRow.SAVED_PREFIX + SAVED_AS, "the row shows it by name"
    )
    SaColorSpacePicker.Saved.delete(SAVED_AS)
    _assert_gamut(SaSettings.proof_profile_space(), "the proof once the saved space is deleted")
    assert_true((row.control as SaChoiceButton).choice_values().has(SaColorSpaceRow.CUSTOM_ID), "and the row calls it Custom now")
