## A touchpad's two finger scroll moves every plain `ScrollContainer` as far as
## the fingers move, one logical pixel of page for every pixel of its delta.
##
## **Godot reads a pan's delta as notches.** On Wayland a touchpad's scroll
## arrives as an `InputEventPanGesture` whose delta is the compositor's axis
## value for the frame, in surface pixels, which are logical and not multiplied
## by the display scale (`platform/linuxbsd/wayland/wayland_thread.cpp`,
## `pg->set_delta(pd.scroll_vector)`), and Mutter's follows the finger.
## `ScrollContainer::gui_input` (`scene/gui/scroll_container.cpp`) moves
## `page * delta / ScrollBar::PAGE_DIVISOR` for it, an eighth of the page for
## every pixel, which jumps to the bottom of a page. Reading ten pixels as a
## wheel notch would still move about 75 logical pixels of a 600 pixel page for
## ten of finger, which is still too fast. This moves a pan by its delta as it stands, as
## GTK, the toolkit of GNOME's own apps, does, and leaves the wheel be.
##
## **A filter ahead of the engine's handler, not a subclass.** Every dialog,
## docker and popup of Sara and of a module builds its scrolls as plain
## `ScrollContainer`s, a dozen places and the engine's own popups among them,
## and a subclass would have to be named in every one of them and in every one
## to come. `Control._call_gui_input` emits `gui_input` before it calls the
## script's `_gui_input` and the engine's handler, under the engine's own
## comment that the signal comes first so it can override an event and accept
## it, so one connection per scroll, made as each enters the tree, is all
## it takes.
##
## **A scroll whose script reads its own input is left to it.** Preferences'
## `SaSettingsScroll` moves a pan the same pixel for pixel and a wheel notch a
## fixed 48 logical pixels, and a filter on its signal would run first and take
## its wheel's place.
class_name SaScrollPace
extends RefCounted


## Every `ScrollContainer` *tree* holds from here on, and every one it holds
## already, scrolls a pan as far as the fingers move.
##
## Called once, by the boot, before the first window is built. Called twice it
## connects nothing twice.
static func install(tree: SceneTree) -> void:
    if tree == null:
        return
    if not tree.node_added.is_connected(take):
        tree.node_added.connect(take)
    if tree.root != null:
        for node: Node in tree.root.find_children("*", "ScrollContainer", true, false):
            take(node)


## Makes *node* scroll a pan as far as the fingers move when it is a
## `ScrollContainer` that leaves its input to the engine, and does nothing
## otherwise.
##
## A scroll that leaves the tree and comes back, a docker let out of the window
## or put back, enters again, and the signal it already listens on is not
## connected a second time, which would move it twice.
static func take(node: Node) -> void:
    var scroll := node as ScrollContainer
    if scroll == null or scroll.has_method(&"_gui_input"):
        return
    if not scroll.gui_input.is_connected(_on_gui_input):
        scroll.gui_input.connect(_on_gui_input.bind(scroll))


## A pan scrolled the way the engine scrolls one, each enabled axis by its own
## part of the delta, but by that part in logical pixels. The bar's value is a
## float, so the fraction of a pixel a slow finger sends is kept there rather
## than rounded away on every event. Accepted when the scroll moved, which
## stops the engine's handler, and left alone when it did not, so a scroll at
## its end passes the pan to the one around it as the engine does. The engine's
## handler then moves the same way from the same end and moves nothing either.
static func _on_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
    var pan := event as InputEventPanGesture
    if pan == null or not is_instance_valid(scroll):
        return
    var across := scroll.get_h_scroll_bar()
    var down := scroll.get_v_scroll_bar()
    var before := Vector2(across.value, down.value)
    if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
        across.value += pan.delta.x
    if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
        down.value += pan.delta.y
    if Vector2(across.value, down.value) != before:
        scroll.accept_event()
