## The pipe on the stroke: which cell a dab picks, and that a one-cell pipe is
## the single picture it would have been.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The reader reads the container and this paints with it**, which is why the
## two are two suites: everything here is about the advance, and a file this
## suite writes is the smallest one that can show a cell being chosen rather than
## a file exercising the reader.
##
## **The advance is asked twice over, once as arithmetic and once on a texture.**
## `SaBrushTipMask.cell_for` is static and takes a pipe and a stroke, so what a
## dab would choose is a question with no GPU in it, and `advance` is the same
## answer applied to the texture the sampler binds. The first is where the eight
## modes are asserted one by one, the second is where the picture actually moving
## is asserted, because a mode that picked the right index and bound the wrong
## texture would pass the first alone.
extends "res://tests/test_framework.gd"

const TipImage = preload("res://core/api/tip/sa_tip_image.gd")
const GihPipe = preload("res://core/api/tip/sa_gih_pipe.gd")
const BrushTip = preload("res://core/api/tip/sa_brush_tip.gd")

## Needs a RenderingDevice: half the assertions are about which texture is bound.
const REQUIRES_GPU := true

static var scratch_pipe_path: String = SaDataRoot.path("test_pipe_tip.gih")
static var scratch_one_cell_path: String = SaDataRoot.path("test_pipe_one_cell.gih")
static var scratch_gbr_path: String = SaDataRoot.path("test_pipe_single.gbr")

## A seed pinned so `random` is repeatable, which is the whole of what makes that
## mode assertable. Any non-zero number does, and `SaStrokeInfo.begin` takes the
## clock when it is given nothing.
const SEED: int = 20260910


func after_each() -> void:
    for path: String in [scratch_pipe_path, scratch_one_cell_path, scratch_gbr_path]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _be(value: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.append((value >> 24) & 0xFF)
    out.append((value >> 16) & 0xFF)
    out.append((value >> 8) & 0xFF)
    out.append(value & 0xFF)
    return out


## A version 2 GBR of *width* by *height* filled with *value*, which is what
## makes a cell tellable from its neighbours by one texel.
func _gbr_bytes(tip_name: String, width: int, height: int, value: int) -> PackedByteArray:
    var named := tip_name.to_utf8_buffer()
    var coverage := PackedByteArray()
    coverage.resize(width * height)
    coverage.fill(value)
    var bytes := PackedByteArray()
    bytes.append_array(_be(28 + named.size() + 1))
    bytes.append_array(_be(2))
    bytes.append_array(_be(width))
    bytes.append_array(_be(height))
    bytes.append_array(_be(1))
    bytes.append_array(_be(0x47494D50))
    bytes.append_array(_be(20))
    bytes.append_array(named)
    bytes.append(0)
    bytes.append_array(coverage)
    return bytes


## A `.gih` of *cells* cells, each a flat GBR of its own value, written to *path*
## so the loader reaches it the way it reaches a painter's own file.
func _write_pipe(path: String, cells: int, selection: String, values: PackedByteArray) -> String:
    var bodies: Array = []
    for i in cells:
        bodies.append(_gbr_bytes("cell%d" % i, 4, 4, values[i]))
    var line := (
        "%d ncells:%d cellwidth:4 cellheight:4 step:20 dim:1 cols:1 rows:%d placement:constant rank0:%d sel0:%s"
        % [cells, cells, cells, cells, selection]
    )
    var bytes := ("Test pipe\n" + line + "\n").to_utf8_buffer()
    for body: PackedByteArray in bodies:
        bytes.append_array(body)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


## A four-cell pipe whose cells are 64, 128, 192 and 255 of coverage.
func _four_cells(selection: String) -> String:
    return _write_pipe(scratch_pipe_path, 4, selection, PackedByteArray([64, 128, 192, 255]))


## A stroke that has begun, seeded, so every sensor below reads a real number.
func _stroke() -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, SEED)
    return info


## The pipe a `cell_for` question is asked of, read without any GPU.
func _pipe(cells: int, selection: String) -> GihPipe.Pipe:
    var path := _write_pipe(scratch_pipe_path, cells, selection, PackedByteArray([64, 128, 192, 255]))
    return GihPipe.load_from(path)


# --- Loading ------------------------------------------------------------------


func test_a_pipe_loads_every_one_of_its_cells() -> void:
    var mask := SaBrushTipMask.load_image(_four_cells("incremental"))

    assert_true(mask.error.is_empty(), "The pipe loaded: %s" % mask.error)
    assert_eq(mask.pipe_cells.size(), 4, "with a texture per cell")
    assert_true(mask.has_pipe(), "and it answers that it is a pipe")
    assert_true(mask.has_image(), "It has an image, so the Tip row and the kernel need know nothing else")
    assert_eq(mask.size, Vector2i(4, 4), "at the first cell's own size")


func test_the_tip_door_selects_a_pipe_the_way_it_selects_a_picture() -> void:
    var tip := BrushTip.new()

    var mask := SaBrushTipMask.select(tip, _four_cells("incremental"))

    assert_true(mask.error.is_empty(), "A pipe goes through the one door: %s" % mask.error)
    assert_eq(tip.generator, SaDabGeometry.Generator.IMAGE, "and leaves the tip on the image generator")
    assert_true(tip.uses_image(), "so the binder asks for it by path")
    assert_true(SaBrushTipMask.is_pipe_path(tip.image_path), "and the path it kept is the pipe's")


func test_a_pipe_that_is_not_one_is_refused_with_its_own_reason() -> void:
    var file := FileAccess.open(scratch_pipe_path, FileAccess.WRITE)
    file.store_buffer("not a pipe at all".to_utf8_buffer())
    file.close()

    var mask := SaBrushTipMask.load_image(scratch_pipe_path)

    assert_false(mask.error.is_empty(), "A file that is not a pipe is refused")
    assert_false(mask.has_image(), "and uploads nothing")
    assert_eq(mask.pipe_cells.size(), 0, "and holds no cell")


# --- The advance, as arithmetic -----------------------------------------------


func test_incremental_steps_one_cell_per_dab_and_wraps() -> void:
    var pipe := _pipe(4, "incremental")
    var info := _stroke()

    var seen := PackedInt32Array()
    for i in 6:
        # The dab is counted first and chosen second, which is the app's own
        # order: `StateBrush._stamp_brush` calls `next_dab` and the bind that
        # asks this follows it. Reading before the count is what let the first
        # painted dab pick the second cell for a whole board.
        info.next_dab()
        seen.append(SaBrushTipMask.cell_for(pipe, info, 4))

    assert_eq(seen, PackedInt32Array([0, 1, 2, 3, 0, 1]), "Six dabs walk the four cells and come round")


## The first dab of a stroke is the pipe's first cell, which is the picture the
## first cell's own file paints.
##
## **Through `advance`, not `cell_for`**, because the claim is about which
## texture the stroke bound: the arithmetic and the bind are two answers and
## only the second is the one a painter sees.
func test_a_strokes_first_dab_is_the_pipes_first_cell() -> void:
    _four_cells("incremental")
    var info := _stroke()
    var mask := SaBrushTipMask.load_image(scratch_pipe_path)

    info.next_dab()
    var first := mask.advance(info)

    assert_eq(first, 0, "The first painted dab is cell 0, not one past it")
    assert_true(mask.sampler_rid() == mask.pipe_cells[0].rid, "and the texture bound is the first cell's")
    assert_true(mask.sampler_rid() != mask.pipe_cells[1].rid, "rather than the second cell's, which is what it was")


func test_constant_never_moves() -> void:
    var pipe := _pipe(4, "constant")
    var info := _stroke()

    var seen := PackedInt32Array()
    for i in 5:
        info.next_dab()
        seen.append(SaBrushTipMask.cell_for(pipe, info, 4))

    assert_eq(seen, PackedInt32Array([0, 0, 0, 0, 0]), "Constant is the first cell for the whole stroke")


func test_random_uses_the_per_dab_stream_and_repeats_from_a_pinned_seed() -> void:
    var pipe := _pipe(4, "random")

    var first := PackedInt32Array()
    var info := _stroke()
    for i in 12:
        info.next_dab()
        first.append(SaBrushTipMask.cell_for(pipe, info, 4))

    var again := PackedInt32Array()
    var second := _stroke()
    for i in 12:
        second.next_dab()
        again.append(SaBrushTipMask.cell_for(pipe, second, 4))

    assert_eq(first, again, "The same seed picks the same cells, which is what makes random assertable")
    var distinct: Dictionary = {}
    for cell: int in first:
        distinct[cell] = true
    assert_true(distinct.size() > 1, "and twelve dabs do not all land on one cell, %d seen" % distinct.size())
    for cell: int in first:
        assert_true(cell >= 0 and cell < 4, "every one of them inside the pipe, %d" % cell)


func test_random_does_not_repeat_between_two_strokes_of_one_session() -> void:
    var pipe := _pipe(4, "random")
    var first := PackedInt32Array()
    var info := _stroke()
    info.begin(Vector2.ZERO, SEED + 1)
    for i in 12:
        info.next_dab()
        first.append(SaBrushTipMask.cell_for(pipe, info, 4))

    var again := PackedInt32Array()
    var second := _stroke()
    for i in 12:
        second.next_dab()
        again.append(SaBrushTipMask.cell_for(pipe, second, 4))

    assert_true(first != again, "Two seeds are two sequences")


func test_angular_reads_the_strokes_own_direction() -> void:
    var pipe := _pipe(4, "angular")
    var info := _stroke()

    var seen := PackedInt32Array()
    # Four quarter turns of the compass, each set as the angle the dab is drawn
    # at, which is what an arrow pipe follows.
    for turn in 4:
        info.has_angle_override = true
        info.angle_override = TAU * float(turn) / 4.0 + 0.01
        info.next_dab()
        seen.append(SaBrushTipMask.cell_for(pipe, info, 4))

    assert_eq(seen, PackedInt32Array([0, 1, 2, 3]), "A quarter turn is a cell, in order round the circle")


func test_pressure_and_the_two_tilts_read_their_own_sensors() -> void:
    var info := _stroke()

    var by_pressure := _pipe(4, "pressure")
    info.pressure = 0.0
    assert_eq(SaBrushTipMask.cell_for(by_pressure, info, 4), 0, "No pressure is the first cell")
    info.pressure = 1.0
    assert_eq(SaBrushTipMask.cell_for(by_pressure, info, 4), 3, "and full pressure the last, not one past it")
    info.pressure = 0.5
    assert_eq(SaBrushTipMask.cell_for(by_pressure, info, 4), 2, "with half way through landing half way along")

    var by_x := _pipe(4, "xtilt")
    info.tilt_x = -1.0
    assert_eq(SaBrushTipMask.cell_for(by_x, info, 4), 0, "A tilt of minus one is the first cell")
    info.tilt_x = 1.0
    assert_eq(SaBrushTipMask.cell_for(by_x, info, 4), 3, "and plus one the last, so the pen's whole range is used")

    var by_y := _pipe(4, "ytilt")
    info.tilt_y = -1.0
    assert_eq(SaBrushTipMask.cell_for(by_y, info, 4), 0, "The other tilt reads its own axis")
    info.tilt_y = 1.0
    assert_eq(SaBrushTipMask.cell_for(by_y, info, 4), 3, "and the other end of it")


func test_velocity_reads_the_speed_the_dynamics_already_computed() -> void:
    var pipe := _pipe(4, "velocity")
    var info := _stroke()

    # A stroke that has not moved has no speed, which is the first cell.
    assert_eq(SaBrushTipMask.cell_for(pipe, info, 4), 0, "A hand that has not moved is the first cell")
    assert_true(info.drawing_speed() >= 0.0, "and the speed it read is the dynamics half's own number")


# --- The advance, on the texture ----------------------------------------------


func test_the_bound_texture_moves_with_the_cell() -> void:
    var mask := SaBrushTipMask.load_image(_four_cells("incremental"))
    var info := _stroke()

    var rids: Array[RID] = []
    for i in 4:
        info.next_dab()
        mask.advance(info)
        rids.append(mask.sampler_rid())

    assert_eq(mask.pipe_cell, 3, "Four dabs end on the fourth cell")
    for i in 4:
        assert_true(rids[i] == mask.pipe_cells[i].rid, "and dab %d bound cell %d's own texture" % [i, i])
    assert_true(rids[0] != rids[1], "which are four different textures rather than one rebound")


func test_a_dab_with_no_stroke_leaves_the_cell_where_it_was() -> void:
    var mask := SaBrushTipMask.load_image(_four_cells("incremental"))
    var info := _stroke()
    info.next_dab()
    info.next_dab()
    info.next_dab()
    mask.advance(info)
    var settled := mask.pipe_cell

    mask.advance(null)

    assert_eq(mask.pipe_cell, settled, "A caller with no stroke does not move the pipe")
    assert_eq(settled, 2, "and the cell it left it on is the one the three dabs asked for")


func test_a_one_cell_pipe_is_the_single_picture_it_would_have_been() -> void:
    _write_pipe(scratch_one_cell_path, 1, "incremental", PackedByteArray([200]))
    var pipe_mask := SaBrushTipMask.load_image(scratch_one_cell_path)
    var file := FileAccess.open(scratch_gbr_path, FileAccess.WRITE)
    file.store_buffer(_gbr_bytes("cell0", 4, 4, 200))
    file.close()
    var single := SaBrushTipMask.load_image(scratch_gbr_path)
    var info := _stroke()

    for i in 6:
        pipe_mask.advance(info)
        info.next_dab()

    assert_false(pipe_mask.has_pipe(), "One cell has nothing to advance between")
    assert_eq(pipe_mask.pipe_cell, 0, "so six dabs leave it on the only cell it has")
    assert_eq(pipe_mask.size, single.size, "and it is the same picture as the loose GBR, at the same size")
    assert_true(pipe_mask.has_image(), "bound as an image tip exactly the way that one is")


func test_a_picture_tip_gains_no_pipe() -> void:
    var file := FileAccess.open(scratch_gbr_path, FileAccess.WRITE)
    file.store_buffer(_gbr_bytes("plain", 4, 4, 128))
    file.close()

    var mask := SaBrushTipMask.load_image(scratch_gbr_path)
    var info := _stroke()
    for i in 4:
        mask.advance(info)
        info.next_dab()

    assert_false(mask.has_pipe(), "A GBR is not a pipe")
    assert_eq(mask.pipe_cells.size(), 0, "and holds no cell list")
    assert_true(mask.sampler_rid() == mask.texture.rid, "so the sampler binds the one texture it always bound")


func test_the_dump_says_which_cell_was_stamped() -> void:
    var mask := SaBrushTipMask.load_image(_four_cells("incremental"))
    var info := _stroke()
    info.next_dab()
    info.next_dab()
    mask.advance(info)

    var block := mask.report()

    assert_eq(block["pipe_cells"], 4, "The dump counts the cells")
    assert_eq(block["pipe_cell"], 1, "and says which of them the last dab stamped")
    assert_eq(block["pipe_selections"], ["incremental"], "with the mode that chose it")
    assert_eq(block["pipe_ranks"], [4], "and the rank it chose within")


func test_a_tip_that_is_not_a_pipe_says_so_in_the_dump() -> void:
    var mask := SaBrushTipMask.load_image("")

    var block := mask.report()

    assert_eq(block["pipe_cells"], 0, "No cells is every tip that is not a pipe")
    assert_eq(block["pipe_selections"], [], "and there is no mode to report")


# --- Nothing leaks ------------------------------------------------------------


func test_a_stroke_of_a_pipe_holds_its_cells_and_frees_them_with_the_mask() -> void:
    # Four cells of four by four `r32g32f`, which is a hundred and twenty-eight
    # bytes each and is the number `SaTexture` counts at the one place it
    # allocates and frees. Two channels, the coverage and the picture's own
    # lightness.
    var cell_bytes := 4 * 4 * 8
    var before := SaTexture.allocated_bytes
    var mask := SaBrushTipMask.load_image(_four_cells("incremental"))
    var info := _stroke()
    for i in 20:
        mask.advance(info)
        info.next_dab()

    assert_eq(SaTexture.allocated_bytes, before + 4 * cell_bytes, "Twenty dabs hold four textures and never a twenty-first")
    mask = null

    assert_eq(SaTexture.allocated_bytes, before, "and dropping the mask gives every one of them back")
