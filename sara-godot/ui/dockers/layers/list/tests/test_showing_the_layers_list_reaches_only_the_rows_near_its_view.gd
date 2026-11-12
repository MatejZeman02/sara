## Showing or hiding the Layers docker reaches the rows near the list's view
## and no other.
##
## On a copy of a large test document a Tab that hid every docker and showed them
## again held a frame of 116 to 126 ms, 75 to 78 ms of it the layout of the
## Layers docker's 827 rows, which a show told and sorted all over again. A
## row far from the view now sleeps: hidden, its controls out of the tree, its
## place held in the column at the size it had, so a show stops at it. Sixty
## rows stand in a list that shows ten, and the frames that put rows to sleep
## are `SaLayerRowSleep.step`, called straight because a suite that awaits
## drops every assertion after the await. The docker is a Window and
## cannot stand in this tree, so its list is lifted out into a plain Control,
## as the held-row suite does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Sixty with the background, which the default document already carries.
const LAYERS := 60
const SHOWN_ROWS := 10

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker
var _host: Control
var _list: SaLayerList


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Layer 1"
    var ops := SaLayerOps.new(_doc)
    for i in range(2, LAYERS):
        ops.add().name = "Layer %d" % i
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _list = _docker.item_list
    _list.get_parent().remove_child(_list)
    _list.owner = null
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "RowSleepHost"
    EventBus.add_child(_host)
    _host.add_child(_list)
    _list.size = Vector2(240, 400)
    _lay_out()
    _list.size = Vector2(240, _list.rows[0].size.y * SHOWN_ROWS + 2.0 * (SHOWN_ROWS - 1))
    _lay_out()


func after_each() -> void:
    if is_instance_valid(_list):
        _host.remove_child(_list)
        _list.free()
    _host.free()
    _host = null
    _docker.free()
    _canvas.free()
    _easel.free()


## The container and the column sort when the frame ends, and this suite never
## lets one end, so they are told to now.
func _lay_out() -> void:
    for child in _list.vbox.get_children():
        if child.is_queued_for_deletion():
            _list.vbox.remove_child(child)
    for i in 2:
        _list.vbox.notification(Container.NOTIFICATION_SORT_CHILDREN)
        _list.notification(Container.NOTIFICATION_SORT_CHILDREN)


## The frames a shown list takes to put its far rows to sleep, at most a
## hundred.
func _settle() -> void:
    for i in 100:
        if not _list.sleep.step():
            return


## How many nodes stand under the list in the tree, which is what a show tells.
func _nodes_under(node: Node) -> int:
    var count := node.get_child_count()
    for child in node.get_children():
        count += _nodes_under(child)
    return count


func _places() -> Array[float]:
    var places: Array[float] = []
    for row in _list.rows:
        places.append(row.position.y)
    return places


func test_the_rows_far_from_the_view_sleep_with_their_controls_out_of_the_tree() -> void:
    assert_eq(_list.rows.size(), LAYERS, "sixty rows stand in the list")
    var shown := SaLayerRowSleep.view(_list)
    assert_eq(shown.x, 0, "the view starts at the top row")
    _settle()
    var far := shown.y + SaLayerRowSleep.FAR
    for index in _list.rows.size():
        var row: SaRowFrame = _list.rows[index]
        if index > far:
            assert_true(_list.sleep.sleeps(row), "row %d, far below the view, sleeps" % index)
            assert_false(row.visible, "row %d, asleep, is hidden, so a show stops at it" % index)
            assert_null(row.hbox.get_parent(), "row %d, asleep, holds its controls out of the tree" % index)
        else:
            assert_false(_list.sleep.sleeps(row), "row %d, near the view, stays awake" % index)
            assert_true(row.visible, "row %d, near the view, is shown" % index)
    assert_eq(_list.sleep.asleep_count(), LAYERS - far - 1, "every row past the near band sleeps")


func test_a_sleeping_row_keeps_its_place_and_the_list_its_height() -> void:
    var before := _places()
    var height := _list.vbox.get_combined_minimum_size().y
    _settle()
    _lay_out()
    assert_true(_list.sleep.asleep_count() > 0, "rows fell asleep")
    assert_eq(_places(), before, "every row stands where it stood, asleep or awake")
    assert_eq(_list.vbox.get_combined_minimum_size().y, height, "the column is as tall as before, so the scroll bar is too")


func test_a_show_of_the_list_tells_a_fraction_of_the_nodes_it_told_before() -> void:
    var awake := _nodes_under(_list.vbox)
    _settle()
    var asleep := _nodes_under(_list.vbox)
    assert_true(asleep * 2 < awake, "under half the nodes stand in the tree once the far rows sleep, %d of %d" % [asleep, awake])


func test_a_hidden_list_puts_every_far_row_to_sleep_in_one_step() -> void:
    _host.visible = false
    assert_false(_list.sleep.step(), "one step leaves no far row awake while the list is hidden")
    _host.visible = true
    assert_true(_list.sleep.asleep_count() > 0, "the far rows sleep")


func test_a_scroll_to_the_end_wakes_the_rows_that_come_into_view() -> void:
    _settle()
    var last: SaRowFrame = _list.rows[LAYERS - 1]
    assert_true(_list.sleep.sleeps(last), "the bottom row sleeps while the view is at the top")
    _list.scroll_vertical = int(_list.vbox.size.y)
    _list.sleep.follow()
    var shown := SaLayerRowSleep.view(_list)
    assert_eq(shown.y, LAYERS - 1, "the view reaches the bottom row")
    for index in range(shown.x - SaLayerRowSleep.NEAR, LAYERS):
        var row: SaRowFrame = _list.rows[index]
        assert_false(_list.sleep.sleeps(row), "row %d, near the view, woke" % index)
        assert_true(row.visible, "row %d, near the view, is shown" % index)
        assert_eq(row.hbox.get_parent(), row, "row %d holds its controls again" % index)
    _settle()
    assert_true(_list.sleep.sleeps(_list.rows[0]), "the top row, now far above the view, sleeps")


func test_a_row_renamed_or_reported_wakes_first() -> void:
    _settle()
    var far: SaRowFrame = _list.rows[LAYERS - 1]
    _list.row_report()
    assert_eq(_list.sleep.asleep_count(), 0, "a report wakes every row it reads")
    assert_eq(far.hbox.get_parent(), far, "the far row holds its controls again")


func test_a_list_freed_with_rows_asleep_frees_their_controls() -> void:
    _settle()
    var far: SaRowFrame = _list.rows[LAYERS - 1]
    var controls: WeakRef = weakref(far.hbox)
    assert_null(far.hbox.get_parent(), "the far row's controls stand out of the tree")
    _host.remove_child(_list)
    _list.free()
    assert_null(controls.get_ref(), "the sleeping row's controls went with it")
