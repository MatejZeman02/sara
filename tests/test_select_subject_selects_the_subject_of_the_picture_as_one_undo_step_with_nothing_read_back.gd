## Select Subject selects the subject of the picture as one
## undo step with nothing read back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A document is made from the teapot, the third photograph, `teapot.jpg`
## beside this file, and Select Subject runs on it. The selection's coverage is
## read back the way the wand's suites read it, which a suite may, and held to
## the reference's mask from `reference_p3.bin` resized bilinearly to the
## photograph. The weights come from the module's data folder or the path
## `SARA_U2NETP_PTH` names, copied into the data folder for the run, and
## without either every case that runs the network says so and skips.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const SubjectSelection = preload("../selection/subject_selection.gd")
const WeightsServer = preload("weights_server.gd")
const WeightsDownload = preload("../weights_download.gd")
const HardRules = preload("res://tests/test_hard_rules.gd")

const REQUIRES_GPU := true
const HERE := "res://modules/sara-background-removal/tests/"
const MODULE := "res://modules/sara-background-removal/"
const REAL_WEIGHTS_VARIABLE := "SARA_U2NETP_PTH"
## The teapot at the size the suite uses, 1,600 by 1,067.
const PHOTOGRAPH := HERE + "teapot.jpg"
const SIZE := Vector2i(1600, 1067)
const SIDE := 320

## The most the selection's coverage may differ from the reference's mask
## resized to the photograph, on average over the canvas. Measured at 0.00049
## on the merged picture and the same on the layer alone, so the bound has a
## margin of four times. The two inputs differ in the rescale, a box of sixteen
## taps here and a Gaussian and then bilinear in the reference.
const MEAN_BOUND := 0.002
## The most the subtract may differ from the previous selection less the
## subject's coverage at any pixel.
const SUBTRACT_TOLERANCE := 0.000001
## The frames a download of the real weights is given, a 16 KiB piece a frame.
const PATIENCE := 1200
## The files of the command's run, which may hold no read of a texture or a
## buffer.
const RUN_FILES: Array[String] = [
    "module.gd",
    "select_subject_tool.gd",
    "selection/subject_selection.gd",
    "network/subject_network.gd",
]

var _registries: SaRegistries = null
var _module: SaModule = null
var _surface: SaSurface = null
var _server: Node = null
## Whether this run copied the weights into the data folder, so it takes
## them away again.
var _copied: bool = false


func before_each() -> void:
    _surface = SaTestFixtures.make_surface(SIZE)
    _registries = SaTestFixtures.make_menu_registries()
    var surface := _surface
    _registries.build_context(func() -> SaEasel: return surface.easel, func() -> Array: return [surface], SaAppDrive.new())
    _module = SubjectModule.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    var layer := SaImageImport.open_into(_surface.get_document(), ProjectSettings.globalize_path(PHOTOGRAPH))
    assert_not_null(layer, "the teapot opens as a layer")
    # Composited as a frame of the running app would, since nothing here draws one.
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    await (Engine.get_main_loop() as SceneTree).process_frame


func after_each() -> void:
    if _server != null and is_instance_valid(_server):
        _server.queue_free()
    _server = null
    if _module != null:
        if _copied:
            DirAccess.remove_absolute(_module.weights_path())
        _module.unregister(_registries.context)
    _copied = false
    _module = null
    _registries = null
    SaTestFixtures.teardown(_surface)
    _surface = null


## Whether the weights are in the data folder, put there from the variable's
## path when they are not. Skips the case when neither has them.
func _weights() -> bool:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no rendering device to run the kernels on")
        return false
    if _module.has_weights():
        return true
    var path := OS.get_environment(REAL_WEIGHTS_VARIABLE)
    if path.is_empty() or not FileAccess.file_exists(path):
        skip("no u2netp.pth in the module's data folder and %s names none" % REAL_WEIGHTS_VARIABLE)
        return false
    DirAccess.copy_absolute(path, _module.weights_path())
    _copied = true
    return _module.has_weights()


func _document() -> SaDocument:
    return _surface.get_document()


## The selection's coverage over the canvas, row after row, read back chunk by
## chunk as the wand's suites read it, nought where no chunk is.
func _coverage() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(SIZE.x * SIZE.y)
    var selection := _document().selection
    for grid_pos: Vector2i in selection.chunks:
        var texture: SaTexture = selection.chunks[grid_pos].field(SaSelection.FIELD)
        var texels := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
        var origin := grid_pos * SaChunk.SIZE
        for y: int in texture.size.y:
            var row := origin.y + y
            if row >= SIZE.y:
                break
            for x: int in texture.size.x:
                var column := origin.x + x
                if column < SIZE.x:
                    out[row * SIZE.x + column] = texels[y * texture.size.x + x]
    return out


## The reference's mask of the teapot at 320 by 320.
static func _reference_mask() -> PackedFloat32Array:
    var bytes := FileAccess.get_file_as_bytes(HERE + "reference_p3.bin").decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
    var plane := SIDE * SIDE
    var mask := PackedFloat32Array()
    mask.resize(plane)
    for at: int in plane:
        mask[at] = bytes.decode_u16(3 * plane + 2 * at) / 65535.0
    return mask


## *mask* resized bilinearly to the photograph, the corners unaligned, as
## PyTorch's `F.upsample` and the network's own resampling take it.
static func _resized(mask: PackedFloat32Array) -> PackedFloat32Array:
    var columns := _taps(SIZE.x)
    var rows := _taps(SIZE.y)
    var out := PackedFloat32Array()
    out.resize(SIZE.x * SIZE.y)
    for y: int in SIZE.y:
        var y0: int = rows[0][y]
        var y1: int = rows[1][y]
        var fy: float = rows[2][y]
        for x: int in SIZE.x:
            var x0: int = columns[0][x]
            var x1: int = columns[1][x]
            var fx: float = columns[2][x]
            var top := (1.0 - fx) * mask[y0 * SIDE + x0] + fx * mask[y0 * SIDE + x1]
            var bottom := (1.0 - fx) * mask[y1 * SIDE + x0] + fx * mask[y1 * SIDE + x1]
            out[y * SIZE.x + x] = (1.0 - fy) * top + fy * bottom
    return out


## Along one axis of *size* pixels: the first mask texel each reads, the
## second, and the fraction of the second.
static func _taps(size: int) -> Array:
    var first := PackedInt32Array()
    var second := PackedInt32Array()
    var fraction := PackedFloat32Array()
    for at: int in size:
        var real := maxf(float(SIDE) / size * (at + 0.5) - 0.5, 0.0)
        var low := mini(floori(real), SIDE - 1)
        first.append(low)
        second.append(mini(low + 1, SIDE - 1))
        fraction.append(minf(real - low, 1.0))
    return [first, second, fraction]


static func _mean_difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    var total := 0.0
    for at: int in a.size():
        total += absf(a[at] - b[at])
    return total / maxf(1.0, a.size())


## The box of the pixels where *coverage* passes a half, the subject's.
static func _box_over_half(coverage: PackedFloat32Array) -> Rect2i:
    var low := Vector2i(SIZE.x, SIZE.y)
    var high := Vector2i(-1, -1)
    for y: int in SIZE.y:
        for x: int in SIZE.x:
            if coverage[y * SIZE.x + x] > 0.5:
                low = Vector2i(mini(low.x, x), mini(low.y, y))
                high = Vector2i(maxi(high.x, x), maxi(high.y, y))
    return Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i()


func test_the_teapot_s_selection_is_the_reference_mask_resized_to_the_photograph() -> void:
    if not _weights():
        return
    var expected := _resized(_reference_mask())
    for merged: bool in [true, false]:
        var reached: bool = _module.select_subject(SaSelection.Mode.REPLACE, merged, _surface)
        assert_true(reached, "Select Subject runs, and says: %s" % _module.said)
        var coverage := _coverage()
        var difference := _mean_difference(coverage, expected)
        var read := "the merged picture" if merged else "the active layer"
        print("    reading %s, the selection differs from the reference's mask by %.5f on average" % [read, difference])
        assert_true(
            difference <= MEAN_BOUND,
            "reading %s, the selection is the reference's mask within %.4f on average, at %.5f" % [read, MEAN_BOUND, difference]
        )
        var teapot := _box_over_half(expected)
        var bounds := _document().selection.bounds
        print("    the teapot's box is %s and the selection's bounds %s" % [teapot, bounds])
        assert_true(
            teapot.size.x > 0 and bounds.encloses(teapot), "the selection's bounds %s enclose the teapot's %s" % [bounds, teapot]
        )
        var subject := _box_over_half(coverage)
        print("    the selection passes a half over %s, where the ants go" % subject)
        assert_true(
            subject.size.x > 0 and subject.grow(8).encloses(teapot) and teapot.grow(8).encloses(subject),
            "and where it passes a half is the teapot's box within 8 pixels, %s against %s" % [subject, teapot]
        )


func test_one_undo_takes_the_selection_away_and_one_redo_brings_it_back() -> void:
    if not _weights():
        return
    var document := _document()
    var steps := document.undo_redo.get_history_count()
    assert_true(_module.select_subject(SaSelection.Mode.REPLACE, true, _surface), "Select Subject runs")
    assert_eq(document.undo_redo.get_history_count(), steps + 1, "one history step")
    assert_eq(document.undo_redo.get_current_action_name(), SubjectSelection.TITLE, "titled for Select Subject")
    var selected := _coverage()
    document.undo_redo.undo()
    assert_false(document.selection.active, "one undo leaves nothing selected")
    assert_true(document.selection.chunks.is_empty(), "and no chunk of it")
    document.undo_redo.redo()
    assert_true(document.selection.active, "one redo selects again")
    assert_eq(_mean_difference(_coverage(), selected), 0.0, "the same coverage")


func test_a_subtract_takes_the_subject_out_of_the_selection_before() -> void:
    if not _weights():
        return
    var document := _document()
    assert_true(_module.select_subject(SaSelection.Mode.REPLACE, true, _surface), "Select Subject runs")
    var subject := _coverage()
    document.selection.select_all(document.canvas_size)
    var steps := document.undo_redo.get_history_count()
    assert_true(_module.select_subject(SaSelection.Mode.SUBTRACT, true, _surface), "and runs again with Alt")
    assert_eq(document.undo_redo.get_history_count(), steps + 1, "as one step")
    var left := _coverage()
    var worst := 0.0
    for at: int in left.size():
        worst = maxf(worst, absf(left[at] - clampf(1.0 - subject[at], 0.0, 1.0)))
    print("    the subtract from everything differs from one less the subject by at most %s" % String.num_scientific(worst))
    assert_true(
        worst <= SUBTRACT_TOLERANCE,
        "everything less the subject is one less its coverage, within %s, at %s" % [SUBTRACT_TOLERANCE, worst]
    )


func test_the_run_reads_back_neither_the_picture_nor_the_mask() -> void:
    for path: String in RUN_FILES:
        assert_false(
            HardRules.READBACK_ALLOWED.has("modules/sara-background-removal/" + path), "%s is not allowed a readback" % path
        )
        var text := FileAccess.get_file_as_string(MODULE + path)
        for word: String in ["texture_get_data", "buffer_get_data", ".read(", ".ask(", "get_image("]:
            assert_false(text.contains(word), "%s holds no %s" % [path, word])
    if not _weights():
        return
    # Built first, so the read of the weights' file is not the run's.
    assert_eq(_module.subject_network().error, "", "the network is made over the real weights")
    var was := SaGpuTiming.enabled
    SaGpuTiming.enabled = true
    SaGpuTiming.reset()
    assert_true(_module.select_subject(SaSelection.Mode.REPLACE, true, _surface), "Select Subject runs")
    var reads: Dictionary = SaGpuTiming.block()["reads"]
    SaGpuTiming.reset()
    var region := {}
    for grid_pos: Vector2i in _document().selection.chunks:
        region[grid_pos] = _document().selection.chunks[grid_pos]
    _document().selection.deselect()
    _document().selection.merge_region(region, SaSelection.Mode.REPLACE)
    var merge_reads: Dictionary = SaGpuTiming.block()["reads"]
    SaGpuTiming.enabled = was
    print("    the run's reads %s, the merge's alone %s" % [reads, merge_reads])
    assert_eq(_count(reads), _count(merge_reads), "the run reads the card as often as the selection's merge alone does, its box")
    assert_eq(_count(reads), 1, "once, the four numbers of the box")


static func _count(reads: Dictionary) -> int:
    var total := 0
    for key: String in reads:
        total += int(reads[key]["reads"])
    return total


func test_a_click_shows_the_busy_cursor_while_it_runs() -> void:
    if not _weights():
        return
    var tree := Engine.get_main_loop() as SceneTree
    var shape := DisplayServer.cursor_get_shape()
    _module.click(SaSelection.Mode.REPLACE, true, _surface)
    assert_true(_module.busy, "the click is running")
    assert_eq(DisplayServer.cursor_get_shape(), DisplayServer.CURSOR_BUSY, "with the busy cursor up before the run")
    for _frame: int in 30:
        if not _module.busy:
            break
        await tree.process_frame
    assert_false(_module.busy, "the run ends")
    assert_eq(DisplayServer.cursor_get_shape(), shape, "and gives the cursor back")
    assert_true(_document().selection.active, "having selected the subject")


func test_with_no_weights_the_click_offers_the_download_and_runs_once_they_are_kept() -> void:
    if not _weights():
        return
    var bytes := FileAccess.get_file_as_bytes(_module.weights_path())
    var digest := FileAccess.get_sha256(_module.weights_path())
    DirAccess.remove_absolute(_module.weights_path())
    _copied = true
    _server = WeightsServer.new(bytes)
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.add_child(_server)
    # Registries of its own, since a tool is registered once a registry.
    var own := SaTestFixtures.make_menu_registries()
    var surface := _surface
    own.build_context(func() -> SaEasel: return surface.easel, func() -> Array: return [surface], SaAppDrive.new())
    var served := SubjectModule.new(_server.url(), digest)
    served.register(own.context.for_module(served.get_id()))
    served.click(SaSelection.Mode.REPLACE, true, _surface)
    assert_true(served.dialog != null and served.dialog.visible, "a click with no weights opens the download's dialog")
    assert_false(_document().selection.active, "and selects nothing yet")
    served.dialog.accept()
    for _frame: int in PATIENCE:
        await tree.process_frame
        if _document().selection.active:
            break
    assert_true(served.has_weights(), "Accept keeps the weights: %s" % served.dialog.status.text)
    assert_true(_document().selection.active, "and the click runs once they are kept")
    assert_eq(_document().undo_redo.get_current_action_name(), SubjectSelection.TITLE, "as Select Subject's step")
    served.unregister(own.context)
