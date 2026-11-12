## While a mask is the paint target the pair is grey, and the
## colours come back after.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter on 2026-10-16: "the colour picker should turn gray-scale, because
## colours don't play role when painting a mask. I woul like to keep the
## original fore/back/ground colours, so they restore when user escapes the mask
## painting." The store follows a real document, and the mask is made by
## `SaMaskOps` as the Layer menu makes it. Escape is read here through the call
## the shortcut router makes, and with a real key press in
## `ui/shortcuts/tests/test_escape_leaves_a_mask_and_gives_the_colour_pair_back.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

static var scratch_path: String = SaDataRoot.path("test_colors.cfg")

## The grey a brush paints into a mask for each: its lightness in an sRGB
## document's own numbers, the luminance row of its matrix.
const RED_GREY := 0.2126
const BLUE_GREY := 0.0722
const TOLERANCE := 1.0e-3

var _kept_foreground: Color


func before_each() -> void:
    _kept_foreground = SaColors.foreground


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


## A document whose first layer has a mask, and a store holding red over blue
## that follows the document.
func _bench(space: SaColorSpace = null) -> Dictionary:
    var host := Node.new()
    host.name = "U161TestHost"
    EventBus.add_child(host)
    var easel := SaEasel.create_default(Vector2i(64, 64), null, space)
    host.add_child(easel)
    var document := easel.document
    var layer := document.active_layer
    assert_true(SaMaskOps.new(document).run(SaMaskOps.ADD, layer), "the layer takes a mask")
    var store := SaColorStore.new()
    store.path = scratch_path
    host.add_child(store)
    store.foreground = Color.RED
    store.background = Color.BLUE
    store.follow(document)
    return {"host": host, "document": document, "layer": layer, "store": store}


func _teardown(bench: Dictionary) -> void:
    (bench["host"] as Node).free()


func _assert_grey(color: Color, grey: float, what: String) -> void:
    assert_almost_eq(color.r, grey, TOLERANCE, what + ", red")
    assert_almost_eq(color.g, grey, TOLERANCE, what + ", green")
    assert_almost_eq(color.b, grey, TOLERANCE, what + ", blue")


func _assert_red_over_blue(store: SaColorStore, what: String) -> void:
    assert_false(store.masking, what + ": the store is no longer grey")
    assert_eq(store.foreground, Color.RED, what + ": red is the foreground again")
    assert_eq(store.background, Color.BLUE, what + ": over blue again")


## The pair turns into two greys while the mask is the target, a lighter grey
## picked meanwhile is painted, and clearing the target gives red and blue back,
## the grey picked meanwhile forgotten.
func test_a_mask_as_the_target_greys_the_pair_and_clearing_it_gives_it_back() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    var document := bench["document"] as SaDocument
    var layer := bench["layer"] as SaLayer
    document.mask_target = layer.mask
    assert_true(store.masking, "a mask as the target greys the store")
    _assert_grey(store.foreground, RED_GREY, "red reads as the grey of its lightness")
    _assert_grey(store.background, BLUE_GREY, "blue reads as the grey of its lightness")
    store.foreground = Color(0.8, 0.8, 0.8)
    _assert_grey(store.foreground, 0.8, "a lighter grey picked meanwhile is the foreground")
    document.mask_target = null
    _assert_red_over_blue(store, "the target cleared")
    _teardown(bench)


## Deleting the mask clears the target, which gives the pair back too.
func test_deleting_the_mask_gives_the_pair_back() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    var document := bench["document"] as SaDocument
    var layer := bench["layer"] as SaLayer
    document.mask_target = layer.mask
    store.foreground = Color(0.7, 0.7, 0.7)
    assert_true(SaMaskOps.new(document).run(SaMaskOps.DELETE, layer), "the mask is deleted")
    assert_null(document.mask_target, "deleting it clears the target")
    _assert_red_over_blue(store, "the mask deleted")
    _teardown(bench)


## What Escape does first, `SaColorStore.leave_mask`, the router's call on `SaColors`,, clears the target, which
## gives the pair back, and says it had something to leave only once.
func test_escape_s_call_leaves_the_mask_and_gives_the_pair_back() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    var document := bench["document"] as SaDocument
    document.mask_target = (bench["layer"] as SaLayer).mask
    store.foreground = Color(0.6, 0.6, 0.6)
    assert_true(store.leave_mask(), "Escape's call had a mask to leave")
    assert_null(document.mask_target, "and cleared the target")
    _assert_red_over_blue(store, "after Escape's call")
    assert_false(store.leave_mask(), "with no mask as the target it leaves the key to the rest of Escape")
    _teardown(bench)


## A document freed with its mask still the target gives the pair back, so a
## closed canvas never leaves the pickers grey.
func test_a_document_that_goes_away_gives_the_pair_back() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    (bench["document"] as SaDocument).mask_target = (bench["layer"] as SaLayer).mask
    var easel := (bench["document"] as SaDocument).get_parent()
    easel.get_parent().remove_child(easel)
    easel.free()
    await (Engine.get_main_loop() as SceneTree).process_frame
    _assert_red_over_blue(store, "the document gone")
    _teardown(bench)


## A saturated colour picked while the mask is the target lands as the grey a
## brush would paint, whether it comes through the store or over the bus as the
## eyedropper sends it. A tool that heard the colour on the bus paints the same
## grey, because the brush takes a mask's colour as its lightness at dab time.
func test_a_saturated_pick_lands_as_a_grey() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    var document := bench["document"] as SaDocument
    document.mask_target = (bench["layer"] as SaLayer).mask
    store.foreground = Color.GREEN
    _assert_grey(store.foreground, 0.7152, "green set on the store lands as its grey")
    EventBus.color_picked.emit(Color.BLUE)
    _assert_grey(store.foreground, BLUE_GREY, "blue picked on the bus lands as its grey")
    var blue_cover := document.color_space.lightness(Color.BLUE)
    assert_almost_eq(blue_cover, store.foreground.r, TOLERANCE, "which is the lightness a brush paints blue as")
    store.background = Color.RED
    _assert_grey(store.background, RED_GREY, "a background set meanwhile is a grey too")
    document.mask_target = null
    _assert_red_over_blue(store, "the target cleared after the picks")
    _teardown(bench)


## In an Oklab document, which is what the app opens, the grey a pick lands as
## paints into the mask what a brush holding the colour paints, the lightness
## of the colour turned into the document's numbers, and the grey turned grey
## again stays as it is.
func test_in_an_oklab_document_the_grey_paints_what_the_colour_would() -> void:
    var bench := _bench(SaColorSpace.oklab())
    var store := bench["store"] as SaColorStore
    var document := bench["document"] as SaDocument
    var space := document.color_space
    document.mask_target = (bench["layer"] as SaLayer).mask
    var red_cover := clampf(space.lightness(space.from_display(Color.RED)), 0.0, 1.0)
    var grey := store.foreground
    assert_almost_eq(grey.r, grey.b, TOLERANCE, "red lands as a neutral")
    var grey_cover := space.lightness(space.from_display(grey))
    assert_almost_eq(grey_cover, red_cover, TOLERANCE, "whose coverage is the one a brush holding red paints")
    store.foreground = grey
    assert_almost_eq(store.foreground.r, grey.r, TOLERANCE, "and a pick of the grey stays that grey")
    document.mask_target = null
    _assert_red_over_blue(store, "the target cleared in Oklab")
    _teardown(bench)


## A session saved while the mask is the target keeps the colours, not the greys.
func test_a_save_while_masking_keeps_the_colours() -> void:
    var bench := _bench()
    var store := bench["store"] as SaColorStore
    (bench["document"] as SaDocument).mask_target = (bench["layer"] as SaLayer).mask
    store.save()
    var config := ConfigFile.new()
    assert_eq(config.load(scratch_path), OK, "the file was written")
    assert_eq(config.get_value("pair", "foreground"), Color.RED, "red is saved")
    assert_eq(config.get_value("pair", "background"), Color.BLUE, "blue is saved")
    _teardown(bench)
