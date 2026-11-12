## A layer's thumbnail is current in every shot the harness takes.
##
## A thumbnail redraws at most every quarter second, counted by adding each
## frame's `delta`, and a scenario waits in drawn frames. How much of that
## quarter second a `wait` covered depended on how fast the frames came, so the
## last stroke's redraw landed before the shot on one run and after it on the
## next, and `adjust-value-graph`'s `0-painted` differed from itself on the
## active layer's row. `SaCaptureRun.shoot` now settles every thumbnail in the
## tree before it draws.
##
## Each case below marks a thumbnail dirty, shoots through a run, and reads the
## thumbnail after. The runner is synchronous and never reaches a frame's
## `_process`, which is the interval not having passed, so a shot that did not
## settle would find the picture exactly as the dirty mark left it. The
## running-app proof is `scenarios/adjust-value-graph.json` shot four times
## and compared with `scripts/shot_diff.py`.
##
## A settle that gave a picture a texture or took one away
## asks for the shot again a frame later, because the slot on screen names the
## old texture until a frame draws it. No frame runs here, so each shot below is
## the settle and that request, and the picture is written by the frame after.
extends "res://tests/test_framework.gd"

## The redraw is a compute dispatch over the layer's chunks, and the shot draws
## the root viewport.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the run writes its shot, removed after each case.
static var scratch_out_dir: String = SaDataRoot.path("d1_thumbnail_shot_test")

const LABEL := "shot"


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## A thumbnail in the tree, as a docker's row puts it there.
func _thumbnail_in_tree(layer: SaLayer, doc: SaDocument) -> SaLayerThumbnail:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    EventBus.add_child(thumb)
    return thumb


func _shoot() -> SaCaptureRun:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_out_dir))
    var run := SaCaptureRun.new(scratch_out_dir)
    run.shoot(LABEL)
    return run


func _clean_up(thumb: SaLayerThumbnail, easel: SaEasel) -> void:
    thumb.get_parent().remove_child(thumb)
    thumb.free()
    easel.free()
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    DirAccess.remove_absolute(folder.path_join("%s.png" % LABEL))
    DirAccess.remove_absolute(folder)


## Paint that arrived after the thumbnail was bound is in the picture the shot
## draws.
func test_a_shot_takes_the_redraw_a_painted_layer_is_waiting_for() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), doc.active_layer)
    var thumb := _thumbnail_in_tree(doc.active_layer, doc)
    assert_true(thumb._dirty, "the bound picture waits on the interval")
    assert_null(thumb._texture, "and nothing has drawn it yet")

    var run := _shoot()

    assert_false(thumb._dirty, "The shot took the redraw that was waiting")
    assert_not_null(thumb._texture, "and the picture it drew holds the paint")
    assert_eq(run.steps, [{"wait": 1}, {"shot": LABEL}], "The shot is taken the frame that draws it")
    _clean_up(thumb, easel)


## The other direction, which is the stroke that landed after the last redraw:
## the picture was drawn, the layer changed, and the mark is still waiting.
func test_a_shot_takes_the_redraw_a_changed_layer_is_waiting_for() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), layer)
    var thumb := _thumbnail_in_tree(layer, doc)
    thumb.settle()
    assert_not_null(thumb._texture, "the painted layer has a picture")

    layer.release_chunks()
    thumb.mark_dirty()
    var run := _shoot()

    assert_false(thumb._dirty, "The shot took the redraw the change asked for")
    assert_null(thumb._texture, "and the picture is the layer as it is now, empty")
    assert_eq(run.steps, [{"wait": 1}, {"shot": LABEL}], "The shot is taken the frame that draws it")
    _clean_up(thumb, easel)


## Settling is for a picture that waits: one that is current keeps its texture,
## so a shot of a docker full of rows does not redraw every row.
func test_settling_a_current_picture_redraws_nothing() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), layer)
    var thumb := _thumbnail_in_tree(layer, doc)
    thumb.settle()
    assert_not_null(thumb._texture, "the first settle drew the picture")

    # Gone without a mark, so only a redraw nobody asked for would notice.
    layer.release_chunks()
    SaLayerList.settle_thumbnails(EventBus)
    assert_not_null(thumb._texture, "A current picture is left as it stands")
    _clean_up(thumb, easel)
