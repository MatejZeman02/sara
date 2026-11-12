## A group opens and shuts in the layers docker without a pause.
##
## A document of 2160 by 720 with 33 layers and a group of four
## pictures took a whole second to open a group. A fold built every row of the
## stack again, about three milliseconds a row for its eye, picture, locks and
## theme, and every new picture then waited out the thumbnail's quarter second
## before it drew. `SaLayerRowReuse` keeps every row a fold leaves standing and
## builds only the rows it brings back, their pictures drawn at once.
##
## Measured here before the change, a press on the mark took 132 to 257 ms and
## the pictures 39 to 74 ms more. The time read below is the press and the
## pictures together, which is what the frame after it draws.
extends "res://tests/test_framework.gd"

## The pictures are compute dispatches over the layers' chunks, read back here
## to say they are the same before and after.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30
const MEMBERS := 4

## The rows of a new document's two layers, the group's own and the painted ones.
const ROWS := 2 + 1 + PAINT_LAYERS

## The ceiling the row sets on a press and the pictures it draws, in
## milliseconds on a quiet machine, moved by `BusyBound` when the machine is
## busy.
const LIMIT_MS := 50.0

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker


## Thirty painted layers over the default document's two, the top four grouped, and a pick
## of two layers outside the group, the active one among them, so a fold moves
## no active mark and the composite is not built again.
func before_each() -> void:
    _easel = SaEasel.create_default(DOC_SIZE)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Background"
    var members: Array[SaLayer] = []
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(_doc).add()
        layer.name = "Paint %d" % i
        _doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 1.0), layer)
        if i >= PAINT_LAYERS - MEMBERS:
            members.append(layer)
    SaLayerOps.new(_doc).group_layers(members).name = "Pictures"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _docker.list_keeper.select_row(_row_of("Paint 3"))
    # A Ctrl press, as the list answers one: the row joins the pick and its
    # layer becomes the active one.
    _docker.item_list.picked.press(_row_of("Paint 7"), true, false)
    _docker.list_keeper.select_row(_row_of("Paint 7"))
    SaLayerList.settle_thumbnails(_docker)


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _doc = null


func _row_of(layer_name: String) -> int:
    for i: int in _docker.item_list.rows.size():
        var layer: SaLayer = _docker.item_list.layer_at(i)
        if layer != null and str(layer.name) == layer_name:
            return i
    return -1


## A press on the group's fold mark, as the painter's, and the pictures the
## frame after it draws. Answers the milliseconds both took.
func _press_mark() -> float:
    var row: SaRowFrame = _docker.item_list.rows[_row_of("Pictures")]
    var start := Time.get_ticks_usec()
    row.disclose.pressed.emit()
    SaLayerList.settle_thumbnails(_docker)
    return (Time.get_ticks_usec() - start) / 1000.0


## Every row as the painter sees it, top first: its name, whether it is lit,
## where it is on screen in the list's order, and its picture's texels.
func _rows() -> Array:
    var out: Array = []
    var list := _docker.item_list
    for i: int in list.rows.size():
        var row: SaRowFrame = list.rows[i]
        out.append([row.lbl.text, row.lit, row.row_index, row.get_index(), String(row.name), _texels(row.thumb)])
    return out


func _texels(thumb: SaLayerThumbnail) -> PackedByteArray:
    if thumb._texture == null:
        return PackedByteArray()
    return GlobalShaderCompiler.get_rd().texture_get_data(thumb._texture.rid, 0)


func _pick() -> Array:
    var list := _docker.item_list
    return [list.picked.selected_indices(), list.picked.selected_idx, list.selected_layers()]


func test_a_fold_and_an_unfold_each_take_under_fifty_milliseconds() -> void:
    assert_eq(_docker.item_list.rows.size(), ROWS, "every layer and the group has a row")
    var bound := BusyBound.new(LIMIT_MS)
    for _press: int in 3:
        bound.time("A fold", _press_mark)
        assert_true(_doc.find_child("Pictures", true, false).folded, "the press shuts the group")
        assert_eq(_docker.item_list.rows.size(), ROWS - MEMBERS, "and folds its four rows away")
        bound.time("An unfold", _press_mark)
        assert_eq(_docker.item_list.rows.size(), ROWS, "the second press brings them back")
    assert_true(bound.all_held, bound.worst)


func test_the_rows_the_pick_and_the_pictures_are_the_same_after_a_fold_and_an_unfold() -> void:
    var rows := _rows()
    var pick := _pick()
    assert_eq((pick[2] as Array).size(), 2, "two layers are picked")
    for row: Array in rows:
        if String(row[0]).begins_with("Paint"):
            assert_false((row[5] as PackedByteArray).is_empty(), "%s's picture is drawn" % row[0])
    _press_mark()
    _press_mark()
    assert_eq(_rows().size(), rows.size(), "as many rows as before")
    var after := _rows()
    for i: int in rows.size():
        assert_eq(after[i].slice(0, 5), rows[i].slice(0, 5), "row %d reads %s as it did, lit as it was" % [i, rows[i][0]])
        assert_true(after[i][5] == rows[i][5], "and %s's picture is the same" % rows[i][0])
    assert_eq(_pick(), pick, "and the pick is the same")


## The rows a fold leaves are kept rather than built again, and each press on
## them reaches its own layer at the place the fold moved it to.
func test_a_kept_row_answers_for_its_own_layer_after_a_fold() -> void:
    var background_row: SaRowFrame = _docker.item_list.rows[_row_of("Background")]
    _press_mark()
    assert_true(_docker.item_list.rows[_row_of("Background")] == background_row, "the Background's row is the same row")
    assert_eq(background_row.row_index, _row_of("Background"), "numbered for where it stands now")
    background_row.eye_btn.pressed.emit()
    assert_false(_doc.find_child("Background", false, false).visible, "and its eye hides the Background")
    assert_true(_doc.find_child("Paint 3", false, false).visible, "and no other layer")
