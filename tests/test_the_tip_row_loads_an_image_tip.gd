## The noise brush's Tip row loads an image tip.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Tip row offers Image beside the door's three generators, with a Tip
## Image grid and a Load Tip action under it. The action loads through the
## tool's `load_tip`, the door's `SaBrushTipMask.select` the stamp calls, and
## the grid is the door's `Kind.TIP_IMAGE`, listed by `SaTipChoices`, whose
## press writes the tip's path. A preset saved with a picture loads with it,
## and a tap through the L of `tips/corner.png` paints the L and nothing of the
## square around it, read back texel by texel.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const TipRowScript = preload("res://modules/sara-noise-brush-engine/tip/tip_row.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## A shipped tip, and a picture from outside the two tip folders.
const TREE := "res://tips/tree.png"
const CORNER := "res://tips/corner.png"
const OUTSIDE := "res://ui/icon-bw.png"
const MISSING := "res://tips/no-such-tip.png"

## The tap's centre and the tip's radius, on a canvas whose smaller side is 256.
const CENTRE := Vector2(128.0, 128.0)
const RADIUS := 40.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _dir: String = SaDataRoot.path("test_s5_the_image_tip")
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_drift = 0.0
    _brush.settings.thickness = 0.0
    _images.clear()
    SaBrushTipMask.forget_loaded_elsewhere()
    DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
    _brush = null
    _images.clear()
    SaBrushTipMask.forget_loaded_elsewhere()
    Fixtures.teardown(_surface)
    _surface = null
    if not DirAccess.dir_exists_absolute(_dir):
        return
    for file_name: String in DirAccess.get_files_at(_dir):
        DirAccess.remove_absolute(_dir.path_join(file_name))
    DirAccess.remove_absolute(_dir)


## The Tip row offers Image after the door's three generators, and the Tip
## Image grid and the Load Tip action follow it, shown only while Image is
## chosen and each reaching the tool.
func test_the_tip_row_offers_image_with_its_grid_and_its_action_under_it() -> void:
    var specs: Dictionary = {}
    for spec: SaOptionSpec in NoiseModuleScript.options():
        specs[spec.key] = spec
    var tip: SaOptionSpec = specs[&"tip_generator"]
    var labels: Array = tip.choices.map(func(choice: Dictionary) -> String: return String(choice["label"]))
    assert_eq(labels, ["Default", "Gaussian", "Soft Curve", "Image"], "The Tip row offers Image after the three generators")
    assert_eq(tip.choices[3]["id"], SaDabGeometry.Generator.IMAGE, "whose id is the generator the kernel paints a picture with")
    var listed: SaOptionSpec = specs[TipRowScript.LIST_KEY]
    assert_eq(listed.label, "Tip image", "The Tip image row")
    assert_eq(listed.kind, SaOptionSpec.Kind.TIP_IMAGE, "as the door's grid of the tips' pictures")
    assert_true(not listed.on_tool and listed.property == ^"tip:image_path", "writing the tip's path")
    var load_tip: SaOptionSpec = specs[&"tip_load"]
    assert_eq(load_tip.kind, SaOptionSpec.Kind.ACTION, "and the Load Tip action under the stamp's key")
    assert_true(load_tip.on_tool and _brush.has_method(String(load_tip.property)), "calling a method the tool has")
    for spec: SaOptionSpec in [listed, load_tip]:
        assert_eq(spec.page, NoiseModuleScript.PAGE, "%s is on the page Tip is on" % spec.label)
        var read_image := func(_key: StringName) -> Variant: return SaDabGeometry.Generator.IMAGE
        var read_gauss := func(_key: StringName) -> Variant: return SaDabGeometry.Generator.GAUSS
        assert_true(spec.shown_under(read_image), "%s is shown under Image" % spec.label)
        assert_false(spec.shown_under(read_gauss), "and hidden under a generator")


## A picture from the tip folders loads onto the tip and selects it, the tool
## says so, a file that is not there is refused with the tip left as it was,
## and an empty path puts the tip back on its generator.
func test_load_tip_selects_a_picture_and_refuses_a_missing_one() -> void:
    var heard: Array[String] = []
    _brush.tip_loaded.connect(func(path: String) -> void: heard.append(path))
    assert_true(_brush.load_tip(TREE), "A shipped tip loads")
    assert_eq(_brush.settings.tip.image_path, TREE, "onto the settings' tip")
    assert_eq(_brush.settings.tip.generator, SaDabGeometry.Generator.IMAGE, "which paints the picture")
    assert_eq(_brush.tip_mask.path, TREE, "and the tool holds its mask")
    assert_true(_brush.tip_mask.has_image(), "with the picture on the card")
    assert_eq(heard, [TREE] as Array[String], "and the tool says so")
    assert_false(_brush.load_tip(MISSING), "A file that is not there is refused")
    assert_eq(_brush.settings.tip.image_path, TREE, "and the tip keeps its picture")
    assert_eq(heard.size(), 1, "with nothing said")
    assert_true(_brush.load_tip(""), "An empty path loads")
    assert_eq(_brush.settings.tip.image_path, "", "and leaves no picture")
    assert_eq(_brush.settings.tip.effective_generator(), SaDabGeometry.Generator.DEFAULT, "so the tip paints its generator")


## A noise preset saved with an image tip loads with the same tip path, read
## back by the store and copied onto a brush's settings the way a painter's
## pick copies it.
func test_a_preset_saved_with_an_image_tip_loads_with_it() -> void:
    assert_true(_brush.load_tip(CORNER), "A tip loads")
    var store := SaPresetStore.new()
    store.dir = _dir
    assert_eq(store.save_preset("Corner Grain", _brush.settings), "Corner Grain", "The preset saves")
    var loaded := store.load_preset("Corner Grain") as NoiseBrushSettingsScript
    assert_not_null(loaded, "and loads")
    assert_eq(loaded.tip.image_path, CORNER, "with the same tip path")
    assert_eq(loaded.tip.generator, SaDabGeometry.Generator.IMAGE, "on the generator that paints it")
    assert_eq(loaded.tip.kind, SaBrushTipScript.Kind.IMAGE, "and the tip's record of it")
    var other := StateNoiseBrushScript.new()
    assert_eq(other.settings.tip.image_path, "", "A brush of its own holds no picture")
    assert_true(store.apply_preset("Corner Grain", other.settings), "until the preset is applied to it")
    assert_eq(other.settings.tip.image_path, CORNER, "and then it holds the same one")
    assert_eq(other.settings.tip.generator, SaDabGeometry.Generator.IMAGE, "on the same generator")


## The list is the door's: every file in the tip folders, each under its
## folder, and a picture loaded from anywhere joins it under its own and stays
## for the run. A press on the grid writes the path, and the next stroke binds
## the picture it names.
func test_the_list_follows_a_load_and_a_written_path_is_the_tip_painted() -> void:
    var spec: SaOptionSpec = null
    for candidate: SaOptionSpec in NoiseModuleScript.options():
        if candidate.key == TipRowScript.LIST_KEY:
            spec = candidate
    var before := _paths(SaTipChoices.listing(_brush.settings.tip.image_path))
    assert_true(before.has(TREE), "The list carries the shipped tips")
    assert_false(before.has(OUTSIDE), "and not a picture from outside the folders")

    assert_true(_brush.load_tip(OUTSIDE), "A picture from outside the folders loads")
    var listed := SaTipChoices.listing(_brush.settings.tip.image_path)
    assert_true(_paths(listed).has(OUTSIDE), "and joins the list")
    assert_eq(String(listed.back()["folder"]), OUTSIDE.get_base_dir(), "under its folder")
    var rows := SaTipChoices.folders(listed).map(func(row: Dictionary) -> String: return String(row["label"]))
    assert_eq(rows.front(), "All", "The filter starts on All")
    assert_true(rows.has("Sara"), "names Sara's own folder")
    assert_eq(rows.back(), "ui", "and the picture's folder last, by its name")

    _brush.settings.set_indexed(spec.property, TREE)
    assert_true(_paths(SaTipChoices.listing(_brush.settings.tip.image_path)).has(OUTSIDE), "It stays once the brush moves off it")
    _tap(1.0)
    assert_eq(_brush.tip_mask.path, TREE, "and a stroke after the write paints the picture written")


## A tap through the L of `tips/corner.png` paints the L and nothing of the
## square it sits in. With the cut letting everything through, the arms take
## the picture's full coverage, and through a noisy field no texel off the L
## takes paint, so the picture's outline bounds the texture.
func test_a_tap_through_a_picture_paints_its_outline_and_nothing_around_it() -> void:
    assert_true(_brush.load_tip(CORNER), "The L loads")
    _brush.settings.grain_contrast = 0.0
    _brush.settings.strength = -0.5
    _tap(1.0)
    var arms := _mean_alpha([Rect2(0.2, 0.2, 0.06, 0.4), Rect2(0.3, 0.78, 0.45, 0.1)])
    assert_true(arms > 0.9, "Through a cut that lets all of it through, the L's arms take paint, %.3f on average" % arms)
    var empty := [Rect2(0.45, 0.1, 0.4, 0.5), Rect2(0.0, 0.0, 1.0, 0.08), Rect2(0.92, 0.0, 0.08, 1.0)]
    assert_eq(_mean_alpha(empty), 0.0, "and the square around the L takes none")

    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.settings.grain_scale = 3.0
    _brush.settings.grain_contrast = 2.5
    _brush.settings.strength = 0.0
    _tap(0.5)
    assert_eq(_mean_alpha(empty), 0.0, "Through a noisy field the square around the L still takes none")
    var inside := _mean_alpha([Rect2(0.2, 0.2, 0.06, 0.4), Rect2(0.3, 0.78, 0.45, 0.1)])
    assert_true(inside > 0.05 and inside < arms, "while the L takes the field's share of its paint, %.3f" % inside)


## A stroke through the L ends on the L's bar whole. The bar's last stretch
## before the end is covered by the last point alone, and the kernel's centres
## found in closed form, which fall with a norm a picture does not have, missed
## it across the middle of the bar until the segment's ends were read as well.
func test_a_stroke_through_a_picture_ends_on_its_whole_bar() -> void:
    assert_true(_brush.load_tip(CORNER), "The L loads")
    _brush.settings.grain_contrast = 0.0
    _brush.settings.strength = -0.5
    _images.clear()
    _brush.begin_stroke(CENTRE - Vector2(80.0, 0.0), 1.0, Vector2.ZERO, 0.0)
    for step in range(1, 17):
        _brush.add_sample(CENTRE - Vector2(80.0 - 5.0 * step, 0.0), 1.0, Vector2.ZERO, 16.0 * step)
    _brush.end_stroke()
    var bar := _mean_alpha([Rect2(0.2, 0.2, 0.06, 0.6)])
    assert_true(bar > 0.9, "The bar at the stroke's end takes paint, %.3f on average" % bar)
    var last := _mean_alpha([Rect2(0.26, 0.34, 0.03, 0.14)])
    assert_true(last > 0.9, "and so does its last stretch across the middle, %.3f" % last)


## The paths of *listed*, as `SaTipChoices.listing` gives them.
func _paths(listed: Array[Dictionary]) -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in listed:
        out.append(String(entry["path"]))
    return out


## A press at the centre and its release, no sample between, which paints the
## tip once at the press's pressure.
func _tap(pressure: float) -> void:
    _images.clear()
    _brush.begin_stroke(CENTRE, pressure, Vector2.ZERO, 0.0)
    _brush.end_stroke()


## The mean alpha over *areas*, each a rectangle of the tip's square at
## [constant CENTRE] in fractions of its side from its top left corner, read at
## every texel whose centre falls inside one.
func _mean_alpha(areas: Array) -> float:
    var corner := CENTRE - Vector2(RADIUS, RADIUS)
    var side := 2.0 * RADIUS
    var total := 0.0
    var count := 0
    for area: Rect2 in areas:
        var from := Vector2i((corner + area.position * side).ceil())
        var to := Vector2i((corner + area.end * side).floor())
        for y in range(from.y, to.y):
            for x in range(from.x, to.x):
                total += _texel(Vector2i(x, y)).a
                count += 1
    return total / float(maxi(count, 1))


## The active layer's texel at a document pixel.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _images.has(grid):
        @warning_ignore("static_called_on_instance")
        _images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_images[grid] as Image).get_pixelv(pixel - grid * side)
