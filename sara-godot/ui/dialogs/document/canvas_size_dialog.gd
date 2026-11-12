## Image > Canvas Size: a new width and height, and a nine-cell anchor saying
## where the old picture sits inside them.
##
## Nothing here resamples. The picture keeps its pixels and the canvas around it
## changes, which is why the dialog has no resolution row: scaling the image is
## its own operation and asking for both in one window would make the anchor
## meaningless for half the answers.
##
## The anchor is nine `Button`s in a three by three grid rather than a dropdown
## of nine names, because "top left" is a picture and reads as one. The centre
## cell is the default, so a painter who ignores the grid gets the growth spread
## evenly, which is what every other program does. Each cell names itself in a
## tooltip and takes no focus, so the pressed one is the only marked square.
@tool
class_name SaCanvasSizeDialog
extends SaDialogWindow

## The painter confirmed. *size* is the new canvas in document pixels and
## *anchor* is a cell of the grid, each component 0, 1 or 2 for near edge,
## centre and far edge.
signal resize_requested(size: Vector2i, anchor: Vector2i)

## The same ceiling File > New uses, and for the same reason: a canvas this size
## is already gigabytes of chunks if it is painted edge to edge.
const MAX_DIMENSION := 16384

## The nine cells' names, indexed the way the anchor is, so a state dump and a
## tooltip say the same words. Read as `LABELS[anchor.y][anchor.x]`.
const LABELS: Array = [
    ["Top left", "Top", "Top right"],
    ["Left", "Centre", "Right"],
    ["Bottom left", "Bottom", "Bottom right"],
]

## The line under the grid for each cell, whole rather than the cell's name
## dropped into one sentence, so a language with cases can decline it. Keyed by
## the cell's name in [constant LABELS].
const ANCHOR_UNCHANGED: Dictionary = {
    "Top left": "Anchor: Top left. The canvas does not change.",
    "Top": "Anchor: Top. The canvas does not change.",
    "Top right": "Anchor: Top right. The canvas does not change.",
    "Left": "Anchor: Left. The canvas does not change.",
    "Centre": "Anchor: Centre. The canvas does not change.",
    "Right": "Anchor: Right. The canvas does not change.",
    "Bottom left": "Anchor: Bottom left. The canvas does not change.",
    "Bottom": "Anchor: Bottom. The canvas does not change.",
    "Bottom right": "Anchor: Bottom right. The canvas does not change.",
}

## The same line when the size changes, the offset's two numbers left as
## placeholders.
const ANCHOR_MOVES: Dictionary = {
    "Top left": "Anchor: Top left. The picture's top-left corner moves to %s, %s px.",
    "Top": "Anchor: Top. The picture's top-left corner moves to %s, %s px.",
    "Top right": "Anchor: Top right. The picture's top-left corner moves to %s, %s px.",
    "Left": "Anchor: Left. The picture's top-left corner moves to %s, %s px.",
    "Centre": "Anchor: Centre. The picture's top-left corner moves to %s, %s px.",
    "Right": "Anchor: Right. The picture's top-left corner moves to %s, %s px.",
    "Bottom left": "Anchor: Bottom left. The picture's top-left corner moves to %s, %s px.",
    "Bottom": "Anchor: Bottom. The picture's top-left corner moves to %s, %s px.",
    "Bottom right": "Anchor: Bottom right. The picture's top-left corner moves to %s, %s px.",
}

## The two numbers the page binds. The spinboxes are the page's, and this
## window reads what they wrote.
var wanted_width: int = 1920
var wanted_height: int = 1080
## Which cell is down.
var anchor := Vector2i(1, 1)
## The declared rows, realized once into `CanvasSizePage`.
var page: SaPage = null

var _current_label: Label = null
var _difference_label: Label = null
## The nine buttons, `_anchor_buttons[y][x]`, so the pressed one can be moved
## without a search.
var _anchor_buttons: Array = []
## What the document was when the window opened, for the difference line and for
## the Reset the spinboxes get on every open.
var _document_size := Vector2i(1920, 1080)


func _init() -> void:
    # Tall enough for the anchor grid as a row of its own under the two numbers,
    # and for the anchor line under it at three lines, which a grow with the
    # sentence about the background fills. The Resize button's own rect is
    # measured in the scenario rather than trusted to this number, because a
    # size reasoned about puts a button below the edge as soon as the font grows.
    _init_dialog("CanvasSizeDialog", tr("Canvas Size"), Vector2i(460, 430), Vector2i(420, 410))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    # Everything above the buttons scrolls when the host is shorter than it, so
    # the buttons stay on it, as New Document's and Export's do. At 1280 by 800
    # and an interface scale of 2 the room below the bar is 335 tall, and the
    # buttons ended at 338.
    var rows_view := SaMake.scroll(column, "RowsScroll")
    rows_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = rows_view
    var rows := SaMake.column(rows_view, "Rows", SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _current_label = SaMake.label(rows, "CurrentLabel")
    _current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(SaMake.column(rows, "CanvasSizePage"))
    page.row_changed.connect(func(_key: StringName, _value: Variant) -> void: _show_difference())
    _select_anchor(Vector2i(1, 1))

    _difference_label = SaMake.label(rows, "DifferenceLabel")
    _difference_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _difference_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    _difference_label.modulate = Color(1.0, 1.0, 1.0, 0.7)

    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size.x = float(SaUI.px(90))
    cancel_button.pressed.connect(hide)
    default_button = SaMake.button(buttons, "ResizeButton", tr("Resize"))
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(_confirm)
    configure(_document_size)


## The page: the two numbers, bound, and the anchor, the one row a row kind
## cannot hold, because nine squares in a picture are no dropdown.
func _declare(ui: SaPage) -> void:
    var rows := ui.section("")
    rows.number("Width", 1, MAX_DIMENSION, self, ^"wanted_width").step(1).named(&"width").node("WidthSpin")
    rows.number("Height", 1, MAX_DIMENSION, self, ^"wanted_height").step(1).named(&"height").node("HeightSpin")
    rows.custom("Anchor", _anchor_grid()).named(&"anchor")


## The nine cells. Each is a toggle in one `ButtonGroup`, so exactly one is down
## and the group does the exclusivity rather than nine handlers undoing each
## other.
func _anchor_grid() -> GridContainer:
    var grid := SaMake.grid(null, "AnchorGrid", 3, 2)
    var group := ButtonGroup.new()
    _anchor_buttons = []
    for y in range(3):
        var row: Array = []
        for x in range(3):
            var cell := SaMake.button(grid, "Anchor%d%d" % [x, y], "", tr(String(LABELS[y][x])))
            cell.toggle_mode = true
            # The comment below is the whole reason this one is here: the cells
            # are unlabelled and which one is down is the only answer they give.
            SaTheme.make_toggle(cell)
            cell.button_group = group
            # No focus ring on a cell. The nine are unlabelled squares and the
            # only thing telling them apart is which one the theme draws as
            # pressed, so a white focus outline on a *different* cell reads as
            # the answer and the real one reads as off. The captured dialog
            # said Centre in the dump and looked like Top left on screen.
            cell.focus_mode = Control.FOCUS_NONE
            cell.custom_minimum_size = Vector2(float(SaUI.px(34)), float(SaUI.px(34)))
            cell.pressed.connect(_on_anchor_pressed.bind(Vector2i(x, y)))
            row.append(cell)
        _anchor_buttons.append(row)
    return grid


## Points the dialog at the document it is about to resize. Called on every open
## rather than once, because the two spinboxes start at what the canvas is now
## and the canvas has moved on since the last time.
func configure(document_size: Vector2i) -> void:
    _document_size = document_size
    wanted_width = document_size.x
    wanted_height = document_size.y
    page.refresh()
    _current_label.text = tr("The canvas is %s × %s px.") % [document_size.x, document_size.y]
    _show_difference()


## The line under the grid, which is the only place the anchor's consequence is
## written down. "Wider by 400" says nothing about which side the 400 lands on,
## and the grid is a picture of squares that says nothing on its own either.
func _show_difference() -> void:
    if _difference_label == null:
        return
    var wanted := requested_size()
    var offset := SaCrop.offset_for(_document_size, wanted, anchor)
    var cell := String(LABELS[anchor.y][anchor.x])
    if wanted == _document_size:
        _difference_label.text = tr(ANCHOR_UNCHANGED[cell])
        return
    var line := tr(ANCHOR_MOVES[cell]) % [offset.x, offset.y]
    # What a grow puts in the ground it adds is the one consequence a painter
    # cannot see from the grid, and a painter would read "transparent" into it:
    # the background is carried out to the new edges.
    if wanted.x > _document_size.x or wanted.y > _document_size.y:
        line += " " + tr("The new area is filled with the background.")
    _difference_label.text = line


## What the two spinboxes currently ask for.
func requested_size() -> Vector2i:
    return Vector2i(wanted_width, wanted_height)


func _on_anchor_pressed(cell: Vector2i) -> void:
    anchor = cell
    _show_difference()


func _select_anchor(cell: Vector2i) -> void:
    anchor = cell
    if _anchor_buttons.size() != 3:
        return
    var row: Array = _anchor_buttons[cell.y]
    var button: Button = row[cell.x]
    button.set_pressed_no_signal(true)
    for y in range(3):
        for x in range(3):
            var other: Button = _anchor_buttons[y][x]
            other.set_pressed_no_signal(Vector2i(x, y) == cell)


func _confirm() -> void:
    var wanted := requested_size()
    hide()
    if wanted != _document_size:
        resize_requested.emit(wanted, anchor)


## The Canvas Size dialog for the state dump, or nothing when it has never been
## opened.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script when the engine exits.
static func capture_state(root: Window) -> Dictionary:
    var dialog := root.find_child("CanvasSizeDialog", true, false)
    if dialog == null or not dialog.has_method("size_report"):
        return {}
    return dialog.call("size_report")


## What the state dump reads. The anchor's name as well as its cell, because a
## picture of nine dark squares is a poor way to grade which one is down.
func size_report() -> Dictionary:
    return {
        "visible": visible,
        "document_size": [_document_size.x, _document_size.y],
        "requested_size": [requested_size().x, requested_size().y],
        "anchor": [anchor.x, anchor.y],
        "anchor_name": String(LABELS[anchor.y][anchor.x]),
        "difference": _difference_label.text if _difference_label != null else "",
        "resize_button": _button_rect("ResizeButton"),
        "window_size": [size.x, size.y],
    }


## A named button's rect inside the window, so the scenario can check it is on
## screen rather than below the bottom edge, which once shipped.
func _button_rect(button_name: String) -> Array:
    var button := find_child(button_name, true, false) as Button
    if button == null:
        return []
    var at := button.get_global_rect()
    return [at.position.x, at.position.y, at.size.x, at.size.y]


## Uses the Canvas Size dialog: it moves the Canvas Size page's rows, puts the
## anchor down and presses Resize, with the dialog already open,
## `{"canvas_size": {"width": 900, "height": 700, "anchor": [2, 0]}}`.
##
## The numbers are rows and are moved the way a hand moves them. What stays here
## is the anchor, which is the page's one custom row and so has no `page_row` of
## its own, and the press, which is not a row. The dialog is a Window, an
## injected click does not route into one, and everything from the row onward is
## the real path with only the pointer skipped.
static func capture_resize(tree: SceneTree, spec: Dictionary) -> String:
    var dialog := tree.root.find_child("CanvasSizeDialog", true, false) as SaCanvasSizeDialog
    if dialog == null:
        return "SaCapture: no Canvas Size dialog open to resize in"
    for key: String in ["width", "height"]:
        if spec.has(key):
            dialog.page.row(StringName(key)).drive(spec[key])
    if spec.has("anchor"):
        var cell := spec["anchor"] as Array
        if cell != null and cell.size() >= 2:
            dialog._select_anchor(Vector2i(int(cell[0]), int(cell[1])))
            dialog._show_difference()
    var before := dialog._document_size
    var wanted := dialog.requested_size()
    var named := String(LABELS[dialog.anchor.y][dialog.anchor.x])
    if bool(spec.get("cancel", false)):
        dialog.hide()
        return "SaCapture: canvas_size cancelled at %d x %d, anchor %s" % [wanted.x, wanted.y, named]
    dialog._confirm()
    return "SaCapture: canvas_size %d x %d -> %d x %d, anchor %s" % [before.x, before.y, wanted.x, wanted.y, named]
