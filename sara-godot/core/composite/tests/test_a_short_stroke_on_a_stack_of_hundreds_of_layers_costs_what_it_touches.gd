## A short stroke on a painting pass's winter painting, 309
## layers, cost 0.77 s through the door and 2437 dispatches, where one on a
## blank document cost 59. The commit marked every chunk the stroke buffered
## dirty whole, and a whole chunk grown by the widest halo in the tree reached
## the four beside it, so the frames after the last dab composited five whole
## chunks under every filter and refreshed every mirror over each. And every
## dab grew its region by the widest halo of the whole stack, hidden layers'
## too, found by a walk of the stack per call.
##
## So the same four frame stroke on a stack of 100 and of 300 layers in groups,
## with a blur and a Mirror effect layer among them and paint in every chunk,
## dispatches at 300 layers no more than a fifth over what it does at 100. And
## the region a dab marks grows by the halos of what reads it and no others: a
## blur beside the stroke adds nothing, a hidden blur adds nothing unless an
## effect layer reads it, a blur on the root does.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(2048, 1024)
const GROUP_EVERY := 30
const BASE: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
## Where the stroke starts, in document pixels, and how far each frame moves it.
const START := Vector2(800.0, 300.0)
const STEP := Vector2(6.0, 1.0)
const RADIUS := 6.0
const INK := Color(0.2, 0.3, 0.6, 1.0)

var _types: SaLayerTypeRegistry
var _blur_key: String


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## A painting of *depth* layers, each painted in one chunk so every chunk of the
## canvas holds paint of many, wrapped in groups of thirty, a blur on a layer a
## third of the way up and a Mirror effect layer reading the second group, and
## an empty layer in that group, active, for the stroke.
func _painting(depth: int) -> SaEasel:
    var easel := Bench.easel(SIZE)
    var registry := easel.compositor.filter_chain.registry
    var blur := SaGaussianBlurFilter.new()
    registry.register(blur, BASE)
    registry.register(MirrorFilter.new(), BASE)
    _blur_key = SaFilterRegistry.key_for(BASE, blur)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(doc.get_node("Background") as SaLayer)
    var grid := SaLayer.grid_positions(SIZE)
    var members: Array[SaLayer] = []
    for index in range(1, depth):
        var layer := ops.add()
        layer.name = "L%d" % index
        _paint(layer, grid[(index * 5) % grid.size()], Color(float(index % 7) / 7.0, 0.4, 0.5, 0.25))
        members.append(layer)
        if index == floori(depth / 3.0):
            assert_not_null(SaFilterOps.new(doc).attach(layer, _blur_key, {"radius": 9.0}), "A blur attaches to %s" % layer.name)
        if members.size() == GROUP_EVERY:
            var group := ops.group_layers(members)
            members.clear()
            if index == GROUP_EVERY * 2:
                doc.set_active_layer(group)
                var mirror := ops.add(SaEffectLayer.TYPE_ID, _types)
                mirror.name = "Mirror"
                assert_not_null(SaFilterOps.new(doc).attach(mirror, MIRROR, {}), "The Mirror attaches to its effect layer")
    doc.set_active_layer(doc.get_node("L45") as SaLayer)
    var ink := ops.add()
    ink.name = "Ink"
    doc.set_active_layer(ink)
    assert_true(SaEffectLayer.reads(doc.get_node("Mirror") as SaLayer, ink, 0), "The Mirror reads the layer the stroke paints")
    Bench.composite(easel)
    return easel


## *layer*'s chunk at *grid_pos* filled with *fill*.
static func _paint(layer: SaLayer, grid_pos: Vector2i, fill: Color) -> void:
    var texture := layer.get_or_create_chunk(grid_pos).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.x, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The four frame stroke, a dab and a composite a frame and the commit's
## composite after, and the dispatches it took.
static func _stroke(easel: SaEasel) -> int:
    var doc := easel.document
    var before := SaCompute.dispatches
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    for frame in 4:
        _dab(doc, START + STEP * float(frame))
        easel.process_pending_composite()
    doc.commit_stroke()
    easel.process_pending_composite()
    return SaCompute.dispatches - before


static func _dab(doc: SaDocument, pos: Vector2) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - RADIUS, pos.y - RADIUS, RADIUS * 2.0, RADIUS * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, INK, RADIUS, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()


func test_the_stroke_at_300_layers_dispatches_at_most_a_fifth_over_the_one_at_100() -> void:
    var shallow := _painting(100)
    _stroke(shallow)
    var at_100 := _stroke(shallow)
    shallow.free()
    var deep := _painting(300)
    _stroke(deep)
    var at_300 := _stroke(deep)
    deep.free()
    print("the four frame stroke dispatched %d at 100 layers and %d at 300" % [at_100, at_300])
    assert_true(at_100 > 0, "The stroke at 100 layers dispatches")
    assert_true(
        float(at_300) <= float(at_100) * 1.2,
        "and the one at 300 layers no more than a fifth over it, %d against %d" % [at_300, at_100]
    )


## The region one dab at *at* marks, spread through *doc*'s filters, in the
## chunk it lands in.
static func _marked(doc: SaDocument, at: SaLayer) -> Rect2i:
    var regions: Dictionary[Vector2i, Rect2i] = {Vector2i(3, 1): Rect2i(32, 32, 16, 16)}
    var out := SaStaleSpread.new().spread(doc, doc.root_filters, regions, SIZE, at)
    return out.get(Vector2i(3, 1), Rect2i())


func test_a_dab_grows_by_the_halos_of_what_reads_it_and_no_others() -> void:
    var easel := _painting(100)
    var doc := easel.document
    var ink := doc.get_node("Ink") as SaLayer
    var mirrored := doc.get_node("L%d" % 33) as SaLayer
    var blurred := doc.get_node("L75") as SaLayer
    assert_not_null(SaFilterOps.new(doc).attach(blurred, _blur_key, {"radius": 9.0}), "A blur attaches to the layer")
    Bench.composite(easel)
    var painted := Rect2i(32, 32, 16, 16)
    assert_eq(_marked(doc, ink), painted, "A dab beside the blurred layers grows by no halo")
    assert_true(_marked(doc, blurred).encloses(painted.grow(9)), "while one on a blurred layer grows by its halo")
    var ops := SaLayerOps.new(doc)
    ops.set_visible(blurred, false)
    assert_eq(_marked(doc, blurred), painted, "and on it hidden, by none")
    ops.set_visible(mirrored, false)
    assert_true(_marked(doc, mirrored).encloses(painted.grow(9)), "but a hidden blurred layer the Mirror reads keeps its halo")
    assert_not_null(SaFilterOps.new(doc).attach(null, _blur_key, {"radius": 5.0}), "A blur attaches to the root")
    Bench.composite(easel)
    assert_true(_marked(doc, ink).encloses(painted.grow(5)), "and a dab anywhere grows by the root's halo")
    easel.free()
