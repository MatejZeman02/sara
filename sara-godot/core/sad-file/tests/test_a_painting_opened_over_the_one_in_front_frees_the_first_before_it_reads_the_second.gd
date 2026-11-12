## A painting opened over the one in front frees the first
## before it reads the second.
##
## An offscreen Sara under an 8 GiB scope loaded the
## seasons painting once and fitted, and loaded it a second time into the
## same document and was killed. The open read every layer of the new file
## while the old layers, their history and the caches made for them were
## still held, so the peak of a second load was two paintings and the first's
## steps. Freed once the file is known to be a `.sad` and before its blobs are
## read, a load into a Sara holding the painting peaks as one into a fresh
## Sara.
##
## The peak is read twice. The card's, from the RenderingDevice at the moment
## every layer of the new file is read and none landed, which is the most an
## open holds, and the process's, from the high-water mark of its resident set
## that `/proc/self/clear_refs` resets before each load.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and an open writes them.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Chunks a side, so two painted layers at full precision are 512 MiB.
const SIDE := 16
const PAINTED := 2
## How far above the first load's peak the second's may go.
const BOUND := 1.15
## The chunks of the first painted layer a step in the history keeps.
const HISTORY_CHUNKS := 64

var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _easel() -> SaEasel:
    var made := Bench.easel(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _easels.append(made)
    return made


## A file of [constant PAINTED] layers each with every chunk a colour of its
## own, written from an easel that is freed before the answer.
func _saved() -> String:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    var document := easel.document
    var shade := 0
    for i in PAINTED:
        var layer := SaLayerOps.new(document).add(&"")
        layer.name = "Painted %d" % i
        for y in SIDE:
            for x in SIDE:
                shade += 1
                var value := float(shade) / float(SIDE * SIDE * PAINTED)
                layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(value, 1.0 - value, 0.5, 1.0))
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(document, path), OK, "The fixture is written")
    SaSadFile.finish_saves()
    easel.free()
    return path


## The bytes of colour the painted layers of *document* hold on the card.
static func _painted_bytes(document: SaDocument) -> int:
    var total := 0
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer or not str(layer.name).begins_with("Painted"):
            continue
        for grid_pos: Vector2i in layer.chunks:
            var texture := layer.get_field(grid_pos)
            if texture != null:
                total += texture.size.x * texture.size.y * SaSadBlob.LAYOUT[texture.format].x * SaSadBlob.LAYOUT[texture.format].y
    return total


## Gives *document* a step of history, a snapshot of [constant HISTORY_CHUNKS]
## chunks of its first painted layer, as a stroke over them leaves.
static func _with_history(document: SaDocument) -> void:
    var layer := document.get_node(NodePath("Painted 0")) as SaLayer
    var state := {}
    for at in HISTORY_CHUNKS:
        var grid_pos := Vector2i(at % SIDE, floori(float(at) / SIDE))
        state[grid_pos] = SaChunkDelta.capture(layer.chunks[grid_pos], Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE))
    document.record_pixel_step("Fixture stroke", layer, state)


static func _card() -> int:
    return GlobalShaderCompiler.get_rd().get_memory_usage(RenderingDevice.MEMORY_TOTAL)


## Resets the process's high-water mark, so the next read is this load's.
static func _reset_high_water() -> void:
    var clear := FileAccess.open("/proc/self/clear_refs", FileAccess.WRITE)
    if clear != null:
        clear.store_string("5")
        clear.close()


## The process's resident high-water mark in bytes, 0 where it cannot be read.
static func _high_water() -> int:
    # Read a line at a time, because a file of /proc reports a length of 0 and
    # a read of the whole file by its length reads nothing.
    var status := FileAccess.open("/proc/self/status", FileAccess.READ)
    if status == null:
        return 0
    while not status.eof_reached():
        var line := status.get_line()
        if line.begins_with("VmHWM:"):
            return int(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) * 1024
    return 0


## The open the door's `load` makes, [method SaSadOpening.whole], taken in its
## two steps so the card is read between them, where every layer is read and
## none has landed. Answers the card's and the process's peaks.
func _load_whole(document: SaDocument, path: String, what: String) -> Vector2i:
    _reset_high_water()
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    var opening := SaSadOpening.new(document, file, path)
    assert_eq(opening.error, OK, "%s: the header is read" % what)
    opening.step(-1)
    var card := _card()
    assert_eq(opening.land(), OK, "%s: the open lands" % what)
    return Vector2i(card >> 20, _high_water() >> 20)


## What File > Open does, [method SaExport.open_sad] over frames, with the card
## read on every frame it takes. Answers the card's and the process's peaks.
func _open_over_frames(document: SaDocument, path: String, what: String) -> Vector2i:
    _reset_high_water()
    var answers: Array[Error] = []
    var card := [_card()]
    var tree := Engine.get_main_loop() as SceneTree
    var sample := func() -> void: card[0] = maxi(card[0], _card())
    tree.process_frame.connect(sample)
    SaExport.open_sad(document, path, answers.append)
    card[0] = maxi(card[0], _card())
    for _i in 600:
        if not answers.is_empty():
            break
        await tree.process_frame
    tree.process_frame.disconnect(sample)
    assert_eq(answers, [OK] as Array[Error], "%s: the open answers once, OK" % what)
    return Vector2i(card[0] >> 20, _high_water() >> 20)


func _bounded(fresh: Vector2i, held: Vector2i, what: String) -> void:
    var said := "%s: card %d MiB into a fresh document, %d MiB into one holding the painting"
    print((said + ", process %d MiB and %d MiB") % [what, fresh.x, held.x, fresh.y, held.y])
    var within := "%s: the %s peak of the second load, %d MiB, is within 15 percent of the first's, %d MiB"
    assert_true(held.x <= fresh.x * BOUND, within % [what, "card's", held.x, fresh.x])
    if fresh.y > 0:
        assert_true(held.y <= fresh.y * BOUND, within % [what, "process's", held.y, fresh.y])


func test_the_door_s_load_into_a_sara_holding_the_painting_peaks_as_one_into_a_fresh_sara() -> void:
    var path := _saved()
    var document := _easel().document
    var fresh := _load_whole(document, path, "The first load")
    var painted := _painted_bytes(document)
    assert_true(painted >= 500 * 1000 * 1000, "The painting holds at least 500 MB: %d bytes" % painted)
    _with_history(document)
    var held := _load_whole(document, path, "The second load")
    _bounded(fresh, held, "load")
    assert_eq(document.undo_redo.get_history_count(), 0, "The history of the first is gone")


func test_file_open_over_a_painting_peaks_as_one_into_a_fresh_sara_and_leaves_no_history() -> void:
    var path := _saved()
    var document := _easel().document
    var fresh := await _open_over_frames(document, path, "The first open")
    _with_history(document)
    assert_eq(document.undo_redo.get_history_count(), 1, "The painting has a step to take back")
    var held := await _open_over_frames(document, path, "The second open")
    _bounded(fresh, held, "open")
    assert_eq(document.undo_redo.get_history_count(), 0, "The undo history after the open is empty")
    assert_eq(document.history.step_count(), 0, "and so is its accounting")


func test_a_load_that_fails_leaves_an_empty_document_with_its_error() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    _easels.append(easel)
    var document := easel.document
    var layer := SaLayerOps.new(document).add(&"")
    layer.name = "Painted 0"
    layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.5, 0.25, 0.75, 1.0))
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_broken.sad"))
    _paths.append(path)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION_PLAIN)
    file.store_32(16)
    file.store_32(64)
    file.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))
    file.close()
    assert_ne_ok(SaExport.load_sad(document, path), "A file whose header will not read is refused")
    assert_null(document.get_node_or_null(NodePath("Painted 0")), "and the painting that was open is gone")
    assert_not_null(document.active_layer, "The document is a new empty one, with a layer to paint on")
    assert_eq(document.canvas_size, Vector2i(64, 64), "at the size it had")


func assert_ne_ok(error: Error, message: String) -> void:
    assert_true(error != OK, "%s: %s" % [message, error_string(error)])
