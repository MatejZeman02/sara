## A whole-canvas step no longer takes the cheap ones with it.
##
## The note was filed by `the-gradient-can-be-undone`, which found the
## gradient tool does have an undo and that what the painter met was the budget:
## eight ramps on a 1920x1080 document left six steps and the `Fill Layer` row
## that was the way back to a flat canvas had gone. The budget follows the
## document now, so the number of whole-canvas steps is a depth the painter sets
## rather than a constant divided by whatever the document happens to cost.
extends "res://tests/test_framework.gd"

## Snapshots are real chunk textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

## A 4 by 3 grid, so a whole-canvas step is twelve chunk snapshots and the
## arithmetic below is small enough to read. 1920x1080 is forty and 480 MiB of
## VRAM, which is the document the note was written on and not one to allocate
## nine times in a suite.
const CANVAS := Vector2i(1024, 768)

## Two pictures: one well under the layer pool, and a flat 2400 square
## that is a hundred chunks and over it.
const SMALL_PICTURE := "res://tests/data/import_gradient.png"
const LARGE_PICTURE := "res://tests/data/a_picture_over_the_layer_pool.png"

var _depth_before: int = 0
var _import_depth_before: String = ""


## What one chunk snapshot of *doc* weighs in the history: a whole tile at the
## document's own texel depth, asked of the document rather than assumed to be
## sixteen bytes (hard rule 3, sparse chunks).
func _chunk_bytes(doc: SaDocument) -> int:
    return SaChunk.SIZE * SaChunk.SIZE * int(SaFieldSpec.BYTES_PER_TEXEL[doc.color_space.texel_format()])


## A whole-canvas step of *doc*, the grid's twelve chunk snapshots.
func _whole_canvas_bytes(doc: SaDocument) -> int:
    return _chunk_bytes(doc) * 12


func before_each() -> void:
    _depth_before = SaSettings.history_depth
    _import_depth_before = SaSettings.import_depth
    SaProblems.announce = false
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    SaSettings.history_depth = _depth_before
    SaSettings.import_depth = _import_depth_before
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true


## The budget is the floor until a step has said what a step on this document
## costs, and follows that step afterwards.
func test_the_budget_follows_what_a_step_here_costs() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    assert_eq(doc.history.largest_step_bytes, 0, "A fresh history has weighed nothing")
    assert_eq(doc.history.effective_budget(), doc.history.budget_bytes, "so the budget is the floor and nothing more")

    _fill(doc, Color(0.1, 0.1, 0.1, 1.0))
    assert_eq(doc.history.largest_step_bytes, _whole_canvas_bytes(doc), "One whole-canvas fill weighs the whole grid")
    assert_eq(
        doc.history.effective_budget(),
        maxi(doc.history.budget_bytes, SaSettings.history_depth * _whole_canvas_bytes(doc)),
        "and the budget is the deeper of the floor and the depth Preferences asks for"
    )

    easel.free()


## The floor still holds a document whose steps are dabs, so nothing about this
## makes a sketchpad's history shallower than it was.
func test_a_document_of_cheap_steps_never_leaves_the_floor() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    # The paint layer holds no chunks, so filling it snapshots nothing.
    doc.fill_layer(Color(0.4, 0.2, 0.2, 1.0), doc.active_layer)
    assert_eq(doc.history.effective_budget(), SaHistory.DEFAULT_BUDGET_BYTES, "The budget is the floor it shipped with")
    assert_eq(doc.history.dropped_steps, 0, "and nothing was dropped")

    easel.free()


## The case the note was filed over: more whole-canvas steps than the old
## constant held, and Ctrl+Z still reaches the canvas it started from.
func test_nine_whole_canvas_steps_undo_back_to_the_start() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    # The floor set to what 256 MiB was worth on the document the note used: six
    # whole-canvas steps and no more. Under the constant alone this run would
    # keep six of the nine and lose the first three.
    doc.history.budget_bytes = _whole_canvas_bytes(doc) * 6
    var before := _texel(doc)

    for i in 9:
        _fill(doc, Color(float(i + 1) / 10.0, 0.2, 0.2, 1.0))

    assert_true(doc.history.effective_budget() > doc.history.budget_bytes, "The depth asks for more than the floor allows")
    assert_eq(doc.history.step_count(), 9, "so all nine whole-canvas steps are held")
    assert_eq(doc.history.dropped_steps, 0, "and none was dropped")

    for i in 9:
        doc.undo_redo.undo()
    assert_false(doc.undo_redo.has_undo(), "Nine undos reach the end of the list")
    assert_almost_eq(_texel(doc).r, before.r, 0.01, "and the canvas it started from is back")

    easel.free()


## Eviction is counted, and the count is the whole of what a drop says.
##
## A corner line per drop answered the half the painter met, six rows in the docker
## and no sign a seventh existed, but a full undo stack should not throw an info
## popup. The count is the docker's footer, which its own suite grades, and the
## log line a tester reads, which is the console's and no part of a suite.
func test_a_dropped_step_is_counted_and_raises_no_refusal() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    SaSettings.history_depth = SaSettingsValues.MIN_HISTORY_DEPTH
    doc.history.budget_bytes = _whole_canvas_bytes(doc) * 2
    for i in 7:
        _fill(doc, Color(float(i + 1) / 8.0, 0.2, 0.2, 1.0))

    assert_eq(doc.history.step_count(), SaSettingsValues.MIN_HISTORY_DEPTH, "Four steps fit at the shallowest depth")
    assert_eq(doc.history.dropped_steps, 3, "so three of the seven were dropped")
    assert_true(SaProblems.pending_refusals.is_empty(), "and nothing arrives on screen over a step the budget took")

    easel.free()


## A depth raised in Preferences reaches a document that is already open, which
## is why it is read at commit rather than copied in when the history is made.
func test_a_depth_the_painter_changes_reaches_an_open_document() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    doc.history.budget_bytes = 1
    _fill(doc, Color(0.1, 0.1, 0.1, 1.0))
    SaSettings.history_depth = SaSettingsValues.MIN_HISTORY_DEPTH
    var shallow := doc.history.effective_budget()
    SaSettings.history_depth = SaSettingsValues.MAX_HISTORY_DEPTH
    var deep := doc.history.effective_budget()

    assert_eq(shallow, SaSettingsValues.MIN_HISTORY_DEPTH * _whole_canvas_bytes(doc), "The shallowest depth is four steps")
    assert_eq(deep, SaSettingsValues.MAX_HISTORY_DEPTH * _whole_canvas_bytes(doc), "the deepest is thirty-two")
    assert_true(deep > shallow, "and the document already open answers to both")

    easel.free()


## A pinned budget is exactly `budget_bytes`, which is what a test measuring the
## arithmetic under the depth sets, and the corner line stays quiet for it.
func test_a_pinned_budget_is_the_number_it_was_given() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    doc.history.pin_budget = true
    doc.history.budget_bytes = _whole_canvas_bytes(doc) * 2
    for i in 5:
        _fill(doc, Color(float(i + 1) / 6.0, 0.2, 0.2, 1.0))

    assert_eq(doc.history.effective_budget(), _whole_canvas_bytes(doc) * 2, "The pin holds the budget at the number given")
    assert_eq(doc.history.step_count(), 2, "so two whole-canvas steps fit")
    assert_true(doc.history.dropped_steps > 0, "and the drops are still counted")
    assert_true(SaProblems.pending_refusals.is_empty(), "with nothing said to a painter who is not there")

    easel.free()


## `reset` forgets what a step here costs, because the next document is not this
## one.
func test_reset_forgets_the_document_it_was_sizing_for() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    _fill(doc, Color(0.1, 0.1, 0.1, 1.0))
    assert_true(doc.history.largest_step_bytes > 0, "A fill has said what a step costs")

    doc.history.reset()
    assert_eq(doc.history.largest_step_bytes, 0, "and a reset forgets it")
    assert_eq(doc.history.dropped_steps, 0, "along with what was dropped")

    easel.free()


## Opening a picture starts a history with no steps and says nothing, over a
## document that had steps of its own and for a picture over the layer pool alike.
##
## The note was "after loading new image: 'Undo history is full' message
## appears". The old document's steps were never the cause, `reset_to_default`
## makes a new history. The picture was: 2400 square is a hundred chunks, over
## the 96 MiB layer pool, so the open's own Delete Layer dropped its Add Layer.
##
## 2400 square is a hundred chunks, and that is over the pool at 32-bit chunks
## only. A picture with no float width of its own opens at the painter's stored
## `import_depth`, and a settings folder made today stores 16-bit, whose chunks
## are half the size, so the picture would fit and the case would assert a
## premise it never built. The case sets the depth it needs and
## `after_each` puts the painter's back.
func test_opening_a_picture_leaves_no_steps_and_says_nothing() -> void:
    SaSettings.import_depth = "f32"
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    for i in 3:
        _fill(doc, Color(float(i + 1) / 4.0, 0.2, 0.2, 1.0))
    assert_eq(doc.history.step_count(), 3, "Three steps before the open")

    assert_not_null(SaDocumentFiles.open_image_into(doc, SMALL_PICTURE), "A small picture opens over them")
    assert_eq(doc.history.step_count(), 0, "and the history it starts holds none")
    assert_true(SaProblems.pending_refusals.is_empty(), "and has said nothing")

    assert_true(100 * _chunk_bytes(doc) > doc.history.layer_budget_bytes, "A hundred chunks are over the layer pool")
    assert_not_null(SaDocumentFiles.open_image_into(doc, LARGE_PICTURE), "and a picture that size opens")
    assert_eq(doc.history.step_count(), 0, "holding no steps either")
    assert_eq(SaProblems.pending_refusals, PackedStringArray(), "and saying nothing about a history nobody made")

    easel.free()


## The rest of the proof: a first step over the pool on
## its own is kept without a word, because a history of one step is not full, and
## the drop still comes the moment a step the painter made is dropped, as a count
## rather than as a line over the canvas.
func test_a_step_over_the_pool_is_held_alone_and_a_drop_is_still_counted() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    doc.history.layer_budget_bytes = 1
    assert_true(SaLayerOps.new(doc).remove(SaLayerOps.new(doc).layers()[0]), "The background comes off as the first step")
    assert_eq(doc.history.step_count(), 1, "and is held, whatever it weighs")
    assert_true(SaProblems.pending_refusals.is_empty(), "without a word")

    SaLayerOps.new(doc).add()
    assert_eq(doc.history.dropped_steps, 1, "The next step drops it, and the count is one")
    assert_true(SaProblems.pending_refusals.is_empty(), "with still nothing over the canvas")

    easel.free()


func _document() -> Array:
    var easel := SaEasel.create_default(CANVAS)
    # Every case here drops steps on purpose, and the drop's remaining line is
    # the console's: a suite that printed one per drop would bury its own
    # transcript, so the line is off for this document alone.
    easel.document.history.announce_drops = false
    return [easel, easel.document]


## On the background layer, which holds its whole grid. A fill of the paint layer
## snapshots a layer with no chunks and weighs nothing.
func _fill(doc: SaDocument, color: Color) -> void:
    doc.fill_layer(color, SaLayerOps.new(doc).layers()[0])


func _texel(doc: SaDocument) -> Color:
    var texture := SaLayerOps.new(doc).layers()[0].get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)
