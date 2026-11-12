## Brings Sara's window in front of the window a file came from, restoring it
## first when it is minimised, before any question about the file opens.
##
## A file comes from somewhere else on the desktop, a file manager the painter
## dropped it from or a second start that handed it over, and that window keeps
## the front and the keyboard unless Sara asks for them. A question opened
## inside Sara's window is only as far forward as the window is, so without
## this the fit dialog of a dropped picture opens behind the file manager and
## the drop seems to do nothing. `SaSingleInstance` and the drop route both
## call [method bring], so the two cannot drift apart.
class_name SaWindowForward
extends RefCounted

## What raises a window. A suite swaps it for a witness that records the call
## and the window's mode at that moment, as the about dialog's suite swaps its
## opener, and puts it back after.
static var raise: Callable = func(window: Window) -> void:
    window.move_to_foreground()
    window.grab_focus()
    if asks_for_attention(DisplayServer.get_name()):
        window.request_attention()


## Whether a raise on the display server named *server* also asks for
## attention. Under Wayland `move_to_foreground` puts nothing on the wire, and
## `request_attention` is the one call that does: an `xdg_activation_v1` token
## with no serial, then an activation of the window with it. A compositor
## that keeps focus where the painter put it, mutter among them, answers that
## by marking Sara as wanting attention rather than by raising it, and no
## serial a drop target holds, the drop's own included, makes mutter raise it,
## as measured. Windows and X11 stay on the raise above, where
## it works and where an asked attention would flash the taskbar as well.
static func asks_for_attention(server: String) -> bool:
    return server == "Wayland"


## Restores *window* when it is minimised, then raises it.
static func bring(window: Window) -> void:
    if window == null:
        return
    if window.mode == Window.MODE_MINIMIZED:
        window.mode = Window.MODE_MAXIMIZED
    raise.call(window)


## The part of a drop that comes before any question: hands *files* to the
## Reference docker when the drop landed on it at *at*, and brings *window*
## forward for a drop Sara takes either way. True when the docker took it, so
## the caller routes the files only when this says false.
static func take_drop(window: Window, files: PackedStringArray, at: Vector2) -> bool:
    if ReferenceDocker.take_drop(window.get_tree(), files, at):
        bring(window)
        return true
    for path in files:
        if takes(path):
            bring(window)
            break
    return false


## Whether a dropped *path* is one the document files open or import: a
## picture, a `.sad` or a layered file.
static func takes(path: String) -> bool:
    if SaImageImport.is_image_path(path) or path.get_extension().to_lower() == "sad":
        return true
    return SaImageImport.formats().layered_named(path) != null
