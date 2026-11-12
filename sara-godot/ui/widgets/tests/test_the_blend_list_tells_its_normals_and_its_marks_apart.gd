## The blend list tells its two Normals apart on hover, and its
## favourite mark apart from its in-use mark.
##
## On an Oklab document the blend list showed "Normal
## (Oklab)", the default, and "Oklab Normal" a few rows below it, two modes that
## differ and whose hover said only their own names. Favourites repeated the
## favourited Normal and Multiply at the top, ticked, and a tick in every other
## Sara menu marks what is on, so a painter reads the tick as the mode in use.
##
## Read off the rows' `tooltip_text` rather than off a tooltip on screen, for the
## reason `test_a_toggle_rows_box_says_what_its_list_gives.gd` gives: a tooltip
## shows under the capture harness only inside a dialog, and this is the property
## the engine draws one from.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateReport = preload("res://harness/report/sa_state_report.gd")
const REQUIRES_GPU := true

const NORMALS: Array[StringName] = [&"normal", &"normal_srgb", &"normal_linear", &"normal_oklab"]


func _button(space: SaColorSpace = null) -> BlendModeButton:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.include_hidden_in_layers = true
    button.refresh()
    if space != null:
        button.space = space
        button.refresh()
    return button


func _tip(button: BlendModeButton, row_id: StringName) -> String:
    return button.popup.label_button(row_id).tooltip_text


## The finding's own case: on an Oklab document the two rows that read "Normal
## (Oklab)" and "Oklab Normal" say different things on hover, and each says
## which space it mixes in.
func test_the_two_normals_of_an_oklab_document_say_different_things() -> void:
    var button := _button(SaColorSpace.oklab())
    var popup := button.popup
    assert_eq(popup.label_button(&"normal").text, "Normal (Oklab)", "Plain Normal carries the document's space")
    assert_eq(popup.label_button(&"normal_oklab").text, "Oklab Normal", "and the pinned one leads with its own")

    var plain := _tip(button, &"normal")
    var pinned := _tip(button, &"normal_oklab")
    assert_true(plain != pinned, "The two hovers differ")
    assert_true(plain.contains("whatever space the document stores"), "Plain Normal says it follows the document: %s" % plain)
    assert_true(plain.contains("On this document it mixes in Oklab."), "and which space that is today")
    assert_true(pinned.contains("Oklab on every document"), "The pinned one says it is Oklab whatever the document: %s" % pinned)
    button.free()


## The four Normals read apart from one another on every document Sara makes,
## including the one where plain Normal equals the pinned Normal it is beside.
func test_no_two_normals_share_a_hover_on_any_document() -> void:
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.linear_srgb(), SaColorSpace.oklab(), SaColorSpace.acescg()]:
        var button := _button(space)
        var seen: Dictionary = {}
        for mode_id: StringName in NORMALS:
            var tip := _tip(button, mode_id)
            assert_false(seen.has(tip), "On %s, %s's hover is not %s's" % [space.blend_space_name(), mode_id, seen.get(tip, "")])
            seen[tip] = mode_id
        button.free()


## Every row the list offers says more on hover than the row already says, which
## is true of every blend row: Colour Dodge said "Colour Dodge".
func test_every_offered_mode_says_what_it_does() -> void:
    var button := _button(SaColorSpace.srgb())
    var popup := button.popup
    assert_true(popup.row_ids().size() > 15, "over the whole list, %d rows" % popup.row_ids().size())
    for row_id: StringName in popup.row_ids():
        var label := popup.label_button(row_id).text
        var tip := _tip(button, row_id)
        assert_true(tip.begins_with(label + "\n"), "%s's hover leads with its whole name, which the bar clips" % row_id)
        assert_true(tip.length() > label.length() + 20, "and goes on to a sentence: %s" % tip)
    button.free()


## A module's mode that brings no sentence keeps the hover every row had before,
## its own name, rather than an empty one.
func test_a_mode_with_no_sentence_says_its_name() -> void:
    var registries := Fixtures.make_registries()
    var mode := SaBlendModeDescriptor.create(&"quiet", "multiply")
    mode.display_name = "Quiet"
    mode.sort_order = 900
    registries.context.for_module(&"third-party").register_blend_mode(mode)

    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.refresh()
    assert_eq(_tip(button, &"quiet"), "Quiet", "The row says its name")
    button.free()


## The dropdown itself carries the hover of the mode it shows, so the bar's
## clipped "Normal (Okl" reads whole and says what it does.
func test_the_dropdown_hover_is_its_modes() -> void:
    var button := _button(SaColorSpace.oklab())
    assert_true(button.select_mode(&"normal_oklab"), "Oklab Normal is choosable")
    assert_eq(button.tooltip_text, _tip(button, &"normal_oklab"), "The dropdown says what its row says")
    assert_true(button.select_mode(&"normal"), "and so is plain Normal")
    assert_true(button.tooltip_text.begins_with("Normal (Oklab)\n"), "whose whole name leads its hover")
    button.free()


## The favourite is a star, filled or an outline, and the mode in use is the
## accent on its words. A favourite not in use wears no accent, and a mode in use
## that is not a favourite wears an outline, so neither mark can be read as the
## other.
func test_a_favourite_is_a_star_and_the_mode_in_use_is_the_accent() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["normal", "multiply"]
    var star := SaUI.get_icon("star")
    var outline := SaUI.get_icon("star_outline")
    assert_not_null(star, "The star ships")
    assert_not_null(outline, "and so does its outline")

    var button := _button(SaColorSpace.oklab())
    var popup := button.popup
    assert_true(button.select_mode(&"screen"), "Screen is in use, and no favourite")

    for row_id: StringName in popup.row_ids():
        var box := popup.check_box(row_id)
        assert_eq(box.get_theme_icon("checked"), star, "%s's box draws a filled star when it is ticked" % row_id)
        assert_eq(box.get_theme_icon("unchecked"), outline, "and an outline when it is not")

    var accent: Color = SaTheme.palette.accent_primary
    for row_id: StringName in [&"normal_fav", &"normal"]:
        assert_true(popup.is_checked(row_id), "%s is a favourite" % row_id)
        assert_false(popup.is_marked(row_id), "and not in use")
        assert_true(popup.label_button(row_id).get_theme_color("font_color") != accent, "so its words are not the accent")

    assert_true(popup.is_marked(&"screen"), "Screen's row wears the in-use mark")
    assert_eq(popup.label_button(&"screen").get_theme_color("font_color"), accent, "which is the accent on its words")
    assert_false(popup.is_checked(&"screen"), "while its box stays an outline")

    SaSettings.blend_favorites = was
    button.free()


## A mode both in use and a favourite wears both marks, each on its own control:
## the star on the box and the accent on the words.
func test_a_favourite_in_use_wears_both_marks_apart() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["multiply"]
    var button := _button()
    var popup := button.popup
    assert_true(button.select_mode(&"multiply"), "Multiply is choosable")
    for row_id: StringName in [&"multiply_fav", &"multiply"]:
        assert_true(popup.is_checked(row_id), "%s's star is filled" % row_id)
        assert_true(popup.is_marked(row_id), "and its words are marked in use")
    SaSettings.blend_favorites = was
    button.free()


## A dump says each row's hover, so a scenario shows the two Normals read
## apart in the running app, where a capture draws no tooltip over a list.
func test_a_dump_carries_each_rows_hover() -> void:
    var button := _button(SaColorSpace.oklab())
    var plain := StateReport._row_tooltip(button.popup, &"normal")
    assert_eq(plain, _tip(button, &"normal"), "Plain Normal's hover is in the dump")
    assert_true(plain != StateReport._row_tooltip(button.popup, &"normal_oklab"), "and differs from Oklab Normal's")
    button.free()


## The Layers docker's row puts "Layer" in front of its dropdown, and the state
## report still reads the dropdown as what the row says, since the word says
## whose mode it is and not which.
func test_the_report_reads_the_mode_past_the_layer_label() -> void:
    var host := Control.new()
    var box := HBoxContainer.new()
    box.name = "BlendBox"
    host.add_child(box)
    var label := Label.new()
    label.text = "Layer"
    box.add_child(label)
    var button := BlendModeButton.new()
    button.text = "Multiply"
    box.add_child(button)
    assert_eq(StateReport._blend_label_text(host), "Multiply", "The row says the mode, not the word in front of it")
    host.free()
