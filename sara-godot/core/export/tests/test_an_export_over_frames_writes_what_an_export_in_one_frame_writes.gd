## A save, an autosave and an export of a large painting hold
## no frame over a tenth of a second. An export rounded the live colour and
## encoded the PNG in the frame it was asked in, 1.1 s on a large painting, and
## an autosave walked its document in its first frame, 0.65 s. Now the
## rounding is one counting pass sent to the card in shares,
## `SaSadSnapshot.round_live_in_turns`, the PNG is read on the main thread and
## encoded and written on a worker, `SaExportInTurns`, and the autosave's walk
## waits for its hashes as a Ctrl+S does.
##
## The painting: one layer holding colour that is not rounded in two chunks,
## the same in two easels, so what is done over frames in one is compared
## with what is done in one frame in the other.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the rounding, the composite and the read run on the card.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## A colour with bits past the twelve a save keeps, so rounding moves it.
const PAINT := Color(0.4123457, 0.3141593, 0.7777777, 1.0)
## The turns a suite drives before it calls a run of them stuck.
const TURNS := 2000

static var at_once: String = SaDataRoot.path("test_at_once.png")
static var over_frames: String = SaDataRoot.path("test_over_frames.png")
static var saved: String = SaDataRoot.path("test_autosaved.sad")

var _a_turn := 0
var _made: Array[SaEasel] = []


func before_each() -> void:
    # One texture a turn, so the two chunks' colour goes out in two shares.
    _a_turn = SaSadHashShares.a_turn
    SaSadHashShares.a_turn = 1


func after_each() -> void:
    SaSadHashShares.a_turn = _a_turn
    SaExportInTurns.finish_all()
    SaSadFile.finish_saves()
    for easel: SaEasel in _made:
        easel.free()
    _made.clear()
    for path: String in [at_once, over_frames, saved]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The painting of the header, composited once.
func _painted() -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    _made.append(easel)
    var layer := easel.document.active_layer
    for grid_pos in HELD:
        layer.get_or_create_chunk(grid_pos).clear(PAINT)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


static func _bytes(easel: SaEasel, grid_pos: Vector2i) -> PackedByteArray:
    var texture := easel.document.active_layer.get_field(grid_pos)
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()


static func _pixels(path: String) -> PackedByteArray:
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    return image.get_data() if image != null else PackedByteArray()


func test_the_rounding_over_frames_rounds_what_the_rounding_in_one_frame_rounds() -> void:
    var once := _painted()
    var turns := _painted()
    var counted := SaSadSnapshot.round_live(once.document)
    assert_true(counted > 0, "The colour is not rounded as painted, so the rounding moves it")
    var rounding := SaSadSnapshot.round_live_in_turns(turns.document)
    rounding.turn()
    assert_false(rounding.done, "The rounding takes more than the turn it was asked in")
    var turned := 1
    while not rounding.done and turned < TURNS:
        rounding.turn()
        OS.delay_usec(500)
        turned += 1
    assert_true(rounding.done, "The rounding ends over turns")
    assert_eq(rounding.moved, counted, "and rounds as many textures as the rounding in one frame")
    for grid_pos in HELD:
        assert_eq(_bytes(turns, grid_pos), _bytes(once, grid_pos), "%s holds what the rounding in one frame left" % grid_pos)
    var again := SaSadSnapshot.round_live_in_turns(turns.document)
    turned = 0
    while not again.done and turned < TURNS:
        again.turn()
        OS.delay_usec(500)
        turned += 1
    assert_eq(again.moved, 0, "A second rounding over turns moves nothing")


func test_a_png_written_over_frames_holds_every_pixel_of_the_png_written_in_one_frame() -> void:
    var once := _painted()
    var turns := _painted()
    assert_eq(SaExport.export_png(once, at_once), OK, "The export in one frame writes its file")
    var options := SaImageFormat.Write.new()
    options.depth = 8
    var heard: Array[Error] = []
    SaExport.export_png_in_turns(turns, over_frames, options, func(error: Error) -> void: heard.append(error))
    assert_true(SaExportInTurns.running(), "The export over frames runs after the call")
    assert_false(FileAccess.file_exists(over_frames), "and has written nothing in the frame it was asked in")
    var turned := 0
    while SaExportInTurns.running() and turned < TURNS:
        SaExportInTurns.turn()
        OS.delay_usec(500)
        turned += 1
    assert_false(SaExportInTurns.running(), "It ends over turns")
    assert_eq(heard, [OK] as Array[Error], "and says once that it wrote its file")
    var expected := _pixels(at_once)
    assert_false(expected.is_empty(), "The PNG written in one frame reads back")
    assert_eq(_pixels(over_frames), expected, "The PNG written over frames holds every pixel of it")
    for grid_pos in HELD:
        var said := "%s is rounded as the export in one frame rounded it" % grid_pos
        assert_eq(_bytes(turns, grid_pos), _bytes(once, grid_pos), said)


func test_an_export_waited_on_by_a_quit_is_whole_before_the_quit_goes_on() -> void:
    var easel := _painted()
    var options := SaImageFormat.Write.new()
    options.depth = 8
    SaExport.export_png_in_turns(easel, over_frames, options)
    assert_true(SaSadFile.saving(), "An export over frames counts as a file still being written")
    var went_on: Array[bool] = []
    SaSadFile.after_saves(func() -> void: went_on.append(true), "quitting")
    assert_true(went_on.is_empty(), "A quit waits for it")
    assert_true(SaSadFile.finish_saves(), "Finishing the saves finishes the export")
    assert_eq(went_on, [true] as Array[bool], "and the quit goes on once")
    assert_true(FileAccess.file_exists(over_frames), "with the file whole")


func test_the_autosave_walks_after_its_hashes_as_a_save_the_painter_asks_for() -> void:
    var easel := _painted()
    var save := SaSadSave.start(easel.document, saved, 0, null, false, Callable(), true, &"", true)
    assert_true(save._later, "The autosave's walk waits for its hashes, so its first frame walks nothing")
    assert_true(SaSadFile.finish_saves(), "It ends")
    assert_true(FileAccess.file_exists(saved), "with its file written")
