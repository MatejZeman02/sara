## The view-time tonemapper's plumbing, and the exposure that feeds it.
##
## The operator itself is a .gdshader and cannot be dispatched from here the way
## a .gmacs kernel can, so what this suite guards is everything around it: that
## the canvas carries the material, that the uniforms track the document rather
## than being written once, and above all that the pixels are never touched.
##
## The curve's shape is checked by painting past 1.0 in the running app and
## looking, which is the only honest way to check a look.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")


## The cases start with the rolloff off, so that switching it on is the change
## they watch, and end on a fresh profile's values, so the suites after this
## one see the defaults they would see on their own.
func before_each() -> void:
    SaSettings.tonemap_highlights = false
    SaSettings.tonemap_knee = _fresh(&"tonemap_knee")
    SaSettings.tonemap_desaturation = _fresh(&"tonemap_desaturation")


func after_each() -> void:
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    SaSettings.tonemap_highlights = _fresh(&"tonemap_highlights")
    SaSettings.tonemap_knee = _fresh(&"tonemap_knee")
    SaSettings.tonemap_desaturation = _fresh(&"tonemap_desaturation")


## On by default. With the knee at white every colour the
## display can show reaches the screen as it does with the rolloff off, so the
## switch changes only what the display cannot show, and a painting made before
## it existed looks as it did wherever it stays inside the cube.
func test_the_tonemapper_is_on_by_default() -> void:
    assert_true(_fresh(&"tonemap_highlights"), "A fresh profile tonemaps")
    assert_almost_eq(_fresh(&"tonemap_knee"), 1.0, 0.0, "from white up")


func test_the_toggle_announces_itself() -> void:
    var seen: Array[bool] = []
    var listener := func(enabled: bool) -> void: seen.append(enabled)
    EventBus.tonemap_changed.connect(listener)
    SaSettings.tonemap_highlights = true
    SaSettings.tonemap_highlights = false
    EventBus.tonemap_changed.disconnect(listener)
    assert_eq(seen, [true, false], "Both edges reach the view")


## The uniform tracks the setting rather than being sampled once at startup,
## which is the bug the colour space dialog already shipped and had to be fixed
## for: a value read at construction is a value that never changes again.
func test_the_uniform_follows_the_setting() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    # Not _ready(): that wants a viewport for the size_changed hookup, and none
    # of what this suite checks needs one.
    canvas.sync_tonemap()

    var mat := canvas.material as ShaderMaterial
    assert_not_null(mat, "The canvas carries a ShaderMaterial")
    assert_false(mat.get_shader_parameter("tonemap_enabled"), "and starts off")

    SaSettings.tonemap_highlights = true
    assert_true(mat.get_shader_parameter("tonemap_enabled"), "The View menu toggle reaches the shader")

    canvas.free()


## The gamut mapping preference reaches the view as a uniform of
## its own, with the rolloff off, because the mapping is not the rolloff's and
## does not wait for it. 0 is clip and 1 is oklab, `SaGamutMapping.MODES`' order.
func test_the_gamut_mapping_uniform_follows_the_setting_with_the_rolloff_off() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_false(SaSettings.tonemap_highlights, "The rolloff is off for the whole case")
    # Clip first, because a fresh profile maps and the case is the round trip
    # rather than the default.
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    assert_eq(mat.get_shader_parameter("gamut_mapping"), 0, "Clip is the shader's 0")
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    assert_eq(mat.get_shader_parameter("gamut_mapping"), 1, "Oklab reaches the shader without the rolloff")
    assert_false(mat.get_shader_parameter("tonemap_enabled"), "and switches the rolloff on for nobody")
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    assert_eq(mat.get_shader_parameter("gamut_mapping"), 0, "and clip goes back the same way")

    canvas.free()


## W and the transfer flag are document data, so the view has to re-read them
## rather than assume sRGB at 1.0 forever.
func test_the_uniforms_track_the_document() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    # Not _ready(): that wants a viewport for the size_changed hookup, and none
    # of what this suite checks needs one.
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_almost_eq(mat.get_shader_parameter("blend_white"), 1.0, 0.0, "A default document's window is 1.0")
    assert_true(mat.get_shader_parameter("document_is_srgb"), "and an sRGB document needs decoding")

    canvas.document.blend_reference_white = 3.0
    canvas.document.color_space = SaColorSpace.linear_srgb()
    canvas.sync_tonemap()
    assert_almost_eq(mat.get_shader_parameter("blend_white"), 3.0, 0.0, "A wider window reaches the shader")
    assert_false(mat.get_shader_parameter("document_is_srgb"), "and a linear document skips the transfer pair")

    canvas.free()


## Both knobs are settings rather than shader constants, so they have to reach
## the material. A slider that moves and changes nothing is the failure mode.
func test_the_sliders_reach_the_shader() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_almost_eq(mat.get_shader_parameter("knee"), 1.0, 0.0, "The default knee is white, Sara's, not a scene-referred one")
    assert_almost_eq(mat.get_shader_parameter("desaturation"), 0.15, 0.0, "and the default desaturation")

    SaSettings.tonemap_knee = 0.35
    SaSettings.tonemap_desaturation = 0.4
    assert_almost_eq(mat.get_shader_parameter("knee"), 0.35, 1e-6, "Moving the knee reaches the shader")
    assert_almost_eq(mat.get_shader_parameter("desaturation"), 0.4, 1e-6, "and so does the desaturation")

    canvas.free()


## The knee cannot reach 0, where there is no identity region left. It reaches
## 1, the default, and goes past it to 4, where chroma
## is kept a while above white, because the magnitude is white above white at
## every knee and what the knee moves is where chroma starts being lost.
func test_the_knee_is_clamped_to_a_usable_range() -> void:
    SaSettings.tonemap_knee = -5.0
    assert_almost_eq(SaSettings.tonemap_knee, 0.05, 1e-6, "A knee below the floor is refused")
    SaSettings.tonemap_knee = 9.0
    assert_almost_eq(SaSettings.tonemap_knee, SaSettings.TONEMAP_KNEE_TOP, 1e-6, "and above the ceiling, the top")
    SaSettings.tonemap_desaturation = 5.0
    assert_almost_eq(SaSettings.tonemap_desaturation, 1.0, 1e-6, "Desaturation saturates at fully neutral")


## Preferences > Canvas and colour, the Display page, is
## where the sliders live, so the page has to exist and has to build. Listing it
## in FIXED_PAGES without a factory would give an empty page, which looks exactly
## like a working one until you click it.
func test_the_display_page_builds() -> void:
    assert_true(SaSettingsWindow.FIXED_PAGES.has("Canvas and colour"), "Preferences offers the page")

    var window := SaSettingsWindow.new()
    assert_true(window.show_page("Canvas and colour"), "and opens it")

    var sliders := 0
    var switches := 0
    var pending: Array = [window.content_container]
    while not pending.is_empty():
        var node: Node = pending.pop_back()
        for child in node.get_children():
            # The previous page is cleared with queue_free(), which does not take
            # effect until the frame ends, so its controls are still children
            # here. Counting them would make this pass for the wrong reason.
            if child.is_queued_for_deletion():
                continue
            pending.append(child)
            if child is HSlider:
                sliders += 1
            elif child is CheckButton:
                switches += 1
    assert_eq(
        sliders, 6, "The page carries the knee, desaturation, exposure stops and the relief's light, strength and gloss sliders"
    )
    assert_eq(switches, 5, "and the rolloff, exposure, whole zoom steps, Shape Check posterise and grid switches")

    window.free()


## The whole design rests on this. If the tonemapper ever reached easel.output,
## the eyedropper would sample a look rather than a colour and export would bake
## one in.
func test_the_tonemapper_never_touches_stored_pixels() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    # Not _ready(): that wants a viewport for the size_changed hookup, and none
    # of what this suite checks needs one.
    canvas.sync_tonemap()

    var document := canvas.document
    document.fill_layer(Color(4.0, 0.25, 0.5, 1.0), document.active_layer)
    document.update_caches()
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()

    SaSettings.tonemap_highlights = true
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()

    var data := rd.texture_get_data(canvas.easel.output.rid, 0)
    assert_almost_eq(data.decode_float(0), 4.0, 1e-4, "A stored 4.0 is still 4.0 with the tonemapper on")
    assert_almost_eq(data.decode_float(4), 0.25, 1e-4, "and so is the green channel")

    canvas.free()


## Exposure is the input path, the way a value above 1.0 is painted at all, and
## it is the foreground's own stops in `SaColors` rather
## than a multiplier on the brush. The colour part stays apart from them, so the
## picker keeps round-tripping what the painter chose.
func test_exposure_is_separate_from_the_picked_colour() -> void:
    var settings := BrushSettingsScript.new()
    assert_false("exposure" in settings, "A brush has no exposure of its own")
    var before := SaColors.foreground
    SaColors.foreground = Color(1.0, 0.0, 0.0)
    SaColors.exposure_stops = 2.0
    assert_true(SaColors.foreground_base.is_equal_approx(Color(1.0, 0.0, 0.0)), "The colour part is the one that was picked")
    assert_true(SaColors.foreground.is_equal_approx(Color(4.0, 0.0, 0.0)), "and the stops ride alongside it")
    SaColors.foreground = before


## Every uniform the canvas writes must exist in the shader.
##
## Two failures at once, and both are silent. A shader that does not compile
## returns an empty uniform list and Godot quietly substitutes a fallback, which
## is how an early `return` in fragment(), illegal in Godot's shading language
## and rejected only at load time, got as far as a running app. And
## set_shader_parameter on a name the shader does not declare does nothing at
## all, so renaming a uniform on one side of this seam breaks the view without
## breaking anything that reports.
func test_the_view_shader_compiles_and_declares_what_the_canvas_writes() -> void:
    var shader: Shader = load("res://shaders/canvas/tonemap.gdshader")
    var declared: Array[String] = []
    for entry: Dictionary in shader.get_shader_uniform_list():
        declared.append(String(entry["name"]))

    assert_false(declared.is_empty(), "An empty uniform list means the shader failed to compile")
    for written: String in [
        "tonemap_enabled",
        "knee",
        "desaturation",
        "gamut_mapping",
        "blend_white",
        "document_is_srgb",
        "document_is_oklab",
        "display_passthrough",
        "to_display_col0",
        "to_display_col1",
        "to_display_col2"
    ]:
        assert_true(declared.has(written), "SaCanvas writes '%s', so the shader must declare it" % written)


## Image > Convert Colour Space rewrites the pixels so the picture keeps looking
## the same. The view has to agree, and it did not.
##
## Godot's 2D pipeline writes canvas colours to the screen with no encode of its
## own, so whatever a document stores went to the screen as though it were
## already sRGB. Converting to Linear sRGB turned a stored 0.5 into 0.214 and put
## that on screen unencoded: the painting went dark, and the operation defined to
## preserve appearance was the one that broke it.
func test_a_linear_document_is_not_displayed_as_though_it_were_encoded() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_true(
        mat.get_shader_parameter("display_passthrough"),
        "An sRGB document is already display ready, and must keep its untouched path"
    )

    canvas.document.color_space = SaColorSpace.linear_srgb()
    canvas.sync_tonemap()
    assert_false(
        mat.get_shader_parameter("display_passthrough"), "A linear document has to be encoded before it reaches the screen"
    )

    canvas.free()


## An Oklab document reaches the screen by the fixed Oklab matrices instead of by
## a curve and a gamut rotation, so it needs both the view transform and the flag
## that says which of the two paths through it to take. Without the flag the view
## reads L, a and b as red, green and blue, which is not a wrong colour but noise.
func test_an_oklab_document_takes_the_perceptual_path() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.document.color_space = SaColorSpace.oklab()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_false(mat.get_shader_parameter("display_passthrough"), "Oklab storage can never take the passthrough")
    assert_true(mat.get_shader_parameter("document_is_oklab"), "and the view is told which decode to run")

    canvas.document.color_space = SaColorSpace.srgb()
    canvas.sync_tonemap()
    assert_false(mat.get_shader_parameter("document_is_oklab"), "while an RGB document keeps the curve and matrix path")

    canvas.free()


## A document that never declared a colour space renders exactly as sRGB, so it
## keeps the untouched path too. Anything else would change how every file
## written before the descriptor existed looks.
func test_an_unspecified_document_still_takes_the_untouched_path() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.document.color_space = SaColorSpace.unspecified()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_true(mat.get_shader_parameter("display_passthrough"), "Unspecified renders as sRGB, which needs nothing done to it")

    canvas.free()


## The gamut half. An sRGB-gamut document gets the exact identity, and a
## wide-gamut one gets a real matrix that still takes its own white to white:
## Bradford adaptation is what makes a D60 document's neutral stay neutral rather
## than turning warm on a D65 screen.
func test_the_display_matrix_is_identity_for_srgb_and_white_preserving_otherwise() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    canvas.sync_tonemap()
    var mat := canvas.material as ShaderMaterial

    assert_eq(mat.get_shader_parameter("to_display_col0"), Vector3(1.0, 0.0, 0.0), "sRGB needs no rotation at all")
    assert_eq(mat.get_shader_parameter("to_display_col1"), Vector3(0.0, 1.0, 0.0), "and exactly none, not almost none")
    assert_eq(mat.get_shader_parameter("to_display_col2"), Vector3(0.0, 0.0, 1.0), "so the common case stays bit-identical")

    canvas.document.color_space = SaColorSpace.acescg()
    canvas.sync_tonemap()
    var columns: Array[Vector3] = [
        mat.get_shader_parameter("to_display_col0"),
        mat.get_shader_parameter("to_display_col1"),
        mat.get_shader_parameter("to_display_col2"),
    ]
    assert_false(columns[0].is_equal_approx(Vector3(1.0, 0.0, 0.0)), "AP1 primaries are not sRGB's, so this is a real matrix")

    # The columns are the images of the basis vectors, so summing them is the
    # image of (1, 1, 1): the document's own white.
    var white: Vector3 = columns[0] + columns[1] + columns[2]
    assert_almost_eq(white.x, 1.0, 0.001, "ACEScg white must land on sRGB white, or every neutral shifts")
    assert_almost_eq(white.y, 1.0, 0.001, "on all three channels")
    assert_almost_eq(white.z, 1.0, 0.001, "which is what the Bradford adaptation is for")

    canvas.free()


## A fresh profile's value for *key*, read from the class rather than written
## down, so the suite follows a default that moves.
static func _fresh(key: StringName) -> Variant:
    var fresh := SaSettingsValues.new()
    var value: Variant = fresh.get(key)
    fresh.free()
    return value
