## The window a second monitor holds: a native OS window whatever the root's
## embedding says, and one that remembers its screen and rectangle.
##
## Every popup and dialog is embedded while the root embeds its subwindows,
## and an embedded host could never leave Sara's own window. A second workspace
## exists to sit on a second monitor, and an embedded one cannot, so this is the
## one window that asks Godot for a native one
## regardless. The dockers dragged into it stay embedded in *it*, under the
## same preference the main window reads, so a docker measures itself the same
## way in either window.
class_name SecondaryWorkspaceHost
extends Window


func _init() -> void:
    # A new Window is visible before it is in any tree, and the flag refuses
    # to move on a window that is showing, so hide it first. The host is shown
    # by `place_from_settings` once it is parented and placed.
    visible = false
    force_native = true


## Puts the host where it was last seen, or centred over its owner when
## nothing is remembered or the remembered place is on no screen that is
## plugged in now. Call once the host is in the tree.
func place_from_settings() -> void:
    var usable: Array[Rect2i] = []
    for screen in DisplayServer.get_screen_count():
        usable.append(DisplayServer.screen_get_usable_rect(screen))
    var rect := placement(SaSettings.secondary_workspace_rect, SaSettings.secondary_workspace_screen, usable)
    if rect.size == Vector2i.ZERO:
        popup_centered()
        return
    size = rect.size
    position = rect.position
    show()


## Where to open: the remembered rectangle when some screen still holds any of
## it, and an empty rectangle otherwise, which the caller reads as "centre it".
##
## The remembered screen is tried first and every other screen after it,
## because a monitor unplugged and plugged back in can come back under another
## index while the rectangle it held is still a real place. A rectangle no
## screen touches is a monitor that is gone, and a window opened there would be
## one nobody can reach, which is the same rule the docker layout store applies
## to a docker saved on a second monitor.
static func placement(remembered: Rect2i, remembered_screen: int, usable: Array[Rect2i]) -> Rect2i:
    if remembered.size.x <= 0 or remembered.size.y <= 0:
        return Rect2i()
    if remembered_screen >= 0 and remembered_screen < usable.size():
        if usable[remembered_screen].intersects(remembered):
            return remembered
    for rect in usable:
        if rect.intersects(remembered):
            return remembered
    return Rect2i()


## Writes the host's screen and rectangle into the profile.
##
## Only a native window on screen has a place worth keeping: an embedded one
## measures itself inside its host and a hidden one is at whatever Godot last
## had, so both are skipped rather than written over a good memory.
func remember() -> void:
    if not visible or not is_inside_tree() or is_embedded():
        return
    SaSettings.secondary_workspace_screen = current_screen
    SaSettings.secondary_workspace_rect = Rect2i(position, size)


func _notification(what: int) -> void:
    # On losing focus rather than on every move, because the file half of the
    # settings writes the profile on each change and a drag is a hundred of
    # them. Focus leaves the host when the painter clicks back into the main
    # window, which is also what happens on the way to quitting Sara.
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
        remember()
