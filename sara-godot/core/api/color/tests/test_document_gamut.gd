## The document declares its gamut, a picked colour means that
## gamut, and the soft proof has something to move.
##
## A painter's note of 2026-09-10 was that soft proofing to sRGB did nothing on
## a Display P3 display, and the answer of 2026-09-11 made the document the source
## of truth for what `1, 0, 0` means. The numbers here are the ones the scenario
## of the same name reads off the running app.
extends "res://tests/test_framework.gd"

## Saving writes chunk textures and the dialog draws a gamut.
const REQUIRES_GPU := true

const EPSILON := 0.0005

## sRGB's red written in Display P3's coordinates through P3's sRGB curve, which
## is what a P3 red proofed to sRGB shows on a P3 display: 234, 51, 35.
const SRGB_RED_IN_P3 := Color(0.917501, 0.200306, 0.138591, 1.0)

## Display P3's red in linear sRGB, past one on red and below zero on the rest.
const P3_RED_IN_LINEAR_SRGB := Vector3(1.224899, -0.042063, -0.019645)

## How far apart the two reds sit in CIE XYZ, which is what the proof moves a P3
## red by.
const RED_DISTANCE_IN_XYZ := 0.078375

const RED := Color(1.0, 0.0, 0.0, 1.0)

var _saved_profile: String = ""


func before_each() -> void:
    _saved_profile = SaSettings.display_profile


func after_each() -> void:
    SaSettings.display_profile = _saved_profile


func _assert_rgb(actual: Color, expected: Color, epsilon: float, message: String) -> void:
    assert_almost_eq(actual.r, expected.r, epsilon, "%s, red" % message)
    assert_almost_eq(actual.g, expected.g, epsilon, "%s, green" % message)
    assert_almost_eq(actual.b, expected.b, epsilon, "%s, blue" % message)


# --- The document declares it ----------------------------------------------------


func test_a_new_document_takes_the_display_profiles_gamut() -> void:
    var expected := {"srgb": SaGamut.ID_SRGB, "display_p3": SaGamut.ID_DISPLAY_P3, "rec2020": SaGamut.ID_REC2020}
    for profile: String in expected:
        SaSettings.display_profile = profile
        var space := SaEasel.default_space()
        assert_eq(space.gamut().id, expected[profile], "a %s display opens a document in its own gamut" % profile)
        assert_eq(space.coordinates, SaColorSpace.Coordinates.OKLAB, "and keeps the coordinates under %s" % profile)
        assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_GAMMA30), "and the curve under %s" % profile)
        assert_eq(space.depth, SaColorSpace.Depth.F16, "and Y1's depth under %s" % profile)


## The choices over sRGB's primaries are a preset, so the colour space
## row names the space rather than reading Custom. A display whose gamut no
## preset pairs with Oklab and the cube root is where Custom is still true.
func test_the_dialog_names_the_default_over_srgb_and_says_custom_where_no_preset_fits() -> void:
    SaSettings.display_profile = "srgb"
    var dialog := NewDocumentDialog.new()
    assert_eq(
        dialog.row_option(&"space").text,
        SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30),
        "the colour space row names the default over sRGB"
    )
    assert_eq(dialog.row_option(&"gamut").text, SaGamut.srgb().display_name, "the gamut row reads the display's gamut")
    assert_eq(dialog.selected_space().gamut().id, SaGamut.ID_SRGB, "and the document it describes is in it")
    dialog.free()

    SaSettings.display_profile = "rec2020"
    var wide := NewDocumentDialog.new()
    assert_eq(wide.row_option(&"space").text, NewDocumentDialog.CUSTOM_LABEL, "over Rec. 2020 primaries the row reads Custom")
    wide.free()


func test_the_documents_gamut_round_trips_through_save_and_load() -> void:
    var path := SaDataRoot.path("test_document_gamut.sad")
    for profile: String in ["srgb", "display_p3", "rec2020"]:
        SaSettings.display_profile = profile
        var easel := SaEasel.create_default(Vector2i(64, 64), null, SaEasel.default_space())
        var saved := easel.document.color_space
        assert_eq(SaExport.save_sad(easel.document, path), OK, "a %s document saves" % profile)

        var reopened := SaEasel.create_default(Vector2i(16, 16), null, SaEasel.default_space())
        assert_eq(SaExport.load_sad(reopened.document, path), OK, "and loads")
        assert_eq(reopened.document.color_space.gamut().id, saved.gamut().id, "in the gamut it was saved in, %s" % profile)
        assert_true(reopened.document.color_space.matches(saved), "with the rest of its space, %s" % profile)

        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
        easel.free()
        reopened.free()


## What Image, Gamut converts to: the gamut moves and nothing else does.
func test_a_gamut_change_keeps_the_rest_and_names_a_preset_when_it_makes_one() -> void:
    var p3 := SaColorSpace.display_p3().with_depth(SaColorSpace.Depth.F16)
    var srgb := p3.with_gamut(SaGamut.srgb())
    assert_eq(str(srgb.id), str(SaColorSpace.ID_SRGB), "Display P3 over sRGB's primaries is sRGB")
    assert_eq(srgb.depth, SaColorSpace.Depth.F16, "at the depth it had")

    var wide := SaColorSpace.oklab_p3().with_gamut(SaGamut.rec2020())
    assert_eq(str(wide.id), str(SaColorSpace.ID_CUSTOM), "Oklab over Rec. 2020 at gamma 3 is no preset")
    assert_eq(wide.gamut().id, SaGamut.ID_REC2020, "and is in Rec. 2020")
    assert_eq(wide.coordinates, SaColorSpace.Coordinates.OKLAB, "storing Oklab still")
    assert_eq(str(wide.transfer.id), str(SaTransferFunction.ID_GAMMA30), "through the same curve")


# --- A picked colour means it ----------------------------------------------------


func test_a_picked_red_is_the_red_of_the_documents_gamut() -> void:
    _assert_rgb(SaColorSpace.display_p3().from_display(RED), RED, EPSILON, "a P3 document stores P3's red as 1, 0, 0")
    _assert_rgb(SaColorSpace.srgb().from_display(RED), RED, 0.0, "an sRGB document stores sRGB's, untouched")

    var lab := SaColorSpace.oklab_p3().from_display(RED)
    var linear := SaOklab.to_linear_srgb(Vector3(lab.r, lab.g, lab.b))
    assert_almost_eq(linear.x, P3_RED_IN_LINEAR_SRGB.x, 0.002, "an Oklab P3 document holds P3's red, past one in sRGB")
    assert_almost_eq(linear.y, P3_RED_IN_LINEAR_SRGB.y, 0.002, "with green below zero")
    assert_almost_eq(linear.z, P3_RED_IN_LINEAR_SRGB.z, 0.002, "and blue below zero, unclamped")

    var narrow := SaColorSpace.oklab().from_display(RED)
    var narrow_linear := SaOklab.to_linear_srgb(Vector3(narrow.r, narrow.g, narrow.b))
    assert_almost_eq(narrow_linear.x, 1.0, 0.002, "an Oklab sRGB document holds sRGB's red")
    assert_almost_eq(narrow_linear.y, 0.0, 0.002, "with nothing of green")


## The curve is not the gamut: the picker's numbers still go through sRGB's curve,
## so mid grey is 0.214 in any linear document whatever its primaries.
func test_the_curve_stays_the_pickers_whatever_the_gamut() -> void:
    var grey := Color(0.5, 0.5, 0.5, 1.0)
    var linear_grey := SaTransferFunction.srgb().decode(0.5)
    _assert_rgb(
        SaColorSpace.linear_srgb().from_display(grey), Color(linear_grey, linear_grey, linear_grey), EPSILON, "linear sRGB"
    )
    _assert_rgb(
        SaColorSpace.rec2020().from_display(grey), Color(linear_grey, linear_grey, linear_grey), EPSILON, "linear Rec. 2020"
    )
    _assert_rgb(SaColorSpace.display_p3().from_display(grey), grey, 0.0, "and Display P3 on the sRGB curve is a passthrough")


func test_the_eyedropper_hands_back_the_triple_the_picker_gave() -> void:
    var colours: Array[Color] = [RED, Color(0.2, 0.7, 0.4, 1.0), Color(0.5, 0.5, 0.5, 1.0), Color(0.9, 0.1, 0.8, 0.5)]
    for space: SaColorSpace in SaColorSpace.presets():
        for colour: Color in colours:
            var back := space.to_display(space.from_display(colour))
            _assert_rgb(back, colour, 0.001, "%s gives back %s" % [space.id, colour])
            assert_eq(back.a, colour.a, "and the alpha %s carried" % space.id)


## A gradient stop is a picked colour too, so a P3 document's ramp from `1, 0, 0`
## starts on the red its fill paints.
func test_a_gradient_stop_means_the_documents_gamut_too() -> void:
    var ramped := SaColorRamp.to_oklab(RED, SaColorSpace.oklab_p3())
    var filled := SaColorSpace.oklab_p3().from_display(RED)
    _assert_rgb(ramped, filled, 0.00001, "the ramp's red is the fill's")
    var unplaced := SaColorRamp.to_oklab(RED)
    assert_true(absf(unplaced.g - ramped.g) > 0.01, "and a ramp with no document is still sRGB's red")


# --- The proof moves it ----------------------------------------------------------


## The view's own chain for one texel, on the matrices `SaCanvas` hands the
## material: the document into linear sRGB, into the proof gamut and clipped
## there, back, into the display's primaries and through the sRGB curve.
func test_a_p3_red_proofed_to_srgb_on_a_p3_display_lands_on_srgbs_red() -> void:
    var document := SaColorSpace.display_p3()
    var proof := SaColorSpace.srgb()
    var display := SaColorSpace.display_p3()
    var curve := SaTransferFunction.srgb()
    var stored := document.from_display(RED)

    var linear: Vector3 = (
        document.to_linear_srgb_matrix() * Vector3(curve.decode(stored.r), curve.decode(stored.g), curve.decode(stored.b))
    )
    var back: Basis = proof.to_linear_srgb_matrix()
    var proofed: Vector3 = back * (back.inverse() * linear).clamp(Vector3.ZERO, Vector3.ONE)
    var unproofed: Vector3 = display.to_linear_srgb_matrix().inverse() * linear
    var shown: Vector3 = display.to_linear_srgb_matrix().inverse() * proofed

    _assert_rgb(
        Color(curve.encode(unproofed.x), curve.encode(unproofed.y), curve.encode(unproofed.z)), RED, 0.001, "off, P3's red"
    )
    _assert_rgb(
        Color(curve.encode(shown.x), curve.encode(shown.y), curve.encode(shown.z)), SRGB_RED_IN_P3, 0.001, "on, sRGB's red"
    )

    var p3_red: Vector3 = document.rgb_to_xyz() * Vector3(1.0, 0.0, 0.0)
    var srgb_red: Vector3 = proof.rgb_to_xyz() * Vector3(1.0, 0.0, 0.0)
    assert_almost_eq(p3_red.distance_to(srgb_red), RED_DISTANCE_IN_XYZ, EPSILON, "and the two sit that far apart in XYZ")


## A reference picture's pixel already names a colour, so it keeps the colour and
## changes its numbers, the opposite of a picked triple.
func test_a_reference_pictures_red_is_picked_as_the_same_colour_in_a_p3_document() -> void:
    var picked := SaColorSpace.picked_across(SaColorSpace.srgb(), SaColorSpace.display_p3(), RED)
    _assert_rgb(picked, SRGB_RED_IN_P3, EPSILON, "sRGB's red is picked where it sits in P3")
    _assert_rgb(SaColorSpace.picked_across(SaColorSpace.srgb(), null, RED), RED, 0.0, "with no document it stays itself")
    var unsaid := Color(0.3, 0.2, 0.1, 1.0)
    _assert_rgb(
        SaColorSpace.picked_across(null, SaColorSpace.display_p3(), unsaid),
        unsaid,
        0.0,
        "and a picture that never said is as it is"
    )
