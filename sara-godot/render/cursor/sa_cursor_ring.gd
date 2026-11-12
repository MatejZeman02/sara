## How the ring is sized and pinned: which canvas under the pointer claims a
## ring and how large, where the pointer is for the ring's purposes, and whether
## a window, a docker or the chrome owns the pixel instead.
##
## One of the three parts of the cursor package, private to it. The rest of the
## tree asks [SaCursorPolicy], which forwards here. Asks [SaPointerDevice]
## where the pointer is and nothing of the facade, so the three parts depend one
## way, device, ring, policy.
##
## **Every walk of `SaCanvas.live_canvases()` here is a question about the
## hand, not about the document**: which canvas the pointer is over, the
## scratchpad as readily as the painting. A ring is drawn wherever a press
## would paint, so a canvas that is not in front still claims one, and asking
## the front surface instead would put the ring on the wrong canvas.
class_name SaCursorRing
extends RefCounted

## Who has pinned the pointer, in which window, and where. Null when nothing is
## pinned, which is almost always.
static var _pin_owner: Object = null
static var _pin_window: Window = null
static var _pin_position: Vector2 = Vector2.ZERO


## Ring radius for the canvas under `pointer` inside `window`, or -1.0 when the
## pointer is not over a canvas that wants one.
##
## `pointer` is in the window's viewport space, which is also the CursorOverlay's
## local space, since the overlay is a full-rect top-level control.
static func cursor_ring_radius_at(window: Window, pointer: Vector2) -> float:
    # *Never* means the system pointer and nothing drawn, in every window, and
    # the ring is the largest thing Sara draws, so a painter who turned the
    # software cursor off gets no ring and no crosshair over the OS pointer. The
    # setting is read here rather
    # than in the overlay because everything that has to agree about the ring,
    # the overlay, the OS cursor policy and the probe, comes through this one
    # function.
    if SaSettings.software_cursor == "never":
        return -1.0
    if window != null:
        # A pointer outside this window is not this window's business. Without
        # this every window answers for the whole screen, so the info docker's
        # scratchpad would claim a pointer that is really over another docker
        # and hide the OS cursor for a ring nobody can see.
        if not Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(pointer):
            return -1.0
        if pointer_is_over_ui(window, pointer):
            return -1.0
    return canvas_ring_radius_at(window, pointer)


## The ring the canvas under `pointer` asks for, ignoring whatever is drawn on
## top of it.
##
## The tail of `cursor_ring_radius_at`, named so a probe can read the geometric
## half on its own. The full answer above needs `gui_get_hovered_control`, which
## answers for wherever the real pointer physically is rather than for the point
## it was asked about, so under Wayland, where a capture cannot place the
## pointer, it masks every geometry bug in this package. This half asks
## nothing but rectangles and so says the same thing wherever the hand left the
## mouse.
static func canvas_ring_radius_at(window: Window, pointer: Vector2) -> float:
    for sa_canvas: SaCanvas in SaCanvas.live_canvases():
        if sa_canvas.get_window() != window or not sa_canvas.is_visible_in_tree():
            continue
        if sa_canvas.cursor_ring_radius < 0.0:
            continue
        if _point_is_over(sa_canvas, pointer):
            return sa_canvas.cursor_ring_radius * SaEnvironmentView.ring_scale(sa_canvas, pointer)
    return -1.0


## The outline the canvas under *pointer* wants its ring drawn as, or empty for
## the circle. Asked the way the radius is, so the two agree.
##
## Here rather than on `SaCanvas`, because it pairs with the radius above and
## walks the same list, so the two belong in one file and the canvas is not one
## of them.
static func cursor_outline_at(window: Window, pointer: Vector2) -> PackedVector2Array:
    for sa_canvas: SaCanvas in SaCanvas.live_canvases():
        if sa_canvas.get_window() != window or not sa_canvas.is_visible_in_tree():
            continue
        if sa_canvas.cursor_ring_radius < 0.0 or sa_canvas.cursor_outline.is_empty():
            continue
        if _point_is_over(sa_canvas, pointer):
            return sa_canvas.cursor_outline
    return PackedVector2Array()


## Whether *pointer*, in the window's viewport space, is on the pixels *canvas*
## draws.
##
## The point is taken into the canvas's own space and tested against its local
## rect, rather than the canvas's rect being taken out into the window's. That
## is not a rearrangement, it is the only form that is right:
##
## - A mirrored view is a negative `SaCanvas.scale`, which `SaCanvasView.get_flip`
##   reads the sign of. `Control.get_global_rect` multiplies the size by the
##   transform's scale, and a transform with one axis negated has a determinant
##   below zero, so the rect comes back with a negative *height* whichever axis
##   is mirrored. `Rect2.has_point` refuses such a rect, prints `Rect2 size is
##   negative, this is not supported` and answers false, so a mirrored canvas
##   would log an error every frame and be told it had no pointer over it.
## - `Rect2.abs()` is wrong too. It normalises the rect in place,
##   so a canvas mirrored about its own right edge comes back as the rectangle
##   *beside* the pixels it draws rather than the ones it draws.
## - The canvas can also be turned, and `get_global_rect` drops the rotation
##   entirely, so a turned canvas would answer for an unturned rectangle. The
##   inverse transform costs the same and is right for both.
##
## A canvas shown as the sky draws on the whole of its Environment view.
static func _point_is_over(canvas: SaCanvas, pointer: Vector2) -> bool:
    var sky := SaEnvironmentView.of_canvas(canvas)
    if sky != null and sky.on:
        return sky.covers(pointer)
    var local: Vector2 = canvas.get_global_transform().affine_inverse() * pointer
    return Rect2(Vector2.ZERO, canvas.size).has_point(local)


## Every window embedded directly in `root`, wherever it sits in the node tree.
##
## Dockers are children of the Main node, not of the Window, so a scan of the
## window's direct children finds none of them, and the pointer over a docker
## would read as "over the canvas", a ring drawn underneath the docker with the
## OS cursor hidden, leaving no pointer at all. Recursion stops at each Window,
## because anything below one is embedded in *that* window and measured in its
## coordinates.
##
## `include_internal` also returns the windows Godot keeps as internal children,
## which is where a dropdown's popup lives: an OptionButton owns its PopupMenu
## and `get_children()` never mentions it. Off by default, so the cursor logic
## keeps answering exactly as it did.
static func embedded_subwindows(root: Node, include_internal: bool = false) -> Array[Window]:
    var found: Array[Window] = []
    for sub in WindowWalk.under(root, include_internal):
        if sub.visible and sub.is_embedded():
            found.append(sub)
    return found


## Every `Window` that is a window of its own: in the tree under *root*, visible,
## and not embedded in a parent viewport. The root window, and every docker,
## dialog and menu once `SaSettings.embed_subwindows` is off.
##
## *asked* itself is never among them, and neither is a window *asked* is drawn
## inside. A window of its own covers what it overlaps, but an ancestor is the
## window this one sits in rather than something standing over it, so a pointer
## inside *asked* is in front of its ancestor and not in it.
##
## When *asked* is a popup, only another popup is among them, since an open list
## is drawn over every docker and dialog whatever their places in the tree.
##
## Internal children are included, so a menu let out of the main window counts
## for the reason [method pointer_is_over_embedded_window] gives about the
## embedded kind.
static func windows_of_their_own(root: Node, asked: Window = null) -> Array[Window]:
    var found: Array[Window] = []
    for sub in WindowWalk.under(root, true):
        if not sub.visible or sub.is_embedded():
            continue
        if sub == asked or (asked != null and is_instance_valid(asked) and sub.is_ancestor_of(asked)):
            continue
        # A popup stands over every window that is not one, so a docker let out
        # under an open list does not cover the list's own pointer.
        if asked is Popup and not (sub is Popup):
            continue
        found.append(sub)
    return found


## Where *other*, a window of its own, sits, as a rectangle in *asked*'s own
## space.
##
## Both ends go through the desktop transform the pen is carried by, which is
## the screen transform with the window's own place on the desktop put back, so
## a display scale, a second monitor and a main window away from the corner are
## the same arithmetic as the ordinary case.
static func rect_in(asked: Window, other: Window) -> Rect2:
    var asked_desktop: Variant = SaPointerDevice.desktop_transform(asked)
    var other_desktop: Variant = SaPointerDevice.desktop_transform(other)
    if asked_desktop == null or other_desktop == null:
        return Rect2()
    var asked_to_desktop: Transform2D = asked_desktop
    var other_to_desktop: Transform2D = other_desktop
    var between := asked_to_desktop.affine_inverse() * other_to_desktop
    var corner := between * Vector2.ZERO
    var far := between * other.get_visible_rect().size
    return Rect2(corner, far - corner)


## Whether *pointer*, in *window*'s own space, falls on a window of its own
## rather than in *window*.
##
## The rule of the cursor package, one window further out. A docker the
## painter has let out is a real window of the operating system stacked over
## the main one, and the same pixel in the main window's space is still over
## the canvas underneath it. Asking the main window alone claims the ring and
## hides the OS cursor for a cursor drawn in a window the docker covers, and
## leaves the painter no pointer at all over their own docker.
##
## The answer is the same wherever the pointer physically is, which is what lets
## the probe read it: nothing here asks the display server.
static func pointer_is_over_a_window_of_its_own(window: Window, pointer: Vector2) -> bool:
    if window == null:
        return false
    var tree := window.get_tree()
    if tree == null:
        return false
    for other in windows_of_their_own(tree.root, window):
        if rect_in(window, other).has_point(pointer):
            return true
    return false


## Whether an embedded window, a docker or an open menu, owns the pixel at
## `pointer`.
##
## Internal children included, which is what makes an open menu count. A
## `PopupMenu` is an internal child of whoever owns it, so a scan of ordinary
## children finds every docker and no menu at all, and the preset list opens
## downwards out of the tool options bar and across the canvas.
## `gui_get_hovered_control` answers null while an embedded subwindow has the
## pointer, so nothing else catches a menu's rows over the canvas either, and
## the canvas would claim a ring drawn underneath the menu. Mouse mode is
## process-wide, so the OS cursor would go with it and leave the painter no
## pointer at all over the menu.
##
## The one rule of the cursor package is why this belongs here: the ring is
## never drawn over a menu, so the ring may never hide the cursor over one. The
## list's own `CursorOverlay` draws the pen's arrow there and never a ring,
## because no canvas is in a list's window.
static func pointer_is_over_embedded_window(window: Window, pointer: Vector2) -> bool:
    if window == null:
        return false
    # An embedded docker is a Window inside the host viewport, not a Control, so
    # it never shows up as a hovered Control and has to be tested directly.
    for sub in embedded_subwindows(window, true):
        if place_of(window, sub).has_point(pointer):
            return true
    return false


## Where *sub*, a window embedded under *asked*, stands, as a rectangle in
## *asked*'s own space.
##
## An embedded window's `position` is in the space of the viewport that embeds
## it, which is *asked*'s own only while *asked* embeds it and has no content
## scale of its own. The note box is a child of the Brush Editor and embedded
## beside it in the root, and the maximised editor is at 1.25, so its place
## added to nothing landed a fifth away from where the editor's pointer read
## it, and the editor drew the pen's arrow under the box. Carried through both
## windows' transforms instead, as [method rect_in] carries a window of its own,
## with the place alone for a window the desktop transform cannot reach.
static func place_of(asked: Window, sub: Window) -> Rect2:
    var carried := rect_in(asked, sub)
    if carried.has_area():
        return carried
    return Rect2(Vector2(sub.position), Vector2(sub.size))


## Whether something other than the canvas owns the pixel under the pointer.
##
## The canvas rect alone is not enough: a docker or the top bar drawn over it
## still leaves the pointer geometrically "inside the canvas", so the brush ring
## kept being drawn over dockers while the OS cursor stayed hidden, exactly
## where the user needs a real pointer to click a slider.
static func pointer_is_over_ui(window: Window, pointer: Vector2) -> bool:
    # A window of its own is over this one, so the pixel is not this window's to
    # draw in. Asked first, because it is the outer of the two: a docker let out
    # of the main window is not embedded in it and the scan below finds nothing
    # there.
    if pointer_is_over_a_window_of_its_own(window, pointer):
        return true
    if pointer_is_over_embedded_window(window, pointer):
        return true

    var hovered := window.gui_get_hovered_control()
    if hovered == null:
        return false
    # A Control that is the canvas, or lives inside it, is not "over UI", and
    # nor is the sky the Environment view draws in the canvas's place.
    var node: Node = hovered
    while node != null:
        if node is SaCanvas or node is SaEnvironmentView:
            return false
        node = node.get_parent()
    return true


## The pointer in `window`'s viewport space, or the pinned point while a
## gesture holds one.
##
## The single source of truth for "where is the pointer", so the decision to hide
## the OS cursor and the decision to draw a ring cannot disagree. A pen is carried
## into every window: Windows Ink reports the mouse, so a main window that read
## it would draw the ring under a let-out docker the pen is over.
static func pointer_in_window(window: Window) -> Vector2:
    if window == null:
        return Vector2(-1.0, -1.0)
    if window == _pin_window and pointer_is_pinned():
        return _pin_position
    return SaPointerDevice.in_window(window)


## Freezes where the application thinks the pointer is, in `window`'s viewport
## space.
##
## For a gesture that moves the mouse without meaning to move the cursor, which
## today is the shift drag that resizes the brush: the painter drags sideways to
## grow the ring, and a ring that travelled with the hand would preview the size
## somewhere other than where the next stroke starts.
## Wayland will not let a client put the pointer back afterwards, and pinning
## needs no permission: everything that asks the policy where the pointer is
## gets the same frozen answer, so the ring, the OS cursor policy and the over-UI test
## agree, while the gesture's own maths keeps reading the event.
##
## Whoever pins must unpin. A pin nobody drops is a cursor that never moves
## again, which is the failure the package's rules exist to prevent, so the
## caller drops it every frame it is not gesturing rather than only on the release.
static func pin_pointer(holder: Object, window: Window, at: Vector2) -> void:
    _pin_owner = holder
    _pin_window = window
    _pin_position = at


## Drops the pin, and only when *holder* is the one holding it.
##
## Sara runs a ToolMachine per paintable surface, the main canvas and the info
## docker's scratchpad, and each drops a pin every frame it is not gesturing as
## the safety net above. Without the owner the idle machine would unpin the
## main canvas's gesture on the next frame, and the ring would travel with the
## hand while its radius grew.
static func unpin_pointer(holder: Object) -> void:
    if holder == _pin_owner:
        _pin_owner = null
        _pin_window = null


## False once either the owner or the window is gone, so a pin cannot outlive
## the objects it belongs to.
static func pointer_is_pinned() -> bool:
    return is_instance_valid(_pin_owner) and is_instance_valid(_pin_window)


## Whether *pointer* in *window* is on a canvas rather than on a docker, a menu
## or the chrome.
##
## The test the tool picture is put up and taken down by. Rectangles only, for
## the reason [method SaCursorPolicy.drawn_at] gives.
static func pointer_is_over_a_canvas(window: Window, pointer: Vector2) -> bool:
    if window == null:
        return false
    if not Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(pointer):
        return false
    if pointer_is_over_a_window_of_its_own(window, pointer):
        return false
    if pointer_is_over_embedded_window(window, pointer):
        return false
    for sa_canvas: SaCanvas in SaCanvas.live_canvases():
        if sa_canvas.get_window() != window or not sa_canvas.is_visible_in_tree():
            continue
        if _point_is_over(sa_canvas, pointer):
            return true
    return false


## The windows under a node that no other window stands between, every one
## whether shown or not, walked once and kept until the tree changes.
##
## Both scans above start from this list and filter it by what can change
## without the tree changing, a window shown or hidden and a window embedded or
## let out. An idle Sara asks two a frame, one for the main window's ring and
## one for the OS cursor sync, and a walk of the whole tree each time is a
## measurable share of a core for a pointer that has not moved, in both layouts.
## A still tree walks nothing.
##
## `SceneTree.tree_changed` is the one signal that covers a node added, removed
## or moved among its siblings, which are the three ways the list or its order
## changes, so the whole memory is dropped on it rather than worked out node by
## node. A root outside the tree has no such signal and is walked every time.
class WindowWalk:
    ## The lists walked since the tree last changed, by the root's instance id
    ## and whether internal children were walked.
    static var _walked: Dictionary = {}
    ## The tree whose `tree_changed` drops [member _walked].
    static var _tree: SceneTree = null

    ## Every window under *root* with no other window between them that embeds
    ## anything, in tree order, and with internal children the lists that hang
    ## from a list. Recursion stops at a window that embeds its own, because
    ## what is below one is inside it and measured in its own coordinates. A
    ## window that embeds nothing does not hold its windows: a filter section's
    ## list is a child of the Filter menu and is placed where the menu is,
    ## embedded in the same viewport with embedded subwindows on and a window of
    ## the operating system with them off. A walk that stops at the menu finds
    ## neither, and the main window would draw the ring under the list. The note
    ## box is the same case outside a list: it is a child of the window the note
    ## is taken in, the Brush Editor say, and embedded beside it in the root,
    ## and a walk that stops at the editor never finds the box, so the system
    ## cursor would be hidden over a window it cannot see.
    static func under(root: Node, include_internal: bool) -> Array[Window]:
        var found: Array[Window] = []
        if root == null:
            return found
        if not root.is_inside_tree():
            _walk(root, include_internal, found)
            return found
        _follow(root.get_tree())
        var key := "%d/%s" % [root.get_instance_id(), include_internal]
        var kept: Variant = _walked.get(key)
        if kept != null:
            for sub: Variant in kept:
                if is_instance_valid(sub):
                    found.append(sub)
            return found
        _walk(root, include_internal, found)
        _walked[key] = found.duplicate()
        return found

    static func _walk(node: Node, include_internal: bool, found: Array[Window]) -> void:
        for child in node.get_children(include_internal):
            var sub := child as Window
            if sub != null:
                found.append(sub)
                if not sub.gui_embed_subwindows and (include_internal or not (sub is Popup)):
                    _walk(sub, include_internal, found)
                continue
            _walk(child, include_internal, found)

    static func _follow(tree: SceneTree) -> void:
        if tree == _tree:
            return
        if _tree != null and is_instance_valid(_tree) and _tree.tree_changed.is_connected(_forget):
            _tree.tree_changed.disconnect(_forget)
        _tree = tree
        _walked.clear()
        tree.tree_changed.connect(_forget)

    static func _forget() -> void:
        _walked.clear()
