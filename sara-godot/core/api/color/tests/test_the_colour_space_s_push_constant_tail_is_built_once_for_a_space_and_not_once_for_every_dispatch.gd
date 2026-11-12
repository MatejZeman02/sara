## The colour space's push constant tail is built once for a
## space and not once for every dispatch.
##
## A space keeps the tail it built and hands it back while the fields it was
## built from read the same. These read the kept tail against one built by the
## old path, copied here as it stood, for every space the app offers, then after
## each field is written, and last count the builds a composite of thirty
## painted layers on twelve chunks costs.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Four chunks by three at the chunk size the app runs at.
const CHUNKS := Vector2i(4, 3)
const LAYERS := 30


## The tail as `SaColorSpacePushConstant.to_push_constant` built it,
## for every call: both matrices, the curve's four numbers, the coordinates and
## a zero. A plain copy, so the suite reads the old answer and not the new code.
static func _old_tail(space: SaColorSpace) -> PackedFloat32Array:
    var packed := PackedFloat32Array()
    for basis: Basis in [space.to_linear_srgb_matrix(), space.from_linear_srgb_matrix()]:
        for column: Vector3 in SaColorSpaceGlsl.basis_columns(basis):
            packed.append(column.x)
            packed.append(column.y)
            packed.append(column.z)
    packed.append_array(space.transfer.to_params())
    packed.append(float(space.coordinates))
    packed.append(0.0)
    return packed


## Whether *got* is *want* float for float, compared as bytes so a sign of zero
## or a NaN reads as the bits it is.
func _same_tail(got: PackedFloat32Array, want: PackedFloat32Array, what: String) -> void:
    assert_eq(got.size(), SaColorSpace.PUSH_CONSTANT_FLOATS, "%s: the tail is not larger" % what)
    assert_eq(got.to_byte_array(), want.to_byte_array(), "%s: the tail is the old path's, bit for bit" % what)


func test_every_space_the_app_offers_gives_the_old_tail() -> void:
    for space: SaColorSpace in SaColorSpace.presets():
        _same_tail(space.to_push_constant(), _old_tail(space), "%s first read" % space.id)
        _same_tail(space.to_push_constant(), _old_tail(space), "%s kept" % space.id)


func test_a_second_read_builds_nothing() -> void:
    var space := SaColorSpace.display_p3()
    var before := SaColorSpacePushConstant.builds
    space.to_push_constant()
    assert_eq(SaColorSpacePushConstant.builds - before, 1, "The first read builds the tail")
    for i in 10:
        space.to_push_constant()
    assert_eq(SaColorSpacePushConstant.builds - before, 1, "and ten more read the kept one")


func test_a_caller_writing_into_its_tail_leaves_the_kept_one_alone() -> void:
    var space := SaColorSpace.acescg()
    var tail := space.to_push_constant()
    tail[0] = 99.0
    tail.append(1.0)
    _same_tail(space.to_push_constant(), _old_tail(space), "after a caller wrote into its copy")


func test_a_field_written_after_a_first_read_gives_the_tail_of_its_present_value() -> void:
    var writes := {
        "primaries": func(s: SaColorSpace) -> void: s.primaries = SaColorSpace.display_p3().primaries,
        "a primary in place": func(s: SaColorSpace) -> void: s.primaries[1] = Vector2(0.265, 0.690),
        "white": func(s: SaColorSpace) -> void: s.white = SaColorSpace.WHITE_D60,
        "transfer": func(s: SaColorSpace) -> void: s.transfer = SaTransferFunction.gamma22(),
        "slope": func(s: SaColorSpace) -> void: s.transfer.slope = 4.5,
        "threshold": func(s: SaColorSpace) -> void: s.transfer.threshold = 0.081,
        "gain": func(s: SaColorSpace) -> void: s.transfer.gain = 1.099,
        "exponent": func(s: SaColorSpace) -> void: s.transfer.exponent = 2.2,
        "coordinates": func(s: SaColorSpace) -> void: s.coordinates = SaColorSpace.Coordinates.OKLAB,
    }
    for named: String in writes:
        var space := SaColorSpace.srgb()
        var first := space.to_push_constant()
        _same_tail(first, _old_tail(space), "%s before" % named)
        (writes[named] as Callable).call(space)
        var after := space.to_push_constant()
        _same_tail(after, _old_tail(space), "%s after" % named)
        assert_false(after == first, "Writing %s changes the tail" % named)


## A document of *space*, thirty layers over the background each painted on
## every one of its twelve chunks.
func _painted(space: SaColorSpace) -> SaEasel:
    var side := SaChunk.SIZE
    var easel := SaEasel.create_default(CHUNKS * side, null, space)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var positions := SaLayer.grid_positions(CHUNKS * side)
    assert_eq(positions.size(), 12, "The document is twelve chunks")
    for i in LAYERS:
        var layer := ops.add()
        layer.opacity = 0.5
        for grid_pos: Vector2i in positions:
            _paint(layer.get_or_create_chunk(grid_pos).albedo(), Color(0.02 * i, 0.5, 1.0 - 0.02 * i, 1.0))
    return easel


func _paint(texture: SaTexture, fill: Color) -> void:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func test_a_composite_of_thirty_layers_on_twelve_chunks_builds_once_per_space() -> void:
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.display_p3(), SaColorSpace.oklab()]:
        var easel := _painted(space)
        var builds := SaColorSpacePushConstant.builds
        var dispatches := SaCompute.dispatches
        easel.document.update_caches()
        easel.request_full_composite()
        easel.process_pending_composite()
        var ran := SaCompute.dispatches - dispatches
        var built := SaColorSpacePushConstant.builds - builds
        assert_true(ran >= LAYERS * 12, "%s: the composite ran a dispatch per layer and chunk, %d" % [space.id, ran])
        # The document's space, and the sRGB a pass with no space of its own
        # packs, which is built once for the whole process.
        assert_true(built <= 2, "%s: the tail was built %d times over %d dispatches" % [space.id, built, ran])
        builds = SaColorSpacePushConstant.builds
        easel.request_full_composite()
        easel.process_pending_composite()
        assert_eq(SaColorSpacePushConstant.builds - builds, 0, "%s: a second composite builds none" % space.id)
        easel.free()
