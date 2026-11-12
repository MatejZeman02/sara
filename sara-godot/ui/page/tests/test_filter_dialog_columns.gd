## A filter dialog's untitled rows span the dialog, and its titled rows keep the
## label column.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Box blur showed an empty container beside an uncentred UI. The empty container
## was the label column every row of the shape
## draws, 210 units wide, beside a preview and a button row declared with no
## label and a slider that carries its caption inside the bar. The section
## guessed the column belonged to the rows declared before the preview. It
## belongs to every untitled row, wherever it is declared, which the shapes
## below grade by where each control is laid out.
##
## Offscreen and windowless, the way `test_filter_dialog.gd` holds a dialog:
## the page realized into a container under `EventBus`, and every sort run by
## hand, because a test function cannot await the frame a `queue_sort` waits
## for. `scenarios/a-filter-dialog-with-no-rows-before-its-preview-keeps-an-empty-column.json`
## is the running app.
extends "res://tests/test_framework.gd"

## The content width the filter window opened at before the fix, 660 less 24 of margin.
const WIDTH := 636.0

var _host: VBoxContainer = null
var _dialog: SaDialog = null


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _dialog = null


## Box blur's own declaration: a title, the preview, one slider and the buttons.
func _box_blur(ui: SaDialog) -> void:
    ui.title("Box blur")
    ui.preview()
    ui.slider("Radius", 1, 20, 3, {"hard_max": 200})
    ui.apply_cancel()


## Every widget kind, preview first, which is the fixture's shape.
func _every_widget(ui: SaDialog) -> void:
    ui.title("Every widget")
    ui.preview()
    ui.slider("Amount", 0.0, 2.0, 1.0)
    ui.checkbox("Invert", false)
    ui.dropdown("Channel", ["All", "Red", "Green"], 0)
    ui.button("Reset", Callable())
    ui.apply_cancel()


## Titled rows before the preview, the shape the section thought was the one
## that already drew right.
func _titled_first(ui: SaDialog) -> void:
    ui.title("Titled first")
    ui.checkbox("Invert", false)
    ui.dropdown("Channel", ["All", "Red", "Green"], 0)
    ui.preview()
    ui.slider("Amount", 0.0, 2.0, 1.0)
    ui.apply_cancel()


func _build(declaration: Callable) -> void:
    _host = VBoxContainer.new()
    EventBus.add_child(_host)
    _host.size = Vector2(WIDTH, 900.0)
    _dialog = SaDialog.new(declaration)
    _dialog.declare_rows()
    _dialog.realize(_host)
    _sort(_host)


## Top down, so every container sorts inside the size its parent just gave it.
func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


func _row_of(widget: String) -> SaPageRow:
    for row in _dialog.rows():
        if _dialog.widget_name(row.key) == widget:
            return row
    return null


func _spans(widget: String) -> void:
    var row := _row_of(widget)
    assert_not_null(row, "the dialog has a %s" % widget)
    assert_false(row.line.get_child(0).visible, "the %s's row draws no label column" % widget)
    var shown := row.line.get_child(1) as Control
    assert_almost_eq(shown.position.x, 0.0, 0.5, "the %s starts at the dialog's left edge" % widget)
    assert_almost_eq(shown.size.x, WIDTH, 0.5, "and is as wide as the dialog")


func _keeps_its_column(widget: String) -> float:
    var row := _row_of(widget)
    assert_not_null(row, "the dialog has a %s" % widget)
    assert_true(row.line.get_child(0).visible, "the %s's row keeps its label column" % widget)
    var shown := row.line.get_child(1) as Control
    assert_true(shown.position.x > 0.0, "so the %s sits to the right of it" % widget)
    return shown.position.x


func test_box_blur_has_no_empty_column_and_its_preview_spans_the_dialog() -> void:
    _build(_box_blur)
    _spans("preview")
    _spans("slider")
    _spans("apply_cancel")
    assert_almost_eq(
        _dialog.preview_control.position.x,
        0.0,
        0.5,
        "the preview itself, not only its row, starts at the left edge, so its picture is centred in the dialog"
    )


func test_a_titled_row_keeps_the_column_and_lines_up_with_the_others() -> void:
    _build(_every_widget)
    _spans("preview")
    _spans("slider")
    _spans("apply_cancel")
    var invert_x := _keeps_its_column("checkbox")
    assert_almost_eq(_keeps_its_column("dropdown"), invert_x, 0.5, "a dropdown's control starts where the checkbox's does")
    # A button row is untitled too, and it is not one of the filling widgets: it
    # keeps the column so the button lines up with the controls above it rather
    # than jumping to the left edge under their titles.
    assert_almost_eq(_keeps_its_column("button"), invert_x, 0.5, "and a button's starts there as well")


func test_titled_rows_before_the_preview_change_nothing_about_the_preview() -> void:
    _build(_titled_first)
    var invert_x := _keeps_its_column("checkbox")
    assert_almost_eq(_keeps_its_column("dropdown"), invert_x, 0.5, "the two titled rows line up")
    _spans("preview")
    _spans("slider")
    _spans("apply_cancel")
