## The noise brush's texture is one of three fields, Bristle,
## Grain and Picture, registered rather than listed, each with one channel or
## two, and laid at an offset of its own for every stroke.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when of the row, a clause a test: two strokes of one preset paint
## two different fields and a held seed paints one field twice, and one field
## read with one channel and with two cuts the same pressure map while only the
## second has a lightness of its own. The field is read on the GPU by the probe
## kernel, which calls the same `noise_field` the dab does, and the painted
## stroke is read off the layer, so both halves are what the kernel did.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

const RADIUS := 14.0
const INSIDE := RADIUS - 3.0
const SPOT := Vector2(60.0, 60.0)
## The probe's window, wide enough for a few specks of the default grain and a
## band of bristles across.
const WINDOW := Rect2i(32, 32, 48, 48)

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## The three shipped fields are registered, in the spec's order, and the
## Texture row and page are made from what is registered.
func test_the_three_fields_are_registered_and_the_texture_row_lists_them() -> void:
    var fields: RefCounted = NoiseFieldsScript.new()
    fields.register_shipped()
    assert_eq(fields.ids(), ["grain", "bristle", "picture"], "Grain, Bristle and Picture are registered")
    assert_eq(fields.two_channel_ids(), ["grain", "bristle"], "and the two drawn ones have two channels, the picture one")
    var extra := SaBrushFieldRegistry.Field.new(
        "streak", "Streak", NoiseFieldsScript.ENGINE, &"bristle", 1, [&"bristle_count"], []
    )
    assert_true(fields.register(extra), "A field is added through the same door")
    assert_false(fields.register(extra), "and one id cannot be taken twice")
    var texture: SaOptionSpec = null
    var page: Array[String] = []
    for spec: SaOptionSpec in NoiseModuleScript.options(fields):
        if spec.key == NoiseFieldsScript.FIELD_KEY:
            texture = spec
        if spec.page == NoiseFieldsScript.PAGE:
            page.append(String(spec.key))
    assert_not_null(texture, "The General page has a Texture row")
    var listed: Array = texture.choices.map(func(choice: Dictionary) -> Variant: return choice["id"])
    assert_eq(listed, ["grain", "bristle", "picture", "streak"], "listing every registered field, the added one too")
    for key: String in ["texture_channels", "texture_relief", "grain_scale", "bristle_count", "picture_name", "picture_rotation"]:
        assert_true(page.has(key), "and the Texture page carries %s" % key)


## Two strokes with one preset and two seeds lay two fields, and the same seed
## lays the same field twice, texel for texel.
func test_two_strokes_of_one_preset_paint_two_fields_and_one_seed_paints_one() -> void:
    assert_true(NoiseFieldsScript.offset_for(7) != NoiseFieldsScript.offset_for(8), "Two seeds draw two offsets")
    assert_eq(NoiseFieldsScript.offset_for(7), NoiseFieldsScript.offset_for(7), "and one seed the same offset every time")
    # The shift puts a full press inside each field's own range, so it paints
    # some of the dab and leaves holes: the grain under a half, the streaks
    # over 0.3 and the pattern's darkest fifth.
    var cuts := {"grain": 0.5, "bristle": 0.3, "picture": 0.8}
    for field_id: String in ["grain", "bristle", "picture"]:
        _brush.settings.texture_field = field_id
        _brush.settings.strength = cuts[field_id]
        var first := _painted_with(7)
        var other := _painted_with(8)
        var again := _painted_with(7)
        var painted := first.count(true)
        assert_true(
            painted > 0 and painted < first.size(),
            "%s paints some texels of the dab and leaves holes, %d of %d" % [field_id, painted, first.size()]
        )
        var differ := 0
        for index in first.size():
            if first[index] != other[index]:
                differ += 1
        assert_true(differ * 10 > first.size(), "%s: a second seed paints another field, %d texels differ" % [field_id, differ])
        assert_eq(first, again, "%s: the same seed paints the same texels" % field_id)


## One field with one channel and with two: the pressure map is the same both
## times, one channel reads the field's one grey as its lightness, the grain or
## the streak, two read a second number, and Relief at nought flattens that
## number to a middle grey. A streak's pressure map is its absence, so one
## bristle channel's lightness is one less the map.
func test_one_channel_or_two_cut_the_same_pressure_map() -> void:
    for field_id: String in ["grain", "bristle"]:
        _brush.settings.texture_field = field_id
        _brush.settings.texture_relief = 1.0
        _brush.settings.texture_channels = 1
        var one := _probe(Vector2(1.0, 0.0))
        _brush.settings.texture_channels = 2
        var two := _probe(Vector2(1.0, 0.0))
        _brush.settings.texture_relief = 0.0
        var flat := _probe(Vector2(1.0, 0.0))
        var map_gap := 0.0
        var one_gap := 0.0
        var two_gap := 0.0
        var flat_gap := 0.0
        for y in WINDOW.size.y:
            for x in WINDOW.size.x:
                var a := one.get_pixel(x, y)
                var b := two.get_pixel(x, y)
                map_gap = maxf(map_gap, absf(a.r - b.r))
                var grey := 1.0 - a.r if field_id == "bristle" else a.r
                one_gap = maxf(one_gap, absf(a.g - grey))
                two_gap = maxf(two_gap, absf(b.g - b.r))
                flat_gap = maxf(flat_gap, absf(flat.get_pixel(x, y).g - 0.5))
        assert_true(map_gap < 0.00001, "%s: two channels cut the same pressure map as one, %.6f apart" % [field_id, map_gap])
        assert_true(one_gap < 0.00001, "%s: one channel's lightness is its grey, %.6f apart" % [field_id, one_gap])
        assert_true(
            two_gap > 0.1, "%s: two channels' lightness is a reading of its own, up to %.3f from the map" % [field_id, two_gap]
        )
        assert_true(flat_gap < 0.00001, "%s: and Relief at nought flattens it to a middle grey" % field_id)


## A picture has one channel whatever the row says, because the store decodes
## a pattern to one grey mask.
func test_a_picture_reads_the_store_and_has_one_channel() -> void:
    _brush.settings.texture_field = "picture"
    _brush.settings.picture_name = "Paper Grain"
    _brush.settings.texture_channels = 2
    var read := _probe(Vector2(1.0, 0.0))
    assert_not_null(_brush.field_binding.picture, "The Picture field binds the store's pattern (%s)" % _brush.field_binding.error)
    var low := 1.0
    var high := 0.0
    var gap := 0.0
    for y in WINDOW.size.y:
        for x in WINDOW.size.x:
            var at := read.get_pixel(x, y)
            low = minf(low, at.r)
            high = maxf(high, at.r)
            gap = maxf(gap, absf(at.g - at.r))
    assert_true(high - low > 0.2, "and the stroke reads the pattern's own grey, %.3f to %.3f" % [low, high])
    assert_true(gap < 0.00001, "with its lightness its pressure map, Channels at two or not")
    _brush.settings.picture_rotation = 90.0
    var turned := _probe(Vector2(1.0, 0.0))
    assert_true(_texels(turned) != _texels(read), "and Rotation turns it")


## The bristles lie along the stroke: across the direction of travel the field
## changes from streak to gap, and along it far less, whichever way it points.
func test_the_bristles_follow_the_direction_of_travel() -> void:
    _brush.settings.texture_field = "bristle"
    _brush.settings.bristle_length = 4.0
    for direction: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
        var read := _probe(direction)
        var along := 0.0
        var across := 0.0
        for y in range(1, WINDOW.size.y):
            for x in range(1, WINDOW.size.x):
                var here := read.get_pixel(x, y).r
                var step_x := absf(here - read.get_pixel(x - 1, y).r)
                var step_y := absf(here - read.get_pixel(x, y - 1).r)
                along += step_x if direction.x > 0.5 else step_y
                across += step_y if direction.x > 0.5 else step_x
        assert_true(
            across > 2.0 * along, "Moving along %s the streaks change across %.1f and along %.1f" % [direction, across, along]
        )


## The texels a press at [constant SPOT] paints with *stroke_seed_value*, well inside the
## tip, on a fresh surface.
func _painted_with(stroke_seed_value: int) -> Array[bool]:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.stroke_seed = stroke_seed_value
    _brush.begin_stroke(SPOT, 1.0)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var out: Array[bool] = []
    var reach := int(INSIDE)
    for y in range(-reach, reach + 1):
        for x in range(-reach, reach + 1):
            if Vector2(x, y).length() > INSIDE:
                continue
            var at := Vector2i(SPOT) + Vector2i(x, y)
            out.append(_alpha(layer, at, images) > 0.5)
    return out


func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            @warning_ignore("static_called_on_instance")
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0


## The field over [constant WINDOW] for a straight stroke of seed 7 through
## its centre along *direction*, as the stroke would read it.
func _probe(direction: Vector2) -> Image:
    _brush.lay_field(7)
    var centre := Vector2(WINDOW.get_center())
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(_brush.probe_field(WINDOW, centre, direction, 0.0, RADIUS))


func _texels(image: Image) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for y in image.get_height():
        for x in image.get_width():
            out.append(image.get_pixel(x, y).r)
    return out
