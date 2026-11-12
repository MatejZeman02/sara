## The space Sara opens on has a preset, so New Document and the Colour Spaces
## page name it.
##
## The note: at factory settings New Document read Colour space "Custom",
## Transfer "Gamma 3.0", Coordinates "Oklab". The default takes its gamut from
## the display profile, so on an sRGB screen it is Oklab and the cube root over
## sRGB's primaries, and `presets()` held no entry for that. Both choosers read
## `presets()`, so the fix is one more entry and neither needed a change.
##
## Descriptors only: what the two choosers then read is in
## `ui/dialogs/document/new_document/tests/test_new_document_names_the_default_colour_space.gd`,
## since a suite under `core` does not name `ui`.
extends "res://tests/test_framework.gd"

## What every preset carried, written out here and not derived from
## the code, because a preset's id reaches `.sad` files and the day one of these
## changes meaning a file somebody saved reads as another space. Each row is the
## header `to_header` writes for it.
const OLD_PRESETS := {
    &"srgb": {"transfer": "srgb", "coordinates": "RGB", "white": [0.312727, 0.329023]},
    &"linear_srgb": {"transfer": "linear", "coordinates": "RGB", "white": [0.312727, 0.329023]},
    &"display_p3": {"transfer": "srgb", "coordinates": "RGB", "white": [0.312727, 0.329023]},
    &"acescg": {"transfer": "linear", "coordinates": "RGB", "white": [0.32168, 0.33767]},
    &"rec2020": {"transfer": "linear", "coordinates": "RGB", "white": [0.312727, 0.329023]},
    &"oklab": {"transfer": "srgb", "coordinates": "OKLAB", "white": [0.312727, 0.329023]},
    &"oklab_p3": {"transfer": "gamma", "coordinates": "OKLAB", "white": [0.312727, 0.329023]},
}

const OLD_PRIMARIES := {
    &"srgb": [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]],
    &"linear_srgb": [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]],
    &"display_p3": [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]],
    &"acescg": [[0.713, 0.293], [0.165, 0.830], [0.128, 0.044]],
    &"rec2020": [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]],
    &"oklab": [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]],
    &"oklab_p3": [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]],
}

const OLD_NAMES := {
    &"srgb": "sRGB",
    &"linear_srgb": "Linear sRGB",
    &"display_p3": "Display P3",
    &"acescg": "ACEScg",
    &"rec2020": "Rec. 2020",
    &"oklab": "Oklab over sRGB",
    &"oklab_p3": "Oklab over Display P3",
}

var _saved_profile: String = ""


func before_each() -> void:
    _saved_profile = SaSettings.display_profile


func after_each() -> void:
    SaSettings.display_profile = _saved_profile


## The preset a descriptor is, at its own depth, or null when it is none.
func _named(space: SaColorSpace) -> SaColorSpace:
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.with_depth(space.depth).matches(space):
            return preset
    return null


## The heart of it. On an sRGB display the easel's default space matches a
## preset, and the name a chooser reads for it is not Custom.
func test_the_default_on_an_srgb_display_matches_a_preset_by_name() -> void:
    SaSettings.display_profile = "srgb"
    var space := SaEasel.default_space()
    var preset := _named(space)
    assert_not_null(preset, "a preset matches the default on an sRGB display")
    if preset == null:
        return
    assert_eq(str(preset.id), str(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "and it is the one added for the sRGB-gamut Oklab space")
    var shown := SaColorSpace.display_name(preset.id)
    assert_true(shown != "Custom", "so the name a chooser reads is a name: %s" % shown)
    assert_eq(space.gamut().id, SaGamut.ID_SRGB, "over sRGB's primaries")
    assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_GAMMA30), "through the cube root")
    assert_eq(space.coordinates, SaColorSpace.Coordinates.OKLAB, "storing Oklab")


## The other two profiles, so a change for one screen does not move the others.
func test_the_default_on_the_other_displays_is_what_it_was() -> void:
    SaSettings.display_profile = "display_p3"
    var wide := SaEasel.default_space()
    assert_eq(str(_named(wide).id), str(SaColorSpace.ID_OKLAB_P3), "a Display P3 display opens on Oklab over Display P3")

    SaSettings.display_profile = "rec2020"
    var wider := SaEasel.default_space()
    assert_null(_named(wider), "a Rec. 2020 display opens on a space no preset names, which is true of it")
    assert_eq(str(wider.id), str(SaColorSpace.ID_CUSTOM), "and says Custom")
    assert_eq(SaColorSpace.display_name(wider.id), "Custom", "which a chooser reads as Custom")


## The new name reads apart from the sRGB Oklab entry beside it, because the two
## differ in the curve alone.
func test_the_new_name_reads_apart_from_oklab_over_srgb() -> void:
    var names: Array[String] = []
    for preset: SaColorSpace in SaColorSpace.presets():
        var shown := SaColorSpace.display_name(preset.id)
        assert_false(names.has(shown), "'%s' is on offer once" % shown)
        names.append(shown)
    assert_true(
        SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30) != SaColorSpace.display_name(SaColorSpace.ID_OKLAB),
        "the cube root entry is not the sRGB curve one"
    )
    assert_false(
        SaColorSpace.oklab().matches(SaColorSpace.oklab_srgb_gamma30()), "and the two are different spaces, as their names say"
    )


## The id is new, and no old id changed meaning: every preset that shipped before
## still carries its id, its name, its primaries, its white, its curve and its
## coordinates, which is what a `.sad` written by the last build names.
func test_every_existing_preset_keeps_its_id_and_its_fields() -> void:
    var by_id: Dictionary = {}
    for preset: SaColorSpace in SaColorSpace.presets():
        by_id[preset.id] = preset
    assert_eq(by_id.size(), OLD_PRESETS.size() + 1, "one preset more than before and no id twice")
    assert_false(OLD_PRESETS.has(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "whose id no old preset carried")
    assert_true(by_id.has(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "and which is on offer")

    for old_id: StringName in OLD_PRESETS:
        assert_true(by_id.has(old_id), "%s is still on offer" % old_id)
        if not by_id.has(old_id):
            continue
        var space: SaColorSpace = by_id[old_id]
        var header := space.to_header()
        var expected: Dictionary = OLD_PRESETS[old_id]
        assert_eq(header["id"], String(old_id), "%s keeps its id" % old_id)
        assert_eq(SaColorSpace.display_name(old_id), OLD_NAMES[old_id], "%s keeps its name" % old_id)
        assert_eq(header["coordinates"], expected["coordinates"], "%s keeps its coordinates" % old_id)
        assert_eq(header["depth"], "F32", "%s carries no depth of its own" % old_id)
        _assert_xy(header["white"], expected["white"], "%s keeps its white" % old_id)
        var primaries: Array = header["primaries"]
        var old_primaries: Array = OLD_PRIMARIES[old_id]
        assert_eq(primaries.size(), old_primaries.size(), "%s keeps three primaries" % old_id)
        for index in mini(primaries.size(), old_primaries.size()):
            _assert_xy(primaries[index], old_primaries[index], "%s primary %d" % [old_id, index])
        var curve: String = header["transfer"]
        if expected["transfer"] == "gamma":
            assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_GAMMA30), "%s keeps the cube root" % old_id)
        else:
            assert_eq(curve, expected["transfer"], "%s keeps its curve" % old_id)


## The new id reaches `.sad`, and a build that has never heard of it composes the
## space back from the numbers the header carries, as it does for any stranger.
func test_a_file_written_with_the_new_id_reads_back_as_itself() -> void:
    var space := SaColorSpace.oklab_srgb_gamma30().with_depth(SaColorSpace.Depth.F16)
    var read_back := SaColorSpace.from_header({"color_space": space.to_header()})
    assert_eq(str(read_back.id), str(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "the id survives the header")
    assert_true(read_back.matches(space), "with every field")

    var stranger: Dictionary = space.to_header().duplicate(true)
    stranger["id"] = "a_preset_from_the_future"
    var unknown := SaColorSpace.from_header({"color_space": stranger})
    assert_true(unknown.matches(space), "and a build that does not know the id still reads the same space from its numbers")


func _assert_xy(actual: Array, expected: Array, what: String) -> void:
    assert_almost_eq(float(actual[0]), float(expected[0]), 1e-6, "%s, x" % what)
    assert_almost_eq(float(actual[1]), float(expected[1]), 1e-6, "%s, y" % what)
