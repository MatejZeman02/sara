## Every open of a painting gives back its objects when the next document
## replaces it.
##
## Each open of a painting once left about 8,000 objects
## behind, one `WeakRef` for every stylebox a layer row bound to the palette
## through `SaTheme.bind`, kept in a list swept only at a palette switch. The
## table is keyed by the style's instance id now and swept as it doubles, as
## the font colours' is, so a bind makes no object. The running app's reading is
## `scenarios/every-open-of-a-painting-in-the-running-app-gives-back-its-objects-when-the-next-document-replaces-it.json`.
extends "res://tests/test_framework.gd"

## The open composites and draws thumbnails, which are compute dispatches.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const SIZE := Vector2i(256, 256)
## Painted layers in the file, each a row of the Layers docker and its binds.
const LAYERS := 24
## Rounds of open and replace after the first, which the count is read against.
const ROUNDS := 3

## The painting the suite opens, and the empty document that replaces it.
static var scratch_painting: String = SaDataRoot.path("a-painting-of-many-layers.sad")
static var scratch_empty: String = SaDataRoot.path("the-document-that-replaces-it.sad")

var _canvas: SaCanvas = null
var _files: SaDocumentFiles = null
var _docker: LayersDocker = null


func before_each() -> void:
    var made := Bench.easel(SIZE)
    assert_eq(SaExport.save_sad(made.document, scratch_empty, 0), OK, "the empty document is written")
    var ops := SaLayerOps.new(made.document)
    for i: int in LAYERS:
        var layer := ops.add()
        layer.name = "Paint %d" % i
        made.document.fill_layer(Color(float(i) / LAYERS, 0.4, 0.2, 0.8), layer)
    assert_eq(SaExport.save_sad(made.document, scratch_painting, 0), OK, "the painting is written")
    made.free()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = Bench.easel(SIZE)
    _canvas.add_child(_canvas.easel)
    _docker = LayersDocker.new()
    _docker.filter_registry = _canvas.easel.compositor.filter_chain.registry
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _files = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)


func after_each() -> void:
    for path: String in [scratch_painting, scratch_empty]:
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _files.free()
    _docker.free()
    _canvas.free()


## The painting opens through File > Open's own call, its rows drawn, and the
## empty file opened after it takes its place, as a recent row or a drop does.
## The first round may fill what the app keeps once, so the rounds after it read
## the count it left, and none reads more than the round before it.
func test_an_open_and_a_replace_three_times_leave_the_object_count_unchanged() -> void:
    await _welcome_picture_read()
    await _round()
    var first := _objects()
    var counts: Array[int] = []
    for i: int in ROUNDS:
        await _round()
        counts.append(_objects())
    print("probe objects after the first round %d, after the next %s" % [first, counts])
    # No round leaves more than the one before it, which a leak of a single
    # object a round fails. Fewer is allowed: after a suite that opened windows,
    # the run lets go of one of that suite's objects during these rounds.
    var before := first
    for i: int in ROUNDS:
        assert_true(counts[i] <= before, "round %d leaves %d objects, the one before it left %d" % [i + 2, counts[i], before])
        before = counts[i]
    assert_true(counts[ROUNDS - 1] <= first, "and the last leaves no more than the first")


## The rows of every open bind their styles, and none of the binds is an object.
func test_a_row_s_binds_make_no_object_and_leave_only_live_styles() -> void:
    await _round()
    var styles := SaTheme.bound_style_count()
    for id: int in SaTheme._bound_styles:
        assert_true(is_instance_valid(instance_from_id(id)), "every style the table holds after a sweep is live")
    await _round()
    assert_true(SaTheme.bound_style_count() <= styles, "a second round binds no more live styles than the first")


func _round() -> void:
    _files.open_path(scratch_painting)
    assert_eq(_canvas.document.file_path, scratch_painting, "the painting is the open document")
    SaLayerList.settle_thumbnails(_docker)
    assert_true(_docker.item_list.rows.size() >= LAYERS, "its %d rows are drawn" % _docker.item_list.rows.size())
    _files.open_path(scratch_empty)
    assert_eq(_canvas.document.file_path, scratch_empty, "the empty document replaced it")
    SaLayerList.settle_thumbnails(_docker)
    # Each close keeps a picture for its welcome card, read back from the card
    # over the frames after it, and one still on its way is two objects more
    # than the rounds after it hold, so it is run to its end first.
    assert_true(WelcomePreviewCache.finish_all(), "the welcome card's picture of the closed document landed")
    # The rows the replace let go of are freed at the frame's end.
    for i: int in 3:
        await (Engine.get_main_loop() as SceneTree).process_frame


## Waits out a read ahead of the welcome picture's parts, one image a frame
## into a kept table of eighteen, which a suite that opened the welcome window
## before this one leaves running. Under the rounds below it read as three
## objects a round for five rounds, and the full run failed this suite on it.
func _welcome_picture_read() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var reading := WelcomePicture._reading
    for _frame in 600:
        if reading == null or not tree.process_frame.is_connected(reading._on_frame):
            return
        await tree.process_frame


static func _objects() -> int:
    return int(Performance.get_monitor(Performance.OBJECT_COUNT))
