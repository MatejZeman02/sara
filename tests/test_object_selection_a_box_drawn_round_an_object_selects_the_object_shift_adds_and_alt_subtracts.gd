## Object Selection, a box drawn round an object selects the
## object, Shift adds and Alt subtracts.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two teapots stand side by side on one canvas, the third photograph,
## `teapot.jpg` beside this file, halved and laid twice. Where each teapot is
## comes from the reference's mask, `reference_p3.bin`, resized to the half.
## A box dragged round the right one selects it and none of the left, a Shift
## box round the left adds it, and an Alt box round a part of it takes the
## part away. Round the right teapot the box's ramp from outside to inside is
## held narrower than Select Subject's on the same picture, in pixels across a
## row, since the box gives the teapot the network's whole 320 texels. The weights
## come from the module's data folder or the path `SARA_U2NETP_PTH` names, as
## the subject suite takes them, and without either every case that runs the
## network says so and skips.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const SubjectSelection = preload("../selection/subject_selection.gd")
const ObjectSelectionTool = preload("../object_selection_tool.gd")

const REQUIRES_GPU := true
const HERE := "res://modules/sara-background-removal/tests/"
const REAL_WEIGHTS_VARIABLE := "SARA_U2NETP_PTH"
const PHOTOGRAPH := HERE + "teapot.jpg"
## The photograph's size, and each teapot's half of the pair's canvas.
const PHOTO := Vector2i(1600, 1067)
const HALF := Vector2i(800, 533)
const PAIR := Vector2i(1600, 533)
const SIDE := 320
## How far the dragged box stands off the teapot it is drawn round.
const SLACK := 16
## The least share of a teapot's pixels a selection of it covers, and the most
## of the other's, on average.
const MOST := 0.8
const ALMOST_NONE := 0.02
## The most a part taken away keeps, on average over the teapot's pixels in it.
const TAKEN := 0.2

var _registries: SaRegistries = null
var _module: SaModule = null
var _surface: SaSurface = null
var _size: Vector2i = Vector2i.ZERO
var _copied: bool = false
var _scratch: String = ""


func after_each() -> void:
    if _module != null:
        if _copied:
            DirAccess.remove_absolute(_module.weights_path())
        _module.unregister(_registries.context)
    _copied = false
    _module = null
    _registries = null
    if _surface != null:
        SaTestFixtures.teardown(_surface)
    _surface = null
    if not _scratch.is_empty():
        DirAccess.remove_absolute(_scratch)
    _scratch = ""


## A surface of *size* holding *image*, with the module registered on it.
func _open(image: Image, size: Vector2i) -> void:
    _size = size
    _surface = SaTestFixtures.make_surface(size)
    _registries = SaTestFixtures.make_menu_registries()
    var surface := _surface
    _registries.build_context(func() -> SaEasel: return surface.easel, func() -> Array: return [surface], SaAppDrive.new())
    _module = SubjectModule.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _scratch = OS.get_temp_dir().path_join("sara-%d.png" % OS.get_process_id())
    image.save_png(_scratch)
    var layer := SaImageImport.open_into(_surface.get_document(), _scratch)
    assert_not_null(layer, "the picture opens as a layer")
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    await (Engine.get_main_loop() as SceneTree).process_frame


static func _photograph() -> Image:
    var image := Image.load_from_file(ProjectSettings.globalize_path(PHOTOGRAPH))
    image.convert(Image.FORMAT_RGBA8)
    return image


## The two teapots side by side, each the photograph at half its size.
static func _pair() -> Image:
    var half := _photograph()
    half.resize(HALF.x, HALF.y, Image.INTERPOLATE_CUBIC)
    var pair := Image.create_empty(PAIR.x, PAIR.y, false, Image.FORMAT_RGBA8)
    pair.blit_rect(half, Rect2i(Vector2i.ZERO, HALF), Vector2i.ZERO)
    pair.blit_rect(half, Rect2i(Vector2i.ZERO, HALF), Vector2i(HALF.x, 0))
    return pair


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


## The selection's coverage over the canvas, row after row, nought where no
## chunk is, read back as the subject suite reads it.
func _coverage() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(_size.x * _size.y)
    var selection := _surface.get_document().selection
    for grid_pos: Vector2i in selection.chunks:
        var texture: SaTexture = selection.chunks[grid_pos].field(SaSelection.FIELD)
        var texels := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
        var origin := grid_pos * SaChunk.SIZE
        for y: int in mini(texture.size.y, _size.y - origin.y):
            for x: int in mini(texture.size.x, _size.x - origin.x):
                out[(origin.y + y) * _size.x + origin.x + x] = texels[y * texture.size.x + x]
    return out


## The reference's mask of the teapot resized bilinearly to *size*, the corners
## unaligned, as the subject suite resizes it.
static func _teapot(size: Vector2i) -> PackedFloat32Array:
    var bytes := FileAccess.get_file_as_bytes(HERE + "reference_p3.bin").decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
    var plane := SIDE * SIDE
    var mask := PackedFloat32Array()
    mask.resize(plane)
    for at: int in plane:
        mask[at] = bytes.decode_u16(3 * plane + 2 * at) / 65535.0
    var out := PackedFloat32Array()
    out.resize(size.x * size.y)
    for y: int in size.y:
        var ry := maxf(float(SIDE) / size.y * (y + 0.5) - 0.5, 0.0)
        var y0 := mini(floori(ry), SIDE - 1)
        var y1 := mini(y0 + 1, SIDE - 1)
        var fy := minf(ry - y0, 1.0)
        for x: int in size.x:
            var rx := maxf(float(SIDE) / size.x * (x + 0.5) - 0.5, 0.0)
            var x0 := mini(floori(rx), SIDE - 1)
            var x1 := mini(x0 + 1, SIDE - 1)
            var fx := minf(rx - x0, 1.0)
            var top := (1.0 - fx) * mask[y0 * SIDE + x0] + fx * mask[y0 * SIDE + x1]
            var bottom := (1.0 - fx) * mask[y1 * SIDE + x0] + fx * mask[y1 * SIDE + x1]
            out[y * size.x + x] = (1.0 - fy) * top + fy * bottom
    return out


## The box of the pixels of *mask*, *size* wide, past a half.
static func _box(mask: PackedFloat32Array, size: Vector2i) -> Rect2i:
    var low := size
    var high := Vector2i(-1, -1)
    for y: int in size.y:
        for x: int in size.x:
            if mask[y * size.x + x] > 0.5:
                low = low.min(Vector2i(x, y))
                high = high.max(Vector2i(x, y))
    return Rect2i(low, high - low + Vector2i.ONE)


## The mean of *coverage* over the pair's pixels where the teapot of *half*,
## 0 for the left and 1 for the right, passes a half inside *part*.
func _share(
    coverage: PackedFloat32Array, teapot: PackedFloat32Array, half: int, part: Rect2i = Rect2i(0, 0, 1 << 20, 1 << 20)
) -> float:
    var total := 0.0
    var count := 0
    for y: int in HALF.y:
        for x: int in HALF.x:
            var at := Vector2i(x + half * HALF.x, y)
            if teapot[y * HALF.x + x] > 0.5 and part.has_point(at):
                total += coverage[at.y * PAIR.x + at.x]
                count += 1
    return total / maxf(1.0, count)


## Drags *box* with the tool as a pointer would, in *shift* and *alt*, and
## waits for the run. Answers what the overlay drew halfway through the drag.
func _drag(tool: ObjectSelectionTool, box: Rect2i, shift: bool = false, alt: bool = false) -> Dictionary:
    tool.press(Vector2(box.position), shift, alt)
    tool.drag_to(Vector2(box.position) + Vector2(box.size) * 0.5)
    tool.drag_to(Vector2(box.end))
    var shown := tool.preview_shape()
    var shown_picture := tool.cursor_picture()
    tool.release()
    var tree := Engine.get_main_loop() as SceneTree
    for _frame: int in 60:
        await tree.process_frame
        if not _module.busy:
            break
    return {"shape": shown, "picture": shown_picture}


func _tool() -> ObjectSelectionTool:
    var tool := ObjectSelectionTool.new()
    tool.surface = _surface
    tool.settings = _registries.tools.get_descriptor(SubjectModule.BOX_TOOL).shared_settings
    return tool


func test_the_tool_stands_after_select_subject_in_the_selection_group() -> void:
    await _open(_pair(), PAIR)
    var descriptor: SaToolDescriptor = _registries.tools.get_descriptor(SubjectModule.BOX_TOOL)
    assert_not_null(descriptor, "Object Selection is registered")
    assert_eq(descriptor.display_name, "Object Selection", "under its name")
    assert_eq(descriptor.category, &"select", "in the selection group")
    assert_true(descriptor.reads_keys.has(KEY_SHIFT) and descriptor.reads_keys.has(KEY_ALT), "reading Shift and Alt")
    assert_not_null(SaUI.get_icon(descriptor.icon_name), "with an icon of its own: %s" % descriptor.icon_name)
    assert_eq(descriptor.toolbox_group, &"wand", "in the Magic Wand's group, so W steps through it")
    var rows := SaSettings.get_layout_order(SubjectModule.TOOLBOX)
    assert_eq(
        rows.find(SubjectModule.BOX_TOOLBOX_ROW),
        rows.find(SubjectModule.TOOLBOX_ROW) + 1,
        "its row right after Select Subject's: %s" % [rows]
    )


func test_a_box_round_the_right_teapot_selects_it_shift_adds_the_left_and_alt_takes_a_part_away() -> void:
    await _open(_pair(), PAIR)
    if not _weights():
        return
    var teapot := _teapot(HALF)
    var left := _box(teapot, HALF)
    var right := Rect2i(left.position + Vector2i(HALF.x, 0), left.size)
    print("    the left teapot's box is %s and the right one's %s" % [left, right])
    var tool := _tool()
    var round_right := right.grow(SLACK).intersection(Rect2i(Vector2i(HALF.x, 0), HALF))
    var drawn := await _drag(tool, round_right)
    assert_eq(drawn["shape"], {"rect": Rect2(round_right), "ellipse": false}, "the box shows while it is dragged")
    var document := _surface.get_document()
    assert_eq(
        document.undo_redo.get_current_action_name(), SubjectSelection.BOX_TITLE, "the drag is one step titled Object Selection"
    )
    var coverage := _coverage()
    var right_share := _share(coverage, teapot, 1)
    var left_share := _share(coverage, teapot, 0)
    print("    a box round the right teapot covers %.3f of it and %.4f of the left" % [right_share, left_share])
    assert_true(right_share >= MOST, "the right teapot is most of it selected, %.3f" % right_share)
    assert_true(left_share <= ALMOST_NONE, "and almost none of the left, %.4f" % left_share)

    var round_left := left.grow(SLACK).intersection(Rect2i(Vector2i.ZERO, HALF))
    drawn = await _drag(tool, round_left, true, false)
    assert_not_null(drawn["picture"], "a Shift drag shows the plus on the pointer")
    coverage = _coverage()
    var both := [_share(coverage, teapot, 0), _share(coverage, teapot, 1)]
    print("    after a Shift box round the left teapot the two are covered %.3f and %.3f" % both)
    assert_true(both[0] >= MOST, "Shift adds the left teapot, %.3f" % both[0])
    assert_true(absf(both[1] - right_share) <= 0.000001, "and keeps the right as it was, %.3f" % both[1])

    @warning_ignore("integer_division")
    var part := Rect2i(round_left.position, Vector2i(round_left.size.x / 2, round_left.size.y))
    var before := _share(coverage, teapot, 0, Rect2i(part.end.x, 0, HALF.x, HALF.y))
    drawn = await _drag(tool, part, false, true)
    assert_not_null(drawn["picture"], "an Alt drag shows the minus on the pointer")
    coverage = _coverage()
    var inside := _share(coverage, teapot, 0, part)
    var outside := _share(coverage, teapot, 0, Rect2i(part.end.x, 0, HALF.x, HALF.y))
    print("    an Alt box round the left teapot's left half leaves %.3f of that half and %.3f of the rest" % [inside, outside])
    assert_true(inside <= TAKEN, "Alt takes the part inside the box away, %.3f left" % inside)
    assert_true(absf(outside - before) <= 0.000001, "and leaves the teapot outside the box as it was, %.3f" % outside)
    assert_true(_share(coverage, teapot, 1) >= MOST, "and the right teapot selected")


func test_a_click_with_no_drag_selects_the_subject_of_the_whole_picture() -> void:
    await _open(_photograph(), PHOTO)
    if not _weights():
        return
    var tool := _tool()
    tool.press(Vector2(800, 500))
    tool.release()
    var tree := Engine.get_main_loop() as SceneTree
    for _frame: int in 60:
        await tree.process_frame
        if not _module.busy:
            break
    var document := _surface.get_document()
    assert_eq(document.undo_redo.get_current_action_name(), SubjectSelection.TITLE, "a click is Select Subject's step")
    var clicked := _coverage()
    assert_true(_module.select_subject(SaSelection.Mode.REPLACE, true, _surface), "Select Subject runs")
    var subject := _coverage()
    var worst := 0.0
    for at: int in subject.size():
        worst = maxf(worst, absf(clicked[at] - subject[at]))
    assert_true(worst <= 0.000001, "and selects what Select Subject does, within %s" % String.num_scientific(worst))


## The mean width in pixels, over the rows of the teapot's middle half, of the
## ramp where *coverage* climbs from a tenth to nine tenths, read inwards from
## each side of *box*.
func _ramp(coverage: PackedFloat32Array, box: Rect2i) -> float:
    var total := 0.0
    var count := 0
    @warning_ignore("integer_division")
    for y: int in range(box.position.y + box.size.y / 4, box.end.y - box.size.y / 4):
        for side: int in [1, -1]:
            var x := box.position.x - SLACK if side == 1 else box.end.x + SLACK
            var low := -1
            @warning_ignore("integer_division")
            for step: int in box.size.x / 2 + SLACK:
                var at := clampi(x + side * step, 0, _size.x - 1)
                var value := coverage[y * _size.x + at]
                if low < 0 and value >= 0.1:
                    low = step
                if value >= 0.9:
                    if low >= 0:
                        total += step - low
                        count += 1
                    break
    return total / maxf(1.0, count)


func test_the_box_s_edge_is_sharper_than_select_subject_s() -> void:
    await _open(_pair(), PAIR)
    if not _weights():
        return
    var left := _box(_teapot(HALF), HALF)
    var box := Rect2i(left.position + Vector2i(HALF.x, 0), left.size)
    assert_true(_module.select_subject(SaSelection.Mode.REPLACE, true, _surface), "Select Subject runs")
    var whole := _ramp(_coverage(), box)
    var round_right := box.grow(SLACK).intersection(Rect2i(Vector2i(HALF.x, 0), HALF))
    assert_true(
        _module.select_subject(SaSelection.Mode.REPLACE, true, _surface, round_right),
        "Object Selection runs round the right teapot"
    )
    var boxed := _ramp(_coverage(), box)
    print("    the ramp from a tenth to nine tenths is %.2f pixels for Select Subject and %.2f for the box" % [whole, boxed])
    assert_true(
        boxed < 0.75 * whole,
        "the box's ramp is under three quarters of Select Subject's, %.2f against %.2f pixels" % [boxed, whole]
    )
