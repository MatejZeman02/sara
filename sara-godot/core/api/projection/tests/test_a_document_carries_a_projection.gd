extends "res://tests/test_framework.gd"
## A document carries a projection: the three kinds the skeleton registers
## through the door a module uses, each mapping a pixel to a view position and
## back, the wrap each one brings, the `.sad` header key that keeps a kind and
## an orientation, a file written before the key reading flat, and an assign
## being one history step that moves no pixel.

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Written before a document had a projection, a 64 by 64 v4 file of one red
## layer, so the reader is held to a file it did not write.
const FIXTURE := "res://tests/data/plain_v4.sad"

## Twice as wide as tall, the shape an equirectangular panorama is.
const SIZE := Vector2(64.0, 32.0)
## The fraction of a pixel a round trip may drift by.
const DRIFT := 0.001

const RED := Color(1.0, 0.0, 0.0, 1.0)


## A kind a module brings, to show the door is the built-ins' own.
class Cylinder:
    extends SaProjection.Kind

    func _init() -> void:
        super(&"cylinder", "Cylinder", SaProjection.Wrap.X, SaProjection.View.SPHERE)


static var scratch_path: String = SaDataRoot.path("test_a_document_carries_a_projection.sad")

var _registries: SaRegistries = null
var _easel: SaEasel = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(64, 64))


func after_each() -> void:
    _registries.context.for_module(&"projection-fixture").remove_all_registrations()
    _easel.free()
    _easel = null
    DirAccess.remove_absolute(scratch_path)


## The centre of every pixel of a 16 by 8 grid laid over SIZE, which keeps
## off both poles, where a direction holds no longitude to come back with.
func _grid() -> Array[Vector2]:
    var out: Array[Vector2] = []
    for row in 8:
        for column in 16:
            out.append(Vector2((column + 0.5) * SIZE.x / 16.0, (row + 0.5) * SIZE.y / 8.0))
    return out


## The header of the `.sad` at *path*, read the way the loader reads it.
func _header_of(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var raw := file.get_buffer(packed_size).decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS)
    file.close()
    var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
    return parsed if parsed is Dictionary else {}


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_or_create_chunk(Vector2i.ZERO).albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func test_the_skeleton_registers_flat_equirectangular_and_polar_through_the_door() -> void:
    var kinds := _registries.projections
    assert_eq(kinds.ids(), [SaProjection.FLAT, SaProjection.EQUIRECTANGULAR, SaProjection.POLAR], "Three kinds, in that order")
    assert_eq(_registries.context.projections, kinds, "The context hands a module the same registry")
    var scoped := _registries.context.for_module(&"projection-fixture")
    assert_true(scoped.register_projection(Cylinder.new()), "A module's kind goes through the same call")
    assert_true(kinds.ids().has(&"cylinder"), "and is listed beside the three")
    assert_false(scoped.register_projection(SaProjection.Kind.new(SaProjection.POLAR, "Polar")), "A taken id is refused")
    scoped.remove_all_registrations()
    assert_eq(kinds.ids().size(), 3, "Unloading the module takes its kind and leaves the skeleton's")


func test_each_kind_maps_a_grid_of_pixels_to_a_direction_and_back() -> void:
    for kind_id: StringName in _registries.projections.ids():
        var kind := _registries.projections.find(kind_id)
        for preset: StringName in SaProjection.Heading.presets():
            var projection := SaProjection.new(kind, SaProjection.Heading.new(preset, 30.0))
            var worst := 0.0
            for pixel: Vector2 in _grid():
                var view := projection.to_view(pixel, SIZE)
                if kind.view == SaProjection.View.SPHERE:
                    assert_almost_eq(view.length(), 1.0, DRIFT, "%s at %s is a unit direction" % [kind_id, pixel])
                var back := projection.from_view(view, SIZE)
                worst = maxf(worst, back.distance_to(pixel))
            assert_true(worst < DRIFT, "%s under %s comes back to the pixel it left" % [kind_id, preset])


func test_the_orientations_turn_the_same_pixel_to_different_directions() -> void:
    var kind := _registries.projections.find(SaProjection.EQUIRECTANGULAR)
    var middle := Vector2(0.0, SIZE.y * 0.5)
    var blender := SaProjection.new(kind).to_view(middle, SIZE)
    var godot := SaProjection.new(kind, SaProjection.Heading.new(SaProjection.Heading.GODOT)).to_view(middle, SIZE)
    assert_almost_eq(godot.distance_to(Vector3(0.0, 0.0, -1.0)), 0.0, DRIFT, "Godot's left edge looks straight ahead")
    assert_almost_eq(blender.distance_to(Vector3(-1.0, 0.0, 0.0)), 0.0, DRIFT, "Blender's looks a quarter turn left")
    var yawed := SaProjection.new(kind, SaProjection.Heading.new(SaProjection.Heading.GODOT, 90.0))
    assert_almost_eq(yawed.to_view(middle, SIZE).distance_to(Vector3(1.0, 0.0, 0.0)), 0.0, DRIFT, "A yaw of 90 turns it right")


func test_equirectangular_and_polar_wrap_in_x_and_flat_does_not() -> void:
    var kinds := _registries.projections
    assert_eq(SaProjection.new(kinds.find(SaProjection.FLAT)).wrapping, SaProjection.Wrap.NONE, "Flat joins no edge")
    assert_eq(
        SaProjection.new(kinds.find(SaProjection.EQUIRECTANGULAR)).wrapping, SaProjection.Wrap.X, "Equirectangular wraps in x"
    )
    assert_eq(SaProjection.new(kinds.find(SaProjection.POLAR)).wrapping, SaProjection.Wrap.X, "Polar wraps in x")
    var past := Vector2(SIZE.x + 3.0, 10.0)
    assert_eq(kinds.find(SaProjection.EQUIRECTANGULAR).fold(past, SIZE), Vector2(3.0, 10.0), "Past the right edge is the left")
    assert_eq(kinds.find(SaProjection.POLAR).fold(past, SIZE), Vector2(3.0, 10.0), "on a disc as well")
    assert_eq(kinds.find(SaProjection.FLAT).fold(past, SIZE), past, "and stays past it on a flat canvas")


func test_a_panorama_folds_over_its_pole_and_stretches_a_dab_towards_it() -> void:
    var sphere := _registries.projections.find(SaProjection.EQUIRECTANGULAR)
    assert_eq(sphere.fold(Vector2(4.0, -2.0), SIZE), Vector2(36.0, 2.0), "Over the top is half a turn round, read down")
    assert_eq(sphere.fold(Vector2(4.0, SIZE.y + 2.0), SIZE), Vector2(36.0, SIZE.y - 2.0), "and over the bottom too")
    assert_almost_eq(sphere.stretch(Vector2(0.0, SIZE.y * 0.5), SIZE), 1.0, DRIFT, "Round at the equator")
    assert_true(sphere.stretch(Vector2(0.0, 2.0), SIZE) > 5.0, "and wide near the pole")
    assert_eq(sphere.stretch(Vector2(0.0, 0.0), SIZE), INF, "and unbounded on it")
    var disc := _registries.projections.find(SaProjection.POLAR)
    assert_almost_eq(disc.stretch(Vector2(0.0, SIZE.x / TAU), SIZE), 1.0, DRIFT, "A disc's ring as long as the width is round")
    assert_eq(disc.stretch(Vector2(0.0, 0.0), SIZE), INF, "and its centre is unbounded")
    assert_eq(_registries.projections.find(SaProjection.FLAT).stretch(Vector2(5.0, 5.0), SIZE), 1.0, "Flat is round everywhere")


func test_a_saved_panorama_opens_with_its_kind_and_orientation() -> void:
    var doc := _easel.document
    var target := SaProjection.new(
        _registries.projections.find(SaProjection.EQUIRECTANGULAR), SaProjection.Heading.new(SaProjection.Heading.GODOT)
    )
    assert_true(SaProjection.assign(doc, target), "Assigned")
    assert_eq(SaExport.save_sad(doc, scratch_path, 0), OK, "It saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, scratch_path, SaCompositor.new()), OK, "and opens")
    assert_eq(loaded.projection.kind.id, SaProjection.EQUIRECTANGULAR, "as equirectangular")
    assert_eq(loaded.projection.orientation.preset, SaProjection.Heading.GODOT, "in Godot's orientation")
    assert_eq(loaded.projection.orientation.yaw, 0.0, "with no yaw")
    var written: Dictionary = _header_of(scratch_path).get(SaProjection.HEADER_KEY, {})
    assert_eq(written.get("kind"), "equirectangular", "which the header names")
    loaded.free()


func test_a_file_written_before_the_key_opens_flat() -> void:
    var doc := _easel.document
    SaProjection.assign(doc, SaProjection.new(_registries.projections.find(SaProjection.POLAR)))
    # Opened over a polar document, so an absent key is seen to mean flat and
    # not to mean keep.
    assert_eq(SaExport.load_sad(doc, ProjectSettings.globalize_path(FIXTURE)), OK, "It opens")
    assert_eq(doc.projection.kind.id, SaProjection.FLAT, "flat")
    assert_true(doc.projection.is_default(), "in the default orientation")
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.NONE, "joining no edge")


func test_a_flat_document_writes_no_key() -> void:
    var doc := _easel.document
    assert_eq(SaExport.save_sad(doc, scratch_path, 0), OK, "It saves")
    assert_false(_header_of(scratch_path).has(SaProjection.HEADER_KEY), "and its header names no projection")


func test_an_assign_is_one_step_that_moves_no_pixel_and_undoes() -> void:
    var doc := _easel.document
    var layer := doc.active_layer
    layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    var before := _texel(layer, Vector2i(5, 7))
    var steps := doc.undo_redo.get_history_count()
    var target := SaProjection.new(_registries.projections.find(SaProjection.EQUIRECTANGULAR))
    assert_true(SaProjection.assign(doc, target), "Assigned")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_false(SaProjection.assign(doc, target), "and assigning it again is no step")
    assert_eq(_texel(layer, Vector2i(5, 7)), before, "no pixel moved")
    doc.undo()
    assert_eq(doc.projection.kind.id, SaProjection.FLAT, "Undo reads the kind it had")
    doc.redo()
    assert_eq(doc.projection.kind.id, SaProjection.EQUIRECTANGULAR, "and redo the one assigned")
