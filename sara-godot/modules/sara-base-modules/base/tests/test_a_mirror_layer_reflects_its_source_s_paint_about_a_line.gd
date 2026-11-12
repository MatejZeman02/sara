## A mirror layer, an effect layer whose first record is the
## base module's Mirror, reflects its source's paint about a line and reads
## that paint alone, never the source's records or its mask (a mirror
## reads paint only).
##
## The painting: four chunks a side, the background hidden, a layer named Boat
## holding a red mark above the canvas's middle, and the mirror layer made
## above it. Where the boat carries a filter and a mask, the filter turns its
## paint blue and the mask hides the mark's left half, and the reflection is
## red and whole all the same.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const HUE: StringName = &"sara-base-modules.hue_saturation_lightness"
const SIZE := Vector2i(1024, 1024)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Across the edge between the chunks at (0, 1) and (1, 1), above the line
## through the canvas's middle at y 512, so its rows 300 to 339 reflect to rows
## 723 down to 684.
const MARK := Rect2i(200, 300, 112, 40)
## The hue turn that takes the red mark to a blue.
const TO_BLUE := -125.0
const TOLERANCE := 1.0e-3

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## An easel whose compositor answers the Mirror and the Hue/Saturation of the
## base module beside the fixture invert.
static func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var filters := easel.compositor.filter_chain.registry
    filters.register(MirrorFilter.new(), OWNER)
    filters.register(SaHueSaturationLightnessFilter.new(), OWNER)
    return easel


## The painting of the header, the boat holding *marks* in red, and when
## *dressed* a hue turn to blue on the boat and a mask hiding the chunk that
## holds the mark's left half. The mirror layer reads the boat through
## *values*.
func _painting(marks: Array[Rect2i], dressed: bool, values: Dictionary = {}) -> SaEasel:
    var easel := _easel()
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var boat := doc.get_node("Layer 1") as SaLayer
    boat.name = "Boat"
    doc.set_active_layer(boat)
    for mark in marks:
        _paint(boat, mark, RED)
    if dressed:
        assert_not_null(SaFilterOps.new(doc).attach(boat, HUE, {"hue": TO_BLUE}), "The hue turn attaches to the boat")
        boat.add_mask(1.0).get_or_create(Vector2i(0, 1)).clear(Color(0.0, 0.0, 0.0, 0.0))
    var mirror := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    mirror.name = "Mirror"
    assert_not_null(SaFilterOps.new(doc).attach(mirror, MIRROR, values), "The Mirror attaches to the effect layer")
    doc.set_active_layer(boat)
    Bench.composite(easel)
    return easel


## Writes *colour* over *area*, in document pixels, into *layer*'s chunks,
## making the chunks it needs, and answers the regions it wrote, grid position
## to chunk-local rectangle.
static func _paint(layer: SaLayer, area: Rect2i, colour: Color) -> Dictionary[Vector2i, Rect2i]:
    var rd := GlobalShaderCompiler.get_rd()
    var written: Dictionary[Vector2i, Rect2i] = {}
    var side := SaChunk.SIZE
    var first := Vector2i((Vector2(area.position) / side).floor())
    var last := Vector2i((Vector2(area.end - Vector2i.ONE) / side).floor())
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid_pos := Vector2i(gx, gy)
            var part := area.intersection(Rect2i(grid_pos * side, Vector2i(side, side)))
            var local := Rect2i(part.position - grid_pos * side, part.size)
            var texture := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
            var bytes := rd.texture_get_data(texture.rid, 0)
            var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
            var one := SaTexture.new(Vector2i.ONE, texture.format)
            one.clear(colour)
            var paint := rd.texture_get_data(one.rid, 0)
            for y in range(local.position.y, local.end.y):
                for x in range(local.position.x, local.end.x):
                    var at := (y * texture.size.x + x) * texel
                    for i in texel:
                        bytes[at + i] = paint[i]
            rd.texture_update(texture.rid, 0, bytes)
            written[grid_pos] = local
    return written


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(child)
    return found


## The dispatches the kernels named *kernel* have taken so far.
static func _tally(kernel: String) -> int:
    var count := 0
    for key: String in SaCompute.by_kernel:
        if key.ends_with("/" + kernel):
            count += int((SaCompute.by_kernel[key] as Dictionary)["dispatches"])
    return count


## The chunks of the canvas whose bytes differ between *before* and *after*,
## two reads of an output of *format*, sorted.
static func _changed(before: PackedByteArray, after: PackedByteArray, format: int) -> Array[Vector2i]:
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(format, 16) as int
    var side := SaChunk.SIZE
    var found: Array[Vector2i] = []
    var grid := Vector2i((Vector2(SIZE) / side).ceil())
    for gy in grid.y:
        for gx in grid.x:
            for y in range(gy * side, (gy + 1) * side):
                var at := (y * SIZE.x + gx * side) * texel
                if before.slice(at, at + side * texel) != after.slice(at, at + side * texel):
                    found.append(Vector2i(gx, gy))
                    break
    return found


## The chunks *area* touches, sorted.
static func _chunks_of(area: Rect2i) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    var side := float(SaChunk.SIZE)
    var first := Vector2i((Vector2(area.position) / side).floor())
    var last := Vector2i((Vector2(area.end - Vector2i.ONE) / side).floor())
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            if Rect2i(Vector2i.ZERO, Vector2i((Vector2(SIZE) / side).ceil())).has_point(Vector2i(gx, gy)):
                found.append(Vector2i(gx, gy))
    return found


## *area* reflected across the level line through the canvas's middle.
static func _level(area: Rect2i) -> Rect2i:
    return Rect2i(area.position.x, SIZE.y - area.end.y, area.size.x, area.size.y)


## Where the red shows in *texture* inside *window*, as the middle of its
## texels weighed by how much of them it covers.
static func _centroid(texture: SaTexture, window: Rect2i) -> Vector2:
    var bytes := _bytes(texture)
    var sum := Vector2.ZERO
    var weight := 0.0
    for y in range(window.position.y, window.end.y):
        for x in range(window.position.x, window.end.x):
            var shown := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            var red := shown.r * shown.a
            sum += (Vector2(x, y) + Vector2(0.5, 0.5)) * red
            weight += red
    return sum / weight if weight > 0.0 else Vector2(-1.0, -1.0)


## Paints *area* red on the hidden boat of *easel* and redraws what that
## dirtied, answering the Mirror's dispatches and the chunks of the canvas that
## changed.
func _dab(easel: SaEasel, area: Rect2i) -> Dictionary:
    var doc := easel.document
    var boat := doc.get_node("Boat") as SaLayer
    var before := _bytes(easel.output)
    var written := _paint(boat, area, RED)
    doc.invalidate_chunk_regions(written)
    var ran := _tally("mirror")
    easel.process_pending_composite()
    return {"dispatches": _tally("mirror") - ran, "changed": _changed(before, _bytes(easel.output), easel.output.format)}


## Whether what the redraw shows is what a composite of everything gives.
func _matches_everything(easel: SaEasel) -> bool:
    var shown := _bytes(easel.output)
    Bench.composite(easel)
    return shown == _bytes(easel.output)


func test_the_reflection_is_the_paint_red_and_whole_past_the_boats_filter_and_mask() -> void:
    var easel := _painting([MARK], true)
    var doc := easel.document
    var mirror := doc.get_node("Mirror") as SaLayer
    var boat := doc.get_node("Boat") as SaLayer
    assert_true(mirror.is_effect() and mirror.source == boat, "The mirror layer reads the boat it was made above")
    assert_true(SaEffectLayer.reads_paint_alone(mirror, easel.compositor.filter_chain.registry), "and reads its paint alone")
    var masked := Bench.texel(easel.output, Vector2i(220, 320))
    var shown := Bench.texel(easel.output, Vector2i(290, 320))
    assert_true(masked.a <= TOLERANCE, "The boat's mask hides the mark's left half, %s" % masked)
    assert_true(shown.a > 0.99 and shown.b > shown.r + 0.2, "and its filter turns the right half blue, %s" % shown)
    for x: int in [204, 220, 250, 260, 290, 308]:
        for y: int in [684, 700, 723]:
            var reflected := Bench.texel(easel.output, Vector2i(x, y))
            assert_true(_near(reflected, RED), "The reflection at (%d, %d) is the red paint, %s" % [x, y, reflected])
    var below := Bench.texel(easel.output, Vector2i(250, 724))
    var above := Bench.texel(easel.output, Vector2i(250, 683))
    assert_true(below.a <= TOLERANCE and above.a <= TOLERANCE, "and it ends on the rows the formula puts its edges on")
    var across := MirrorFilter.reflected(Vector2(250.5, 300.5), Vector2(512, 512), Vector2.RIGHT)
    assert_eq(across, Vector2(250.5, 723.5), "row 300 reflects to row 723")
    easel.free()


## A group read is its members drawn without the group's own records and mask:
## the hue turn and the mask sit on a group around the boat this time.
func test_a_group_is_read_as_its_members_without_its_own_filter_and_mask() -> void:
    var easel := _painting([MARK], false)
    var doc := easel.document
    var boat := doc.get_node("Boat") as SaLayer
    var mirror := doc.get_node("Mirror") as SaLayer
    doc.set_active_layer(boat)
    var fleet := SaLayerOps.new(doc).group_active()
    assert_true(fleet != null and SaLayerStack.parent_of(boat) == fleet, "The boat is wrapped in a group")
    assert_not_null(SaFilterOps.new(doc).attach(fleet, HUE, {"hue": TO_BLUE}), "The hue turn attaches to the group")
    fleet.add_mask(1.0).get_or_create(Vector2i(0, 1)).clear(Color(0.0, 0.0, 0.0, 0.0))
    assert_true(SaEffectLayer.read(doc, mirror, fleet), "The mirror reads the group")
    doc.invalidate_all_allocated_chunks()
    Bench.composite(easel)
    var masked := Bench.texel(easel.output, Vector2i(220, 320))
    var shown := Bench.texel(easel.output, Vector2i(290, 320))
    assert_true(masked.a <= TOLERANCE, "The group's mask hides the mark's left half, %s" % masked)
    assert_true(shown.a > 0.99 and shown.b > shown.r + 0.2, "and its filter turns the right half blue, %s" % shown)
    for x: int in [204, 250, 308]:
        for y: int in [684, 723]:
            var reflected := Bench.texel(easel.output, Vector2i(x, y))
            assert_true(_near(reflected, RED), "The reflection at (%d, %d) is the members' red paint, %s" % [x, y, reflected])
    easel.free()


func test_a_line_tilted_by_thirty_degrees_puts_a_dot_where_the_formula_does() -> void:
    var dot := Rect2i(299, 249, 3, 3)
    var easel := _painting([dot], false, {"angle": 30.0})
    var along := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
    var expected := MirrorFilter.reflected(Vector2(300.5, 250.5), Vector2(512, 512), along)
    var window := Rect2i(Vector2i(expected.floor()) - Vector2i(8, 8), Vector2i(17, 17))
    var found := _centroid(easel.output, window)
    assert_true(found.distance_to(expected) <= 1.0, "The dot's reflection centres at %s, the formula says %s" % [found, expected])
    var straight := Bench.texel(easel.output, Vector2i(300, 773))
    assert_true(straight.a <= TOLERANCE, "and nothing shows where a level line would have put it, %s" % straight)
    easel.free()


func test_a_dab_on_new_ground_redraws_only_the_chunks_its_reflection_touches() -> void:
    var easel := _painting([MARK], false)
    var doc := easel.document
    (doc.get_node("Boat") as SaLayer).visible = false
    Bench.composite(easel)
    var dab := Rect2i(600, 100, 16, 16)
    assert_false((doc.get_node("Mirror") as SaLayer).chunks.has(Vector2i(2, 0)), "The mirror holds nothing where the dab lands")
    var took := _dab(easel, dab)
    var reflected := _level(dab)
    assert_eq(took["changed"], _chunks_of(reflected), "The canvas changed in the chunk the dab's reflection touches and no other")
    assert_eq(took["dispatches"], 2, "The Mirror ran there and over the dab's own region, of the canvas's sixteen chunks")
    var shown := Bench.texel(easel.output, reflected.get_center())
    assert_true(_near(shown, RED), "The reflection shows, %s" % shown)
    assert_true(_matches_everything(easel), "and the redraw is the bytes a composite of everything gives")
    easel.free()


func test_a_dab_on_held_ground_redraws_only_the_chunks_its_reflection_touches() -> void:
    var easel := _painting([MARK], false)
    var doc := easel.document
    (doc.get_node("Boat") as SaLayer).visible = false
    Bench.composite(easel)
    # In the chunk at (1, 1), which the mark already holds, a little right of it.
    var dab := Rect2i(400, 280, 16, 16)
    assert_true((doc.get_node("Mirror") as SaLayer).chunks.has(Vector2i(1, 1)), "The mirror holds the dab's chunk")
    var took := _dab(easel, dab)
    var reflected := _level(dab)
    assert_eq(took["changed"], _chunks_of(reflected), "The canvas changed in the chunk the dab's reflection touches and no other")
    assert_eq(took["dispatches"], 2, "The Mirror ran there and over the dab's own region, of the canvas's sixteen chunks")
    assert_true(_near(Bench.texel(easel.output, reflected.get_center()), RED), "The reflection shows")
    assert_true(_matches_everything(easel), "and the redraw is the bytes a composite of everything gives")
    easel.free()


func test_the_line_the_fade_the_tint_and_the_paint_alone_read_survive_a_save() -> void:
    var values := {"point_x": 40.0, "point_y": 55.0, "angle": 12.0, "fade": 300, "tint": "#336699ff", "tint_amount": 25}
    var easel := _painting([MARK], true, values)
    var doc := easel.document
    var path := ProjectSettings.globalize_path(SaDataRoot.path("f8_mirror_layer.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")
    var loaded := _easel()
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    _types.rebind(_layers(loaded.document))
    var reopened := loaded.document.get_node("Mirror") as SaLayer
    assert_true(reopened != null and reopened.is_effect(), "as an effect layer")
    assert_true(reopened.source == loaded.document.get_node("Boat"), "reading the boat by name")
    assert_eq(reopened.filters.size(), 1, "holding its one record")
    var record := reopened.filters[0]
    assert_eq(record.key, MIRROR, "the Mirror")
    for key: String in ["point_x", "point_y", "angle", "fade", "tint_amount"]:
        assert_eq(float(record.parameters[key]), float(values[key]), "%s as it was" % key)
    assert_eq(Color(str(record.parameters["tint"])), Color(str(values["tint"])), "the tint as it was")
    assert_true(
        SaEffectLayer.reads_paint_alone(reopened, loaded.compositor.filter_chain.registry), "and the paint-alone read with them"
    )
    Bench.composite(loaded)
    var worst := 0.0
    var before := _bytes(easel.output)
    var after := _bytes(loaded.output)
    for y in range(0, SIZE.y, 5):
        for x in range(0, SIZE.x, 5):
            var p := SaFieldSpec.decode_texel(before, easel.output.format, y * SIZE.x + x)
            var q := SaFieldSpec.decode_texel(after, loaded.output.format, y * SIZE.x + x)
            worst = maxf(worst, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    assert_true(worst <= TOLERANCE, "The reopened canvas reads the same, worst %s" % worst)
    easel.free()
    loaded.free()
