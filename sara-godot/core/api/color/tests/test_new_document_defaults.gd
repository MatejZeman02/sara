## What a fresh install opens on, and the preset that names it.
##
## A painter asked for Display P3, gamma 3.0, Oklab coordinates and 16-bit
## float, and reported that the colour space row read Custom. It read Custom
## because every piece of that combination existed and no preset named it, so
## `_on_axis_selected` had nothing to match against.
##
## Asked under a Display P3 display profile, which gave the default the
## profile's gamut. `test_document_gamut.gd` asks the other two profiles.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")

var _saved_profile: String = ""


func before_each() -> void:
    _saved_profile = SaSettings.display_profile
    SaSettings.display_profile = "display_p3"


func after_each() -> void:
    SaSettings.display_profile = _saved_profile


## The four the note names, in one descriptor, so a later change to any of them
## fails here rather than in a screenshot.
func test_the_default_space_is_what_a_painter_asked_for() -> void:
    var space := SaEasel.default_space()
    assert_eq(str(space.id), str(SaColorSpace.ID_OKLAB_P3), "Display P3 with Oklab coordinates is a preset now")
    assert_eq(space.gamut().id, SaGamut.ID_DISPLAY_P3, "the gamut is Display P3")
    assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_GAMMA30), "the curve is the cube root")
    assert_eq(space.coordinates, SaColorSpace.Coordinates.OKLAB, "the chunks hold Oklab")
    assert_eq(space.depth, SaColorSpace.Depth.F16, "and each channel gets sixteen bits")
    assert_eq(space.white, SaColorSpace.WHITE_D65, "D65, which is what Display P3 is normalised to")


## The preset itself carries no depth, because `with_depth` is applied before a
## match. One that named F16 could not name an F32 document that was otherwise
## itself, and the row would read Custom again.
func test_the_preset_carries_no_depth_of_its_own() -> void:
    var preset := SaColorSpace.oklab_p3()
    for depth: int in SaColorSpace.storage_depths():
        var document := SaColorSpace.oklab_p3().with_depth(depth)
        assert_true(preset.with_depth(document.depth).matches(document), "The preset names the document at depth %d" % depth)


## What the dialog does with it: every row opens on the default, and the colour
## space row names the combination rather than reading Custom.
func test_the_dialog_opens_on_the_default_rather_than_on_custom() -> void:
    var dialog := NewDocumentDialog.new()
    var chosen := dialog.selected_space()
    assert_eq(str(chosen.id), str(SaColorSpace.ID_OKLAB_P3), "The dialog describes the default space")
    assert_eq(chosen.depth, SaColorSpace.Depth.F16, "at the default depth")

    var presets := SaColorSpace.presets()
    var custom_row := presets.size()
    var space_option := dialog.row_option(&"space")
    assert_true(int(space_option.selected_value()) < custom_row, "and the colour space row is a name rather than Custom")
    assert_eq(space_option.text, SaColorSpace.display_name(SaColorSpace.ID_OKLAB_P3), "which is the one a painter asked for")
    dialog.free()


## The id is additive: it reaches the `.sad` header, and a build that has never
## heard of it composes the space back out of the primaries, the white and the
## curve, which are what the header treats as authoritative.
func test_a_file_written_with_the_new_id_opens_in_a_build_that_does_not_know_it() -> void:
    var space := SaEasel.default_space()
    var header: Dictionary[String, Variant] = {"color_space": space.to_header()}
    var read_back := SaColorSpace.from_header(header)
    assert_true(read_back.matches(space.with_depth(read_back.depth)), "The header round-trips through a build that knows the id")

    # The same header with an id nothing has ever registered, which is what an
    # older build sees.
    var stranger: Dictionary = header["color_space"].duplicate(true)
    stranger["id"] = "a_preset_from_the_future"
    var unknown := SaColorSpace.from_header({"color_space": stranger})
    assert_eq(unknown.gamut().id, SaGamut.ID_DISPLAY_P3, "An unknown id still opens on the primaries it carries")
    assert_eq(str(unknown.transfer.id), str(SaTransferFunction.ID_GAMMA30), "and the curve it names")
    assert_eq(unknown.coordinates, SaColorSpace.Coordinates.OKLAB, "and the coordinates it declares")
    assert_true(unknown.is_specified, "It was told what it is, so it is not unspecified")


## The canvas a fresh install actually paints on, not just the document it
## describes itself as. MainCanvas builds its easel at `create_default`'s null-
## space F32 before resetting the document to this default's F16, and nothing
## else re-derived the output from the document it now held: every stroke
## composited an F16 scratch onto a stale F32 canvas, which the compositor's
## own storage-format guard refused, silently, forever. `sara_shot.py` with a
## `stroke` step on an unmodified default document is what found it, because
## `history.steps` went to 1 while the canvas stayed exactly as blank as before.
func test_the_main_canvas_output_matches_the_default_documents_depth() -> void:
    var main_canvas := MainCanvasScript.new()
    main_canvas._ready()

    assert_eq(
        main_canvas.canvas.easel.output.format,
        main_canvas.canvas.document.color_space.texel_format(),
        "The canvas a stroke composites onto must be allocated at the document's own depth"
    )

    main_canvas.free()
