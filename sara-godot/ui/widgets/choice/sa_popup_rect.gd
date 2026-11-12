## Where a list opens against the control it came from, in the space `popup()`
## measures a rectangle in.
##
## A class of its own because the question is geometry and not a list:
## `SaChoicePopup` owns the rows, and this owns the anchor's rectangle in the
## embedder's space and which side of it has room.
##
## **The anchor is measured through its screen transform**, not its `size`. A
## control inside a maximised docker is laid out in the docker's units, a quarter
## smaller than the host's, so its `size` is the wrong number for a window
## embedded in the host. `get_screen_transform` carries the docker's position and
## its `content_scale_factor` both, where `get_screen_position` carries them
## for the corner alone, which would open the list at the right corner and the
## wrong width.
class_name SaPopupRect
extends RefCounted


## The rectangle *popup* opens at under *anchor*, sized from *wanted*, which takes
## the anchor's width in the popup's own units and answers the size the list
## wants in them. The popup's factor has to be applied before this is asked,
## since the answer is that size times the factor.
static func place(anchor: Control, popup: Window, wanted: Callable) -> Rect2i:
    var factor := popup.content_scale_factor
    var span := of_anchor(anchor)
    var size: Vector2i = wanted.call(span.size.x / factor)
    var asked := Vector2i((Vector2(size) * factor).round())
    var room := room_for(popup)
    var at := under(span, asked, room)
    # A list that has to scroll draws a bar that takes its own width out of the
    # rows', which asked for none of it, so the bar would lie over the shortcut
    # column.
    # Widened only then, since a list that fits has no bar.
    var widened := with_bar(popup, asked, at.size.y)
    if widened != asked:
        at = under(span, widened, room)
    return at


## *wanted* made as much wider as *popup*'s scroll bar, when the list is placed
## *placed_height* tall, which is shorter than it asked, and its own `wanted_size`
## did not already add the bar for the cap. *wanted* and the answer are in
## screen pixels.
static func with_bar(popup: Window, wanted: Vector2i, placed_height: int) -> Vector2i:
    var list := popup as SaChoicePopup
    if list == null or placed_height >= wanted.y or list._bar_asked:
        return wanted
    var factor := popup.content_scale_factor
    return Vector2i(wanted.x + roundi(float(bar_width(list)) * factor), wanted.y)


## The width *popup*'s scrollbar takes out of its rows when the list scrolls, in
## the popup's own units. Read off the list's scroll container, which the list
## keeps to itself.
static func bar_width(popup: SaChoicePopup) -> int:
    return ceili(popup._scroll.get_v_scroll_bar().get_combined_minimum_size().x)


## Puts an open *popup* back at the height its rows want under *anchor*, where
## `place` puts it, keeping its width, and answers that rectangle, or a zero one
## when there is nothing to fit. Asked after every search: a search hides
## rows and sets no size, so an emptied search would leave the list as short as
## its field. The width stays, so the field does not move under typing.
static func refit(anchor: Variant, popup: Window, wanted: Callable) -> Rect2i:
    # A `Variant` rather than a `Control`, so an anchor freed since the list
    # opened is turned away here and not by the call's own type check.
    var control := anchor as Control if is_instance_valid(anchor) else null
    if not popup.visible or control == null or not control.is_inside_tree():
        return Rect2i()
    var at := place(control, popup, wanted)
    at.size.x = popup.size.x
    popup.position = at.position
    popup.size = at.size
    return at


## The anchor's rectangle where an embedded popup's `position` is measured, the
## embedder's logical space, or screen pixels when the popup is a real OS window.
static func of_anchor(anchor: Control) -> Rect2:
    var xform := anchor.get_screen_transform()
    return Rect2(xform.origin, xform.basis_xform(anchor.size))


## Where a menu opened by *press* puts its top-left corner, in the space the
## popup's `position` is measured in, which is the space `of_anchor` answers in.
##
## *press* is the event as *control*'s `gui_input` hands it over, its `position`
## local to *control*. Its `global_position` is never read, because no one space
## holds it: a press heard at a window's `window_input` carries the physical
## pixels of the display there, and `xformed_by` moves `position` alone, so a
## menu opened at it on a window scaled by 2 lands twice as far from the corner
## as the pointer. Every right-click menu asks this, so a new one cannot
## mix the two spaces again.
static func at_press(press: InputEventMouse, control: Control) -> Vector2i:
    return at_point(control, press.position)


## Where a menu opened at *local*, a point in *control*'s own coordinates, puts
## its top-left corner, in the space `of_anchor` answers in. Rounded down, so
## the menu's rectangle holds the press it opened at.
static func at_point(control: Control, local: Vector2) -> Vector2i:
    return Vector2i((control.get_screen_transform() * local).floor())


## Where a menu opened at *point*, in *window*'s logical coordinates, puts its
## top-left corner. The answer `at_point` gives for a control filling *window*,
## for a caller that has the point and not the control, as the canvas menu has.
static func at_window_point(window: Window, point: Vector2) -> Vector2i:
    if window.is_embedding_subwindows():
        return Vector2i(point.floor())
    var at := Vector2(window.position) + window.get_final_transform() * point
    return Vector2i(at.floor())


## *extent*, a length of a window inside *host*, in the host's logical units:
## itself when the host embeds its windows, and through the host's scale when
## the window is one of the system's, whose size is the screen's pixels.
static func extent_in(host: Window, extent: Vector2) -> Vector2:
    if host == null or host.is_embedding_subwindows():
        return extent
    return extent / host.get_final_transform().get_scale()


## A placed *popup*'s top-left corner in its main window's logical coordinates,
## the space a scenario aims a press in, so a reader compares the two. The
## inverse of `at_point` for a control of the main window: an embedded popup is
## already there, and a popup of its own is in the screen's pixels.
static func in_main_window(popup: Window) -> Vector2:
    var at := Vector2(popup.position)
    if not popup.is_inside_tree() or popup.is_embedded():
        return at
    var root := popup.get_tree().root
    return root.get_final_transform().affine_inverse() * (at - Vector2(root.position))


## The rectangle *popup* may use: the visible rect of the viewport it is embedded
## in, or the usable screen when it is a real OS window. A zero rect when neither
## can be found, which `under` reads as no limit.
##
## The embedder is walked to rather than taken as the parent's viewport, because
## the parent's viewport is the docker and a docker embeds nothing: the list is
## embedded in the root beside it, the way `Window` finds its own embedder.
static func room_for(popup: Window) -> Rect2i:
    if not popup.is_inside_tree():
        return Rect2i()
    if not popup.is_embedded():
        return DisplayServer.screen_get_usable_rect(popup.current_screen)
    var node := popup.get_parent()
    while node != null:
        var viewport := node.get_viewport()
        if viewport == null:
            break
        if viewport.gui_embed_subwindows:
            return Rect2i(viewport.get_visible_rect())
        node = viewport.get_parent()
    return Rect2i()


## Where a list *wanted* large opens against *anchor*, inside *room*.
##
## Under the anchor when the list fits there. Otherwise on whichever side has
## more room, and no taller than that side, so the list never lies over the
## button it came from. The engine's own fitting pushes a popup that overflows
## the bottom back up over its anchor, which is what a list opened from a
## dropdown near the foot of a maximised docker did once. Rows scroll, so a
## shorter list loses nothing but a scroll.
static func under(anchor: Rect2, wanted: Vector2i, room: Rect2i) -> Rect2i:
    var left := int(anchor.position.x)
    var below := ceili(anchor.end.y)
    if room.size == Vector2i.ZERO:
        return Rect2i(Vector2i(left, below), wanted)
    var room_below := room.end.y - below
    var above := floori(anchor.position.y)
    var room_above := above - room.position.y
    if wanted.y <= room_below or room_below >= room_above:
        return Rect2i(Vector2i(left, below), Vector2i(wanted.x, clampi(room_below, 1, wanted.y)))
    var height := mini(wanted.y, room_above)
    return Rect2i(Vector2i(left, above - height), Vector2i(wanted.x, height))


## Where a child list *wanted* large opens beside *row*, a row of the list whose
## rectangle is *parent*, inside *room*.
##
## Right of the parent with its top at the row's, which is where a submenu opens.
## On the left instead when the right has no room for it and the left has, and
## moved up, never over the room's top, when it would run off the foot. No taller
## than the room, since rows scroll.
static func beside(parent: Rect2, row: Rect2, wanted: Vector2i, room: Rect2i) -> Rect2i:
    var left := ceili(parent.end.x)
    var top := floori(row.position.y)
    if room.size == Vector2i.ZERO:
        return Rect2i(Vector2i(left, top), wanted)
    if left + wanted.x > room.end.x and floori(parent.position.x) - wanted.x >= room.position.x:
        left = floori(parent.position.x) - wanted.x
    var height := mini(wanted.y, room.size.y)
    top = clampi(top, room.position.y, room.end.y - height)
    return Rect2i(Vector2i(left, top), Vector2i(wanted.x, height))
