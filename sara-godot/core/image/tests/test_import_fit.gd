## Where a picture that is not the canvas's size ends up.
##
## A paste and a drop are imports, and the three fits are the only thing the
## painter is asked. Each one is read back off the layer here rather than
## trusted: the picture is a solid colour, so a texel says whether it reached
## a place and an alpha of zero says it did not.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)

## The middle of it, written out rather than divided, because a constant is not
## a place to spend a warning annotation.
const MIDDLE := Vector2i(256, 128)


func _document() -> SaEasel:
    return SaEasel.create_default(CANVAS)


## A solid opaque red picture of *size*, so every texel of it is recognisable
## and everything the layer has not been given is a transparent zero.
func _picture(size: Vector2i) -> Image:
    var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    return image


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


func _place(easel: SaEasel, size: Vector2i, fit: SaImageImport.Fit) -> SaLayer:
    return SaImageImport.place(easel.document, _picture(size), "Fitted", SaColorSpace.srgb(), fit)


## Stretch fills the canvas, corner to corner, whatever shape it arrived in.
func test_stretch_covers_the_whole_canvas() -> void:
    var easel := _document()
    var layer := _place(easel, Vector2i(100, 100), SaImageImport.Fit.STRETCH)
    assert_not_null(layer, "The picture lands")
    for corner: Vector2i in [Vector2i(0, 0), Vector2i(CANVAS.x - 1, 0), Vector2i(0, CANVAS.y - 1), CANVAS - Vector2i.ONE]:
        assert_almost_eq(_texel(layer, corner.x, corner.y).a, 1.0, 1e-3, "The picture reaches %s" % corner)
    easel.free()


## Actual size keeps the picture's own pixels and centres it, so the margin
## either side is what the canvas has spare.
func test_actual_size_is_centred_and_keeps_its_pixels() -> void:
    var easel := _document()
    var picture := Vector2i(200, 100)
    var layer := _place(easel, picture, SaImageImport.Fit.ACTUAL)
    @warning_ignore("integer_division")
    var at := (CANVAS - picture) / 2
    assert_eq(at, Vector2i(156, 78), "The top left is half the difference")

    assert_almost_eq(_texel(layer, at.x + 1, at.y + 1).a, 1.0, 1e-3, "Its first pixel is inside the picture")
    assert_almost_eq(_texel(layer, at.x - 2, at.y + 1).a, 0.0, 1e-3, "and the column left of it is empty")
    assert_almost_eq(_texel(layer, at.x + picture.x + 1, at.y + 1).a, 0.0, 1e-3, "as is the one past its right edge")
    assert_almost_eq(_texel(layer, MIDDLE.x, MIDDLE.y).a, 1.0, 1e-3, "and the centre of the canvas is covered")
    easel.free()


## Fit inside scales until one axis is full and leaves a margin on the other,
## which is the difference between it and Stretch on a picture of another shape.
func test_fit_inside_fills_one_axis_and_letterboxes_the_other() -> void:
    var easel := _document()
    # Square on a 2:1 canvas, so the height decides: 256 by 256, centred.
    var layer := _place(easel, Vector2i(100, 100), SaImageImport.Fit.INSIDE)
    assert_almost_eq(_texel(layer, MIDDLE.x, 1).a, 1.0, 1e-3, "The top edge is reached, because height decided")
    assert_almost_eq(_texel(layer, MIDDLE.x, CANVAS.y - 2).a, 1.0, 1e-3, "and so is the bottom")
    assert_almost_eq(_texel(layer, 1, MIDDLE.y).a, 0.0, 1e-3, "The left margin is empty")
    assert_almost_eq(_texel(layer, CANVAS.x - 2, MIDDLE.y).a, 0.0, 1e-3, "and so is the right")
    easel.free()


## A picture larger than the canvas keeps what hangs over the edge, which is
## the promise and the reason Actual size is offered at all.
func test_actual_size_keeps_the_overhang() -> void:
    var easel := _document()
    var picture := Vector2i(1024, 512)
    var layer := _place(easel, picture, SaImageImport.Fit.ACTUAL)
    @warning_ignore("integer_division")
    var at := (CANVAS - picture) / 2
    assert_eq(at, Vector2i(-256, -128), "The top left is off the canvas")
    assert_true(layer.chunks.has(Vector2i(-1, -1)), "so the picture owns a chunk left of and above the canvas")
    assert_almost_eq(_texel(layer, 0, 0).a, 1.0, 1e-3, "and the canvas is covered from its own origin")
    assert_eq(easel.document.canvas_size, CANVAS, "without the canvas growing")
    easel.free()


## The fit maths on its own, which is what decides the placement above.
func test_the_fit_resizes_only_where_it_should() -> void:
    var stretched := _picture(Vector2i(100, 100))
    assert_eq(
        SaImageImport.fit_image(stretched, CANVAS, SaImageImport.Fit.STRETCH), Vector2i.ZERO, "Stretch starts at the origin"
    )
    assert_eq(stretched.get_size(), CANVAS, "and is the canvas")

    var actual := _picture(Vector2i(100, 100))
    assert_eq(SaImageImport.fit_image(actual, CANVAS, SaImageImport.Fit.ACTUAL), Vector2i(206, 78), "Actual size is centred")
    assert_eq(actual.get_size(), Vector2i(100, 100), "and is not resized")

    var inside := _picture(Vector2i(100, 100))
    assert_eq(SaImageImport.fit_image(inside, CANVAS, SaImageImport.Fit.INSIDE), Vector2i(128, 0), "Fit inside is centred")
    assert_eq(inside.get_size(), Vector2i(256, 256), "and scaled until the smaller axis is full")

    var origin := _picture(Vector2i(100, 100))
    assert_eq(SaImageImport.fit_image(origin, CANVAS, SaImageImport.Fit.ORIGIN), Vector2i.ZERO, "The default is the top left")
    assert_eq(origin.get_size(), Vector2i(100, 100), "and touches nothing")


## The shape test the capture still reads. The choice the dialog opens on no
## longer follows it: `preselected_fit` follows the sizes.
func test_the_preselected_choice_is_the_one_that_loses_nothing() -> void:
    assert_true(SaImportFitDialog.same_ratio(Vector2i(1600, 900), Vector2i(1920, 1080)), "16:9 against 16:9")
    assert_false(SaImportFitDialog.same_ratio(Vector2i(300, 200), Vector2i(1920, 1080)), "3:2 against 16:9")
    assert_false(SaImportFitDialog.same_ratio(Vector2i(300, 0), Vector2i(1920, 1080)), "and nothing has no shape")


## The setting the "Do not ask again" box writes, and what the Workspace row
## sets it back to.
func test_the_remembered_choice_is_a_setting_that_survives_a_bad_value() -> void:
    var was := SaSettings.import_fit
    assert_eq(SaImportFitDialog.fit_from_setting("stretch"), SaImageImport.Fit.STRETCH, "Each word names a fit")
    assert_eq(SaImportFitDialog.fit_from_setting("actual"), SaImageImport.Fit.ACTUAL, "including the centred one")
    assert_eq(SaImportFitDialog.fit_from_setting("inside"), SaImageImport.Fit.INSIDE, "and the scaled one")
    assert_eq(SaImportFitDialog.fit_from_setting("ask"), SaImageImport.Fit.ORIGIN, "and asking is not a fit")

    SaSettings.import_fit = "inside"
    assert_eq(SaSettings.import_fit, "inside", "The choice is kept")
    SaSettings.import_fit = "sideways"
    assert_eq(SaSettings.import_fit, "ask", "and a word nothing knows falls back to asking")
    SaSettings.import_fit = was


## A host outside the tree cannot show a window, and a headless test is one.
## It places rather than hanging, which is what makes the path testable at all.
func test_a_detached_host_places_without_asking() -> void:
    var was := SaSettings.import_fit
    SaSettings.import_fit = "ask"
    var easel := _document()
    var placed: Array[SaLayer] = []
    SaImportFitDialog.place(
        null,
        easel.document,
        _picture(Vector2i(100, 100)),
        "Detached",
        SaColorSpace.srgb(),
        func(layer: SaLayer) -> void: placed.append(layer)
    )
    assert_eq(placed.size(), 1, "The picture went down anyway")
    assert_eq(str(placed[0].name), "Detached", "under the name it was given")
    assert_almost_eq(_texel(placed[0], 1, 1).a, 1.0, 1e-3, "at the top left, which is where no answer puts it")
    SaSettings.import_fit = was
    easel.free()


## A remembered choice is not asked about, which is the whole of "Do not ask
## again": the same call that would have opened the dialog places instead.
func test_a_remembered_choice_places_without_asking() -> void:
    var was := SaSettings.import_fit
    SaSettings.import_fit = "stretch"
    var easel := _document()
    var placed: Array[SaLayer] = []
    SaImportFitDialog.place(
        null,
        easel.document,
        _picture(Vector2i(100, 100)),
        "Remembered",
        SaColorSpace.srgb(),
        func(layer: SaLayer) -> void: placed.append(layer)
    )
    assert_eq(placed.size(), 1, "The picture went down")
    assert_almost_eq(_texel(placed[0], CANVAS.x - 2, CANVAS.y - 2).a, 1.0, 1e-3, "stretched to the canvas, as remembered")
    SaSettings.import_fit = was
    easel.free()


## Paste reaches for Sara's own clipboard first and the desktop's second, so a
## Copy inside Sara is never overruled by whatever a browser left lying about.
func test_paste_prefers_saras_own_clipboard() -> void:
    var easel := _document()
    var document := easel.document
    var painted := SaLayerOps.new(document).add()
    painted.fill(Color(0.0, 1.0, 0.0, 1.0))
    document.set_active_layer(painted)
    assert_true(SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard.copy(document, painted) > 0, "Copy took something")

    var bar := TopMenuBar.new()
    bar._ready()

    var before := document.get_child_count()
    SaShortcutCommands.paste(document, bar)
    assert_eq(document.get_child_count(), before + 1, "The paste added a layer")
    assert_almost_eq(_texel(document.active_layer, 4, 4).g, 1.0, 1e-3, "and it is what Copy took, not a picture")
    bar.free()
    easel.free()


## The dialog's own list: every RGB preset, nothing that is not RGB, and
## the caller's guess preselected rather than the first row.
func test_the_input_space_row_offers_the_rgb_presets() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(300, 200), CANVAS, SaColorSpace.linear_srgb())
    assert_eq(dialog.chosen_space().id, SaColorSpace.ID_LINEAR_SRGB, "An EXR opens the row on linear sRGB")
    assert_true(dialog.select_space(SaColorSpace.ID_DISPLAY_P3), "Display P3 is one of the rows")
    assert_eq(dialog.chosen_space().id, SaColorSpace.ID_DISPLAY_P3, "and picking it is what the row then says")
    assert_false(dialog.select_space(SaColorSpace.ID_OKLAB), "Oklab is not, because no PNG, JPEG or EXR is ever written in it")
    dialog.free()


## the half that matters. The space the dropdown lands on is what the
## picture is converted *from*, so the same red arrives as two different reds.
##
## Read as sRGB into an sRGB document it is converted by nothing and stays
## exactly as it was written. Read as Display P3 it is a wider red than sRGB
## can hold, so it lands outside the cube: above one on red and below zero on
## green, which the float chunks keep (hard rule 5) and an integer format
## would have flattened into the same colour as the first.
func test_the_chosen_space_is_what_the_picture_is_converted_from() -> void:
    var easel := _document()
    var as_srgb := SaImageImport.place(
        easel.document, _picture(Vector2i(300, 200)), "As sRGB", SaColorSpace.srgb(), SaImageImport.Fit.STRETCH
    )
    var srgb_texel := _texel(as_srgb, MIDDLE.x, MIDDLE.y)
    assert_almost_eq(srgb_texel.r, 1.0, 1e-3, "An sRGB red into an sRGB document is converted by nothing")
    assert_almost_eq(srgb_texel.g, 0.0, 1e-3, "on every channel")

    var as_p3 := SaImageImport.place(
        easel.document, _picture(Vector2i(300, 200)), "As P3", SaColorSpace.display_p3(), SaImageImport.Fit.STRETCH
    )
    var p3_texel := _texel(as_p3, MIDDLE.x, MIDDLE.y)
    assert_true(p3_texel.r > 1.05, "The same bytes read as Display P3 are a red sRGB cannot reach")
    assert_true(p3_texel.g < -0.05, "and it lands outside the cube rather than clamped onto its face")
    easel.free()
