## A note taken inside Sara, on the control it is about.
##
## One shortcut, or Help > Take a Note, and the control under the pointer is
## highlighted as it moves. A click freezes it, the window is photographed with
## that control outlined, and a small box takes the text. `sa_note_describe.gd`
## turns the frozen control and the text into the entry: node path, window or
## bar, value, the settings it reads, and the build. That is what makes the
## note actionable for a reader who has not seen the screen.
##
## Not an issue tracker, and sent nowhere. The file lives in a default
## `notes` folder beside the logs, `Documents/Sara` on Android, or wherever `SARA_NOTES_DIR` points, and the capture
## harness's `note` step (`sa_capture_notes.gd`) writes into the capture's own
## directory instead. One file per launch, `<day>-<HHMM>.md`, named at the first note
## of the run, so a session of notes stays a session. All of that is `sa_note_file.gd`.
##
## The photograph is a readback of the root viewport outside a stroke, which is
## what the recorder does too, and hard rule 1 forbids a readback during a
## stroke only. Dockers as real OS windows are outside that viewport and are
## not in the picture, which the entry says when it happens. What is written is
## a WebP: the whole window shrunk, or the region a shift-drag framed at full
## resolution, which `sa_note_image.gd` decides.
##
## An open menu is a window of its own, and a note can be taken on an item in
## one, named in the entry and the tag. `sa_note_menu.gd` says which menu is
## open and which item: an engine `PopupMenu` is outlined whole and made deaf
## for the click, because it gives no rectangle for an item and hears the
## release first, and a row of Sara's own `SaChoicePopup`, every menu under the
## top bar, is a control the note freezes on and outlines by itself.
class_name SaNoteMode
extends Node

const NODE_NAME := "SaNoteMode"

## The InputMap action, in project.godot so it exists on a fresh install and the
## shortcuts dialog lists it. The command registered on it is the public door
## the chord fires through, the same one a module's command uses.
const ACTION := &"ui_take_note"
const COMMAND_TITLE := "Take a note on a control"

## The words the Help menu row shows, shorter because it stands under Help.
const COMMAND_LABEL := "Take a Note"

## Meta key under which a control names the SaSettings properties it reads.
const SETTINGS_META := &"sa_settings"

## The pointer this mode asks the canvas for, in place of whatever the active
## tool wanted. A question mark, because in this mode the pointer asks a control
## what it is rather than painting with it.
const CURSOR_SHAPE := Control.CURSOR_HELP

## The name this mode holds the pointer under, in `ToolMachine.pointer_holder`.
const POINTER_HOLDER := &"note_mode"

## Stripped from a node name before it is tried as a settings property.
const NAME_SUFFIXES: Array[String] = [
    "_check", "_checkbox", "_opt", "_option", "_slider", "_toggle", "_switch", "_spin", "_button"
]

signal note_written(path: String)

var notes_dir: String = ""  ## Where the run's markdown file and its images go.

var active: bool = false

## Whether a note is being taken anywhere in this process.
##
## Static because the shortcut router reads it with no reason to know where
## the mode node sits. The tool machine cannot name this class, so
## `_hold_pointer` writes the same fact into `ToolMachine.pointer_holder` beside
## it: while that stands no canvas asks for a brush ring and every canvas asks
## for `CURSOR_SHAPE`, so the OS pointer stays visible for the whole of the
## mode. Without it the note box is an embedded window drawn over a canvas
## that still claims the pointer under it, so the ring is drawn behind the box
## with the OS cursor hidden for it, leaving the painter no pointer at all, and
## the ring takes control wherever it pokes out past the box's edge.
static var taking_note: bool = false
## The control a click froze, null while the highlight still follows the pointer.
var frozen: Control = null
var hovered: Control = null  ## The control the highlight is on.

## The open menu the pointer is on and the item in it, or nothing.
var menu := SaNoteMenu.new()

## The region a shift-drag framed, in the root viewport's coordinates, and
## empty when the note is about the whole window.
var region := Rect2()

var _image: Image = null
## The root viewport's logical size when the picture was taken, which is what
## the region is measured in and the readback is not.
var _logical := Vector2.ZERO
var _region_from := Vector2.ZERO
var _region_drag: bool = false
## The window the last pointer motion went to, which is how the hover finds a
## menu that is a window of its own (`SaNoteMenu.under_pointer`). Forgotten at
## the start and the end of the mode, and whenever it has been freed, since
## the note box it was on is freed with the note.
var _pointer_window: Window = null
## Whether the release that follows the freezing press is still owed a swallow.
##
## **Plain rather than private.** A Button acts on release, so the press alone
## does not keep it from firing, and `ui/notes/tests/test_note_mode.gd` sets
## this to stand where a real press would have left it. A private is written by
## its own class only, and a constructor argument cannot express a state
## halfway through a gesture.
var swallow_release: bool = false
var _stamp: Dictionary = {}  ## The frozen moment, so the image and the entry share one name.
## What the entry says about the frozen control, read at the freeze rather
## than at the save: a row of a menu is freed when the menu is rebuilt on its
## next open, and a note box can outlive that.
var _described: Dictionary = {}

# --- Installing ---------------------------------------------------------------


## Puts the mode under `main` and registers its command in the registries
## `main` carries. Idempotent: the second call finds the first node.
static func install(main: Node) -> SaNoteMode:
    if main == null:
        return null
    var existing := main.get_node_or_null(NODE_NAME) as SaNoteMode
    if existing != null:
        return existing
    var mode := SaNoteMode.new()
    mode.name = NODE_NAME
    main.add_child(mode)
    var registries: Variant = main.get("registries")
    if registries != null and registries.get("commands") is SaCommandRegistry:
        register_command(registries.commands, mode)
    return mode


## The command *mode* answers to, with its chord and the sentence the Help menu
## shows on hover, in *commands*.
##
## Its own function, because the sentence moved off the menu file and onto the
## descriptor, and a detached bar has no Main to install a mode under. A test
## that wants the row explained the way a painter sees it explained calls this
## with a mode of its own.
##
## Does nothing when the command is already there, which is what makes
## `install` idempotent.
static func register_command(commands: SaCommandRegistry, mode: SaNoteMode) -> void:
    if commands == null or mode == null or commands.has(ACTION):
        return
    var command := SaCommandDescriptor.create(ACTION, COMMAND_TITLE, mode.toggle)
    command.category = &"help"
    command.label = COMMAND_LABEL
    command.sentence = (
        "Highlight the control under the pointer, and a click freezes it, photographs the window and takes your note "
        + "about it."
    )
    commands.register(command)


## Installs from anywhere in the main tree, deferred, because the menu that
## calls this is built inside Main's `_ready`, where `add_child()` is refused.
## A detached bar has no Main above it
## and installs nothing.
static func ensure_from(node: Node) -> void:
    var main := _main_above(node)
    if main != null and main.get_node_or_null(NODE_NAME) == null:
        SaNoteMode.install.call_deferred(main)


static func _main_above(node: Node) -> Node:
    var cursor := node
    while cursor != null:
        if "registries" in cursor:
            return cursor
        cursor = cursor.get_parent()
    return null


## The installed mode, or null.
static func find_in(tree: SceneTree) -> SaNoteMode:
    if tree == null or tree.current_scene == null:
        return null
    return tree.current_scene.get_node_or_null(NODE_NAME) as SaNoteMode


## Help > Take a Note. Installs on first use, so the menu needs no setup order.
static func toggle_in(tree: SceneTree) -> void:
    var mode := find_in(tree)
    if mode == null and tree != null:
        mode = install(tree.current_scene)
    if mode != null:
        mode.toggle()


func _ready() -> void:
    if notes_dir.is_empty():
        notes_dir = SaNoteFile.default_notes_dir()
    set_process(false)


# --- The mode -----------------------------------------------------------------


func toggle() -> bool:
    if active:
        stop()
    else:
        start()
    return true


func start() -> void:
    if active:
        return
    active = true
    frozen = null
    hovered = null
    menu.clear()
    region = Rect2()
    _image = null
    _described = {}
    _region_drag = false
    swallow_release = false
    _pointer_window = null
    for window: Window in _windows():
        var overlay := SaNoteOverlay.attach_to(window)
        overlay.mode = self
    _hold_pointer(true)
    _republish_cursor()
    set_process(true)
    print("SaNoteMode: on, click a control to note it, Escape leaves")


func stop() -> void:
    if not active:
        return
    active = false
    frozen = null
    hovered = null
    menu.clear()
    region = Rect2()
    _image = null
    _described = {}
    _region_drag = false
    _pointer_window = null
    menu.unhush()
    set_process(false)
    for window: Window in _windows():
        var overlay := SaNoteOverlay.find_in(window)
        if overlay != null:
            overlay.clear()
            overlay.clear_region()
            overlay.mode = null
    _hold_pointer(false)
    _republish_cursor()


## The mode node can be freed while it is on, in a test or when the scene goes,
## and a static flag nobody clears would leave every canvas without its ring for
## the rest of the process.
func _exit_tree() -> void:
    if active:
        _hold_pointer(false)


## Takes the pointer from the active tool or hands it back, in both places that
## read it: the flag the router asks, and the tool machine's own member.
func _hold_pointer(holding: bool) -> void:
    taking_note = holding
    ToolMachine.pointer_holder = POINTER_HOLDER if holding else &""
    ToolMachine.pointer_holder_shape = CURSOR_SHAPE


## Asks every tool machine in the tree to publish its cursor again, because the
## answer `taking_note` changes is only recomputed when something calls for it.
##
## The machines poll their own tool for a radius that moved, so they would catch
## the ring up within a frame either way, but not the OS cursor shape, and a
## frame of the brush ring at the moment the mode opens is exactly the flicker
## the note complains about.
func _republish_cursor() -> void:
    if not is_inside_tree():
        return
    for node in get_tree().root.find_children("*", "ToolMachine", true, false):
        var machine := node as ToolMachine
        if machine != null:
            machine.refresh_cursor()


func _process(_delta: float) -> void:
    if not active or frozen != null or _region_drag:
        return
    # The window the last motion went to can have gone since, a list closed or
    # the note box cancelled with the pen over it, and a freed window handed
    # on is a script error every frame until the next motion.
    if not is_instance_valid(_pointer_window):
        _pointer_window = null
    var control := hovered_control()
    var item := SaNoteMenu.under_pointer(get_tree().root, _pointer_window)
    if control == hovered and menu.same_as(item):
        return
    hovered = control
    menu.take(item)
    if menu.is_set():
        print("SaNoteMode: over %s" % menu.tag())
    else:
        print("SaNoteMode: over %s" % (String(control.get_path()) if control != null else "nothing"))
    _show_hover()


## `Screen, item 8 of 20`, the tag on an open menu, and "" with none open.
func menu_tag() -> String:
    return menu.tag()


func _show_hover() -> void:
    for window: Window in _windows():
        var overlay := SaNoteOverlay.attach_to(window)
        overlay.mode = self
        overlay.show_region(region)
        # An open menu carries the mark, on the item or on the whole list, and
        # the tag names the item, because the dropdown or the bar the menu
        # belongs to is not what the pointer is on.
        if menu.is_set() and window == menu.window:
            overlay.highlight(menu.rect(), menu.tag())
        elif not menu.is_set() and hovered != null and hovered.get_window() == window:
            overlay.highlight(hovered.get_global_rect(), tag_for(hovered))
        else:
            overlay.clear()


## Every window a control can be in: the root, each embedded subwindow, and a
## docker as a real OS window, so a click on it still freezes even though the
## photograph cannot include it.
func _windows() -> Array:
    var root := get_tree().root
    var found: Array = [root]
    found.append_array(_all_windows(root))
    return found


## Internal children included, because a dropdown's PopupMenu belongs to its
## OptionButton and `get_children()` never mentions it, so leaving it out leaves no
## overlay on the window that has the pointer.
func _all_windows(node: Node) -> Array:
    var found: Array = []
    for child in node.get_children(true):
        if child is Window and child.visible:
            found.append(child)
        found.append_array(_all_windows(child))
    return found


## The control the GUI reports under the pointer, in whichever window holds it.
## Embedded windows are tested by rectangle first, since an embedded docker is
## a Window inside the host viewport rather than a Control, and the focused
## one wins where two overlap.
func hovered_control() -> Control:
    var root := get_tree().root
    # The viewport's own reading, not the OS pointer: an injected motion moves
    # only the first.
    var pointer := root.get_mouse_position()
    var under: Window = null
    for sub in SaCursorPolicy.embedded_subwindows(root, true):
        if not Rect2(Vector2(sub.position), Vector2(sub.size)).has_point(pointer):
            continue
        if under == null or sub.has_focus():
            under = sub
    if under == null:
        var in_root := _noteworthy(root.gui_get_hovered_control())
        if in_root != null:
            return in_root
        # A motion forwarded to a subwindow does not move the root's own
        # reading, so the one docker that reports a hover is it.
        for sub in SaCursorPolicy.embedded_subwindows(root, true):
            if sub.gui_get_hovered_control() != null and (under == null or sub.has_focus()):
                under = sub
        if under == null:
            return null
    if under is SaChoicePopup:
        return _noteworthy(_row_or_owner(under, under.get_mouse_position()))
    if under is Popup:
        return _noteworthy(popup_owner(under))
    return _noteworthy(under.gui_get_hovered_control())


## Never the overlay's own box, and never a control the tree is discarding.
func _noteworthy(control: Control) -> Control:
    if control == null or control.is_queued_for_deletion():
        return null
    var cursor: Node = control
    while cursor != null:
        if cursor is SaNoteOverlay:
            return null
        cursor = cursor.get_parent()
    return control


## The deepest visible control of `window` under `point`, the way the GUI
## would pick it: later children are tried first, a control that ignores the
## mouse lets its children answer but never answers itself, and an open menu
## answers with the control it belongs to instead, see popup_owner. Except a
## choice list, whose rows are controls: the row under the point is the answer.
static func control_at(window: Window, point: Vector2) -> Control:
    if window is SaChoicePopup:
        return _row_or_owner(window, point)
    if window is Popup:
        return popup_owner(window)
    return control_under(window, point)


## The row of *popup* under *point*, or over a heading, a gap or the search
## field the control the list belongs to, the way any other popup answers.
static func _row_or_owner(popup: SaChoicePopup, point: Vector2) -> Control:
    var row := SaNoteMenu.row_holding(control_under(popup, point))
    return row if row != null else popup_owner(popup)


## The control an open popup stands for: the dropdown, button or bar it belongs
## to. A menu draws its own items through children Godot keeps internal, so
## there is nothing inside one to name, and the dropdown is what a note about
## an open menu is about anyway.
static func popup_owner(popup: Window) -> Control:
    var cursor: Node = popup.get_parent() if popup != null else null
    while cursor != null:
        var control := cursor as Control
        if control != null:
            return control
        cursor = cursor.get_parent()
    return null


## The deepest visible control under *point* in *node*'s window, or null. Public
## because `SaNoteMenu` asks it for the row under a point.
static func control_under(node: Node, point: Vector2) -> Control:
    if node is SaNoteOverlay or node is CursorOverlay:
        return null
    for index in range(node.get_child_count() - 1, -1, -1):
        var child := node.get_child(index)
        if child is Window:
            continue
        var control := child as Control
        if control != null:
            if not control.is_visible_in_tree() or not control.get_global_rect().has_point(point):
                continue
            var deeper := control_under(control, point)
            if deeper != null:
                return deeper
            if control.mouse_filter != Control.MOUSE_FILTER_IGNORE and not (control is SaNoteOverlay):
                return control
        elif child is CanvasItem or not (child is Viewport):
            var deeper := control_under(child, point)
            if deeper != null:
                return deeper
    return null


## The tag drawn over the highlight: the node's name and class.
static func tag_for(control: Control) -> String:
    return "%s (%s)" % [control.name, control.get_class()]


# --- Input, from the overlays -------------------------------------------------


## Every event a window sees while the mode is on. True when it was taken.
func handle_window_input(event: InputEvent, window: Window) -> bool:
    if not active:
        return false
    var key := event as InputEventKey
    if key != null and key.pressed and not key.echo:
        if key.keycode == KEY_ESCAPE:
            if frozen != null:
                cancel()
            else:
                stop()
            return true
        if frozen != null and key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
            save(box_text())
            return true
        return false
    if event is InputEventMouseMotion:
        _pointer_window = window
    if _region_drag and event is InputEventMouseMotion:
        _drag_region_to(SaNoteImage.point_in_root(window, _root(), (event as InputEventMouseMotion).position))
        return true
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if _region_drag and not button.pressed:
        _region_drag = false
        _drag_region_to(SaNoteImage.point_in_root(window, _root(), button.position))
        if not SaNoteImage.is_region(region):
            region = Rect2()
            _show_region()
        print("SaNoteMode: region %s" % ("cleared" if region.size == Vector2.ZERO else str(region.size)))
        return true
    if not button.pressed and swallow_release:
        # A Button acts on release, so the press alone does not keep it from
        # firing.
        swallow_release = false
        menu.unhush()
        return true
    if frozen != null:
        # The box takes its own clicks. Anything else is left alone, so a
        # painter can still scroll a page while the box is open.
        return false
    if button.pressed and button.shift_pressed:
        # Shift-drag frames the part of the window the note is about, which is
        # kept whole while the rest of the shot is shrunk. The frame is drawn
        # before the control is clicked, so both fit in one note.
        _region_drag = true
        _region_from = SaNoteImage.point_in_root(window, _root(), button.position)
        region = Rect2(_region_from, Vector2.ZERO)
        _show_region()
        return true
    if button.pressed:
        # The press names its own point, and the control under that point is
        # the one meant, even when the polled hover has not caught up with an
        # injected click that never moved the pointer. An open list standing
        # over the point is where it was meant, whichever window heard it,
        # which under WinTab with subwindows off was the main window.
        var over := SaNoteMenu.menu_over(window, button.position)
        var aimed: Window = over.get("menu", window)
        var at: Vector2 = over.get("at", button.position)
        if aimed is SaChoicePopup:
            menu.take(SaNoteMenu.item_at(aimed, at))
        else:
            menu.take(SaNoteMenu.under_pointer(get_tree().root, aimed))
        var target := control_at(aimed, at)
        if target == null:
            target = hovered
        if target == null:
            return false
        swallow_release = true
        menu.hush(aimed as PopupMenu)
        freeze(target)
        return true
    return false


## The root window, or null before the mode is in a tree, which is how a
## headless test drives `handle_window_input` without one.
func _root() -> Window:
    return get_tree().root if is_inside_tree() else null


## Grows the region to the pointer, in the root viewport's coordinates.
func _drag_region_to(point: Vector2) -> void:
    region = SaNoteImage.region_between(_region_from, point)
    _show_region()


## Draws the region on every window, since it is framed over whatever it covers.
func _show_region() -> void:
    for window: Window in _windows():
        var overlay := SaNoteOverlay.attach_to(window)
        overlay.mode = self
        overlay.show_region(region)


func box_pressed(what: String) -> void:  ## Save, Export or Cancel in the box.
    if what == "save":
        save(box_text())
    elif what == "export":
        export_notes()
    else:
        cancel()


# --- Freezing and saving ------------------------------------------------------


## The picture of *root* a note or a shot takes: the root's texture, with every
## window of its own drawn in at its place, since a list or a docker let out of
## the window is not in the root's texture. Null when there is no root.
static func picture_of(root: Window) -> Image:
    if root == null:
        return null
    return SaNoteImage.with_windows(root.get_texture().get_image(), root)


## Outlines `control`, photographs the root window with the outline drawn, and
## opens the box. Async, because the photograph is the next frame's.
func freeze(control: Control, initial_text: String = "") -> void:
    if control == null or not active:
        return
    frozen = control
    hovered = control
    _stamp = SaNoteFile.now()
    if not menu.is_set():
        # A `note` step freezes on a row by name, with no pointer over it.
        var row := SaNoteMenu.row_holding(control)
        if row != null:
            menu.take(SaNoteMenu.item_of(row.get_window() as SaChoicePopup, row))
    var window := control.get_window()
    var near := control.get_global_rect()
    if window is Popup:
        # The box outlives the menu, which closes when the box takes the focus,
        # so it opens in the window the menu belongs to, beside the row.
        near.position += Vector2(window.position)
        var holder := popup_owner(window)
        window = holder.get_window() if holder != null else get_tree().root
    for other: Window in _windows():
        var mark := SaNoteOverlay.attach_to(other)
        mark.mode = self
        if menu.is_set() and other == menu.window:
            mark.freeze(menu.rect(), menu.tag())
        elif not menu.is_set() and other == control.get_window():
            mark.freeze(control.get_global_rect(), tag_for(control))
        else:
            mark.clear()
    # The frame is guidance, not part of the picture: it would otherwise run
    # along the edge of its own crop.
    for other: Window in _windows():
        SaNoteOverlay.attach_to(other).clear_region()
    await RenderingServer.frame_post_draw
    develop(control, window, near, initial_text)


## The half of the freeze after the frame the picture waits for: the photograph,
## the entry and the box, over the control *control* in *window* at *near*,
## the box opening on *initial_text*.
##
## The arguments are untyped because a control can be freed during that frame,
## a menu row rebuilt or a docker closed, and a freed object handed to a typed
## argument is an engine error of its own. A later freeze has taken over
## when `frozen` is no longer *control*, and a control or window gone since the
## click drops the note quietly, with the menu unhushed and the marks cleared.
func develop(control: Variant, window: Variant, near: Rect2, initial_text: String = "") -> void:
    if not is_same(frozen, control):
        menu.unhush()
        return
    if not is_instance_valid(control) or not is_instance_valid(window):
        _drop_frozen()
        return
    var viewport := get_tree().root
    _image = picture_of(viewport)
    _logical = viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
    _described = SaNoteDescribe.describe(control, viewport, menu.tag())
    # The picture is taken, so the menu can hear again, and it is closed here
    # rather than left to lose the focus to the box, which a menu of its own
    # need not do (`SaNoteMenu.close`).
    menu.unhush()
    menu.close()
    var subject: String = menu.text() if menu.is_set() else String(control.name)
    var overlay := SaNoteOverlay.attach_to(window)
    overlay.open_box(near, tr("Note on %s") % subject, initial_text)
    # The box is a window of its own, so its keys reach here the way every
    # other window's do.
    var box := overlay.box
    if box != null:
        SaNoteOverlay.attach_to(box).mode = self


## Lets go of a note whose control went before its picture was taken, and
## leaves the mode following the pointer again with no mark left standing.
func _drop_frozen() -> void:
    frozen = null
    hovered = null
    _stamp = {}
    menu.unhush()
    menu.clear()
    for other: Window in _windows():
        var mark := SaNoteOverlay.find_in(other)
        if mark != null:
            mark.clear()
            mark.clear_region()


func cancel() -> void:
    frozen = null
    _image = null
    region = Rect2()
    stop()


## Writes the image and appends the entry. Returns the markdown file's path,
## or an empty string when nothing was frozen.
func save(text: String) -> String:
    if frozen == null or _described.is_empty():
        return ""
    var info := _described.duplicate()
    info["text"] = text.strip_edges()
    info["stamp"] = _stamp.duplicate()
    var day := String(_stamp.get("date", ""))
    var stem := "%s-%s-%s" % [day, String(_stamp.get("compact", "")), SaNoteFile.file_safe(String(info["name"]))]
    var image_name := "%s.%s" % [stem, SaNoteImage.EXTENSION]
    # One folder per session, so a note and the images it links sit together and
    # the link inside the note stays the bare file name.
    var run_dir := SaNoteFile.run_dir(notes_dir, _stamp)
    var complaint := SaNoteFile.make_run_dir(run_dir)
    if not complaint.is_empty():
        push_error("SaNoteMode: %s" % complaint)
        return ""
    var image_path := run_dir.path_join(image_name)
    var picture := SaNoteImage.for_note(_image, region, _logical)
    if picture != null and SaNoteImage.save(picture, image_path) == OK:
        info["image"] = image_name
    else:
        info["image"] = ""
    var path := run_dir.path_join(SaNoteFile.run_file_name(_stamp))
    var entry := format_entry(info)
    if not SaNoteFile.append(path, entry, SaNoteFile.run_file_header(_stamp)):
        push_error("SaNoteMode: cannot write %s" % path)
        return ""
    print("SaNoteMode: wrote %s" % path)
    note_written.emit(path)
    frozen = null
    _image = null
    stop()
    return path


## Zips the current session's notes folder, and the engine's own log beside it,
## and says where it went, or says there is nothing to export. One press, no
## dialog, nothing sent anywhere, and the folder stays where it was. A session
## with no note still has a log, which is the shape a crash's restart leaves, so
## the button that goes home does not refuse in exactly the case a crash makes.
func export_notes() -> String:
    var run_dir := SaNoteFile.run_dir(notes_dir, _stamp)
    var log_dir := SaNoteFile.engine_log_dir()
    var had_notes := DirAccess.dir_exists_absolute(run_dir) and not DirAccess.get_files_at(run_dir).is_empty()
    var had_log := not SaNoteFile.log_files_for(log_dir).is_empty()
    var path := SaNoteFile.export_run_dir(run_dir, log_dir)
    if path.is_empty():
        SaMessage.notice(tr("No notes to export"))
        return ""
    if had_notes and had_log:
        SaMessage.notice(tr("Notes and Sara's log exported to %s") % path)
    elif had_notes:
        SaMessage.notice(tr("Notes exported to %s") % path)
    else:
        SaMessage.notice(tr("Sara's log exported to %s") % path)
    return path


func box_text() -> String:
    for window: Window in _windows():
        var overlay := SaNoteOverlay.find_in(window)
        if overlay != null and overlay.box_open():
            return overlay.box_text()
    return ""


func _set_box_text(text: String) -> void:
    for window: Window in _windows():
        var overlay := SaNoteOverlay.find_in(window)
        if overlay != null and overlay.box_open():
            overlay.set_box_text(text)


# --- Forwards to sa_note_describe.gd, for the names the tests call here -------


static func format_entry(info: Dictionary) -> String:
    return SaNoteDescribe.format_entry(info)


static func guess_setting(node_name: String) -> String:
    return SaNoteDescribe.guess_setting(node_name)


static func settings_for(control: Control) -> Array:
    return SaNoteDescribe.settings_for(control)


static func value_of(control: Control) -> String:
    return SaNoteDescribe.value_of(control)


static func label_of(control: Control) -> String:
    return SaNoteDescribe.label_of(control)
