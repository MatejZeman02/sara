## Where the Brush Presets docker opens and how it is shown and put away: beside
## the pointer on a right press, through the Dockers menu's command, and lent on
## a summon.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A class of its own, apart from `brush_presets_docker.gd` by responsibility.
## The docker owns its grid, its filter, its tags and its actions. This owns one decision,
## where a window of the docker's size stands for a press and which door shows
## it, and holds no state: every answer is read off the window it is handed and
## the host that window is embedded in, so nothing here can drift from the
## docker's own `position`, `size` and `visible`. Static for that reason, the
## way `SaPopupRect` is, and handed the window rather than built with it, so the
## docker takes no piece that points back at it.
extends RefCounted

## The gap between the pressed point and the docker's nearest edge.
##
## Wide enough that a painter pressing twice in the same place is pressing on
## canvas both times, since a hand does not land on the same pixel, and narrow
## enough that the docker still reads as opening at the pointer, which is the
## whole of what the summon is.
const POINTER_GAP: int = 12


## Shows *docker*, puts it in front and gives it the keyboard.
##
## *at* is where it should open when it is closed, in the host window's logical
## coordinates, and nothing for the button. The right press on the canvas lends
## the docker through [method toggle_at] instead. A docker that is already open
## is left where the painter put it and only focused: moving a window somebody
## has placed is the opposite of what "opens the docker" means once it is open.
##
## Opening goes through the registered command rather than through `visible`,
## because showing a docker is a layout edit: the Dockers menu carries a
## checkmark for it, the geometry is restored from the profile, and the layout
## is saved. Setting the flag here would show the window and leave all three
## behind.
##
## **The move happens before the show, not after it**. The restore that the
## third of those brings is `DockerLayoutStore.reapply_deferred`: it writes the
## stored position, queues the same write for the end of the frame, and then
## re-asserts it once a frame for sixty more. A position written after the show
## is undone before the painter can see it, so the docker would open wherever
## it was last left. Telling the store first is what a
## `docker` capture step already does against the same settle loop, and every
## one of those later writes then asserts the place the press asked for.
##
## The store is told even though nothing here writes the profile: `note_placement`
## is the cache and the intent, not the file, so a right press moves the docker
## the way a drag does and does not save a layout behind the painter's back.
##
## **Beside the pointer rather than under it**. With the docker's own top left
## on the pressed point, the point stops being canvas: the second right press
## of the toggle lands inside an embedded `Window`, never reaches
## `ToolMachine.handle_input`, and shuts nothing. [method beside_pointer] keeps
## the docker at the press and leaves the press on the canvas, which is the only
## reading that costs neither anything.
static func reveal(docker: Window, at: Variant = null) -> bool:
    var was_open := docker.visible
    if not was_open and at is Vector2:
        docker.position = beside_pointer(docker, at as Vector2)
        note_placement(docker)
    if not was_open:
        _set_shown(docker, true)
    if not docker.visible:
        return false
    docker.grab_focus()
    return true


## Tells the layout store *docker* stands where it now stands, so the restore
## the show is about to run, and the settle loop behind it, assert that rather
## than the position the profile holds.
##
## Answers false in a host with no docker manager, which is every test that
## builds the docker on its own, for the reason `_set_shown`'s own fallback
## exists: a docker with nobody to keep its layout has no layout to lose.
static func note_placement(docker: Window) -> bool:
    var main := _docker_manager(docker)
    if main == null or not main.has_method("note_docker_placement"):
        return false
    return bool(main.call("note_docker_placement", docker))


## Hides *docker* again, through the same door [method reveal] opens it by, so
## the Dockers menu checkmark and the saved layout follow. Answers whether it
## ended up hidden.
static func conceal(docker: Window) -> bool:
    if docker.visible:
        _set_shown(docker, false)
    return not docker.visible


## Lends *docker* to the brush's right press at *point*, or sends it home when
## it is already out on one. *point* is in the host window's logical coordinates.
## Answers whether the press moved it, so a press that did nothing is left to the
## context menu.
##
## **On a borrow, not on the layout**, so the docker stays where the painter
## put it. Shown through the Dockers menu's command, its place would be written
## over and the shipped layout forked under a name the painter never chose. The
## summon a chord makes writes neither, and
## sending it back restores the place and the visibility the press found. The
## summon's leave comes with it, as for a chord.
##
## Centred on the middle of [method beside_pointer]'s rectangle, because the
## borrow centres a docker on the point it is given, and the press has to stay
## canvas for the second one to reach the tool machine. A docker of its
## own is placed in the desktop's pixels, so the corner is carried there by
## where the docker stands now, read in the host's space and in its own.
##
## *dockers* is the manager that owns the summon, the main scene's when none is
## handed in, which is every caller but a suite. A host with none flips the flag
## by hand, for the reason [method note_placement] answers false there.
static func toggle_at(docker: Window, point: Vector2, dockers: MainDockers = null) -> bool:
    if dockers == null:
        dockers = _docker_manager(docker) as MainDockers
    if dockers == null:
        if not docker.visible:
            docker.position = beside_pointer(docker, point)
        docker.visible = not docker.visible
        return true
    var section := String(SaDockerIds.BRUSH_PRESETS)
    if dockers.summon.is_summoned(docker):
        dockers.summon.send_back(section)
        return not dockers.layout_store.is_borrowed(section)
    # From the host's logical units into the space `position` is in.
    var corner := Vector2(beside_pointer(docker, point))
    var host := _host(docker)
    if host != null:
        corner = Vector2(SaPopupRect.at_window_point(host, corner))
    dockers.summon_docker_by_id(SaDockerIds.BRUSH_PRESETS, false, Vector2i(corner) + Vector2i(Vector2(docker.size) * 0.5))
    return dockers.layout_store.is_borrowed(section)


## Shows or hides *docker* through the door the Dockers menu row takes, so
## the checkmark, the geometry restore and the saved layout all follow.
##
## **Through the command registry**. Running the `docker_brush_presets` command
## is what the chord and the menu row do, so all three take one path, rather
## than the manager's `_toggle_docker_by_id`, which matches on the registered
## docker id and not the shortcut id. The fallback below that sets `visible` by
## hand is for a host with no docker manager, which is every test.
static func _set_shown(docker: Window, want: bool) -> void:
    if docker.visible == want:
        return
    var commands := _command_registry(docker)
    if commands != null:
        commands.execute(&"docker_brush_presets")
    if docker.visible != want:
        docker.visible = want


## The application's command registry, or null in a host that has none.
##
## Reached through the same autoload the rest of the app does rather than through
## the docker manager, because a command is the skeleton's and a docker is not
## the thing that owns the list of them.
static func _command_registry(docker: Window) -> SaCommandRegistry:
    var main_node := _main_node(docker)
    if main_node == null or not ("registries" in main_node):
        return null
    return (main_node.registries as Object).get("commands") as SaCommandRegistry


## The node that owns every docker, when a main scene holds one.
static func _docker_manager(docker: Window) -> Object:
    var main_node := _main_node(docker)
    if main_node == null or not ("dockers" in main_node):
        return null
    var dockers: Object = main_node.dockers
    return dockers if dockers != null and dockers.has_method("toggle_docker_by_id") else null


## The main scene *docker* runs under, or null outside the tree.
static func _main_node(docker: Window) -> Node:
    var tree := docker.get_tree() if docker.is_inside_tree() else null
    return tree.current_scene if tree != null else null


## Where *docker* goes for a press at *at*: beside the point, never over it,
## and wholly inside the host.
##
## Down and right of the pointer where there is room for it, which is where a
## menu opens and is what a painter expects, and up or left on whichever axis
## there is not. One axis clear of the point is enough for the point to be
## outside the docker, and doing both is what keeps the corner cases from
## reading as a jump.
##
## A host with no room for the docker and the gap on either side of the point
## clamps the way [method inside_host] does and the press lands on the docker
## again. That is a window smaller than 304 by 384 with the pointer in the middle
## of it, where there is nowhere to put a 280 by 360 docker that is not under the
## pointer, and the toggle is the lesser loss.
## Every length is in the host's logical units, the press's own.
static func beside_pointer(docker: Window, at: Vector2) -> Vector2i:
    var room := _host_room(docker)
    var extent := Vector2i(_extent_in_host(docker))
    var wanted := Vector2i(at)
    wanted.x = clear_axis(int(at.x), extent.x, POINTER_GAP, int(room.x))
    wanted.y = clear_axis(int(at.y), extent.y, POINTER_GAP, int(room.y))
    return inside_host(docker, Vector2(wanted))


## One axis of [method beside_pointer]: *point* plus the gap when the docker's
## *extent* fits after it, *point* minus the gap and the extent when it fits
## before it, and the point itself when neither fits.
static func clear_axis(point: int, extent: int, gap: int, room: int) -> int:
    if point + gap + extent <= room:
        return point + gap
    if point - gap - extent >= 0:
        return point - gap - extent
    return point


## *at* clamped so the whole of *docker* is inside the window it is embedded in.
##
## A right click near the bottom right corner would otherwise open the docker
## mostly off screen, which is where its drag bar goes with it and is a window a
## painter cannot move back.
static func inside_host(docker: Window, at: Vector2) -> Vector2i:
    var host := _host(docker)
    var wanted := Vector2i(at)
    if host == null:
        return wanted
    var room := host.get_visible_rect().size - _extent_in_host(docker)
    return Vector2i(int(clampf(wanted.x, 0.0, maxf(room.x, 0.0))), int(clampf(wanted.y, 0.0, maxf(room.y, 0.0))))


## The window *docker* is embedded in, or null when it has no parent.
static func _host(docker: Window) -> Window:
    return docker.get_parent().get_window() if docker.get_parent() != null else null


## The docker's size in its host's logical units, [method SaPopupRect.extent_in].
static func _extent_in_host(docker: Window) -> Vector2:
    return SaPopupRect.extent_in(_host(docker), Vector2(docker.size))


## The host window's visible size, or the docker's own when it has no host,
## which is every suite that builds the docker on its own.
static func _host_room(docker: Window) -> Vector2:
    var host := _host(docker)
    return host.get_visible_rect().size if host != null else Vector2(docker.size)
