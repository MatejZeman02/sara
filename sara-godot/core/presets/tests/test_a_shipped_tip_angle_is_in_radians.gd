## A shipped preset's tip angle is in radians, as the tip reads it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaBrushTip.angle` is in radians, and Chisel Marker shipped `"tip:angle":
## 45.0`, which the tip read as 45 radians, so its dab stood at 58.3 degrees
## from the horizontal rather than the 45 its author wrote. Masked Stipple's
## `"masking:tip:angle": 30.0` was 30 radians the same way.
##
## The first case lays one dab of Chisel Marker as it ships, on a document the
## default's size so the radius is the one a painter gets, and reads the dab's
## long axis off the float texels by their second moments. The angle is read in
## the frame the tip turns in, x to the right and y down, which is the one
## `state_brush.gd` hands the shader.
##
## The second reads every shelf of shipped presets a module registers, through
## the roles the presets bar reads, so a shelf a module adds later is read too.
## A field naming an angle is held to the unit its reader declares, and a field
## this suite does not know fails it rather than passing unread.
##
## In `tests/` rather than the stamp's own suites, because the shelves are found
## through `ModuleLoader`, which a module cannot name past the door.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The default document, whose short side a shipped radius is a fraction of.
const DOCUMENT := Vector2i(1920, 1080)
const CENTRE := Vector2(960.0, 540.0)

## The two fields a drawing angle sensor carries in degrees, as `SaSensor`
## declares them: `angle_offset` is read as `angle_offset / 360.0` of a turn,
## and `fan_step` is the degrees between two fanned dabs. Neither is the tip's.
const DEGREE_FIELDS: Array[String] = ["angle_offset", "fan_step"]


func after_each() -> void:
    ModuleLoader.unload_all()


## The row's first clause: one dab of Chisel Marker as it ships stands at 45
## degrees, within one.
func test_one_dab_of_chisel_marker_stands_at_45_degrees() -> void:
    var surface := Fixtures.make_surface(DOCUMENT)
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings = ShippedPresetsScript.build(StateBrushScript.BrushSettingsScript, _recipe("Chisel Marker"))
    assert_not_null(brush.settings, "Chisel Marker is a shipped recipe the stamp's settings carry")
    if brush.settings == null:
        Fixtures.teardown(surface)
        return
    # What a stroke's start does, without the document's stroke it opens: the
    # evaluator reads no options until it is handed the settings.
    brush.dynamics.settings = brush.settings
    brush.dynamics.begin_stroke()
    brush.stroke_info.begin(CENTRE, 4242)
    brush._stamp_brush(CENTRE, 1.0)

    var moments := _moments(surface.get_document().stroke_layer)
    Fixtures.teardown(surface)
    assert_true(float(moments["mass"]) > 100.0, "The dab paints, %.1f texels' worth of alpha" % float(moments["mass"]))
    assert_true(float(moments["spread"]) > 2.0, "and is a long tip rather than a disc, %.2f to one" % float(moments["spread"]))
    var degrees := rad_to_deg(float(moments["axis"]))
    assert_almost_eq(degrees, 45.0, 1.0, "Its long axis stands at 45 degrees, read at %.2f" % degrees)


## The row's second clause: every angle field of every shipped preset is in
## the unit its reader declares, the tip's radians no larger than a whole turn.
func test_every_angle_field_of_every_shipped_preset_is_in_its_readers_unit() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true

    var shelves := 0
    var read: Array[String] = []
    for role: StringName in registries.roles.list_roles():
        if not String(role).begins_with("shipped_presets"):
            continue
        shelves += 1
        var recipes: Array = registries.roles.script_for(role).call("entries")
        for entry: Dictionary in recipes:
            _walk(entry, "%s: %s" % [role, entry.get("name", "?")], "", read)
    assert_true(shelves >= 3, "The stamp's, the noise brush's and the filter brush's shelves are read, %d found" % shelves)
    assert_true(read.has("shipped_presets: Chisel Marker tip:angle"), "Chisel Marker's tip angle is among the fields read")
    assert_true(read.has("shipped_presets: Masked Stipple masking:tip:angle"), "and Masked Stipple's mask angle, of %s" % [read])


## Masked Stipple's mask stands at the 30 degrees its author wrote, and Chisel
## Marker's tip at 45, each read off the settings the recipe builds.
func test_the_two_angles_are_the_degrees_their_author_wrote() -> void:
    var chisel := ShippedPresetsScript.build(StateBrushScript.BrushSettingsScript, _recipe("Chisel Marker"))
    var stipple := ShippedPresetsScript.build(StateBrushScript.BrushSettingsScript, _recipe("Masked Stipple"))
    assert_almost_eq(rad_to_deg(float(chisel.get_indexed("tip:angle"))), 45.0, 1e-3, "Chisel Marker's tip at 45 degrees")
    assert_almost_eq(rad_to_deg(float(stipple.get_indexed("masking:tip:angle"))), 30.0, 1e-3, "Masked Stipple's mask at 30")


## Reads every field under *value* whose name says angle, *where* naming the
## recipe for a failure, and appends what it read to *read*.
func _walk(value: Variant, where: String, key: String, read: Array[String]) -> void:
    if value is Dictionary:
        for inner: Variant in value:
            _walk(value[inner], where, String(inner), read)
        return
    if value is Array:
        for item: Variant in value:
            _walk(item, where, key, read)
        return
    var leaf := key.get_slice(":", key.get_slice_count(":") - 1)
    if not (leaf.contains("angle") or DEGREE_FIELDS.has(leaf)):
        return
    read.append("%s %s" % [where, key])
    if not (value is float or value is int):
        assert_true(false, "%s %s is a number, %s" % [where, key, value])
        return
    var number := absf(float(value))
    var said := "%s %s, %s," % [where, key, value]
    if leaf == "angle":
        assert_true(number <= TAU, "%s is in radians, as the tip reads it, and no larger than a turn" % said)
    elif DEGREE_FIELDS.has(leaf):
        assert_true(number <= 360.0, "%s is in degrees, as the sensor reads it, and no larger than a turn" % said)
    else:
        assert_true(false, "%s %s names an angle in a unit this suite does not know, so it says which" % [where, key])


## The recipe the stamp's shelf ships as *preset_name*.
func _recipe(preset_name: String) -> Dictionary:
    for entry: Dictionary in ShippedPresetsScript.entries():
        if String(entry["name"]) == preset_name:
            return entry
    assert_true(false, "%s is a shipped recipe" % preset_name)
    return {}


## The alpha-weighted second moments of everything *layer* holds, in document
## pixels, and the long axis they give.
##
## `axis` is that axis's angle from the x axis in radians, folded into
## [0, PI), and `spread` how many times longer the dab is along it than across.
## Each chunk is read at its own `pixel_size()` from its own origin.
func _moments(layer: SaLayer) -> Dictionary:
    var rd := GlobalShaderCompiler.get_rd()
    var mass := 0.0
    var sum := Vector2.ZERO
    var points: Array[Vector3] = []
    for grid: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid]
        var field := layer.get_field(grid)
        if field == null:
            continue
        var side := chunk.pixel_size()
        var texel := float(SaLayer.CHUNK_SIZE) / float(side)
        var origin := Vector2(grid * SaLayer.CHUNK_SIZE)
        var data := rd.texture_get_data(field.rid, 0).to_float32_array()
        for y in side:
            for x in side:
                var alpha := data[(y * side + x) * 4 + 3]
                if alpha <= 0.0:
                    continue
                var at := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
                points.append(Vector3(at.x, at.y, alpha))
                mass += alpha
                sum += at * alpha
    if mass <= 0.0:
        return {"mass": 0.0, "spread": 0.0, "axis": NAN}
    var centre := sum / mass
    var xx := 0.0
    var yy := 0.0
    var xy := 0.0
    for point: Vector3 in points:
        var d := Vector2(point.x, point.y) - centre
        xx += point.z * d.x * d.x
        yy += point.z * d.y * d.y
        xy += point.z * d.x * d.y
    var axis := fposmod(0.5 * atan2(2.0 * xy, xx - yy), PI)
    # The two eigenvalues of the moment matrix, the variance along the long
    # axis and across it.
    var half_sum := 0.5 * (xx + yy)
    var root := sqrt(0.25 * (xx - yy) * (xx - yy) + xy * xy)
    var across := maxf(half_sum - root, 1e-6)
    return {"mass": mass, "spread": sqrt((half_sum + root) / across), "axis": axis}
