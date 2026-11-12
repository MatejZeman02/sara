## The colour space picker gives the space its rows hold, value by value, and
## a space saved in one picker is listed under the presets of the next.
##
## The picker is built as a host builds it, its rows declared on a page bound
## through the host and realized into a column, and moved through the controls
## a painter's hand moves, so the bindings are what is tested and not a member
## written behind the page's back. Nothing here is added to the tree, because a
## suite that maps a window hangs the run.
extends "res://tests/test_framework.gd"

## Six coordinates no preset gamut holds, a white no named one is, and a
## gamma between the named curves.
const RED := Vector2(0.6812, 0.3105)
const GREEN := Vector2(0.2034, 0.7341)
const BLUE := Vector2(0.1427, 0.0518)
const WHITE := Vector2(0.3301, 0.3412)
const GAMMA := 2.7
const SAVED_AS := "Suite's wide space"


## What a dialog is to the picker: the object its rows are bound through and
## the page they are drawn on. A node freed by hand as a dialog is, because the
## page's rows hold their target and a counted host would hold itself.
class Host:
    extends Node

    var picker := SaColorSpacePicker.new()
    var page: SaPage = null
    var column := VBoxContainer.new()

    func _init() -> void:
        page = SaPage.new(_declare)
        page.declare_rows()
        page.realize(column)
        page.row_changed.connect(func(key: StringName, _value: Variant) -> void: picker.row_changed(key))
        picker.moved.connect(page.refresh)

    func _declare(ui: SaPage) -> void:
        ui.section("")
        picker.declare_picked(ui, self, &"picker")
        picker.declare_details(ui, self, &"picker")

    func option(key: StringName) -> SaChoiceButton:
        return page.row(key).control as SaChoiceButton


var _kept: Array = []


## Frees *host* and the column its rows were drawn in, as a dialog's close does.
func _done(host: Host) -> void:
    host.column.free()
    host.free()


func before_each() -> void:
    _kept = SaSettings.saved_color_spaces.duplicate(true)
    SaSettings.saved_color_spaces = []


func after_each() -> void:
    SaSettings.saved_color_spaces = _kept


## Types a number into a spin box as a hand does, the value and then its signal,
## because a `Range` assigned to by a script outside the tree may not announce.
func _type(spin: SpinBox, value: float) -> void:
    spin.set_value_no_signal(value)
    spin.value_changed.emit(spin.value)


## Moves every row of *host* to the custom space this suite is about.
func _make_custom(host: Host) -> void:
    host.page.row(&"gamut").drive(SaGamut.presets().size())
    var fields := host.column.find_child("PrimariesFields", true, false) as SaColorSpacePicker.PrimariesField
    var wanted: Array[Vector2] = [RED, GREEN, BLUE]
    for i in 3:
        _type(fields.lights[i].x_spin, wanted[i].x)
        _type(fields.lights[i].y_spin, wanted[i].y)
    var white_field := host.column.find_child("WhitePointXy", true, false) as SaColorSpacePicker.XyField
    _type(white_field.x_spin, WHITE.x)
    _type(white_field.y_spin, WHITE.y)
    var slider := host.column.find_child("GammaSlider", true, false) as HSlider
    slider.set_value_no_signal(GAMMA)
    slider.value_changed.emit(slider.value)


## Every value of *space* against the ones this suite typed, within 1e-6.
func _assert_custom(space: SaColorSpace, where: String) -> void:
    var wanted: Array[Vector2] = [RED, GREEN, BLUE]
    for i in 3:
        assert_almost_eq(space.primaries[i].x, wanted[i].x, 1e-6, "%s: primary %d's x" % [where, i])
        assert_almost_eq(space.primaries[i].y, wanted[i].y, 1e-6, "%s: primary %d's y" % [where, i])
    assert_almost_eq(space.white.x, WHITE.x, 1e-6, "%s: the white's x" % where)
    assert_almost_eq(space.white.y, WHITE.y, 1e-6, "%s: the white's y" % where)
    assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_GAMMA), "%s: the curve is a pure power" % where)
    assert_almost_eq(space.transfer.exponent, GAMMA, 1e-6, "%s: the gamma" % where)


func test_the_rows_give_the_primaries_the_white_the_curve_and_the_gamma_typed() -> void:
    var host := Host.new()
    _make_custom(host)
    var space := host.picker.selected_space()
    _assert_custom(space, "the picker")
    assert_eq(str(space.id), str(SaColorSpace.ID_CUSTOM), "a space no preset names is custom")
    assert_eq(host.option(&"space").text, SaColorSpacePicker.CUSTOM_LABEL, "and the preset row reads Custom")
    assert_eq(host.option(&"gamut").text, SaColorSpacePicker.CUSTOM_LABEL, "as does the gamut row")
    assert_eq(host.option(&"white").text, SaColorSpacePicker.CUSTOM_LABEL, "and the white point row")
    assert_eq(host.option(&"transfer").text, host.picker.tr(SaColorSpacePicker.GAMMA_LABEL), "and the curve row")

    # A named white and a named curve are rows a painter picks too.
    host.page.row(&"white").drive(2)
    assert_true(host.picker.selected_space().white.is_equal_approx(SaColorSpacePicker.WHITE_D50), "D50 is offered")
    host.page.row(&"transfer").drive(0)
    assert_eq(str(host.picker.selected_space().transfer.id), str(SaTransferFunction.ID_SRGB), "and the sRGB curve")
    _done(host)


## A named gamut puts its own primaries and white back, and the preset row
## follows the values to the preset they now are.
func test_a_named_gamut_fills_the_fields_and_the_preset_follows() -> void:
    var host := Host.new()
    _make_custom(host)
    host.page.row(&"gamut").drive(0)
    host.page.row(&"transfer").drive(0)
    var space := host.picker.selected_space()
    assert_true(space.gamut().matches(SaGamut.srgb()), "sRGB's primaries are back")
    assert_true(space.white.is_equal_approx(SaColorSpace.WHITE_D65), "with sRGB's white")
    assert_eq(str(space.id), str(SaColorSpace.ID_SRGB), "so the space is sRGB again")
    assert_eq(host.option(&"space").text, "sRGB", "and the preset row says so")
    var fields := host.column.find_child("PrimariesFields", true, false) as SaColorSpacePicker.PrimariesField
    assert_almost_eq(fields.lights[0].x_spin.value, 0.64, 1e-6, "and the red field shows sRGB's red")
    _done(host)


func test_a_saved_space_is_listed_under_the_presets_of_the_next_picker() -> void:
    var first := Host.new()
    _make_custom(first)
    assert_eq(first.picker.save_as(SAVED_AS), SAVED_AS, "the space is saved under the name typed")
    assert_eq(first.option(&"space").text, SAVED_AS, "and the preset row names it at once")
    assert_false(first.picker.save_row.delete_button.disabled, "which Delete can act on")
    _done(first)

    var second := Host.new()
    var labels := second.option(&"space").choice_labels()
    var presets := SaColorSpace.presets().size()
    assert_eq(labels.size(), presets + 3, "the second picker lists the presets, the saved space, Custom and Profile file")
    assert_eq(labels[presets], SAVED_AS, "with the saved space right under the presets")
    assert_eq(labels[-2], SaColorSpacePicker.CUSTOM_LABEL, "and Custom under it")
    assert_eq(labels[-1], SaColorSpacePicker.PROFILE_FILE_LABEL, "with Profile file last")

    second.page.row(&"space").drive(0)
    assert_eq(str(second.picker.selected_space().id), str(SaColorSpace.ID_SRGB), "sRGB first")
    second.page.row(&"space").drive(presets)
    _assert_custom(second.picker.selected_space(), "the saved space picked")
    assert_eq(second.picker.saved_name(), SAVED_AS, "and the row shows it by its name")

    # Renamed and deleted where it is listed.
    assert_true(second.picker.rename_saved("Print proof"), "the saved space takes a new name")
    assert_eq(second.option(&"space").text, "Print proof", "which the row shows")
    assert_true(second.picker.delete_saved(), "and is deleted")
    assert_eq(second.option(&"space").choice_labels().size(), presets + 2, "leaving the presets, Custom and Profile file")
    assert_eq(second.option(&"space").text, SaColorSpacePicker.CUSTOM_LABEL, "its values on the rows as Custom")
    _assert_custom(second.picker.selected_space(), "after the delete")
    assert_true(SaSettings.saved_color_spaces.is_empty(), "and the settings hold none")
    _done(second)


## A space that is no preset and no saved space shows as Custom with its values.
func test_a_space_no_preset_names_shows_as_custom_with_its_values() -> void:
    var custom := SaColorSpace.create(
        SaColorSpace.ID_CUSTOM, PackedVector2Array([RED, GREEN, BLUE]), WHITE, SaTransferFunction.gamma(GAMMA)
    )
    var host := Host.new()
    host.picker.show_space(custom)
    assert_eq(host.option(&"space").text, SaColorSpacePicker.CUSTOM_LABEL, "the row reads Custom")
    assert_eq(host.picker.name_of(custom), SaColorSpacePicker.CUSTOM_LABEL, "and the picker names it so")
    var white_field := host.column.find_child("WhitePointXy", true, false) as SaColorSpacePicker.XyField
    assert_almost_eq(white_field.xy().x, WHITE.x, 1e-6, "the white's fields show its values")
    _assert_custom(host.picker.selected_space(), "shown")
    _done(host)


## A record the header reader cannot read is left out rather than listed as sRGB.
func test_a_broken_record_is_not_listed() -> void:
    SaSettings.saved_color_spaces = [{"name": "Broken"}, "not a record"]
    assert_true(SaColorSpacePicker.Saved.listed().is_empty(), "nothing readable, nothing listed")
    assert_eq(SaColorSpacePicker.Saved.save("  ", SaColorSpace.srgb()), "", "and an empty name saves nothing")
