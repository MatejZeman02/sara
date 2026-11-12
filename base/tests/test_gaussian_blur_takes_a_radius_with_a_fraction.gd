## Gaussian Blur takes a radius with a fraction, so 1.5 blurs
## more than 1 and less than 2, and a record saved with a whole radius opens and
## blurs as it did.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter cut its radius to a whole number before the kernel saw it, so 1.5
## blurred as 1 and 2.5 as 2. Now the kernel takes the radius as a float: sigma
## is a third of it, the bell is lowered by its own height one texel past it,
## and the walk takes whole taps out to it rounded up, which is the reach the
## pass is given.
##
## Each case blurs one row of paint across a one-chunk canvas and reads the
## alpha down the column through it. Every tap of a row across lands on paint,
## so the row sums to the bell's line and the column reads the bell itself, the
## weight at each distance over the line, which this suite works out on the CPU
## from the same three numbers the kernel uses.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## The four radii the note asked for, in the order the blur widens.
const RADII: Array[float] = [1.0, 1.5, 2.0, 2.5]
## The row painted, the column read across it, and the paint's span, which
## passes the column by more than any reach here on either side.
const ROW := 128
const COLUMN := 128
const FROM := 32
const TO := 224
## How far either side of the row the column is read, past the widest reach.
const SPAN := 4
## The float error of a column read against the bell worked out here, far under
## the 0.05 the nearest two radii differ by at the row itself.
const TOLERANCE := 0.00001
static var scratch_path: String = SaDataRoot.path("d25_gaussian_blur_radius.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i.ONE * SaChunk.SIZE)
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _paint_row()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## One row of white at alpha one, [const ROW] from [const FROM] to [const TO],
## over a chunk otherwise empty, uploaded since the brush is not what this
## suite is about.
func _paint_row() -> void:
    var texture := _layer.get_or_create_chunk(Vector2i.ZERO).albedo()
    assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y * 4)
    for x in range(FROM, TO):
        var i := (ROW * texture.size.x + x) * 4
        for channel in 4:
            values[i + channel] = 1.0
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    _layer.mark_unresolved(Vector2i.ZERO)


## The alpha of *texture* down [const COLUMN], from [const SPAN] above the row
## to [const SPAN] below it.
static func _column(texture: SaTexture) -> PackedFloat32Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := PackedFloat32Array()
    for y in range(ROW - SPAN, ROW + SPAN + 1):
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + COLUMN).a)
    return out


## The column the bell of *radius* lays across one row of alpha one, as
## `gaussian.gmacs` weighs it: sigma a third of the radius, each weight lowered
## by the bell's height one texel past the radius, the taps out to the radius
## rounded up, and every weight over the sum of one row of them.
static func _bell(radius: float) -> PackedFloat32Array:
    var sigma := maxf(radius / 3.0, 0.001)
    var spread := 2.0 * sigma * sigma
    var past := 3.0 * sigma + 1.0
    var reach := ceili(radius)
    var weights := PackedFloat32Array()
    var line := 0.0
    for offset in range(-SPAN, SPAN + 1):
        var weight := 0.0
        if absi(offset) <= reach:
            weight = exp(-float(offset * offset) / spread) - exp(-past * past / spread)
        weights.append(weight)
        line += weight
    for i in weights.size():
        weights[i] /= line
    return weights


## What Apply writes at *radius*, handed over as *radius* is, an int or a float.
func _applied(radius: Variant) -> PackedFloat32Array:
    var filter := SaGaussianBlurFilter.new()
    filter.set_parameters({"radius": radius})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    assert_true(SaFilterApply.call_run(filter, ctx), "The blur records its pass")
    assert_true(SaFilterApply.apply(ctx, filter.title()), "which Apply walks over the layer")
    return _column(_layer.get_field(Vector2i.ZERO))


## The spread of *column* about the row, its alpha weighing each distance
## squared, which is the edge's width read as one number.
static func _width(column: PackedFloat32Array) -> float:
    var moment := 0.0
    var mass := 0.0
    for i in column.size():
        var distance := float(i - SPAN)
        moment += distance * distance * column[i]
        mass += column[i]
    return moment / mass


## The largest difference between two columns at one distance.
static func _distance(one: PackedFloat32Array, other: PackedFloat32Array) -> float:
    var most := 0.0
    for i in mini(one.size(), other.size()):
        most = maxf(most, absf(one[i] - other[i]))
    return most


func _assert_bell(column: PackedFloat32Array, radius: float, what: String) -> void:
    var bell := _bell(radius)
    assert_true(
        _distance(column, bell) < TOLERANCE, "%s lays the bell of radius %.1f: %s against %s" % [what, radius, column, bell]
    )


## The note: "radius 1.5 moved no pixel by more than 1/255 and 2.5 laid the
## same picture as 2". Each radius lays a column unlike the one before it, wider
## at its edge, and the bell the kernel's weights say it should.
func test_each_radius_blurs_wider_than_the_one_before() -> void:
    var columns: Array[PackedFloat32Array] = []
    for radius in RADII:
        _paint_row()
        var column := _applied(radius)
        _assert_bell(column, radius, "Apply at radius %.1f" % radius)
        columns.append(column)
    for i in range(1, RADII.size()):
        var moved := _distance(columns[i - 1], columns[i])
        assert_true(moved > 0.05, "Radius %.1f lays a column unlike %.1f's, %.6f apart at most" % [RADII[i], RADII[i - 1], moved])
        assert_true(
            _width(columns[i]) > _width(columns[i - 1]),
            "and an edge wider than it, %.6f against %.6f" % [_width(columns[i]), _width(columns[i - 1])]
        )


## The dialog's slider steps in tenths of a pixel, so the painter reaches 1.5
## without the door.
func test_the_dialog_steps_in_tenths_of_a_pixel() -> void:
    var dialog := SaDialog.new()
    var host := VBoxContainer.new()
    SaGaussianBlurFilter.new().build(dialog)
    # Realized into a host freed below, the way the filter window realizes it,
    # so the rows' controls go with it and nothing leaks at exit.
    dialog.realize(host)
    var row := dialog.row(&"radius") as SaSlider
    assert_true(row != null, "The dialog has a Radius slider")
    if row != null:
        assert_almost_eq(row.step_value, 0.1, 0.000001, "which steps in tenths of a pixel")
        assert_eq(row.decimal_places, 1, "and shows one decimal")
    host.free()


## A record saved before the fix holds a whole radius, written as an int, and
## opened again it blurs as the whole radius always did: the bell of radius 2,
## the column an attached blur drew before the save.
func test_a_record_with_a_whole_radius_opens_and_blurs_as_before() -> void:
    var filter := SaGaussianBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    SaFilterOps.new(_doc).attach(_layer, key, {"radius": 2})
    Bench.composite(_easel)
    var before := _column(_easel.output)
    _assert_bell(before, 2.0, "The attached blur of a whole radius")
    assert_eq(SaExport.save_sad(_doc, scratch_path, 0), OK, "The document saves")
    filter.set_parameters({"radius": 9.5})
    var loaded := SaExport.load_sad(_doc, ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    assert_eq(loaded, OK, "and loads")
    _layer = _doc.get_node_or_null("Background") as SaLayer
    assert_true(_layer != null and _layer.filters.size() == 1, "with its one attached blur")
    if _layer == null or _layer.filters.size() != 1:
        return
    assert_almost_eq(float(_layer.filters[0].parameters.get("radius", -1.0)), 2.0, 0.0, "at radius 2")
    Bench.composite(_easel)
    var after := _column(_easel.output)
    assert_true(_distance(before, after) == 0.0, "which draws the column it drew before: %s against %s" % [after, before])
