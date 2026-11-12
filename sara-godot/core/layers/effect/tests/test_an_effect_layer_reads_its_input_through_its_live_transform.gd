## An effect layer reads its input as it is drawn, through the
## input's live transform, so a move, a turn, a scale and the Crop tool's crop
## all reach the effect.
##
## Bug 3 of the hunt of 2026-10-08: `SaEffectLayer._drawn_input` read the
## input's own chunk at the same grid position, where its paint was painted, so
## a move or a crop left the effect's kaleidoscope that of the untouched photo
## while a kaleidoscope on the root followed the move. The effect now reads the
## cache of the input's map, as the canvas draws the input.
##
## The painting is four chunks across and three down, the grey background
## hidden, and a layer named Source holding a tint of its own in every chunk.
## The effect layer above it reads Source with Source hidden, so the canvas is
## the effect alone, as in the sibling suite. Every composite after the first is the
## pending one, so what a change invalidated is all the refresh is handed, as in
## the running app.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const GRID := Vector2i(4, 3)
const KALEIDOSCOPE: StringName = &"kaleidoscope.kaleidoscope"
const EIGHT_MIRRORS := {"mirrors": 8, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}
## The hunt's move, 300 pixels right.
const MOVE := Vector2(300.0, 0.0)
## The hunt's crop, `{"crop": {"from": [200, 150], "to": [1100, 900]}}`, kept
## inside this smaller canvas and off its middle.
const BOX := Rect2i(200, 150, 600, 450)
const TOLERANCE := 1.0e-4
## The largest difference of a channel between the effect's kaleidoscope and
## the root's, both drawn from one cache.
const SAME := 1.0e-3
## Where the hunt's move leaves nothing, and where it takes the paint of
## LEFT_BEHIND, both well inside a chunk.
const LEFT_BEHIND := Vector2i(100, 100)
const MOVED_TO := Vector2i(400, 100)


## The fixture invert declaring that it reads its input's paint alone, as the
## base module's Mirror does, so the suite reaches that read with no module.
class InvertAlone:
    extends "res://tests/fixtures/modules/point-fixture/invert_filter.gd"

    func title() -> String:
        return "Point Fixture Invert Alone"

    func reads_paint_alone() -> bool:
        return true


var _presets_dir: String = ""


func before_each() -> void:
    # First, so the filters made below carry nothing into a painter's store.
    _presets_dir = SaDataRoot.path("test_p3_live_input_presets_%d" % OS.get_process_id())
    SaFilterPreset.root = _presets_dir
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for owner: StringName in [&"kaleidoscope", Bench.OWNER]:
        DirAccess.remove_absolute(SaFilterPreset.store_for(owner).dir)
    DirAccess.remove_absolute(_presets_dir)
    SaFilterPreset.root = SaFilterPreset.default_root()


## The tint of the chunk at *grid_pos*, opaque.
static func _tint(grid_pos: Vector2i) -> Color:
    return Color(float(grid_pos.x) / GRID.x, float(grid_pos.y) / GRID.y, 0.5, 1.0)


static func _inverted(color: Color) -> Color:
    return Color(1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a)


## The painting of the header with *key* on an effect layer reading Source,
## or with *on_root* on the root and no effect layer, composited once.
func _painting(key: StringName, on_root: bool = false) -> SaEasel:
    var easel := Bench.easel(GRID * SaChunk.SIZE)
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    easel.compositor.filter_chain.registry.register(Kaleidoscope.new(), &"kaleidoscope")
    easel.compositor.filter_chain.registry.register(InvertAlone.new(), Bench.OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    for y in GRID.y:
        for x in GRID.x:
            source.get_or_create_chunk(Vector2i(x, y)).clear(_tint(Vector2i(x, y)))
    var values: Dictionary = EIGHT_MIRRORS if key == KALEIDOSCOPE else {}
    if on_root:
        assert_not_null(SaFilterOps.new(doc).attach(null, key, values), "%s attaches to the root" % key)
    else:
        var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
        effect.name = "Effect"
        assert_true(SaEffectLayer.input_of(effect) == source, "The effect layer made above Source reads it")
        assert_not_null(SaFilterOps.new(doc).attach(effect, key, values), "%s attaches to the effect layer" % key)
        source.visible = false
        doc.set_active_layer(source)
    Bench.composite(easel)
    return easel


## Draws Source through *map* as the Transform tool's one step does, and
## composites what that invalidated.
static func _transformed(easel: SaEasel, map: Basis) -> bool:
    var doc := easel.document
    var put := SaLiveTransform.put(doc, doc.get_node("Source") as SaLayer, map)
    easel.process_pending_composite()
    return put


## Crops Source to *box* as the Crop tool does, its box drawn and then Enter,
## and composites what that invalidated.
static func _cropped(easel: SaEasel, box: Rect2i) -> bool:
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var before := SaLiveTransform.of(source)
    var shown := SaLiveTransform.crop_to(doc, source, box)
    var committed := SaLiveTransform.commit(doc, source, before)
    easel.process_pending_composite()
    return shown and committed


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _keys(chunks: Dictionary) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    found.assign(chunks.keys())
    found.sort()
    return found


static func _near(a: Color, b: Color, within: float = TOLERANCE) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= within


## The largest difference of a channel between the outputs of *one* and
## *other*, read every eighth texel each way.
static func _largest_difference(one: SaEasel, other: SaEasel) -> float:
    var a := _bytes(one.output)
    var b := _bytes(other.output)
    var size := one.output.size
    var largest := 0.0
    for y in range(0, size.y, 8):
        for x in range(0, size.x, 8):
            var index := y * size.x + x
            var p := SaFieldSpec.decode_texel(a, one.output.format, index)
            var q := SaFieldSpec.decode_texel(b, other.output.format, index)
            largest = maxf(largest, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return largest


## Whether the effect's kaleidoscope after *change* is the root's after the
## same change, the two ways of applying one filter the hunt found disagreeing.
func _agrees_with_the_root(change: Callable, what: String) -> void:
    var on_effect := _painting(KALEIDOSCOPE)
    var on_root := _painting(KALEIDOSCOPE, true)
    var untouched := _bytes(on_effect.output)
    assert_true(change.call(on_effect), "%s on the effect layer's input" % what)
    assert_true(change.call(on_root), "%s under the root's kaleidoscope" % what)
    assert_true(_bytes(on_effect.output) != untouched, "%s changes the effect's kaleidoscope" % what)
    var largest := _largest_difference(on_effect, on_root)
    assert_true(largest <= SAME, "%s: the effect's kaleidoscope is the root's, largest difference %f" % [what, largest])
    on_effect.free()
    on_root.free()


func test_a_move_reaches_the_effect_where_the_moved_paint_shows() -> void:
    var easel := _painting(Bench.INVERT)
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(
        _near(Bench.texel(easel.output, LEFT_BEHIND), _inverted(_tint(Vector2i.ZERO))),
        "Before the move the effect inverts Source"
    )
    assert_true(_transformed(easel, SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "Source is moved")
    var cache := SaLiveTransform.paint_of(source)
    assert_true(cache != source, "Source is drawn through the cache of its map")
    assert_eq(_keys(effect.chunks), _keys(cache.chunks), "The effect holds a chunk where the moved paint shows and nowhere else")
    var left := Bench.texel(easel.output, LEFT_BEHIND)
    assert_true(left.a <= TOLERANCE, "Where the move took the paint from, the effect shows nothing, %s" % left)
    var moved := Bench.texel(easel.output, MOVED_TO)
    var want := _inverted(_tint(Vector2i.ZERO))
    assert_true(_near(moved, want), "Where it took it to, the effect inverts the moved paint, %s against %s" % [moved, want])
    var pending := _bytes(easel.output)
    Bench.composite(easel)
    assert_eq(_bytes(easel.output), pending, "and the canvas is the one a full composite draws")
    easel.free()


func test_the_effect_s_kaleidoscope_follows_a_move_as_the_root_s_does() -> void:
    _agrees_with_the_root(
        _transformed.bind(SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "A move of 300 right"
    )


func test_a_turn_and_a_scale_reach_the_effect() -> void:
    var middle := Vector2(GRID * SaChunk.SIZE) / 2.0
    var map := SaLiveTransform.composed(Vector2(40.0, -20.0), 30.0, Vector2(0.75, 0.75), middle)
    _agrees_with_the_root(_transformed.bind(map), "A turn of 30 degrees and a scale to three quarters")


func test_the_crop_tool_s_crop_reaches_the_effect() -> void:
    var easel := _painting(Bench.INVERT)
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(_cropped(easel, BOX), "Source is cropped to the box")
    assert_eq(
        _keys(effect.chunks),
        _keys(SaLiveTransform.paint_of(source).chunks),
        "The effect holds a chunk where the cropped paint shows"
    )
    var last := BOX.end - Vector2i.ONE
    for at: Vector2i in [BOX.position, last, BOX.get_center()]:
        var shown := Bench.texel(easel.output, at)
        var want := _inverted(_tint(Vector2i((Vector2(at) / SaChunk.SIZE).floor())))
        assert_true(_near(shown, want), "Inside the crop at %s the effect inverts Source, %s against %s" % [at, shown, want])
    for at: Vector2i in [BOX.position - Vector2i.ONE, last + Vector2i.ONE, Vector2i(10, 10), Vector2i(1000, 700)]:
        var shown := Bench.texel(easel.output, at)
        assert_true(shown.a <= TOLERANCE, "Outside the crop at %s the effect shows nothing, %s" % [at, shown])
    easel.free()
    _agrees_with_the_root(_cropped.bind(BOX), "The Crop tool's crop")


func test_undo_puts_the_effect_back_on_the_paint_as_it_was_painted() -> void:
    var easel := _painting(KALEIDOSCOPE)
    var doc := easel.document
    var untouched := _bytes(easel.output)
    assert_true(_transformed(easel, SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "Source is moved")
    var moved := _bytes(easel.output)
    assert_true(moved != untouched, "The move changes the effect's kaleidoscope")
    assert_true(doc.undo(), "The move is one step")
    doc.update_caches()
    easel.process_pending_composite()
    assert_eq(_bytes(easel.output), untouched, "whose undo puts the kaleidoscope of the untouched painting back")
    assert_true(doc.redo(), "and the redo")
    doc.update_caches()
    easel.process_pending_composite()
    assert_eq(_bytes(easel.output), moved, "the moved one")
    easel.free()


func test_a_group_input_reads_its_moved_member_where_it_shows() -> void:
    var easel := _painting(Bench.INVERT)
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    doc.set_active_layer(source)
    var group := SaLayerOps.new(doc).group_active()
    assert_not_null(group, "Source is put in a group")
    doc.set_active_layer(source)
    source.visible = true
    assert_true(SaEffectLayer.read(doc, effect, group), "The effect reads the group")
    group.visible = false
    easel.process_pending_composite()
    assert_true(_transformed(easel, SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "Source is moved inside it")
    assert_eq(
        _keys(effect.chunks),
        _keys(SaLiveTransform.paint_of(source).chunks),
        "The effect holds a chunk where the moved member shows"
    )
    var left := Bench.texel(easel.output, LEFT_BEHIND)
    assert_true(left.a <= TOLERANCE, "and nothing where it was painted, %s" % left)
    var moved := Bench.texel(easel.output, MOVED_TO)
    assert_true(_near(moved, _inverted(_tint(Vector2i.ZERO))), "The group's moved member shows inverted, %s" % moved)
    easel.free()


func test_an_effect_that_reads_paint_alone_reads_the_moved_paint() -> void:
    var easel := _painting(SaFilterRegistry.key_for(Bench.OWNER, InvertAlone.new()))
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(
        SaEffectLayer.reads_paint_alone(effect, easel.compositor.filter_chain.registry), "The effect reads Source's paint alone"
    )
    var want := _inverted(_tint(Vector2i.ZERO))
    assert_true(_near(Bench.texel(easel.output, LEFT_BEHIND), want), "Unmoved, it inverts Source where it was painted")
    assert_true(_transformed(easel, SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "Source is moved")
    var left := Bench.texel(easel.output, LEFT_BEHIND)
    assert_true(left.a <= TOLERANCE, "Moved, nothing shows where the paint was painted, %s" % left)
    var moved := Bench.texel(easel.output, MOVED_TO)
    assert_true(_near(moved, want), "and the moved paint shows inverted, %s" % moved)
    easel.free()
