## A shot waits for an owed fold to be paid.
##
## A click on a layer owes its fold to `SaFoldDebt`, which pays it
## over the frames after, and a scenario's `wait` counts frames, so on a busy
## machine a `shot` came before the fold was paid. `SaShotSettle` now counts
## an owed fold as unsettled. A canvas in the root window owes its fold here,
## and the shot is asked for every frame until it is written: the first case
## reads it written only once `is_owed()` turned false, the second holds the
## debt unpaid and reads it written at the bound, with the log line.
extends "res://tests/test_framework.gd"

## The canvas composites and the fold folds, which are compute dispatches.
const REQUIRES_GPU := true

## More frames than either case takes.
const MOST_FRAMES := 240
const Fixtures = preload("res://tests/fixtures.gd")

var _host: Node
var _capture: SaCapture
var _out_dir := ""

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    # Parented to an autoload rather than the root, for the reason
    # test_canvas_sampling.gd gives: the runner calls this mid-`_ready`.
    _host = Node.new()
    _host.name = "U228ShotHost"
    EventBus.add_child(_host)
    _out_dir = SaDataRoot.path("owed_fold_shot_test")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
    _capture = SaCapture.new(_out_dir)
    _host.add_child(_capture)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    SaShotSettle.owed_frames_bound = 600
    if _host != null:
        _host.free()
        _host = null
    var absolute := ProjectSettings.globalize_path(_out_dir)
    for name: String in DirAccess.get_files_at(absolute):
        DirAccess.remove_absolute(absolute.path_join(name))
    DirAccess.remove_absolute(absolute)


## A canvas in the root window, given the frames its first composite and
## fold take, so the debt owed after is the only one.
func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    _host.add_child(canvas)
    for i: int in 4:
        await (Engine.get_main_loop() as SceneTree).process_frame
    _front = Fixtures.FrontDocuments.over(canvas)
    return canvas


func _written(label: String) -> bool:
    return FileAccess.file_exists(ProjectSettings.globalize_path(_out_dir).path_join("%s.png" % label))


## Asks for the shot every frame until it is written, the way the run's
## spliced `wait` and `shot` ask, and answers the frames it took, or -1.
## *owed_before* gathers whether the fold was owed at each refused ask.
func _shoot_until_written(label: String, owed_before: Array[bool], debt: SaFoldDebt) -> int:
    for frames: int in MOST_FRAMES:
        _capture.run.shoot(label)
        if _written(label):
            return frames
        owed_before.append(debt.is_owed())
        await (Engine.get_main_loop() as SceneTree).process_frame
    return -1


func test_the_shot_is_taken_only_once_the_fold_is_paid() -> void:
    var canvas: SaCanvas = await _canvas()
    var document := canvas.document
    assert_not_null(document, "the canvas holds a document")
    var debt := document.fold.debt
    debt.quiet_msec = 100
    debt.owe(document)
    assert_false(debt.owes_whole(), "the debt is of an activation alone, which only a fold pays")
    assert_true(debt.is_owed(), "the fold is owed before the shot is asked for")

    var line_before := SaShotSettle.last_owed_line
    var owed_before: Array[bool] = []
    var frames: int = await _shoot_until_written("paid", owed_before, debt)
    assert_true(frames > 0, "the shot waited at least a frame, and was written in the end: %d" % frames)
    assert_false(debt.is_owed(), "the fold was paid when the shot was written")
    assert_false(owed_before.has(false), "every refused ask was refused while the fold was owed")
    assert_eq(SaShotSettle.last_owed_line, line_before, "a shot after the payment logs no owed fold")


func test_a_fold_that_never_pays_is_shot_at_the_bound_with_a_log_line() -> void:
    var canvas: SaCanvas = await _canvas()
    var document := canvas.document
    var debt := document.fold.debt
    # Never an idle frame, which is a debt that never pays.
    debt.quiet_msec = 1 << 40
    SaShotSettle.owed_frames_bound = 12
    debt.owe(document)
    assert_false(debt.owes_whole(), "the debt is of an activation alone, which no composite pays")

    var owed_before: Array[bool] = []
    var frames: int = await _shoot_until_written("unpaid", owed_before, debt)
    assert_eq(frames, 12, "the shot is taken at the bound rather than never")
    assert_true(debt.is_owed(), "with the fold still owed")
    assert_true(SaShotSettle.last_owed_line.contains("unpaid"), "and the log names the shot: %s" % SaShotSettle.last_owed_line)
    assert_true(SaShotSettle.last_owed_line.contains("fold owed"), "as taken with a fold owed")
