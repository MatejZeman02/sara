## The inside of a filter's window: the page scrolled, and its Apply row pinned
## below the scroll so it never scrolls away.
##
## Both windows a filter's page opens in, the one-shot [SaFilterDialogWindow]
## and the attached filter's [SaFilterEditWindow], put one of these in their
## content. The Apply row stands outside the scroll, because as the page's last
## row inside it a tall page such as the Kaleidoscope's pushes Cancel and Apply
## below the dialog's edge, where only the scroll bar reaches them.
##
## A `ScrollContainer` asks for no height of its own, so a scroll that is only
## a child here hides the page from `SaDialogWindow.fit_opening_size`, and every
## filter would open at the size its window was built with. Both windows hand
## the scroll over as their `scrolling_body`, so the fit gives it the page's own
## height, or what the host has room for.
##
## The row is moved rather than declared elsewhere, because a filter's `build`
## says `apply_cancel()` or leaves it to `SaDialog.for_filter`, and either way
## it is one row of the page: its binding, its name and its buttons stay the
## page's, and only where it is drawn changes. The footer holds its minimum
## height, so the window's fit grows to show it.
class_name SaFilterDialogFrame
extends MarginContainer

## The size both windows are built with and put back to on every open, logical.
## The height is the floor's, so the fit that follows grows the window to the
## page it shows and a short filter after a tall one opens short.
const OPENING_SIZE := Vector2i(520, 160)
## The least either window is made, logical. Under the shortest page, because
## at 280 Gaussian Blur, its thumbnail hidden while Preview on canvas is on,
## kept a blank band 75 high over its Apply row.
const FLOOR := Vector2i(360, 160)

## The scroll the page sits in, which both windows make their `scrolling_body`.
var scroll: ScrollContainer = null
## The rows the page is realized into, inside the scroll.
var rows: VBoxContainer = null
## The pinned strip under the scroll, holding the page's Apply row once one
## is shown, and over it whatever the window pins there, the Filter dialog's
## choice of Bake, Attach and Layer.
var footer: VBoxContainer = null


func _init() -> void:
    name = "FilterFrame"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        add_theme_constant_override(side, SaUI.px(12))

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", SaUI.px(8))
    add_child(column)

    scroll = ScrollContainer.new()
    scroll.name = "FilterScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(scroll)

    rows = VBoxContainer.new()
    rows.name = "FilterPage"
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Down as well as across, so a window the painter drags taller hands the
    # page the height and `_give_the_picture_the_free_height` can pass it on.
    rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(rows)

    footer = VBoxContainer.new()
    footer.name = "PinnedButtons"
    column.add_child(footer)


## Realizes *dialog* into the scrolled rows and moves its Apply row into the
## footer. A page with no Apply row leaves the footer empty.
func show_page(dialog: SaDialog) -> void:
    _empty(footer, is_inside_tree())
    dialog.realize(rows)
    _give_the_picture_the_free_height(dialog)
    var pinned := apply_row(dialog)
    if pinned == null:
        return
    var line := pinned.line if pinned.line != null else pinned.control
    if line == null or line.get_parent() == null:
        return
    line.get_parent().remove_child(line)
    footer.add_child(line)


## Pins *control* in a row of its own over the Apply row, at the end of the
## line where Apply stands, so the choice it offers reads as one thing said
## about Apply rather than as another button beside it. Emptied with the rest
## of the strip by the next page shown.
func pin_over_buttons(control: Control) -> void:
    control.size_flags_horizontal = Control.SIZE_SHRINK_END
    footer.add_child(control)
    footer.move_child(control, 0)


## Empties every row and the pinned strip. What a window's close runs.
##
## Outside the tree, which is how a suite holds a window, they are freed at
## once, because a queued row of a window closed in the frame it opened is
## counted as a leak. In the tree they are queued, because the close is the
## answer to Apply's or Cancel's own `pressed`, and a button freed inside its
## own signal printed a freed-object error on every press.
func clear() -> void:
    _empty(rows, is_inside_tree())
    _empty(footer, is_inside_tree())


## The page's Apply row, the one `SaDialog.apply_cancel` drew, or null for a
## filter that wrote no such call.
##
## Asked for by the widget name and not by a key, because the row carries an
## empty label: it is adopted under whatever `SaPage._free_key` makes of "", so
## `apply_cancel` names it in `widget_name` and nowhere else.
static func apply_row(dialog: SaDialog) -> SaPageRow:
    if dialog == null:
        return null
    for declared: SaPageRow in dialog.rows():
        if dialog.widget_name(declared.key) == "apply_cancel":
            return declared
    return null


## The pinned strip's rectangle in the window, and whether all of it lies
## inside the window, which is what the state dump and a scenario read to say
## the buttons are on screen without scrolling.
func describe_buttons() -> Dictionary:
    var box := footer.get_global_rect()
    var window := get_viewport_rect()
    return {
        "rect": [box.position.x, box.position.y, box.size.x, box.size.y],
        "shown": footer.get_child_count() > 0 and box.size.y > 0.0 and window.encloses(box),
    }


## Lets the dialog's picture, and every box between it and the page, grow into
## whatever height the window has beyond the page's own.
##
## The window opens at the page's height, so on the first frame there is none.
## A painter who drags the window taller is asking for a bigger picture, and
## Hue/Saturation/Lightness drew its strip at 200 with the rest of the window
## empty dark under it. Every box on the way up is told, because a box hands
## spare height only to a child that asks to expand.
func _give_the_picture_the_free_height(dialog: SaDialog) -> void:
    var node: Node = dialog.preview_control
    if node == null or not rows.is_ancestor_of(node):
        return
    while node != rows:
        (node as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
        node = node.get_parent()


static func _empty(box: Container, live: bool) -> void:
    for child in box.get_children():
        box.remove_child(child)
        if live:
            child.queue_free()
        else:
            child.free()
