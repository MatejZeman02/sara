## The gamut mapping preference. The maintainers' word of 2026-09-17:
## "gamut mapping dropdown should be in the preferences with options: clip|oklab.
## Oklab would lock the hue and move chroma until in range. It is important for
## the negative colors where we clip right now."
##
## The export path is run twice over one texture holding a negative channel and
## a channel above one, once in each mode, and the written file is read back.
## Clip has to be the per-channel clamp byte for byte, as it was before the
## preference existed. Oklab has to land inside the cube on the hue it started
## on. A file that keeps its range has to be what it was in both modes, which
## is the no-clamp invariant (hard rule 5). The TIFF's half of both cases moved
## with the TIFF writer into the image formats module, to
## `test_a_tiff_takes_the_gamut_mapping.gd` beside it.
##
## The last case holds the "one shared function". `gamut_map` and the five
## functions it calls, the analytic intersection, live in
## three files, because a CanvasItem shader and the `.gmacs`
## dialect share no include, so the bodies are read as text and compared once
## the two syntaxes are written one way.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the cell walk dispatches real kernels.
const REQUIRES_GPU := true

const CHUNK := SaChunk.SIZE

## What the texture stores, as the sRGB-curve numbers an sRGB document holds: a
## red past one with a negative green, the colour a wide-gamut painting leaves
## behind and the one a painter's note names.
const OUTSIDE := Color(1.2, -0.2, 0.3, 1.0)

## An ordinary colour, which neither mode may move by a bit.
const INSIDE := Color(0.25, 0.5, 0.75, 1.0)

const VIEW_SHADER := "res://shaders/canvas/tonemap.gdshader"
const ROLLOFF_KERNEL := "res://shaders/compute/tonemap_rolloff.gmacs"
const MAPPING_KERNEL := "res://shaders/compute/map_into_gamut.gmacs"

## The six functions the view and the export share.
const SHARED: Array[String] = [
    "in_display_gamut",
    "with_chroma_scale",
    "signed_cbrt",
    "largest_cubic_root",
    "channel_exit",
    "gamut_map",
]

var _scratch: Array[String] = []


func after_each() -> void:
    for path: String in _scratch:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _scratch.clear()


## A chunk-sized RGBA32F texture whose every texel is *stored*.
func _filled(stored: Color) -> SaTexture:
    var texture := SaTexture.new(Vector2i(CHUNK, CHUNK))
    var texels := PackedFloat32Array()
    texels.resize(CHUNK * CHUNK * 4)
    for i in CHUNK * CHUNK:
        texels[i * 4 + 0] = stored.r
        texels[i * 4 + 1] = stored.g
        texels[i * 4 + 2] = stored.b
        texels[i * 4 + 3] = stored.a
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


func _path(file: String) -> String:
    var path := SaDataRoot.path("g1-%s" % file)
    _scratch.append(path)
    return path


## The sRGB curve's decode with the sign carried, which is what both kernels
## read a stored number through.
func _decoded(c: Color) -> Vector3:
    var out := Vector3.ZERO
    var channels := [c.r, c.g, c.b]
    for i in 3:
        var magnitude := absf(channels[i])
        var linear := magnitude / 12.92 if magnitude < 0.04045 else pow((magnitude + 0.055) / 1.055, 2.4)
        out[i] = signf(channels[i]) * linear
    return out


## The Oklab hue angle of an sRGB-curve colour, in degrees.
func _hue_degrees(c: Color) -> float:
    var lab := SaOklab.from_linear_srgb(_decoded(c))
    return rad_to_deg(atan2(lab.z, lab.y))


func test_the_decision_is_made_once() -> void:
    assert_eq(SaGamutMapping.normalized("oklab"), SaGamutMapping.OKLAB, "A mode's key is kept")
    assert_eq(SaGamutMapping.normalized("perceptual"), SaGamutMapping.CLIP, "and a key nobody knows reads as clip")
    assert_eq(SaGamutMapping.uniform_value(SaGamutMapping.CLIP), 0, "Clip is the shader's 0")
    assert_eq(SaGamutMapping.uniform_value(SaGamutMapping.OKLAB), 1, "and oklab its 1")
    assert_true(SaGamutMapping.export_maps(SaGamutMapping.OKLAB, false), "A file that narrows is mapped under oklab")
    assert_false(SaGamutMapping.export_maps(SaGamutMapping.CLIP, false), "and never under clip")
    assert_false(SaGamutMapping.export_maps(SaGamutMapping.OKLAB, true), "A file that keeps its range is never mapped")
    assert_eq(SaGamutMapping.for_export(SaGamutMapping.OKLAB, true), SaGamutMapping.CLIP, "so it is handed clip")


## Oklab, a painter's answer of 2026-09-27, which made the preference a view
## toggle of its own and on by default. The migration that moves an older profile is proved in
## `ui/settings/look/tests/test_gamut_mapping_is_a_view_toggle.gd`.
func test_a_fresh_profile_maps() -> void:
    # A Node, so it is freed by hand: a bare `new()` in the assertion leaked it.
    var values := SaSettingsValues.new()
    assert_eq(values.gamut_mapping, SaGamutMapping.OKLAB, "A new profile maps, a painter's answer of 2026-09-27")
    values.gamut_mapping = "perceptual"
    assert_eq(values.gamut_mapping, SaGamutMapping.CLIP, "and a key nobody knows is stored as clip")
    values.free()
    assert_true(SaSettingsKeys.KEYS.has("gamut_mapping"), "and the key is one the profile saves")


func test_clip_writes_the_per_channel_clamp_byte_for_byte() -> void:
    var texture := _filled(OUTSIDE)
    var before := SaExportGamut.encoded_byte_image(texture, SaColorSpace.srgb())
    var clip := SaExportGamut.encoded_byte_image(texture, SaColorSpace.srgb(), null, PackedFloat32Array(), SaGamutMapping.CLIP)
    assert_eq(clip.get_data(), before.get_data(), "Clip is the export as it stood, byte for byte")

    var path := _path("clip.png")
    assert_eq(SaExport.export_png_texture(texture, SaColorSpace.srgb(), path, 8, PackedFloat32Array(), SaGamutMapping.CLIP), OK)
    var written := Image.load_from_file(ProjectSettings.globalize_path(path))
    var texel := written.get_pixel(3, 5)
    assert_eq([texel.r8, texel.g8, texel.b8], [255, 0, 77], "Each channel is cut at the cube's edge on its own")


func test_oklab_lands_inside_the_cube_on_the_hue_it_started_on() -> void:
    var texture := _filled(OUTSIDE)
    var mapped := SaExportGamut.encoded_image(texture, SaColorSpace.srgb(), PackedFloat32Array(), SaGamutMapping.OKLAB)
    var texel := mapped.get_pixel(3, 5)
    for channel: float in [texel.r, texel.g, texel.b]:
        assert_true(channel >= -0.0001 and channel <= 1.0001, "Every channel is inside the cube, this one at %f" % channel)
    var turned := absf(_hue_degrees(texel) - _hue_degrees(OUTSIDE))
    assert_true(turned < 0.5, "The Oklab hue is held, and it turned by %f degrees" % turned)
    var clamped := Color(clampf(OUTSIDE.r, 0.0, 1.0), clampf(OUTSIDE.g, 0.0, 1.0), clampf(OUTSIDE.b, 0.0, 1.0))
    var clip_turned := absf(_hue_degrees(clamped) - _hue_degrees(OUTSIDE))
    assert_true(clip_turned > turned, "which the clamp does not manage: it turns the hue by %f" % clip_turned)
    assert_almost_eq(texel.a, OUTSIDE.a, 0.000001, "Alpha is not a colour and is left alone")

    var path := _path("oklab.png")
    assert_eq(SaExport.export_png_texture(texture, SaColorSpace.srgb(), path, 8, PackedFloat32Array(), SaGamutMapping.OKLAB), OK)
    var written := Image.load_from_file(ProjectSettings.globalize_path(path)).get_pixel(3, 5)
    assert_true(written.g8 > 0, "The written file gave chroma up, so the green the clamp zeroed is %d" % written.g8)
    assert_eq(written.r8, roundi(texel.r * 255.0), "and the bytes are the mapped floats rounded")


func test_a_colour_inside_the_cube_is_not_written_at_all() -> void:
    var texture := _filled(INSIDE)
    var clip := SaExportGamut.encoded_image(texture, SaColorSpace.srgb(), PackedFloat32Array(), SaGamutMapping.CLIP)
    var oklab := SaExportGamut.encoded_image(texture, SaColorSpace.srgb(), PackedFloat32Array(), SaGamutMapping.OKLAB)
    assert_eq(oklab.get_data(), clip.get_data(), "An ordinary picture exports bit for bit the same in both modes")
    assert_true(SaExportGamut.cells_visited > 0, "and the oklab one did walk its cells, so the kernel ran and declined")


func test_every_export_that_narrows_takes_the_mode() -> void:
    var texture := _filled(OUTSIDE)
    var space := SaColorSpace.srgb()
    var none := PackedFloat32Array()
    var files := {}
    for mode: String in SaGamutMapping.MODES:
        var png16 := _path("%s-16.png" % mode)
        var jpg := _path("%s.jpg" % mode)
        assert_eq(SaExport.export_png_texture(texture, space, png16, 16, none, mode), OK)
        assert_eq(SaExport.export_jpg_texture(texture, space, jpg, 0.9, none, mode), OK)
        files[mode] = [png16, jpg]
    for i in 2:
        var clip := FileAccess.get_file_as_bytes(files[SaGamutMapping.CLIP][i])
        var oklab := FileAccess.get_file_as_bytes(files[SaGamutMapping.OKLAB][i])
        assert_false(clip.is_empty(), "%s was written" % files[SaGamutMapping.CLIP][i])
        assert_true(clip != oklab, "%s differs from its clipped twin" % files[SaGamutMapping.OKLAB][i])


func test_the_files_that_keep_their_range_are_bit_exact_in_both_modes() -> void:
    var texture := _filled(OUTSIDE)
    var space := SaColorSpace.srgb()
    # The float a 32-bit file is written from, asked the way the facade asks.
    var kept := SaExportGamut.encoded_image(
        texture, space, PackedFloat32Array(), SaGamutMapping.for_export(SaGamutMapping.OKLAB, true)
    )
    assert_almost_eq(kept.get_pixel(3, 5).g, OUTSIDE.g, 0.0000001, "so its negative is still a negative")
    assert_almost_eq(kept.get_pixel(3, 5).r, OUTSIDE.r, 0.0000001, "and its value above one is still above one")

    # The EXR takes no mode at all: there is no argument for a caller to get wrong.
    var exr := _path("kept.exr")
    assert_eq(SaExport.export_exr_texture(texture, exr), OK)
    var read := Image.load_from_file(ProjectSettings.globalize_path(exr)).get_pixel(3, 5)
    assert_almost_eq(read.g, OUTSIDE.g, 0.0000001, "The EXR keeps the negative")
    assert_almost_eq(read.r, OUTSIDE.r, 0.0000001, "and the value above one")


## The body of *function* in *source*, one statement a line, with the two
## syntaxes written one way: no comments, no braces, no semicolons, no types on
## the signature, and the dialect's words for GLSL's operators.
func _body(source: String, function: String, dialect: bool) -> Array[String]:
    var lines: Array[String] = []
    var header := ("def %s(" if dialect else " %s(") % function
    var inside := false
    for raw: String in source.split("\n"):
        var comment := raw.find("#" if dialect else "//")
        var line := (raw.substr(0, comment) if comment >= 0 else raw).strip_edges()
        if not inside:
            inside = raw.begins_with("def ") and raw.contains(header) if dialect else _declares(raw, header)
            continue
        if line.is_empty():
            continue
        # The next top-level declaration ends a dialect body, the closing brace
        # in the first column ends a GLSL one.
        if (dialect and not raw.begins_with(" ")) or (not dialect and raw.begins_with("}")):
            break
        var written := _one_syntax(line)
        # A closing brace on a line of its own is GLSL's and says nothing.
        if not written.is_empty():
            lines.append(written)
    return lines


## Whether *raw* is a GLSL declaration of the function *header* names, which a
## call to it, indented inside another body, is not.
func _declares(raw: String, header: String) -> bool:
    return not raw.begins_with(" ") and raw.contains(header) and raw.strip_edges().ends_with("{")


func _one_syntax(line: String) -> String:
    var out := line.trim_suffix(";").trim_suffix("{").trim_suffix(":").strip_edges()
    out = out.trim_prefix("}").strip_edges()
    for pair: Array in [
        ["greaterThanEqual", "greater_than_equal"],
        ["lessThanEqual", "less_than_equal"],
        ["&&", "and"],
        ["||", "or"],
    ]:
        out = out.replace(pair[0], pair[1])
    if out.begins_with("if (") and out.ends_with(")"):
        out = "if " + out.substr(4, out.length() - 5)
    # A GLSL statement broken over two lines begins its second with the operator.
    return out


func test_the_three_copies_of_gamut_map_are_one_function() -> void:
    var view := FileAccess.get_file_as_string(VIEW_SHADER)
    var rolloff := FileAccess.get_file_as_string(ROLLOFF_KERNEL)
    var mapping := FileAccess.get_file_as_string(MAPPING_KERNEL)
    for function: String in SHARED:
        var in_view := " ".join(_body(view, function, false))
        var in_rolloff := " ".join(_body(rolloff, function, true))
        var in_mapping := " ".join(_body(mapping, function, true))
        assert_false(in_view.is_empty(), "%s is read out of the view shader" % function)
        assert_eq(in_rolloff, in_view, "%s in tonemap_rolloff.gmacs is the view's" % function)
        assert_eq(in_mapping, in_view, "%s in map_into_gamut.gmacs is the view's" % function)


## The mapping is not the rolloff's: the view's call sits after the display
## matrix and before the encode, outside `if (tonemap_enabled)`.
func test_the_view_maps_outside_the_rolloffs_branch() -> void:
    var view := FileAccess.get_file_as_string(VIEW_SHADER)
    var rolloff := view.find("if (tonemap_enabled)")
    var matrix := view.find("mat3(display_col0, display_col1, display_col2) * lin")
    # The last mention: the first is the guard that lets a texel outside the cube
    # into the block at all, which sits above everything.
    var mapped_at := view.rfind("gamut_mapping == 1 &&")
    var encode := view.rfind("linear_to_srgb_mirrored(lin)")
    assert_true(rolloff >= 0 and matrix > rolloff, "The display matrix follows the rolloff's branch")
    assert_true(mapped_at > matrix, "The mapping runs after the display matrix, on the display's own cube")
    assert_true(mapped_at < encode, "and before the encode")
    # The block the call sits in is skipped whole on a display-ready document,
    # so the guard has to open for a texel the mapping would move.
    assert_true(view.contains("|| !display_identity || unheld)"), "The passthrough guard opens for a texel outside the cube")
