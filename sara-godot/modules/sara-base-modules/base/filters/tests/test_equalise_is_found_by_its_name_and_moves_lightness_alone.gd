## Equalise is found by its name, and it moves lightness alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer of eight saturated colours, one flat chunk each, at eight hues and
## eight lightnesses, in a float document so a texel keeps what the kernel
## wrote. Levels opens over a record on the layer in the edit window with the
## channel row on Master, and the press is the panel's own `equalize`, which
## counts the layer through the door. The values it leaves run through the
## `levels` kernel over the layer, and every texel is read back: each chunk is
## one colour still, and that colour's Oklab chroma and hue are what were
## painted while its lightness is spread from black to white. The door half
## registers the base module the way the loader does, searches the browser for
## "equal", and opens the row it lists.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

## The colours as Oklab lightness, chroma and hue in degrees, darkest first,
## every one inside sRGB and far from grey.
const PAINTED: Array[Vector3] = [
    Vector3(0.45, 0.12, 30.0),
    Vector3(0.50, 0.14, 75.0),
    Vector3(0.55, 0.11, 140.0),
    Vector3(0.58, 0.12, 250.0),
    Vector3(0.60, 0.12, 180.0),
    Vector3(0.62, 0.10, 280.0),
    Vector3(0.70, 0.12, 330.0),
    Vector3(0.72, 0.13, 10.0),
]

## How far a float texel's Oklab may move through the kernel's round trip
## and back through this suite's, which is float rounding and nothing else.
const ROUND_TRIP := 1e-4

## How far a level may land from its share: the map is read between two of its
## 256 entries, and both are the share whatever side of a bin a level is on.
const SHARE := 1e-3

var _easel: SaEasel = null
var _document: SaDocument = null
var _space: SaColorSpace = null


func before_each() -> void:
    _space = SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32)
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * PAINTED.size(), SaChunk.SIZE), null, _space)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _document = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _document = null
    _space = null


## *painted*, a row of `PAINTED`, as the document stores it.
func _stored(painted: Vector3) -> Color:
    var lab := SaOklab.from_polar(Vector3(painted.x, painted.y, deg_to_rad(painted.z)))
    var light := _space.from_linear_srgb_matrix() * SaOklab.to_linear_srgb(lab)
    var curve := _space.transfer
    return Color(curve.encode(light.x), curve.encode(light.y), curve.encode(light.z), 1.0)


## *texel* as Oklab lightness, chroma and hue in radians.
func _lch(texel: Color) -> Vector3:
    var curve := _space.transfer
    var light := Vector3(curve.decode(texel.r), curve.decode(texel.g), curve.decode(texel.b))
    return SaOklab.to_polar(SaOklab.from_linear_srgb(_space.to_linear_srgb_matrix() * light))


func _paint() -> SaLayer:
    var background := _document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in background.chunks.keys():
        background.chunks.erase(grid_pos)
    var layer := _document.get_node("Layer 1") as SaLayer
    for index in PAINTED.size():
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(_stored(PAINTED[index]))
    _document.set_active_layer(layer)
    return layer


## The one colour chunk *index* of *layer* holds, after checking that every
## texel of it is that colour, which is a byte compare against a chunk filled
## with it rather than a read of each texel.
func _flat(layer: SaLayer, index: int) -> Color:
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(Vector2i(index, 0)))
    var texel := image.get_pixel(0, 0)
    var filled := Image.create_empty(image.get_width(), image.get_height(), false, image.get_format())
    filled.fill(texel)
    assert_eq(image.get_data(), filled.get_data(), "Every texel of chunk %d is one colour" % index)
    return texel


## Levels attached to *layer*, opened in the edit window on Master and pressed,
## and the values the press left.
func _press_on_master(layer: SaLayer) -> Dictionary:
    var registry := SaFilterRegistry.new()
    var levels := SaLevelsFilter.new()
    registry.register(levels, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, levels)
    _easel.compositor.filter_chain.registry = registry
    var record := SaFilterOps.new(_document).attach(layer, key, levels.parameters())
    var window := SaFilterEditWindow.new()
    window.watch(registry)
    window.open(record, _document)
    var panel := window.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "The edit window shows the Levels panel")
    if panel == null:
        window.free()
        return {}
    panel.set_values({"channel": "master"})
    assert_true(panel.equalize(), "Equalize takes a map with the channel row on Master")
    var values := panel.values()
    window.free()
    return values


func test_equalize_on_master_moves_lightness_alone_and_spreads_it() -> void:
    var layer := _paint()
    var values := _press_on_master(layer)
    if values.is_empty():
        return
    assert_eq(values["channel"], "master", "The handles are on Master")
    assert_eq(values["equalize_channel"], "lightness", "and the map is counted on Oklab L")
    var filter := SaLevelsFilter.new()
    filter.set_parameters(values)
    var ran := SaPointAdjust.new().apply(_document, layer, SaPointAdjust.LEVELS, filter.values(), "Levels")
    assert_true(ran, "The levels pass runs")

    var last := PAINTED.size() - 1
    for index in PAINTED.size():
        var painted := PAINTED[index]
        var now := _lch(_flat(layer, index))
        assert_almost_eq(now.y, painted.y, ROUND_TRIP, "Chunk %d keeps its chroma, %.5f" % [index, now.y])
        var turned := angle_difference(deg_to_rad(painted.z), now.z)
        assert_almost_eq(turned, 0.0, ROUND_TRIP, "and its hue, turned %.6f" % turned)
        var share := float(index) / float(last)
        assert_almost_eq(now.x, share, SHARE, "and its lightness goes to its share, %.4f" % share)
    var darkest := _lch(_flat(layer, 0)).x
    var brightest := _lch(_flat(layer, last)).x
    assert_true(darkest < 0.01 and brightest > 0.99, "The lightness spans black to white, %.3f to %.3f" % [darkest, brightest])


## The base module registered the way the loader does it, with the app's
## commands, which is what the Filter menu and the browser list.
func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    return registries


func test_the_browsers_search_for_equal_lists_a_row_that_opens_levels_with_equalize() -> void:
    var registries := _registries()
    var key := StringName("%s.equalize" % OWNER)
    var levels_key := StringName("%s.%s" % [OWNER, SaPointAdjust.LEVELS])
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    docker.browser.search_for("equal")
    var listed: Array = docker.describe()["listed"]
    assert_true(listed.has(String(key)), "Searching for equal lists Equalize, %s" % [listed])
    assert_true(listed.has(String(levels_key)), "and Levels, whose sentence names it")
    docker.free()

    var entry := registries.filters.get_filter(key)
    assert_true(entry != null, "The row is a filter of the registry")
    if entry == null:
        return
    assert_eq(registries.filters.section_of(key), &"tone", "under Tone, beside Levels")
    var dialog := SaDialog.for_filter(entry)
    var page := VBoxContainer.new()
    dialog.realize(page)
    assert_eq(dialog.dialog_title, "Levels", "Opening it shows Levels")
    var panel := page.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "with the Levels panel")
    if panel != null:
        var button := panel.find_child("EqualizeButton", true, false) as Button
        assert_true(button != null and button.visible, "and its Equalize button in view")
        assert_true(panel.ready.is_connected(panel.equalize), "which it presses as the page shows")
    page.free()

    var filed := entry.filed_as(key)
    assert_eq(filed.key, levels_key, "A record of it is a Levels record")
    assert_eq(filed.parameters["equalize_channel"], "", "holding no map before the press")
