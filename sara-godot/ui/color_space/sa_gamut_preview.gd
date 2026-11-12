## The highlight roll-off, drawn on colour.
##
## `SaCurvePlot` beside this says what the roll-off does to a *value*. It cannot
## say what it does to a *colour*, and the desaturation half of the operator only
## exists as a colour. This is that picture: every hue a display can show, each
## running from white down to its own most saturated colour, with the real
## operator run over it as both sliders drag.
##
## The one decision worth knowing. The material is
## `shaders/canvas/tonemap.gdshader` itself, the canvas's own operator, rather
## than a transcription of it. `SaCurvePlot` already carries one transcription
## and its header calls that cost out, so a second would be the fourth copy of
## four lines of arithmetic and the first to get the Oklab desaturation and the
## gamut map wrong. It works because the shader is `shader_type canvas_item` and
## reads `COLOR`, which Godot has already filled from the texture, and it does
## not care that the texture is a preview rather than a canvas.
##
## The second. The widget comes in two, and the reference half of the pair is
## the same shader with `tonemap_enabled` off and `display_exposure` at one over
## `STORED_SCALE`. That exposure is the whole of it. The picture is baked three
## stops above white so the operator has work to do, and the operator's own
## first act is to bring the peak back down to white, so a reference drawn at
## the stored exposure is the picture three stops up with its channels clipped
## one by one: paler, flatter, and not the same picture at all. Undoing the bake
## puts the reference at the magnitude the operator lands on, and the two halves
## then differ by the desaturation alone, which is the only thing the pair
## exists to show.
@tool
class_name SaGamutPreview
extends TextureRect

## The same footprint `SaCurvePlot` asks for, so the two sit as a pair.
const BASE_WIDTH := 240.0
const BASE_HEIGHT := 96.0

## What the picture is baked at, above white. At a stored 1.0 the roll-off has
## almost nothing to do and the widget shows a picture that barely moves as the
## sliders drag. `SaCurvePlot.STORED_MAX` is 4.0 because a painter stacking
## passes reaches about 3.0, so this sits where the curve's own x axis says the
## interesting part is.
const STORED_SCALE := 3.0

## The picture's own size in texels, fixed rather than following the UI scale.
##
## Generating it costs about 110 milliseconds at this size and four times that
## at twice it, which is a wait a painter would feel on opening Preferences. A
## texture drawn larger than it was baked softens a little. A texture baked much
## larger than it is drawn is the trap the build guide names, because the
## shader's tent filter averages taps it should not, so the error to make is
## this one.
const TEXELS := Vector2i(240, 96)

## Bisection steps for the gamut boundary, the same twelve the shader's own
## `gamut_map` spends. Twelve halvings leave 2.4e-4 of lightness, which is
## under a sixteenth of an 8-bit step, so the picture cannot tell.
const BOUNDARY_STEPS := 12

## Built once a session and shared. The picture never changes: only `knee` and
## `desaturation` move and both are uniforms, so rebuilding it on a slider tick
## is the obvious wrong turn and rebuilding it per Preferences window is a
## slower one.
static var _picture: ImageTexture = null


## `run_operator` false builds the reference half of the Preferences pair. The
## header's second decision says why that is the same shader rather than no
## material, and why it carries an exposure of its own.
func _init(run_operator: bool = true) -> void:
    custom_minimum_size = Vector2(SaUI.pxf(BASE_WIDTH), SaUI.pxf(BASE_HEIGHT))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_PASS
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    stretch_mode = TextureRect.STRETCH_SCALE

    var shader_material := ShaderMaterial.new()
    shader_material.shader = load("res://shaders/canvas/tonemap.gdshader")
    material = shader_material
    # Never from `SaSettings.tonemap_highlights`. The sliders this sits under
    # mean nothing with the roll-off off, and a blank preview while dragging
    # them is worse than useless, so the operated half runs whatever the canvas
    # setting says.
    shader_material.set_shader_parameter("tonemap_enabled", run_operator)
    if not run_operator:
        # The bake, undone. Without it the reference half draws the stored
        # texels raw and the display clips them channel by channel, so the pair
        # compares a rolled-off picture against a washed-out one rather than
        # against itself. The header's second decision has the reasoning.
        shader_material.set_shader_parameter("display_exposure", 1.0 / STORED_SCALE)


## The picture is taken on entering the tree rather than in `_init`, because
## its first bake is about 110 ms of arithmetic on the main thread and only a
## preview that is drawn needs it. The search builds the Display page off the
## tree to read its rows and frees it again, and baked there the picture was
## most of a 180 ms frame that could land on the painter's click.
func _enter_tree() -> void:
    if texture == null:
        texture = picture()


## The operated half and the plain one side by side, touching, the plain one
## mirrored left to right, so they touch and the difference is clear. Drawn
## the same way round, the hues meeting in the middle would be the strip's two
## ends. Mirrored, the hue at the operated half's
## right edge meets itself, so the seam is the operator's difference alone.
## The Display page and the Tonemap dialog both build their pair here.
static func pair(operated: SaGamutPreview, plain: SaGamutPreview) -> HBoxContainer:
    var both := HBoxContainer.new()
    both.add_theme_constant_override("separation", 0)
    plain.flip_h = true
    both.add_child(operated)
    both.add_child(plain)
    return both


## Both sliders call this, so the picture follows the drag.
##
## Only these two uniforms are ever written here. Every other one already
## defaults to an sRGB document on an sRGB display with no proof, and the single
## exposure in play is the reference half's, set once in `_init`. The reference
## half takes this call as well and is unmoved by it, which is what makes the
## pair a comparison: both materials carry the same knee and the same
## desaturation, and only `tonemap_enabled` decides whether either is read.
func configure(knee: float, desaturation: float) -> void:
    var shader_material := material as ShaderMaterial
    if shader_material == null:
        return
    shader_material.set_shader_parameter("knee", knee)
    shader_material.set_shader_parameter("desaturation", desaturation)


## What this half runs, for a dump: the shader it carries and every uniform
## something wrote on it.
##
## The pair in Preferences is read from two of these side by side. A shot of the
## two coloured strips says whether they land as one picture, and only this says
## why: the shader path has to be the same on both, and the written uniforms
## have to differ by `tonemap_enabled` and by the reference half's exposure and
## by nothing else. A uniform nobody wrote reads back null from Godot and is
## left out, which is what makes the two lists comparable at all.
func shader_report() -> Dictionary:
    var shader_material := material as ShaderMaterial
    if shader_material == null or shader_material.shader == null:
        return {"shader": "", "uniforms": {}}
    var written := {}
    for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
        var uniform_name: String = uniform.get("name", "")
        var value: Variant = shader_material.get_shader_parameter(uniform_name)
        if value != null:
            written[uniform_name] = value
    return {"shader": shader_material.shader.resource_path, "uniforms": written}


## The picture, built on the first ask and kept.
static func picture() -> ImageTexture:
    if _picture == null:
        _picture = ImageTexture.create_from_image(build_image(TEXELS))
    return _picture


## The gamut picture as the shader wants to read it: half-float, and holding
## document-encoded values rather than light-linear ones.
##
## The encode is not decoration. `document_is_srgb` is true, so the shader's
## first act is `srgb_to_linear_mirrored`, and a linear texture would arrive
## darkened by that. Half-float rather than 8-bit for the same kind of reason
## one step later: the picture is baked above white and eight bits clamp at 1.0,
## which would leave the roll-off nothing above the knee to work on.
##
## The geometry is `scripts/gen_gamut_images.py`, and the same picture at 2048
## by 1024 is committed as `tests/data/oklch_gamut_srgb.exr` for anything that
## wants to check this against it. x is hue over a full turn, the bottom row is
## every hue's cusp, and going up a row's chroma falls at one absolute rate
## shared by every column, so a hue runs out of chroma and turns white at its own
## height. Between the two a column rides the real gamut boundary rather than a
## straight line to white, which is the region a roll-off works in.
static func build_image(texels: Vector2i) -> Image:
    var cusps := SaOklab.gamut_cusps(texels.x)
    var ceiling := 0.0
    for cusp: Vector3 in cusps:
        ceiling = maxf(ceiling, cusp.y)

    var curve := SaTransferFunction.srgb()
    var image := Image.create_empty(texels.x, texels.y, false, Image.FORMAT_RGBAH)
    var rows := maxi(texels.y - 1, 1)
    for x in texels.x:
        var cusp: Vector3 = cusps[x]
        # The cusp's own hue rather than the column's left edge, so the bottom
        # row is the corner itself and every row above rides the same hue.
        var hue := cusp.z
        for y in texels.y:
            # Distance up from the bottom row, in absolute chroma, the same for
            # every hue. A column whose cusp is short runs out first.
            var chroma := cusp.y - float(rows - y) * ceiling / float(rows)
            var linear := Vector3.ONE
            if chroma > 0.0:
                var lightness := SaOklab.max_lightness(chroma, hue, cusp.x, BOUNDARY_STEPS)
                linear = SaOklab.to_linear_srgb(Vector3(lightness, chroma * cos(hue), chroma * sin(hue)))
                linear = linear.clampf(0.0, 1.0)
            image.set_pixel(
                x,
                y,
                Color(
                    curve.encode(linear.x * STORED_SCALE),
                    curve.encode(linear.y * STORED_SCALE),
                    curve.encode(linear.z * STORED_SCALE),
                    1.0
                )
            )
    return image
