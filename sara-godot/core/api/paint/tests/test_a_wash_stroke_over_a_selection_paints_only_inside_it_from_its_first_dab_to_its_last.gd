## A stroke paints only where the selection it was pressed under is, from its
## first dab to its last, whatever happens to the selection while it is still
## being walked, as a painter found it.
##
## A long stroke is walked over many frames, `SaWalkBudget` carrying what a
## frame has no room for, so a door's next step or a painter's key can change
## the selection while the stroke still has dabs to lay. Each dab used to ask
## the live selection for its chunk's mask, and every dab after a deselect
## painted through the everything stand-in: a forty pass zigzag wash with a
## `select: none` one frame behind it painted 979,744 texels outside its
## selection on a 3840 by 2160 document. The stroke now keeps the selection it
## was pressed under in `SaStrokeTransaction.selection`.
##
## A suite ticks no tool, so the brush walks each motion whole when it comes,
## and dropping the selection between two motions is the same as dropping it
## between two frames of a carried walk. Each case presses, zigzags over the
## first half, drops the selection, zigzags over the second half and lets go,
## then reads every texel of the layer outside the mask as it was before.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Three by two chunks, so the selection leaves whole chunks out and the
## zigzag runs through chunks it holds and chunks it does not.
const CANVAS := Vector2i(768, 512)
## The zigzag's passes, top to bottom, from x 24 to x 744: the first pass
## runs above the polygon's top edge, the last below its bottom, and both
## ends of every pass lie outside it.
const PASSES := 24
const FIRST_Y := 40.0
const LAST_Y := 470.0
const LEFT_X := 24.0
const RIGHT_X := 744.0
## A colour the eraser case starts from, everywhere on the layer.
const UNDER := Color(0.2, 0.5, 0.3, 1.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


## A ragged polygon, a blob round the canvas's middle whose radius jumps from
## vertex to vertex, the same each run.
func _ragged() -> PackedVector2Array:
    var points := PackedVector2Array()
    var jumps := [0.62, 0.95, 0.7, 1.0, 0.55, 0.88, 0.66, 0.97, 0.6, 0.83, 0.74, 0.99, 0.58, 0.9, 0.68, 0.8]
    for i in jumps.size():
        var angle := TAU * float(i) / float(jumps.size())
        points.append(Vector2(384.0, 256.0) + Vector2(cos(angle) * 300.0, sin(angle) * 190.0) * float(jumps[i]))
    return points


func _select_ragged() -> void:
    _doc.selection.change("Select", _doc.selection.select_polygon.bind(_ragged()))


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.handle_input(event)


func _move_to(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.pressure = 1.0
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


## The zigzag's corners, one pass after another.
func _corners() -> Array[Vector2]:
    var corners: Array[Vector2] = []
    for i in PASSES:
        var y := lerpf(FIRST_Y, LAST_Y, float(i) / float(PASSES - 1))
        var ends := [LEFT_X, RIGHT_X] if i % 2 == 0 else [RIGHT_X, LEFT_X]
        corners.append(Vector2(float(ends[0]), y))
        corners.append(Vector2(float(ends[1]), y))
    return corners


## Paints the zigzag in *mode*, an eraser when *erasing*, and drops the
## selection halfway through it when *drop* is true.
func _zigzag(mode: int, erasing: bool, drop: bool) -> void:
    var brush := _machine.active_tool
    brush.settings.painting_mode = mode
    brush.settings.opacity = 0.6
    brush.settings.radius = 9.0 / float(mini(CANVAS.x, CANVAS.y))
    brush.settings.opacity_by_pressure = false
    brush.eraser_toggled = erasing
    var corners := _corners()
    _surface.view.mouse_position = corners[0]
    _button(true)
    for i in range(1, corners.size()):
        if drop and i == corners.size() >> 1:
            _doc.selection.change(SaSelection.DROP_TITLE, _doc.selection.deselect)
            assert_false(_doc.selection.active, "the selection is gone with the pen still down")
        _move_to(corners[i])
    _button(false)


## Every texel of the layer's colour, chunk by chunk, an absent chunk as null.
func _layer() -> Dictionary:
    var read := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in SaLayer.grid_positions(CANVAS):
        var chunk: SaChunk = _doc.active_layer.chunks.get(grid, null)
        read[grid] = null
        if chunk != null:
            read[grid] = rd.texture_get_data(chunk.albedo().rid, 0).to_float32_array()
    return read


## The selection's coverage, chunk by chunk, a chunk it leaves out as null.
func _mask() -> Dictionary:
    var read := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in SaLayer.grid_positions(CANVAS):
        var texture := _doc.selection.texture_for(grid)
        read[grid] = null
        if texture != null:
            read[grid] = rd.texture_get_data(texture.rid, 0).to_float32_array()
    return read


## How many texels outside *mask* differ between *before* and *after*, the
## channels of a chunk that is absent read as nought.
static func _changed_outside(mask: Dictionary, before: Dictionary, after: Dictionary) -> int:
    var changed := 0
    var side := SaChunk.SIZE
    for grid: Vector2i in mask:
        var coverage: Variant = mask[grid]
        var was: Variant = before[grid]
        var now: Variant = after[grid]
        if was == null and now == null:
            continue
        for texel in side * side:
            if coverage != null and (coverage as PackedFloat32Array)[texel] > 0.0:
                continue
            for channel in 4:
                var a := 0.0 if was == null else (was as PackedFloat32Array)[texel * 4 + channel]
                var b := 0.0 if now == null else (now as PackedFloat32Array)[texel * 4 + channel]
                if a != b:
                    changed += 1
                    break
    return changed


## How many texels differ anywhere between two reads.
static func _changed(before: Dictionary, after: Dictionary) -> int:
    var everything := {}
    for grid: Vector2i in before:
        everything[grid] = null
    return _changed_outside(everything, before, after)


func _fill_layer() -> void:
    for grid: Vector2i in SaLayer.grid_positions(CANVAS):
        _doc.active_layer.get_or_create_chunk(grid).albedo().clear(UNDER)


## One case: the zigzag with the selection dropped halfway, read outside the
## mask, then the same zigzag on a fresh layer with the selection kept, read
## against it texel for texel.
func _check(mode: int, erasing: bool, name: String) -> void:
    if erasing:
        _fill_layer()
    _select_ragged()
    var mask := _mask()
    var before := _layer()
    _zigzag(mode, erasing, true)
    var dropped := _layer()
    var painted := _changed(before, dropped)
    assert_true(painted > 1000, "%s: the zigzag painted, %d texels" % [name, painted])
    assert_eq(_changed_outside(mask, before, dropped), 0, "%s: no texel outside the selection changed" % name)

    # The same stroke with the selection left alone, which is the stroke as it
    # always painted, since the selection it was pressed under is the live one
    # throughout. Inside the selection the two agree texel for texel.
    assert_true(_doc.undo(), "%s: the stroke undoes" % name)
    assert_eq(_changed(before, _layer()), 0, "%s: the undo brought the layer back" % name)
    _doc.selection.change(SaSelection.RESELECT_TITLE, _doc.selection.reselect)
    assert_true(_doc.selection.active, "%s: the selection is back" % name)
    _zigzag(mode, erasing, false)
    var kept := _layer()
    assert_eq(_changed(dropped, kept), 0, "%s: inside the selection it paints what it painted with the selection kept" % name)


func test_a_wash_stroke_paints_nowhere_the_selection_it_was_pressed_under_leaves_out() -> void:
    _check(StampSettingsScript.PaintingMode.WASH, false, "wash")


func test_a_build_up_stroke_paints_nowhere_the_selection_it_was_pressed_under_leaves_out() -> void:
    _check(StampSettingsScript.PaintingMode.BUILD_UP, false, "build-up")


func test_an_eraser_stroke_erases_nowhere_the_selection_it_was_pressed_under_leaves_out() -> void:
    _check(StampSettingsScript.PaintingMode.BUILD_UP, true, "eraser")


## Outside a stroke a context reads the live selection, so a fill or a dab
## after the stroke follows a selection changed since, and a stroke's commit
## lets the selection it held go.
func test_the_held_selection_goes_with_the_stroke() -> void:
    _select_ragged()
    _zigzag(StampSettingsScript.PaintingMode.WASH, false, false)
    assert_null(_doc.stroke_transaction.selection, "the commit let the pressed selection go")
