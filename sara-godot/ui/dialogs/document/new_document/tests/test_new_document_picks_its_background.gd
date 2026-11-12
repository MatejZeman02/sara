## New Document picks the background, its colour and a ground.
##
## The dialog selects a background (colour and optional impasto texture). Every
## new document was grey, and a painter who wanted white, a toned ground or a paper repainted the layer or
## added one by hand. These hold the three rows, the four stacks they make, the
## colour in each kind of space, and the grey every other caller keeps.
##
## The dialog is never added to the tree here: a test that maps a real window
## hangs the run, which is why `test_new_document_rows.gd` says the same.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, and the document allocates chunks.
const REQUIRES_GPU := true

const SIZE := Vector2i(300, 200)
## A toned colour with three different channels, so a swapped or clamped channel
## shows, and none of them at an end a curve leaves alone.
const TONED := Color(0.85, 0.7, 0.5, 1.0)

var _types: SaLayerTypeRegistry = null


func before_each() -> void:
    _types = SaLayerTypeRegistry.new()
    _types.register(SaLayerTypeDescriptor.paper())
    _types.register(SaLayerTypeDescriptor.canvas())


func after_each() -> void:
    _types = null


## A document of *choice* in *space*, which the caller frees.
func _document(choice: Dictionary, space: SaColorSpace = SaColorSpace.srgb()) -> SaDocument:
    var document := SaDocument.new()
    document.setup_default_document(SIZE, SaCompositor.new(), space, SaDocument.DEFAULT_DPI, choice, _types)
    return document


## The stack bottom first, by name.
static func _names(document: SaDocument) -> Array[String]:
    var out: Array[String] = []
    for child: Node in document.get_children():
        if child is SaLayer:
            out.append(String(child.name))
    return out


## The texel at *x*, *y* of a stored *layer*, in the document's own space.
static func _texel_of(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


func _assert_colour(got: Color, want: Color, what: String) -> void:
    assert_almost_eq(got.r, want.r, 2e-3, "%s, red" % what)
    assert_almost_eq(got.g, want.g, 2e-3, "%s, green" % what)
    assert_almost_eq(got.b, want.b, 2e-3, "%s, blue" % what)


## Colour, white and None: today's document apart from the colour, which the
## note asked to choose.
func test_the_dialog_opens_on_a_white_colour_and_no_ground() -> void:
    var dialog := NewDocumentDialog.new(_types)
    var chosen := dialog.selected_background()
    assert_eq(chosen[SaDocumentBackground.KIND], SaDocumentBackground.COLOUR, "The background row opens on Colour")
    assert_eq(chosen[SaDocumentBackground.COLOR], Color.WHITE, "the swatch on white")
    assert_eq(chosen[SaDocumentBackground.GROUND], &"", "and the ground on None")
    assert_eq(dialog.row_option(&"background").text, "Colour", "which the row reads")
    assert_eq(dialog.row_option(&"ground").text, "None", "and so does the ground's")
    dialog.free()


## The Ground row offers every registered ground and nothing else, and its
## tooltip is the chosen ground's own hint.
func test_the_ground_row_offers_the_registered_grounds_with_their_hints() -> void:
    var dialog := NewDocumentDialog.new(_types)
    var option := dialog.row_option(&"ground")
    assert_eq(option.choice_labels(), ["None", "Paper", "Canvas"] as Array[String], "None, then the two grounds")
    assert_true(dialog.select_row(&"ground", "Canvas"), "Canvas is picked")
    assert_eq(dialog.selected_background()[SaDocumentBackground.GROUND], &"canvas", "and the choice carries its id")
    assert_eq(option.tooltip_text, SaLayerTypeDescriptor.canvas().hint, "and the row says what a canvas is")
    dialog.free()

    var bare := NewDocumentDialog.new()
    assert_eq(bare.row_option(&"ground").choice_labels(), ["None"] as Array[String], "With no registry the row offers None")
    bare.free()


## Transparent takes the colour and the ground off the page, and the choice it
## hands on carries no ground even when one was picked before.
func test_transparent_hides_the_colour_and_the_ground() -> void:
    var dialog := NewDocumentDialog.new(_types)
    dialog.select_row(&"ground", "Paper")
    assert_true(dialog.page.row(&"background_colour").line.visible, "The colour row is on the page under Colour")
    assert_true(dialog.select_row(&"background", "Transparent"), "Transparent is picked")
    assert_false(dialog.page.row(&"background_colour").line.visible, "and the colour row leaves")
    assert_false(dialog.page.row(&"ground").line.visible, "with the ground row")
    assert_eq(dialog.selected_background()[SaDocumentBackground.GROUND], &"", "and no ground travels with it")
    dialog.free()


## A colour: the stored Background as before, filled with the chosen colour.
func test_a_colour_fills_the_stored_background() -> void:
    var document := _document({"kind": SaDocumentBackground.COLOUR, "color": TONED, "ground": &""})
    assert_eq(_names(document), ["Background", "Layer 1"] as Array[String], "A background under the paint layer")
    var bottom: SaLayer = document.get_child(0)
    assert_false(bottom.is_generated(), "which stores its pixels")
    _assert_colour(_texel_of(bottom, 290, 190), TONED, "filled with the colour to the far corner")
    _assert_colour(document.background_fill(), TONED, "and a grow of the canvas extends it in the same colour")
    document.free()


## Transparent: no Background, only the layer to paint on.
func test_transparent_lays_no_background() -> void:
    var document := _document({"kind": SaDocumentBackground.TRANSPARENT, "color": TONED, "ground": &"paper"})
    assert_eq(_names(document), ["Layer 1"] as Array[String], "Only the paint layer")
    assert_eq(document.active_layer.name, "Layer 1", "and the brush is on it")
    document.free()


## A ground: the generated layer in the Background's place, its grain standing
## about the chosen colour at its median and its second scaled by the same
## ratio, so the grain keeps its contrast .
func test_paper_and_canvas_lie_at_the_bottom_in_the_chosen_colour() -> void:
    for descriptor: SaLayerTypeDescriptor in [SaLayerTypeDescriptor.paper(), SaLayerTypeDescriptor.canvas()]:
        var document := _document({"kind": SaDocumentBackground.COLOUR, "color": Color.WHITE, "ground": descriptor.id})
        var what := String(descriptor.id)
        assert_eq(_names(document), ["Background", "Layer 1"] as Array[String], "The %s is named Background" % what)
        var bottom: SaLayer = document.get_child(0)
        assert_eq(bottom.layer_type, descriptor.id, "and is a %s" % what)
        assert_true(bottom.is_generated(), "which stores nothing")
        assert_true(bottom.chunks.is_empty(), "and allocates no chunk")
        var light: Color = bottom.generator_params["color"]
        var dark: Color = bottom.generator_params["second"]
        _assert_colour(light.lerp(dark, descriptor.grain_median), Color.WHITE, "The %s is white at its median" % what)
        var first: Color = descriptor.generator_defaults["color"]
        var second: Color = descriptor.generator_defaults["second"]
        assert_almost_eq(
            light.r - dark.r, 1.0 - second.r / first.r, 1e-4, "and its second keeps the default's ratio to the first"
        )
        assert_almost_eq(light.b - dark.b, 1.0 - second.b / first.b, 1e-4, "in every channel")
        document.free()


## The colour the swatch showed is the colour an Oklab and a linear document
## hold, read back through the document's own space.
func test_an_oklab_and_a_linear_document_get_the_colour_the_swatch_showed() -> void:
    for space: SaColorSpace in [SaColorSpace.oklab(), SaColorSpace.linear_srgb()]:
        var document := _document({"kind": SaDocumentBackground.COLOUR, "color": TONED, "ground": &""}, space)
        var held := _texel_of(document.get_child(0) as SaLayer, 10, 10)
        _assert_colour(space.to_display(held), TONED, "A %s background shows the swatch" % space.id)
        document.free()

        var paper := _document({"kind": SaDocumentBackground.COLOUR, "color": TONED, "ground": &"paper"}, space)
        var params := (paper.get_child(0) as SaLayer).generator_params
        var tinted := (params["color"] as Color).lerp(params["second"], SaLayerTypeDescriptor.paper().grain_median)
        _assert_colour(space.to_display(tinted), TONED, "and so does a %s paper at its median" % space.id)
        paper.free()


## Every other caller, the harness, an opened picture and the suites, names no
## background and keeps the grey one.
func test_no_background_still_builds_the_grey_one() -> void:
    var document := SaDocument.new()
    document.setup_default_document(SIZE, SaCompositor.new(), SaColorSpace.oklab())
    assert_eq(_names(document), ["Background", "Layer 1"] as Array[String], "A stored background as before")
    var held := _texel_of(document.get_child(0) as SaLayer, 10, 10)
    _assert_colour(held, document.background_fill(), "filled with the grey")
    _assert_colour(document.color_space.to_display(held), SaDocument.BACKGROUND_GREY, "which shows as mid grey")
    document.free()


## A ground the registry does not know lays the colour rather than nothing.
func test_an_unknown_ground_falls_back_to_the_colour() -> void:
    var document := _document({"kind": SaDocumentBackground.COLOUR, "color": TONED, "ground": &"no_such_ground"})
    var bottom: SaLayer = document.get_child(0)
    assert_false(bottom.is_generated(), "A stored layer stands in")
    _assert_colour(_texel_of(bottom, 10, 10), TONED, "in the chosen colour")
    document.free()
