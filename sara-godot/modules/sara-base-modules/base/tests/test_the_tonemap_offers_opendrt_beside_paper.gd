## OpenDRT beside Paper in the Tonemap filter.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Tonemap's OpenDRT method is Jed Smith's OpenDRT v1.1.0 ported to
## `opendrt.gmacs`, and this suite holds the port to the DCTL's own numbers.
## `opendrt_reference.gd`, beside this file, is the DCTL's `transform`
## transcribed a second time with its five fixed settings written in, and the
## two are read against one another through the same seventy-two parameters.
## With `oklab_hue` off the kernel has to answer what that transcription
## answers, which is what makes "off computes what the DCTL computes" a claim
## rather than a comment. With it on the six Brilliance windows have to sit an
## even sixth of the Oklab hue circle apart, which is the whole reason for
## moving the hue there, and a colour the display cannot show has to come back
## inside the cube with its hue held.
##
## **The document is linear and F32.** OpenDRT's input is scene-linear light
## and its output is display-referred light, and a linear sRGB F32 document
## stores both as they are, so a stored number is a light and the two
## transcriptions can be read against each other with no transfer curve in the
## way.
##
## **Oklab hue is on by default**, and it is this port's own switch rather than
## the DCTL's, so every test that reads a DCTL number turns it off first.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Params = preload("res://modules/sara-base-modules/base/usual/opendrt_parameters.gd")
const Reference = preload("res://modules/sara-base-modules/base/tests/opendrt_reference.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
## A scene-linear grey ramp, the middle grey OpenDRT's tonescale is built
## around landing near its own middle.
const RAMP_LOW := 0.001
const RAMP_HIGH := 16.0
const RAMP_SAMPLES := 64
const MIDDLE_GREY := 0.18
## What the tonescale answers for middle grey: `tn_lg` is ten per cent of the
## display's peak and the purity modules lift it a little, so a bound either
## side of the ten per cent OpenDRT is calibrated to.
const MIDDLE_GREY_LOW := 0.08
const MIDDLE_GREY_HIGH := 0.16
## The kernel is a float shader over floats and this side is GDScript, so a
## colour is read against the DCTL to this.
const DCTL_BOUND := 3e-3
## Two degrees of hue, in radians: finer than an eye tells a hue by.
const HUE_BOUND := 0.035
## A sixth of the circle, which is where the six Brilliance windows sit.
const SIXTH := PI / 3.0
## How far from its own sixth a measured window centre may land. Zero point
## nought four is under the sampling step, and the point of the bound is the
## whole sixth, which the DCTL's own opponent-space windows miss by far more.
const CENTRE_BOUND := 0.04
## The Oklab hue of linear sRGB red, which the kernel's own constant carries,
## so a window centre of nought is red as a painter reads it.
const RED_HUE := 0.5102275498
## Brilliance's six windows in the order the parameter table lists them.
const WINDOWS: Array[StringName] = [&"brl_r", &"brl_g", &"brl_b", &"brl_c", &"brl_m", &"brl_y"]
## Which of `WINDOWS` stands over the sixth beginning at nought. The table
## lists red, green, blue, then cyan, magenta, yellow, and the circle runs red,
## yellow, green, cyan, blue, magenta.
const WINDOW_AT_SIXTH := [0, 5, 1, 3, 2, 4]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaTonemapFilter = null
var _key: StringName = &""
var _kept_tonemap := false
var _kept_knee := 0.5
var _kept_desaturation := 0.15


func before_each() -> void:
    _kept_tonemap = SaSettings.tonemap_highlights
    _kept_knee = SaSettings.tonemap_knee
    _kept_desaturation = SaSettings.tonemap_desaturation
    SaSettings.tonemap_highlights = false
    var space := SaColorSpace.linear_srgb().with_depth(SaColorSpace.Depth.F32)
    _easel = SaEasel.create_default(SIZE, null, space)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    _filter = SaTonemapFilter.new()
    registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _easel.compositor.filter_chain.registry = registry
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = SaLayer.new()
    _layer.name = "Sample"
    _doc.add_child(_layer)
    _layer.fill(Color(0.0, 0.0, 0.0, 1.0))


func after_each() -> void:
    SaSettings.tonemap_highlights = _kept_tonemap
    SaSettings.tonemap_knee = _kept_knee
    SaSettings.tonemap_desaturation = _kept_desaturation
    if _easel != null:
        _easel.free()
        _easel = null
    _doc = null
    _layer = null
    _filter = null


# The DCTL's own settings, and the rows this port reads beside them.


## Standard's own numbers with the OpenDRT method, and any row *extra* names
## written over them. The table's defaults are Standard, which the first test
## holds the dialog to.
func _open_drt(extra: Dictionary = {}) -> Dictionary:
    var values := Params.defaults()
    values["method"] = Params.METHOD_OPENDRT
    for name: String in extra:
        values[name] = extra[name]
    return values


## Paper's own record, which is the filter's defaults and the Method row.
static func _paper() -> Dictionary:
    return {"method": Params.METHOD_PAPER}


## *colours* written along the chunk's first row, the Tonemap run over the
## layer at *values*, and the row read back as it stands afterwards.
##
## One write and one read for the whole row, so a sweep of a hundred hues is
## two dispatches rather than a hundred.
func _baked_row(colours: Array[Vector3], values: Dictionary) -> Array[Color]:
    var texture := _layer.get_field(Vector2i.ZERO)
    var flat := PackedFloat32Array()
    flat.resize(SIZE.x * SIZE.y * 4)
    var last: Vector3 = colours[colours.size() - 1]
    for i in SIZE.x * SIZE.y:
        flat[i * 4 + 0] = last.x
        flat[i * 4 + 1] = last.y
        flat[i * 4 + 2] = last.z
        flat[i * 4 + 3] = 1.0
    for x in colours.size():
        var c: Vector3 = colours[x]
        flat[x * 4 + 0] = c.x
        flat[x * 4 + 1] = c.y
        flat[x * 4 + 2] = c.z
        flat[x * 4 + 3] = 1.0
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(texture.rid, 0, flat.to_byte_array())
    assert_true(SaFilterOps.new(_doc).apply_once(_layer, _key, values, "Tonemap"), "The Tonemap runs over the sample layer")
    var bytes := rd.texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for x in colours.size():
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, x))
    return out


## One colour through the Tonemap, and back as a linear triple.
func _baked_one(colour: Vector3, values: Dictionary) -> Vector3:
    var read := _baked_row([colour], values)[0]
    return Vector3(read.r, read.g, read.b)


# The view's own highlight rolloff, and the two ways of reading a colour.


## *linear* put through the view's rolloff, or through the display encoding
## alone when *rolloff* is false, and read back as the screen shows it.
##
## The operands are the view's own: `shaders/compute/tonemap_rolloff.gmacs` is
## the port of `highlight_rolloff` in `shaders/canvas/tonemap.gdshader`, run by
## the export cell walk, and the knee and desaturation are the Preferences >
## Display settings the view reads.
func _shown(linear: Vector3, rolloff: bool) -> Vector3:
    var texture := SaTexture.new(Vector2i(64, 64))
    var texels := PackedFloat32Array()
    texels.resize(64 * 64 * 4)
    for i in 64 * 64:
        texels[i * 4 + 0] = linear.x
        texels[i * 4 + 1] = linear.y
        texels[i * 4 + 2] = linear.z
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    var params := SaExportGamut.tonemap_params(rolloff, SaSettings.tonemap_knee, SaSettings.tonemap_desaturation, 1.0)
    var image := SaExportGamut.encoded_image(texture, SaColorSpace.linear_srgb(), params)
    var read := image.get_pixel(0, 0)
    return Vector3(read.r, read.g, read.b)


static func _lab(linear: Vector3) -> Vector3:
    return SaOklab.from_linear_srgb(linear)


static func _chroma(linear: Vector3) -> float:
    return SaOklab.to_polar(_lab(linear)).y


static func _hue(linear: Vector3) -> float:
    return SaOklab.to_polar(_lab(linear)).z


static func _hue_gap(a: Vector3, b: Vector3) -> float:
    return absf(angle_difference(_hue(a), _hue(b)))


static func _peak(linear: Vector3) -> float:
    return maxf(linear.x, maxf(linear.y, linear.z))


# The parameter set and the rows.


## The DCTL's whole parameter space and the three rows this port adds.
func test_the_block_holds_the_dctl_s_own_seventy_two_parameters_in_its_own_order() -> void:
    assert_eq(Params.ORDER.size(), 72, "The block is seventy-two floats")
    assert_eq(Params.SETTINGS_FLOATS, 72, "which the kernel's own constant repeats")
    assert_true(Params.is_complete(), "and every slot is a row of the table")
    for key: StringName in [&"brl_c", &"brl_m", &"brl_y", &"tn_lcon_pc"]:
        assert_true(Params.rows_by_key().has(key), "%s is one of the three additions" % key)
    var table := Params.rows_by_key()
    for key: StringName in [&"brl_c", &"brl_m", &"brl_y"]:
        assert_almost_eq(float(table[key]["d"]), 0.0, 1e-9, "%s opens at nought, so a DCTL preset is untouched" % key)
    assert_false(bool(table[&"tn_lcon_pc"]["d"]), "Contrast Low Per Channel opens off")
    assert_true(bool(table[&"oklab_hue"]["d"]), "Oklab hue opens on")
    assert_false(Params.ORDER.has(&"oklab_hue"), "and rides the push constant rather than the block")


## Standard is the table's own defaults, which the dialog declares and the
## filter hands the kernel, so the two have not drifted.
func test_standard_matches_the_table() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(_filter)
    dialog.realize(host)
    var table := Params.defaults()
    for key: StringName in Params.ORDER:
        var row := dialog.row(key)
        assert_not_null(row, "%s has a row" % key)
        assert_almost_eq(float(row.read()), float(table[String(key)]), 1e-9, "%s opens at Standard" % key)
    var block := Params.pack(_filter.parameters())
    assert_eq(block.size(), 72, "The filter packs seventy-two floats for the kernel")
    host.free()


## The Method row, and which rows each method shows.
func test_the_method_row_offers_paper_and_opendrt() -> void:
    assert_eq(Params.METHODS, ["Paper", "OpenDRT"], "The row lists the two methods in that order")
    assert_eq(Params.METHOD_IDS, [Params.METHOD_PAPER, Params.METHOD_OPENDRT], "and its ids are the methods")
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(_filter)
    dialog.realize(host)
    var method := dialog.row(&"method")
    assert_eq(method.read(), Params.METHOD_PAPER, "A fresh filter opens at Paper")
    var knee := dialog.row(&"knee")
    var hue := dialog.row(&"oklab_hue")
    assert_true(knee.line.visible, "At Paper the Knee slider is on the page")
    assert_false(hue.line.visible, "and the OpenDRT rows are out of the way")
    method.write(Params.METHOD_OPENDRT)
    assert_eq(_filter.parameters()["method"], Params.METHOD_OPENDRT, "and picking OpenDRT is what the record keeps")
    assert_false(knee.line.visible, "At OpenDRT the Knee slider steps aside")
    assert_true(hue.line.visible, "and the OpenDRT rows are on the page")
    host.free()


# Bullet one: the ramp, the DCTL, the fit and the six windows.


func test_the_ramp_rises_from_the_dark_to_below_white_at_the_top() -> void:
    var light: Array[Vector3] = []
    for i in RAMP_SAMPLES:
        var t := float(i) / float(RAMP_SAMPLES - 1)
        var value := RAMP_LOW * pow(RAMP_HIGH / RAMP_LOW, t)
        light.append(Vector3(value, value, value))
    light.append(Vector3(MIDDLE_GREY, MIDDLE_GREY, MIDDLE_GREY))
    light.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
    var read := _baked_row(light, _open_drt())
    for i in range(1, read.size()):
        var before: Color = read[i - 1]
        var now: Color = read[i]
        assert_true(
            now.r > before.r, "The ramp rises at step %d, %s of a scene-linear %s then %s" % [i, before.r, light[i - 1].x, now.r]
        )
    var top: Color = read[read.size() - 1]
    assert_true(top.r < 1.0, "Sixteen stops above middle grey stays under white: %s" % top.r)
    assert_true(top.r > 0.8, "and close to it, so the shoulder is a shoulder: %s" % top.r)
    for sample: Color in read:
        assert_true(sample.r <= 1.0, "No step of the ramp is above the display's peak: %s" % sample.r)
    var middle: Color = read[light.find(Vector3(MIDDLE_GREY, MIDDLE_GREY, MIDDLE_GREY))]
    var held := "Middle grey 0.18 lands at %s, the tonescale's own grey"
    assert_true(middle.r >= MIDDLE_GREY_LOW and middle.r <= MIDDLE_GREY_HIGH, held % middle.r)
    var dctl := Reference.display_light(Vector3(MIDDLE_GREY, MIDDLE_GREY, MIDDLE_GREY), _filter.parameters())
    assert_almost_eq(middle.r, dctl.x, DCTL_BOUND, "and at what the DCTL gives it, %s" % dctl.x)


func test_with_oklab_hue_off_the_kernel_reads_the_dctl_s_own_numbers() -> void:
    var colours: Array[Vector3] = [
        Vector3(0.18, 0.18, 0.18), Vector3(2.5, 0.6, 0.15), Vector3(0.15, 1.5, 3.0), Vector3(0.02, 0.03, 0.04)
    ]
    var values := _open_drt({"oklab_hue": false})
    var read := _baked_row(colours, values)
    var held := _filter.parameters()
    for i in colours.size():
        var c: Color = read[i]
        var mine := Vector3(c.r, c.g, c.b)
        var theirs := Reference.display_light(colours[i], held)
        var gap := (mine - theirs).length()
        assert_true(
            gap <= DCTL_BOUND, "%s reads %s where the DCTL's own formula gives %s, apart %s" % [colours[i], mine, theirs, gap]
        )


## A saturated colour the display cannot show: the fit brings it inside the
## cube with the hue it had, where the DCTL's own per-channel clamp twists it.
##
## The look's hue-shaping modules and the two whose compression moves a ratio
## toward white are off for this one, so what is read is the fit's own holding
## and not the pipeline's own hue movement.
func test_a_colour_outside_the_cube_comes_back_inside_with_its_hue_held() -> void:
    var outside := Vector3(30.0, 0.1, 30.0)
    var look := {
        "hc_enable": false,
        "hs_rgb_enable": false,
        "hs_cmy_enable": false,
        "pt_enable": false,
        "ptm_enable": false,
        "brl_enable": false,
    }
    var shown := look.duplicate()
    shown["oklab_hue"] = true
    var fitted := _baked_one(outside, _open_drt(shown))
    var held := look.duplicate()
    held["oklab_hue"] = false
    var clipped := _baked_one(outside, _open_drt(held))
    assert_true(_peak(clipped) >= 1.0, "The DCTL's own clamp leaves a channel at the cube's face: %s" % clipped)
    assert_true(_peak(fitted) <= 1.0 + 1e-5, "and the fit brings it inside: %s" % fitted)
    var fit_gap := _hue_gap(outside, fitted)
    var clip_gap := _hue_gap(outside, clipped)
    assert_true(fit_gap <= HUE_BOUND, "The fitted colour holds its hue, turned %s radians" % fit_gap)
    assert_true(clip_gap > fit_gap, "where the clamp twists it, turned %s against the fit's %s" % [clip_gap, fit_gap])


## The six Brilliance windows, an even sixth of the Oklab hue circle apart.
##
## The rendering space's desaturate is at nought for this one, so the ratio the
## windows read is one fixed matrix away from the input and the colour handed
## the kernel at a window's own hue arrives at that hue. Six colours, one at
## each sixth, and each window run alone with its gain at two and the other
## five at nought. At a fixed hue every window reads the same response, so the
## one that lifts the lightness most is the one whose centre is nearest, and
## the window nearest the sixth it was placed at is its own.
func test_the_six_brilliance_windows_sit_an_even_sixth_apart() -> void:
    var colours: Array[Vector3] = []
    for k in 6:
        colours.append(_at_window_hue(SIXTH * float(k)))
    var quiet := _baked_row(colours, _open_drt(_brilliance(0.0)))
    var lifts := []
    for window: StringName in WINDOWS:
        var one := _brilliance(0.0)
        one[window] = 2.0
        var loud := _baked_row(colours, _open_drt(one))
        var row := PackedFloat32Array()
        for k in 6:
            row.append(_lab(_linear(loud[k])).x - _lab(_linear(quiet[k])).x)
        lifts.append(row)
    for k in 6:
        var loudest := 0
        for w in WINDOWS.size():
            if lifts[w][k] > lifts[loudest][k]:
                loudest = w
        assert_eq(
            loudest,
            WINDOW_AT_SIXTH[k],
            (
                "The loudest window at the sixth %d is %s, lifted by %s against its own %s"
                % [k, WINDOWS[loudest], lifts[loudest][k], lifts[k][k]]
            )
        )
        assert_true(
            lifts[WINDOW_AT_SIXTH[k]][k] > 0.0,
            "and %s lifts there at all: %s" % [WINDOWS[WINDOW_AT_SIXTH[k]], lifts[WINDOW_AT_SIXTH[k]][k]]
        )


## The linear triple whose Oklab hue is *hue*, from red at nought, and which
## reaches the kernel's rendering space at that same hue.
##
## The kernel renders in P3-D65 and reads the ratio's hue from it, so the input
## is the colour the rendering space's own matrices take there.
static func _at_window_hue(hue: float) -> Vector3:
    var in_render := SaOklab.to_linear_srgb(SaOklab.from_polar(Vector3(0.55, 0.15, hue + RED_HUE)))
    return Reference.rec709_from_render_space(in_render)


func _brilliance(gain: float) -> Dictionary:
    return {
        "rs_sa": 0.0,
        "brl": 0.0,
        "brl_r": gain,
        "brl_g": gain,
        "brl_b": gain,
        "brl_c": gain,
        "brl_m": gain,
        "brl_y": gain,
        "brl_st": 1.0,
    }


static func _linear(c: Color) -> Vector3:
    return Vector3(c.r, c.g, c.b)


# Bullet two: the record a document saved before the row still loads.


## A record that names no method reads Paper, with the knee and the
## desaturation it was saved with, which is why both kept their keys.
func test_a_record_saved_before_the_method_row_opens_as_paper() -> void:
    var saved := {"knee": 0.72, "desaturation": 0.31}
    var other := SaTonemapFilter.new()
    other.set_parameters(saved)
    var held := other.parameters()
    assert_eq(held["method"], Params.METHOD_PAPER, "A record naming no method reads Paper")
    assert_almost_eq(float(held["knee"]), 0.72, 1e-6, "and keeps the knee it was saved with")
    assert_almost_eq(float(held["desaturation"]), 0.31, 1e-6, "and the desaturation")
    assert_almost_eq(float(held["tn_lg"]), float(Params.defaults()["tn_lg"]), 1e-6, "A row it never named reads Standard")


## Every look preset fills the sliders it names with the DCTL's own numbers,
## and the Oklab check, which is this port's own row, is not one of them.
func test_each_look_preset_fills_the_sliders_it_names() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(_filter)
    dialog.realize(host)
    var preset := dialog.row(&"look_preset")
    for index in Params.LOOKS.size():
        preset.write(index)
        var held := _filter.parameters()
        var wanted := Params.look_values(index)
        for name: String in wanted:
            assert_almost_eq(
                float(held[name]), float(wanted[name]), 1e-6, "%s at %s is the DCTL's own" % [Params.LOOKS[index], name]
            )
        assert_true(bool(held["oklab_hue"]), "and %s leaves the Oklab check alone" % Params.LOOKS[index])
    var tonescale := dialog.row(&"tonescale_preset")
    for index in Params.TONESCALES.size():
        var before := _filter.parameters()
        tonescale.write(index)
        var held := _filter.parameters()
        var wanted := Params.tonescale_values(index)
        for name: String in wanted:
            assert_almost_eq(
                float(held[name]), float(wanted[name]), 1e-6, "Tonescale %s writes %s" % [Params.TONESCALES[index], name]
            )
        assert_eq(held["method"], before["method"], "A tonescale preset leaves the Method row where the painter put it")
    host.free()


# Bullet three: the double rolloff, and what it costs.


## Paper rolls the highlights off to white, and at the default knee of 1.0 the
## view's own rolloff over the result finds nothing past white to give up, so
## the chroma is not taken a second time.
func test_the_view_s_rolloff_over_a_paper_tonemap_gives_up_no_chroma_twice() -> void:
    var stored := Vector3(2.4, 0.7, 0.2)
    var baked := _baked_one(stored, _paper())
    var as_stored := _chroma(_shown(stored, false))
    var after_paper := _chroma(_shown(baked, false))
    var after_view := _chroma(_shown(baked, true))
    assert_true(after_paper < as_stored, "Paper gives up chroma above the knee, %s then %s" % [as_stored, after_paper])
    assert_almost_eq(
        after_view,
        after_paper,
        1e-6,
        "and the view's rolloff over the result takes no more, %s then %s" % [after_paper, after_view]
    )


# Bullet four: the view steps aside for a picture already tonemapped.


## A Tonemap on the picture turns the view's rolloff off while the setting
## stays on, and hiding or removing the filter brings it back.
func test_the_view_steps_aside_for_a_tonemap_on_the_picture() -> void:
    var canvas := _canvas()
    var mat := canvas.material as ShaderMaterial
    SaSettings.tonemap_highlights = true
    canvas.sync_tonemap()
    assert_true(mat.get_shader_parameter("tonemap_enabled"), "The rolloff runs with the setting on")
    var ops := SaFilterOps.new(canvas.document)
    var record := ops.attach(null, _key, _open_drt())
    assert_not_null(record, "A Tonemap attaches to the picture")
    canvas.sync_tonemap()
    assert_true(SaSettings.tonemap_highlights, "The setting is left on")
    assert_false(bool(mat.get_shader_parameter("tonemap_enabled")), "and the view's rolloff steps aside")
    ops.set_enabled(record, false)
    record.touch()
    canvas.sync_tonemap()
    assert_true(bool(mat.get_shader_parameter("tonemap_enabled")), "Hiding the filter brings the rolloff back")
    ops.set_enabled(record, true)
    record.touch()
    ops.detach(null, record)
    canvas.sync_tonemap()
    assert_true(bool(mat.get_shader_parameter("tonemap_enabled")), "and so does taking it off the picture")
    canvas.free()


## A Tonemap attached to one layer leaves the view alone, since the layers
## above and below still need it.
func test_a_tonemap_on_one_layer_leaves_the_view_alone() -> void:
    var canvas := _canvas()
    var mat := canvas.material as ShaderMaterial
    SaSettings.tonemap_highlights = true
    var layer := SaLayer.new()
    layer.name = "Paint"
    canvas.document.add_child(layer)
    layer.fill(Color(0.2, 0.4, 0.6, 1.0))
    var ops := SaFilterOps.new(canvas.document)
    assert_not_null(ops.attach(layer, _key, _open_drt()), "A Tonemap attaches to the layer")
    canvas.sync_tonemap()
    assert_true(
        bool(mat.get_shader_parameter("tonemap_enabled")), "The view lays its own rolloff over the layer's result all the same"
    )
    canvas.free()


## A canvas on a document whose chain knows this filter, the shape the two
## tests above drive.
func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    var registry := SaFilterRegistry.new()
    registry.register(SaTonemapFilter.new(), OWNER)
    canvas.easel.compositor.filter_chain.registry = registry
    canvas.sync_tonemap()
    return canvas
