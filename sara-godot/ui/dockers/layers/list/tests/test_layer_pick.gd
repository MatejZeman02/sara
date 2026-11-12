## Which rows are picked is a class of its own, `SaLayerPick`,
## cut out of the layers list by responsibility. What makes it a cut and not a
## smear is held here: it works with no list and no row in the room, told only
## how many rows there are and which of them are a filter's, and it announces
## the indices whose look moved.
extends "res://tests/test_framework.gd"

var _moved: Array = []


func _pick(filter_rows: Array[bool]) -> SaLayerPick:
    var pick := SaLayerPick.new()
    for is_filter in filter_rows:
        pick.row_added(is_filter)
    _moved.clear()
    pick.style_moved.connect(func(indices: Array[int]) -> void: _moved.append(indices.duplicate()))
    return pick


func test_it_picks_with_no_list_behind_it() -> void:
    var pick := _pick([false, false, false, false])
    assert_eq(pick.press(1, false, false), 1, "a plain press makes the row active")
    assert_eq(pick.press(3, false, true), 1, "a shift press leaves the active row where it was")
    assert_eq(pick.selected_indices(), [1, 2, 3] as Array[int], "and takes the run from the anchor")
    assert_eq(pick.press(1, true, false), 3, "a ctrl press on the active row hands the mark to what is left")
    assert_eq(pick.selected_indices(), [2, 3] as Array[int], "with the row gone from the set")
    assert_eq(pick.anchor, 3, "and the anchor follows the mark")


func test_a_filters_row_never_joins_the_set() -> void:
    var pick := _pick([false, true, true, false])
    pick.select(0)
    pick.select_to(3)
    assert_eq(pick.selected_indices(), [0, 3] as Array[int], "a shift run across two filters leaves them out")
    pick.select(1)
    assert_eq(pick.selected_idx, 0, "and a plain select of a filter's row moves nothing")


func test_it_announces_the_rows_whose_look_moved() -> void:
    var pick := _pick([false, false, false])
    pick.select(0)
    assert_eq(_moved[-1], [0] as Array[int], "the row that lit")
    pick.select(2)
    var last: Array = _moved[-1]
    last.sort()
    assert_eq(last, [0, 2], "the row that went dark and the row that lit, each once")
    pick.reset()
    pick.row_added(false)
    pick.restore([0, 5] as Array[int], 0)
    assert_eq(_moved[-1], [0] as Array[int], "and never a row the list no longer has")


func test_a_filter_is_lit_by_its_record_and_a_layer_by_the_set() -> void:
    var pick := _pick([false, true])
    var record := SaAttachedFilter.new()
    var heard: Array = []
    pick.filter_picked.connect(func(r: SaAttachedFilter) -> void: heard.append(r))
    pick.select(0)
    pick.pick_filter(record)
    assert_eq(heard, [record], "the pick is announced")
    assert_eq(_moved[-1], [0, 1] as Array[int], "and the filters' rows and the set's restyle")
    assert_true(pick.is_lit(1, record), "the filter's row is lit by its record")
    # A filter's row and its layer's lit alike read as two picked rows.
    assert_false(pick.is_lit(0, null), "while the layer under it is not lit")
    assert_true(pick.is_target(0), "but the target, because the painter keeps painting there")
    assert_eq(pick.selected_indices(), [0] as Array[int], "and the set still holds it")
    pick.pick_filter(record)
    assert_eq(heard.size(), 1, "the same record again says nothing")
    assert_eq(pick.press(0, false, false), 0, "a press on a layer's row")
    assert_null(pick.selected_record, "takes the pick back from the filter")


func test_an_eye_acts_on_the_set_only_from_inside_it() -> void:
    var pick := _pick([false, false, false])
    pick.select(0)
    pick.select_extra(2)
    assert_eq(pick.acted_on(2), [0, 2] as Array[int], "a row of the set brings the set")
    assert_eq(pick.acted_on(1), [1] as Array[int], "and a row outside it acts alone")
    assert_true(pick.leads(2), "the active row of several stands apart")
    pick.select(1)
    assert_false(pick.leads(1), "and one row alone has nothing to stand apart from")


func test_a_rebuild_that_replaced_the_set_collapses_to_the_active_row() -> void:
    var pick := _pick([false, false, false])
    pick.restore([0, 1] as Array[int], 2)
    assert_eq(pick.selected_indices(), [2] as Array[int], "a set without the active row is a set the operation replaced")
    assert_eq(pick.anchor, 2, "and a shift click ranges from the active row")
