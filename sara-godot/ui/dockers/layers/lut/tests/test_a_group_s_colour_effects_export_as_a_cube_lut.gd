## A group's colour effects export as a `.cube` 3D table that
## DaVinci Resolve reads, and the table loaded through Filter > Colour > LUT on
## the picture without them gives the picture the group gives.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The picture is a gradient across two chunks, opaque, with red running across,
## green down and blue across both, so the lattice and the picture share no
## points. The group above it is pass-through and holds a Curves, a
## Hue/Saturation/Lightness and a Brightness/Contrast adjustment layer at half
## opacity. The file is written, read back as a reader reads it, and loaded
## through the LUT filter's own load on a copy of the picture with no group.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const DialogScript = preload("res://ui/dockers/layers/lut/effects_lut_dialog.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
const CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const CURVES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.5], [1.0, 1.0]], "red": [[0.0, 0.0625], [1.0, 0.9375]]}}
## A grade's Hue/Saturation: a little less colour and a little more light.
## It turns in Oklch, whose cube roots are steep where a channel nears nought,
## so a turn of the hue or a lift of the saturation that takes a colour past
## the gamut bends between two points of any table: the last test measures
## that, and a table of 33 holds this setting within a step of eight bits.
const HUE := {"hue": 0.0, "saturation": 90.0, "lightness": 1.0}
## A hue turn and a saturation lift that push the gradient's greens past the
## gamut, where a table's points are too far apart.
const HUE_TURN := {"hue": 12.0, "saturation": 115.0, "lightness": 4.0}
const BRIGHTNESS := {"brightness": 25.0, "contrast": 20.0}
const BLUR := {"radius": 6.0}
## One step of eight bits, what the note asks every texel to stay within.
const STEP := 1.0 / 255.0

var _types: SaLayerTypeRegistry
var _files: Array[String] = []
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for path in _files:
        DirAccess.remove_absolute(path)
    _files.clear()
    for easel in _easels:
        easel.free()
    _easels.clear()


## An easel whose filters are the base module's the suite uses, and whose one
## visible layer is the gradient, left active.
func _picture() -> SaEasel:
    var easel := Bench.easel(SIZE)
    _easels.append(easel)
    var registry := easel.compositor.filter_chain.registry
    for filter: SaFilter in [
        SaCurvesFilter.new(),
        SaHueSaturationLightnessFilter.new(),
        SaBrightnessContrastFilter.new(),
        SaGaussianBlurFilter.new(),
        SaLutFilter.new(),
    ]:
        registry.register(filter, OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var layer := doc.get_node("Layer 1") as SaLayer
    layer.name = "Gradient"
    _paint(layer)
    doc.set_active_layer(layer)
    return easel


static func _colour_at(x: int, y: int) -> Color:
    var r := float(x) / float(SIZE.x - 1)
    var g := float(y) / float(SIZE.y - 1)
    return Color(r, g, fposmod(r * 3.0 + g * 0.5, 1.0), 1.0)


static func _paint(layer: SaLayer) -> void:
    for grid_pos: Vector2i in CHUNKS:
        var texture := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        var values := PackedFloat32Array()
        values.resize(texture.size.x * texture.size.y * 4)
        for y in texture.size.y:
            for x in texture.size.x:
                var c := _colour_at(grid_pos.x * texture.size.x + x, y)
                var i := (y * texture.size.x + x) * 4
                values[i] = c.r
                values[i + 1] = c.g
                values[i + 2] = c.b
                values[i + 3] = 1.0
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


static func _key(filter: SaFilter) -> StringName:
    return SaFilterRegistry.key_for(OWNER, filter)


## An adjustment layer above the active one called *title*, carrying *values*
## of *filter* when it is given, left active.
func _adjustment(easel: SaEasel, title: String, filter: SaFilter, values: Dictionary, opacity: float = 1.0) -> SaLayer:
    var layer := SaLayerOps.new(easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = title
    layer.opacity = opacity
    if filter != null:
        var made := SaFilterOps.new(easel.document).attach(layer, _key(filter), values)
        assert_not_null(made, "%s attaches to %s" % [filter.title(), title])
    return layer


## The group of the note over the gradient: Curves, Hue/Saturation and a
## Brightness/Contrast at half opacity, bottom first, in a pass-through group.
func _graded(easel: SaEasel) -> SaLayer:
    var ops := SaLayerOps.new(easel.document)
    var curves := _adjustment(easel, "Curves", SaCurvesFilter.new(), CURVES)
    var group := ops.group_active()
    group.name = "Grade"
    easel.document.set_active_layer(curves)
    _adjustment(easel, "Hue", SaHueSaturationLightnessFilter.new(), HUE)
    _adjustment(easel, "Half", SaBrightnessContrastFilter.new(), BRIGHTNESS, 0.5)
    for member in SaLayerStack.members(easel.document, group):
        assert_eq(member.group, group, "%s sits in the group" % member.name)
    assert_eq(SaLayerStack.members(easel.document, group).size(), 3, "The group holds the three")
    easel.document.set_active_layer(group)
    return group


func _texels(easel: SaEasel) -> PackedByteArray:
    easel.document.invalidate_chunks(CHUNKS)
    Bench.composite(easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


## The worst channel difference between two outputs of the suite's size, over
## every texel.
static func _worst(a: PackedByteArray, b: PackedByteArray, format: int) -> Array:
    var worst := 0.0
    var at := Vector2i.ZERO
    for y in SIZE.y:
        for x in SIZE.x:
            var index := y * SIZE.x + x
            var p := SaFieldSpec.decode_texel(a, format, index)
            var q := SaFieldSpec.decode_texel(b, format, index)
            var off := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
            if off > worst:
                worst = off
                at = Vector2i(x, y)
    return [worst, at]


func _path(file: String) -> String:
    var path := ProjectSettings.globalize_path(SaDataRoot.path(file))
    _files.append(path)
    return path


## The file at *path* through the LUT filter's own load, attached to the active
## layer of a fresh picture with no group, and that picture's output.
func _through_the_lut(path: String, side: int = 33) -> PackedByteArray:
    var copy := _picture()
    var lut := SaLutFilter.new()
    var panel := SaLutFilter.LutPanel.new(lut)
    panel.load_file(path)
    var line := (panel.get_node("LutLine") as Label).text
    panel.free()
    assert_true(line.contains(str(side)), "The LUT filter reads the file as %d a side: %s" % [side, line])
    var record := SaFilterOps.new(copy.document).attach(copy.document.active_layer, _key(lut), lut.parameters())
    assert_not_null(record, "The table attaches to the copy's gradient")
    return _texels(copy)


func test_the_table_loaded_through_the_lut_filter_gives_the_group_s_picture() -> void:
    var easel := _picture()
    var plain := _texels(easel)
    var group := _graded(easel)
    var graded := _texels(easel)
    assert_true(_worst(plain, graded, easel.output.format)[0] > 0.05, "The group changes the picture")
    var export := SaEffectsLut.new(easel.document, group)
    assert_eq(export.left_out(), PackedStringArray(), "Nothing of this group is left out")
    assert_true(export.carries_anything(), "and it carries a colour change")
    var path := _path("grade.cube")
    assert_eq(export.write(path, 33), 33 * 33 * 33, "The file has a row for every point of the lattice")
    assert_false(export.moved, "and the effects do not change with the place")
    var through := _through_the_lut(path)
    var found := _worst(graded, through, easel.output.format)
    assert_true(found[0] <= STEP, "Every texel is within 1/255 of the group's own, worst %s at %s" % found)


func test_the_file_reads_as_a_cube_reader_reads_it() -> void:
    var easel := _picture()
    var export := SaEffectsLut.new(easel.document, _graded(easel))
    var path := _path("reader.cube")
    export.write(path, 33)
    var size := 0
    var domain_min := PackedStringArray()
    var domain_max := PackedStringArray()
    var rows: Array[Vector3] = []
    for raw in FileAccess.get_file_as_string(path).split("\n"):
        var line := raw.strip_edges()
        if line.is_empty() or line.begins_with("#") or line.begins_with("TITLE"):
            continue
        var words := line.split(" ", false)
        if words[0] == "LUT_3D_SIZE":
            size = words[1].to_int()
        elif words[0] == "DOMAIN_MIN":
            domain_min = words.slice(1)
        elif words[0] == "DOMAIN_MAX":
            domain_max = words.slice(1)
        else:
            assert_eq(words.size(), 3, "A data row is three numbers: %s" % line)
            rows.append(Vector3(words[0].to_float(), words[1].to_float(), words[2].to_float()))
    assert_eq(size, 33, "A LUT_3D_SIZE 33 line")
    assert_eq(domain_min, PackedStringArray(["0.0", "0.0", "0.0"]), "A DOMAIN_MIN line of nought")
    assert_eq(domain_max, PackedStringArray(["1.0", "1.0", "1.0"]), "A DOMAIN_MAX line of one")
    assert_eq(rows.size(), 35937, "35,937 rows")
    # The Curves lifts red's black to 1/16 and the Hue/Saturation moves it,
    # so along the first row red rises while green and blue stay near black,
    # and the step to the next row is where green first moves.
    var along := rows[32] - rows[0]
    var down := rows[33] - rows[0]
    assert_true(along.x > 0.5, "Red changes fastest: row 32 is red's far end, %s" % rows[32])
    assert_true(absf(down.x) < 0.1 and down.y > 0.0, "and row 33 is the first green step, %s" % rows[33])
    var cube := SaLutFilter.Cube.parse(FileAccess.get_file_as_string(path))
    assert_eq(cube.problem, "", "The LUT filter's own reader takes it")
    assert_eq(cube.size, 33, "at 33 a side")


## A group of a blur, a painted layer and a masked adjustment layer around
## the Curves the table carries.
func _cluttered(easel: SaEasel) -> SaLayer:
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var curves := _adjustment(easel, "Curves", SaCurvesFilter.new(), CURVES)
    var group := ops.group_active()
    group.name = "Cluttered"
    doc.set_active_layer(curves)
    _adjustment(easel, "Blur", SaGaussianBlurFilter.new(), BLUR)
    var paint := ops.add()
    paint.name = "Paint"
    paint.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.75, 0.25, 0.5, 0.5))
    var masked := _adjustment(easel, "Masked", SaHueSaturationLightnessFilter.new(), HUE)
    masked.mask = SaMask.new(masked)
    assert_eq(SaLayerStack.members(doc, group).size(), 4, "The group holds the four")
    doc.set_active_layer(group)
    return group


func test_what_a_table_cannot_carry_is_named_and_left_out() -> void:
    var easel := _picture()
    var export := SaEffectsLut.new(easel.document, _cluttered(easel))
    var lines := export.left_out()
    assert_eq(lines.size(), 3, "Three things are left out: %s" % [lines])
    var said := "\n".join(lines)
    for title: String in ["Blur", "Paint", "Masked"]:
        assert_true(said.contains("'%s'" % title), "%s is named: %s" % [title, said])
    var dialog: Window = DialogScript.new()
    dialog.call(&"fill", export)
    var shown := (dialog.find_child("LeftOut", true, false) as Label).text
    dialog.free()
    for title: String in ["Blur", "Paint", "Masked"]:
        assert_true(shown.contains("'%s'" % title), "The dialog names %s before saving: %s" % [title, shown])
    var path := _path("cluttered.cube")
    export.write(path, 33)
    var bare := _picture()
    var curves_only := _adjustment(bare, "Curves", SaCurvesFilter.new(), CURVES)
    var group := SaLayerOps.new(bare.document).group_active()
    bare.document.set_active_layer(group)
    assert_eq(curves_only.group, group, "The bare group holds the Curves alone")
    var plain := SaEffectsLut.new(bare.document, group)
    assert_eq(plain.left_out(), PackedStringArray(), "and leaves nothing out")
    var plain_path := _path("bare.cube")
    plain.write(plain_path, 33)
    var cluttered_text := FileAccess.get_file_as_string(path).split("\n", true, 2)[2]
    var bare_text := FileAccess.get_file_as_string(plain_path).split("\n", true, 2)[2]
    assert_true(cluttered_text == bare_text, "Past the title the file is the export of the group without them")


func test_an_oklab_document_exports_the_values_its_lut_filter_sees() -> void:
    var space := SaColorSpace.oklab_p3().with_depth(SaColorSpace.Depth.F32)
    var easel := Bench.easel(SIZE)
    _easels.append(easel)
    easel.document.color_space = space
    var registry := easel.compositor.filter_chain.registry
    registry.register(SaCurvesFilter.new(), OWNER)
    var layer := easel.document.get_node("Layer 1") as SaLayer
    easel.document.set_active_layer(layer)
    _adjustment(easel, "Curves", SaCurvesFilter.new(), CURVES)
    var export := SaEffectsLut.new(easel.document, easel.document.active_layer)
    var entries := export.table(5)
    assert_eq(entries.size(), 3 * 125, "A table of five a side")
    # The corner of black stays black under the curve's master point at
    # nought, and the red lift shows on the red channel alone.
    var black := entries.slice(0, 3)
    assert_true(absf(black[1]) < 0.01 and absf(black[2]) < 0.01, "Black keeps green and blue at nought: %s" % [black])
    assert_true(black[0] > 0.03, "and red's lift reads in the RGB view: %s" % [black])


## How far the table at *side* is from a group of one Hue/Saturation of
## *values* over the gradient, the worst texel.
func _hue_error(values: Dictionary, side: int) -> float:
    var easel := _picture()
    _adjustment(easel, "Hue", SaHueSaturationLightnessFilter.new(), values)
    var group := SaLayerOps.new(easel.document).group_active()
    easel.document.set_active_layer(group)
    var graded := _texels(easel)
    var path := _path("hue_%d.cube" % side)
    SaEffectsLut.new(easel.document, group).write(path, side)
    return _worst(graded, _through_the_lut(path, side), easel.output.format)[0]


func test_a_hue_turn_past_the_gamut_is_held_closer_by_a_bigger_table() -> void:
    var gentle := _hue_error(HUE, 33)
    var coarse := _hue_error(HUE_TURN, 33)
    var fine := _hue_error(HUE_TURN, 65)
    assert_true(gentle <= STEP, "The grade's setting is held within a step at 33, %s" % gentle)
    assert_true(fine < coarse * 0.6, "A turn past the gamut is what the points between miss: %s at 33, %s at 65" % [coarse, fine])
