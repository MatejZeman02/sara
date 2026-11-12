## A run exports as numbered frames, one picture every so many
## steps, named by the step it shows, a few steps a frame, and the layer left
## at the last step written.
##
## The suite registers the `shift_right`, which moves every cell one texel
## right a step, so a stroke in picture *n* stands *n* texels right of where it
## was painted, and a picture out of order or a step lost shows as a column.
## Each picture is written by the PNG export the File menu's dialog runs, and
## read back from the disk by [method SaSimulation.Frames.read_back], the
## helper the scenario's state dump reads the files through as well.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const ROW := 10
## The painted stroke, three texels long, from this column.
const PAINTED_X := 100
const LENGTH := 3
const BLUE := Color(0.2, 0.4, 0.9, 1.0)

var _registries: SaRegistries
var _easels: Array[SaEasel] = []
var _folder: String = ""


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false
    _registries = Fixtures.make_registries()
    var suite := _registries.context.for_module(&"k9-suite")
    suite.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)
    _folder = SaDataRoot.path("k9-frames")
    _empty_folder()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))


func after_each() -> void:
    SaProblems.announce = true
    SaProblems.pending_refusals = PackedStringArray()
    for easel in _easels:
        easel.free()
    _easels.clear()
    _empty_folder()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_folder))


func _empty_folder() -> void:
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_folder)):
        return
    for file: String in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_folder.path_join(file)))


## An easel of two chunks, the background emptied and the stroke painted on
## it, with the test rule on it, active.
func _easel() -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    var stroke := {}
    for x in LENGTH:
        stroke[Vector2i(PAINTED_X + x, ROW)] = BLUE
    _fill(layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), stroke)
    _fill(layer.get_or_create_chunk(Vector2i(1, 0)).albedo(), {})
    easel.document.set_active_layer(layer)
    SaSimulation.put_on(layer, _registries.simulation_rules.find(&"shift_right"))
    return easel


## *texture* transparent but for the texels of *texels*, position to colour.
func _fill(texture: SaTexture, texels: Dictionary) -> void:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    for at: Vector2i in texels:
        image.set_pixelv(at, texels[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## A run over *easel*'s simulated layer, every picture a PNG through the
## export the dialog runs. The step the picture shows was taken in the same
## frame, so the writer composites what it marked first, as the dialog's does
## and as Copy Merged does, because the export's own flush takes only what the
## window held back.
func _run(easel: SaEasel, steps: int, every: int, file_name: String = "spread.png") -> SaSimulation.Frames:
    var document := easel.document
    var writer := func(path: String) -> Error:
        easel.process_pending_composite()
        return SaExport.export_png(easel, path)
    return SaSimulation.Frames.new(
        document,
        SaSimulation.simulated_layer(document),
        _registries.simulation_rules,
        _folder.path_join(file_name),
        steps,
        every,
        writer
    )


## Advances *run* a frame at a time until it ends, and answers how many frames
## of the app it took.
func _drive(run: SaSimulation.Frames, most: int = 400) -> int:
    var frames := 0
    while frames < most:
        frames += 1
        if not run.advance():
            break
    return frames


## The leftmost column of row [constant ROW] that shows the blue stroke, or
## -1 for a picture with none. Blue against red tells it from a paper of any
## grey and from a transparent texel alike.
func _stroke_at(picture: Image) -> int:
    if picture == null:
        return -1
    for x in picture.get_width():
        var texel := picture.get_pixel(x, ROW)
        if texel.a > 0.5 and texel.b > texel.r + 0.3:
            return x
    return -1


func _names(paths: PackedStringArray) -> Array[String]:
    var out: Array[String] = []
    for path: String in paths:
        out.append(path.get_file())
    return out


func test_ten_steps_export_as_ten_pngs_named_in_order_each_one_texel_further_right() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    var run := _run(easel, 10, 1)
    assert_eq(run.problem, "", "The run starts on a layer with a simulation")
    var frames := _drive(run)
    assert_true(run.finished, "The run ends")
    assert_eq(run.problem, "", "with nothing refused")
    assert_eq(frames, 10, "one picture a frame of the app, at a picture a step")
    var listed := SaSimulation.Frames.listed(_folder.path_join("spread.png"))
    var want: Array[String] = []
    for step in range(1, 11):
        want.append("spread_%s.png" % str(step).pad_zeros(4))
    assert_eq(_names(listed), want, "Ten files, named by their steps, padded so they sort")
    assert_eq(_names(run.written), want, "in the order the run wrote them")
    var pictures := SaSimulation.Frames.read_back(listed)
    for index in pictures.size():
        assert_eq(
            _stroke_at(pictures[index]),
            PAINTED_X + index + 1,
            "%s shows the stroke %d texels right of where it was painted" % [listed[index].get_file(), index + 1]
        )
    assert_eq(SaSimulation.record_of(layer).steps, 10, "The layer stands at the last step written")
    assert_false(SaSimulation.record_of(layer).playing, "and paused")


func test_every_third_of_ten_steps_writes_the_steps_it_names_and_stops_at_the_last_written() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    var run := _run(easel, 10, 3, "third.png")
    assert_eq(run.count, 3, "Ten steps at a picture every third are three pictures")
    var frames := _drive(run)
    assert_eq(frames, 3, "Three steps and a picture fit a frame of the app")
    assert_eq(
        _names(SaSimulation.Frames.listed(_folder.path_join("third.png"))),
        ["third_0003.png", "third_0006.png", "third_0009.png"] as Array[String],
        "The pictures are of steps 3, 6 and 9"
    )
    var pictures := SaSimulation.Frames.read_back(run.written)
    for index in pictures.size():
        assert_eq(_stroke_at(pictures[index]), PAINTED_X + 3 * (index + 1), "Picture %d is three steps on" % (index + 1))
    assert_eq(SaSimulation.record_of(layer).steps, 9, "and the layer stands at step 9, the last written, not at 10")
    var short := _run(easel, 2, 5, "short.png")
    assert_eq(short.every, 2, "A picture every five of two steps is a picture every two")
    assert_eq(short.count, 1, "and one picture")
    assert_eq(short.name_for(11), _folder.path_join("short_0011.png"), "named by the step it will show")


func test_a_picture_wider_than_a_frame_of_steps_spreads_over_frames_and_numbers_from_where_the_layer_stood() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    for _i in 5:
        SaSimulation.step(easel.document, layer, _registries.simulation_rules)
    var run := _run(easel, 40, 20, "wide.png")
    assert_eq(run.first_step, 5, "The run starts at the step the layer stands at")
    assert_true(run.advance(), "Eight steps of twenty")
    assert_eq(run.at_step, 5 + SaSimulation.Frames.STEPS_PER_FRAME, "are a frame's share")
    assert_true(run.written.is_empty(), "and write nothing yet")
    var frames := 1 + _drive(run)
    assert_eq(frames, 6, "Forty steps at eight a frame are five frames, and the last ends it")
    assert_eq(
        _names(run.written), ["wide_0025.png", "wide_0045.png"] as Array[String], "The names are the steps the layer reached"
    )
    assert_eq(SaSimulation.record_of(layer).steps, 45, "and it stands at the second")


func test_cancel_finishes_the_picture_under_way_so_the_layer_stands_at_a_step_written() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    var run := _run(easel, 50, 10, "cancelled.png")
    assert_true(run.advance(), "Eight steps of the first ten")
    run.cancel()
    assert_false(run.finished, "Cancel waits for the picture under way")
    assert_false(run.advance(), "which the next frame finishes")
    assert_true(run.finished, "and the run ends")
    assert_eq(_names(run.written), ["cancelled_0010.png"] as Array[String], "with that one picture written")
    assert_eq(SaSimulation.record_of(layer).steps, 10, "and the layer at its step")
    var idle := _run(easel, 50, 10, "idle.png")
    idle.cancel()
    assert_true(idle.finished, "A run cancelled before its first step ends at once")
    assert_false(idle.advance(), "and takes none")
    assert_eq(SaSimulation.record_of(layer).steps, 10, "so the layer stays where it was")
    assert_true(SaSimulation.Frames.listed(_folder.path_join("idle.png")).is_empty(), "and nothing is written")


func test_a_layer_stepped_from_elsewhere_stops_the_run_and_says_why() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    var run := _run(easel, 4, 1, "moved.png")
    assert_true(run.advance(), "The first picture is written")
    SaSimulation.step(easel.document, layer, _registries.simulation_rules)
    SaProblems.pending_refusals = PackedStringArray()
    assert_false(run.advance(), "A step the run did not take stops it")
    assert_true(run.problem.contains("step 2"), "and the problem says where the layer went: %s" % run.problem)
    assert_eq(SaProblems.pending_refusals.size(), 1, "said once in the corner")
    assert_eq(run.written.size(), 1, "with the one picture it wrote kept")
    var other := SaEasel.create_default(SIZE)
    _easels.append(other)
    var nothing := _run(other, 3, 1, "nothing.png")
    assert_false(nothing.problem.is_empty(), "A document with no simulation has no run")
    assert_true(nothing.finished, "and it ends before it starts")
