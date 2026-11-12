## What a stroke on a deep painting still cost, past the composite,
## was the Layers docker. Every dab marked all 300 rows'
## pictures, so the rows in view redrew a picture each a quarter second for
## 9 to 13 ms a frame, and the 300 rows each ran `_process` every frame, shown
## or scrolled away. The commit then asked whether the rows matched the stack
## and drew every row again, 33 ms a stroke.
##
## So a four frame stroke on a stack of 300 layers with the docker built marks
## the row of the layer painted and no other on every frame, its commit marks
## that row with the Mirror effect layer's, whose picture is what it makes of
## the layers it reads, and a change outside a stroke still marks every row. A
## row marked while scrolled out of sight stops processing until a scroll asks
## again.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(2048, 1024)
const DEPTH := 300
const GROUP_EVERY := 30
const MIRROR: StringName = &"sara-base-modules.mirror"
const START := Vector2(800.0, 300.0)
const STEP := Vector2(6.0, 1.0)
const RADIUS := 6.0
const INK := Color(0.2, 0.3, 0.6, 1.0)

var _easel: SaEasel
var _canvas: SaCanvas
var _docker: LayersDocker


func before_each() -> void:
    _easel = _painting()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    SaLayerList.settle_thumbnails(_docker)


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()


## A painting of [constant DEPTH] layers, each painted in one chunk, wrapped in
## groups of thirty, with a Mirror effect layer over the second group reading
## an empty layer in it, Ink, which is active for the stroke.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(MirrorFilter.new(), &"sara-base-modules")
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var types := Fixtures.make_registries().layer_types
    var grid := SaLayer.grid_positions(SIZE)
    var members: Array[SaLayer] = []
    for index in range(1, DEPTH):
        var layer := ops.add()
        layer.name = "L%d" % index
        _paint(layer, grid[(index * 5) % grid.size()], Color(float(index % 7) / 7.0, 0.4, 0.5, 0.25))
        members.append(layer)
        if members.size() == GROUP_EVERY:
            var group := ops.group_layers(members)
            members.clear()
            if index == GROUP_EVERY * 2:
                doc.set_active_layer(group)
                var mirror := ops.add(SaEffectLayer.TYPE_ID, types)
                mirror.name = "Mirror"
                SaFilterOps.new(doc).attach(mirror, MIRROR, {})
    doc.set_active_layer(doc.get_node("L45") as SaLayer)
    ops.add().name = "Ink"
    doc.set_active_layer(doc.get_node("Ink") as SaLayer)
    Bench.composite(easel)
    return easel


static func _paint(layer: SaLayer, grid_pos: Vector2i, fill: Color) -> void:
    var texture := layer.get_or_create_chunk(grid_pos).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.x, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


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


## The names of the layers whose rows hold a picture marked to redraw, and the
## pictures settled after, as a frame that draws them leaves them.
func _touched() -> PackedStringArray:
    var names := PackedStringArray()
    var list: SaLayerList = _docker.item_list
    for index in list.rows.size():
        var row: SaRowFrame = list.rows[index]
        if is_instance_valid(row.thumb) and row.thumb._dirty:
            var layer: SaLayer = list.layer_at(index)
            names.append(str(layer.name) if layer != null else "a filter's row")
    SaLayerList.settle_thumbnails(_docker)
    return names


func test_each_frame_of_a_stroke_touches_the_row_of_the_layer_painted_alone() -> void:
    var doc := _easel.document
    assert_true(_docker.item_list.rows.size() >= DEPTH, "the docker holds a row a layer, %d" % _docker.item_list.rows.size())
    assert_eq(_touched().size(), 0, "and every picture is drawn before the stroke")
    var follows: Array[int] = [0]
    var count := func() -> void: follows[0] += 1
    _docker.list_keeper.followed.connect(count)
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    for frame in 4:
        _dab(doc, START + STEP * float(frame))
        _easel.process_pending_composite()
        assert_eq(_touched(), PackedStringArray(["Ink"]), "frame %d of the stroke touches the Ink row alone" % frame)
    doc.commit_stroke()
    _easel.process_pending_composite()
    var committed := _touched()
    committed.sort()
    assert_eq(committed, PackedStringArray(["Ink", "Mirror"]), "the commit touches the Ink row and the Mirror that reads it")
    _docker.list_keeper.followed.disconnect(count)
    assert_eq(follows[0], 1, "and the docker follows the stroke once, at its end")


func test_a_change_outside_a_stroke_touches_every_row() -> void:
    var doc := _easel.document
    doc.invalidate_chunks([Vector2i(1, 1)])
    assert_eq(_touched().size(), _docker.item_list.rows.size(), "a change no stroke made marks every row")


## The list is hung on a plain control on the EventBus, as the tooltip suite
## hangs its labels, because the runner's root takes no child while it readies
## the suites, and the docker is a window that would open one of its own.
func test_a_row_scrolled_out_of_sight_stops_processing_until_a_scroll() -> void:
    var list: SaLayerList = _docker.item_list
    var home := list.get_parent()
    var host := Control.new()
    EventBus.add_child(host)
    list.reparent(host)
    list.size = Vector2(300.0, 300.0)
    for _frame in 3:
        await (Engine.get_main_loop() as SceneTree).process_frame
    var last: SaRowFrame = null
    for row: SaRowFrame in list.rows:
        if row.is_visible_in_tree() and (last == null or row.global_position.y > last.global_position.y):
            last = row
    assert_true(
        list.size.y > 0.0 and list.get_v_scroll_bar().max_value > list.size.y,
        "the list scrolls, %s tall of %s, the docker %s" % [list.size, list.get_v_scroll_bar().max_value, _docker.size]
    )
    _easel.document.invalidate_chunks([Vector2i(1, 1)])
    assert_true(last.thumb.is_processing(), "a marked row asks whether it is shown")
    last.thumb._process(SaLayerThumbnail.REFRESH_SECONDS)
    assert_false(last.thumb.is_processing(), "and the lowest row shown, out of sight below the fold, stops asking")
    assert_true(last.thumb._dirty, "still owing its picture")
    list.scroll_vertical = int(list.get_v_scroll_bar().max_value)
    assert_true(last.thumb.is_processing(), "a scroll wakes it")
    list.reparent(home)
    host.free()
