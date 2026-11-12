## An open of a large painting spreads its effect layers'
## refresh over frames, so no frame of the open passes a tenth of a second.
##
## The open's whole composites refreshed every effect layer of the file in one
## frame, 0.45 s at the landing and 1.07 s at the end on a large painting's 217
## effect layers. The regions now wait while the open fills, each effect
## showing the picture under it, and land once the last chunk is in, paced as
## a stroke's landing is and from the view's middle outwards. This suite saves
## a file of six effect layers over six paint layers, opens it over frames
## with a pace that stops after every piece of work, and reads that no effect
## is refreshed while it fills, that no frame after it writes more than one
## chunk, that the first chunk written is in the middle, and that the settled
## picture is the one the same file read whole gives.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Four chunks by two.
const SIZE := Vector2i(1024, 512)
const EFFECTS := 6
const TOLERANCE := 1.0e-4
const AT := Vector2i(9, 9)
## A texel of chunk (1, 1), where the first suite's view is.
const SHOWN := Vector2i(1, 1) * SaLayer.CHUNK_SIZE + AT

var _types: SaLayerTypeRegistry
var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    _easels.append(easel)
    return easel


static func _colour(i: int, grid_pos: Vector2i) -> Color:
    return Color(0.1 + 0.12 * i, 0.2 + 0.2 * grid_pos.x, 0.3 + 0.3 * grid_pos.y, 1.0)


## A file of [constant EFFECTS] pairs, each a paint layer filling every chunk
## and above it an effect layer that inverts it, so every effect reads an
## input of its own and every run of the refresh is one effect.
func _saved() -> String:
    var easel := _easel()
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    for i in EFFECTS:
        var paint := SaLayerOps.new(doc).add(&"")
        paint.name = "Paint %d" % i
        for grid_pos in SaLayer.grid_positions(SIZE):
            paint.get_or_create_chunk(grid_pos).clear(_colour(i, grid_pos))
        doc.set_active_layer(paint)
        var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
        effect.name = "Mirror %d" % i
        assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to Mirror %d" % i)
        if effect.source != paint:
            SaEffectLayer.read(doc, effect, paint)
    Bench.composite(easel)
    var shown := Bench.texel(easel.output, Vector2i(1, 1) * SaLayer.CHUNK_SIZE + AT)
    var under := _colour(EFFECTS - 1, Vector2i(1, 1))
    assert_false(_near(shown, under), "The saved picture shows the effects, %s over %s" % [shown, under])
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(doc, path), OK, "The file is written")
    return path


static func _opening(document: SaDocument, path: String) -> SaSadOpening:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    return SaSadOpening.new(document, file, path)


## Composites budgeted frames of *easel* until nothing is held and no
## refresh goes on, at most 400, and answers how many it took.
static func _settle(easel: SaEasel, counts: Array[int] = []) -> int:
    var frames := 0
    while frames < 400:
        easel.process_pending_composite(true)
        frames += 1
        counts.append(_effect_chunks(easel))
        if easel.backlog.is_empty() and not easel.compositor.effect._pace.running(easel.document, {}):
            break
    return frames


static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(child)
    return found


## How many chunks the effect layers of *easel* hold.
static func _effect_chunks(easel: SaEasel) -> int:
    var count := 0
    for effect in SaEffectLayer.effects_of(easel.document):
        count += effect.chunks.size()
    return count


## The grid positions of the effect chunks of *easel*, by effect name.
static func _held(easel: SaEasel) -> Dictionary[String, Array]:
    var held: Dictionary[String, Array] = {}
    for effect in SaEffectLayer.effects_of(easel.document):
        held[str(effect.name)] = effect.chunks.keys()
    return held


## The file at *path* opened over frames into a fresh easel whose effect pace
## stops after every piece of work, as File > Open does it with *view* in the
## window, with a budgeted frame of the easel after each frame of the tree.
## Notes in *filling* the effect chunks after each frame the open filled, and
## in *shown* the picture at [constant SHOWN]. Answers the easel once the
## open has answered.
func _opened_over_frames(path: String, filling: Array[int], view: Rect2i, shown: Array[Color] = []) -> SaEasel:
    var easel := _easel()
    easel.compositor.effect._pace.frame_usec = 0
    var document := easel.document
    var answers: Array[Error] = []
    var land := func() -> Rect2i:
        _types.rebind(_layers(document))
        return view
    _opening(document, path).over_frames(answers.append, land, 0)
    var frames := 0
    while answers.is_empty() and frames < 400:
        await (Engine.get_main_loop() as SceneTree).process_frame
        frames += 1
        # While chunks are still to come, which now ends some frames
        # before the open's answer, the record of the open kept in between.
        if SaSadFile.chunks_to_come(document):
            easel.process_pending_composite(true)
            filling.append(_effect_chunks(easel))
            shown.append(Bench.texel(easel.output, SHOWN))
    assert_eq(answers, [OK] as Array[Error], "The open answers OK, after %d frames" % frames)
    assert_eq(SaEffectLayer.effects_of(document).size(), EFFECTS, "with every effect layer one again")
    return easel


func test_no_effect_is_refreshed_while_the_open_fills_and_the_walk_draws_what_is_under_it() -> void:
    var filling: Array[int] = []
    var shown: Array[Color] = []
    await _opened_over_frames(_saved(), filling, Rect2i(SHOWN, Vector2i.ONE), shown)
    assert_true(filling.size() > 1, "The open filled over %d frames" % filling.size())
    assert_eq(filling.max(), 0, "No effect chunk was written while it filled, %s" % [filling])
    var under := _colour(EFFECTS - 1, Vector2i(1, 1))
    var drawn := shown.filter(func(texel: Color) -> bool: return _near(texel, under))
    assert_false(drawn.is_empty(), "The view drew the paint under the effects, %s against %s" % [shown, under])


func test_each_frame_after_the_fill_writes_one_chunk_at_most_the_middle_first() -> void:
    var easel: SaEasel = await _opened_over_frames(_saved(), [] as Array[int], Rect2i(Vector2i.ZERO, SIZE))
    var counts: Array[int] = [_effect_chunks(easel)]
    var first: Dictionary[String, Array] = {}
    var frames := 0
    while frames < 400:
        easel.process_pending_composite(true)
        frames += 1
        counts.append(_effect_chunks(easel))
        if first.is_empty() and counts[-1] > 0:
            first = _held(easel)
        if easel.backlog.is_empty() and not easel.compositor.effect._pace.running(easel.document, {}):
            break
    assert_true(easel.backlog.is_empty(), "The backlog empties, in %d frames" % frames)
    var most := 0
    for index in range(1, counts.size()):
        most = maxi(most, counts[index] - counts[index - 1])
    assert_eq(most, 1, "No frame wrote more than the one chunk its budget pays for, %s" % [counts])
    var grid := SaLayer.grid_positions(SIZE).size()
    assert_eq(counts[-1], EFFECTS * grid, "Every effect holds every chunk at the end")
    var middle: Array = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)]
    var written: Array = []
    for name: String in first:
        written.append_array(first[name])
    assert_eq(written.size(), 1, "The first frame that writes writes one chunk, %s" % [first])
    assert_true(written.size() == 1 and middle.has(written[0]), "and it is in the view's middle, %s" % [written])


func test_the_settled_picture_is_the_one_the_file_read_whole_gives() -> void:
    var path := _saved()
    var paced: SaEasel = await _opened_over_frames(path, [] as Array[int], Rect2i(Vector2i.ZERO, SIZE))
    var frames := _settle(paced)
    assert_true(paced.backlog.is_empty(), "The backlog empties, in %d frames" % frames)
    var whole := _easel()
    assert_eq(SaExport.load_sad(whole.document, path, whole.compositor), OK, "The file reads whole")
    _types.rebind(_layers(whole.document))
    Bench.composite(whole)
    var a := SaExport.get_texture_image_float(paced.output)
    var b := SaExport.get_texture_image_float(whole.output)
    assert_true(a.get_data() == b.get_data(), "The settled picture is the whole read's in every texel, %s" % [_first_apart(a, b)])
    var top := EFFECTS - 1
    var shown := a.get_pixel(SaLayer.CHUNK_SIZE + AT.x, SaLayer.CHUNK_SIZE + AT.y)
    var under := _colour(top, Vector2i(1, 1))
    assert_false(_near(shown, under), "and it shows the effects, %s over %s" % [shown, under])


## The first texel where *a* and *b* differ, by rows, or an empty line.
static func _first_apart(a: Image, b: Image) -> String:
    for y in a.get_height():
        for x in a.get_width():
            if a.get_pixel(x, y) != b.get_pixel(x, y):
                return "(%d, %d) %s against %s" % [x, y, a.get_pixel(x, y), b.get_pixel(x, y)]
    return ""


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE
