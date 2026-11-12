## Base for Sara's own dialog windows: Preferences, New Document, and whatever
## follows them.
##
## A docker gets its chrome from `DockerWindow`, which also enrols it in the
## docker layout store, the show/hide menu and the Preferences category list. A
## dialog is none of those things, so it cannot be a DockerWindow, but it needs
## the same chrome, and the Preferences window is what happens when a window is
## built without it: no pointer over it, no ALT-drag, no resize, and no way to
## close it at all.
##
## Everything a dialog needs is here, so the next one cannot be missing a piece.
## Subclasses call `_init_dialog()` and put their UI in `content`.
@tool
class_name SaDialogWindow
extends Window

## Sent before every maximise or restore, the chord's and the button's alike,
## so a window with a state of its own, Preferences rolled up to its title
## strip, can leave it before the rectangle is kept.
signal maximise_toggling

const DockerResizerScript = preload("res://ui/dockers/docker_resizer.gd")
const DockerDragHandleScript = preload("res://ui/dockers/docker_drag_handle.gd")

## Logical room kept clear above and below a dialog that is fitted to its host,
## so a dialog as tall as the screen still shows its own title strip and its
## bottom edge.
const HOST_MARGIN: int = 24

## The least a scrolling body is squeezed to, in logical units, by a short host or
## by a painter's drag, so either leaves a few lines to read and not a sliver.
const SCROLLING_BODY_FLOOR: int = 96

## The group every dialog on screen belongs to, from the frame it is shown to the
## frame it is hidden. A dialog shown over another asks it, and the nodes of a
## group the engine keeps are never a freed one, which a list of ours would be
## until something pruned it.
const OPEN_GROUP := &"sa_open_dialogs"

## The most steps a dialog is cascaded down and right, so a host crowded with
## dialogs ends the walk and does not loop.
const CASCADE_ATTEMPTS: int = 8

## `func() -> int`, the first logical row below the main window's top bar, which
## no dialog is kept above. Unset reads as the host's own top edge.
##
## A host of the whole main window, bar included, would open New Document over
## the menus at an interface scale of 2. `MainDialogs` hands this `MainDockers.below_bar`, the row the default layout
## is fitted under through `DockerLayoutStore.top_inset`, so a dialog and a docker
## start on the same row. Static, because a dialog is built by whoever opens it,
## the filter menus, the layers docker and `SaMessage` as well as `MainDialogs`,
## and every one of them opens over the same bar. A Callable rather than a
## number, because the bar grows a row when a painter turns the second one on.
static var top_inset: Callable = Callable()

## Geometry in logical units. `Window.size` is physical for a real OS window and
## logical for an embedded subwindow, and which of the two this is cannot be
## known in `_init`.
var logical_size: Vector2i = Vector2i(480, 320)
var logical_min_size: Vector2i = Vector2i(320, 200)

## True while this class writes its own geometry, so the tracker below does not
## read a size it derived back as one a painter gave it, the same flag
## `DockerWindow` holds.
var _deriving_geometry: bool = false

## The size `fit_opening_size` last held the window to, which the tracker below
## does not read back either. The engine sends `size_changed` again when a window
## is hidden and when `popup_centered` gives it the size it already has, and
## both times the size is the room of a smaller host rather than the one the
## dialog wants.
var _fitted_size: Vector2i = Vector2i(-1, -1)

var drag_handle: PanelContainer
var close_button: Button
var resizer: Control

## The title strip's maximise, `SaDockerMaximise`'s own button, so a press does
## what Ctrl+Space does over this dialog and nothing else. Built for every
## dialog and hidden: the dialogs a painter works in rather than answers, the
## Brush Editor and Preferences, show it, and a small question like Radius
## keeps the close alone and still takes the chord.
var maximise_button: Button

## Where a subclass puts its UI. Anchored below the drag bar.
var content: Control

## The button Enter presses. Set by a subclass to its confirming button, and
## left null on a dialog that confirms nothing.
##
## These are plain `Window`s rather than `AcceptDialog`s, so there is no default
## button underneath and Enter did nothing anywhere but on a focused button.
var default_button: Button = null

## Whether a number typed into a field and taken with Enter goes on to press
## `default_button`, the way it does in a Qt or a GTK dialog. True for a dialog
## that asks a question, false for the Brush Editor, whose default would write
## the preset over, and for the two filter windows and Colour Range, where Enter
## takes the number and the preview runs again on it.
var number_field_answers: bool = true

## The one region of this dialog that scrolls when the host is shorter than the
## dialog would like to be, or null for a dialog that is never made smaller than
## its content.
##
## A subclass sets it in `_init` to a `ScrollContainer` holding the one child that
## grows with the dialog's text. `fit_opening_size` opens the dialog at the height
## its child wants when the host has the room, and less when it has not, and asks
## no more of it than `SCROLLING_BODY_FLOOR`, which is the only way a dialog can be
## shorter than its content without a button leaving it.
var scrolling_body: ScrollContainer = null

## Where focus lands when the dialog opens, or null for the first control the
## Tab walk would reach.
##
## Focus has to start somewhere: `ui_focus_next` moves focus and does not create
## it, so a dialog with nothing focused could not be entered from the keyboard
## at all, whatever every control's `focus_mode` said.
var first_focus: Control = null

## The window this dialog was last held above, its transient parent, or null
## while it is hidden. Without the hold a dialog on
## Windows sinks under the main window whenever that is clicked and has a
## taskbar entry of its own, the fault the same hold cures for the dockers.
var held_by: Window = null

var _control_node: Control
var _drag_handle_input: DockerDragHandle = null
## The trail's ticket while the dialog shows, so a stall during it names it.
var _trail_ticket: int = SaTrail.NOTED
## The instance ids of the dialogs that were on screen in this one's host when it
## was shown, the only ones it is cascaded off. Ids and not the windows, for the
## reason `OPEN_GROUP` gives. A dialog the painter opened later is above this one,
## so this one's own fit growing over that one's strip is not a reason to move.
var _shown_over: Array[int] = []


## Builds the window shell. Call from a subclass `_init()` before adding UI.
func _init_dialog(dialog_name: String, dialog_title: String, default_size: Vector2i, min_dialog_size: Vector2i) -> void:
    name = dialog_name
    title = dialog_title
    logical_size = default_size
    logical_min_size = min_dialog_size
    size = default_size
    min_size = min_dialog_size
    transient = true
    # Sara draws its own chrome. Godot's title bar sits outside the window's own
    # viewport, and a Control can only draw inside one, so a CursorOverlay cannot
    # cover it, which is why the pointer vanished over exactly that strip.
    borderless = true

    close_requested.connect(hide)

    _control_node = Control.new()
    _control_node.name = "Control"
    _control_node.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_control_node)
    DockerUtils.create_docker_background(_control_node)

    _build_drag_bar(dialog_title)

    content = Control.new()
    content.name = "Content"
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    _control_node.add_child(content)

    # The bar is a PanelContainer, so it grows past BASE_DRAG_H whenever the
    # title font needs more room, which it does at Sara's font size. Offsetting
    # the content by the constant left it under the grown bar, with the page
    # title drawn over the title strip. Track the bar's real height instead.
    _sync_content_offset()
    drag_handle.resized.connect(_sync_content_offset)

    visibility_changed.connect(_on_visibility_changed)
    about_to_popup.connect(_cascade_later)
    # A dialog that joins the tree already visible is held here, and every
    # later show is held in `_on_visibility_changed`.
    tree_entered.connect(_hold_above_transient_parent)
    tree_exiting.connect(_leave_the_trail)


## The row a dialog's buttons go in, at the foot of *column* and aligned to its
## end, answered for the caller to fill: the way out first and the default
## last. Call it once the rest of *column* is built.
##
## Each dialog built its own row, and the rows disagreed: Export and New
## Document pinned theirs to the bottom edge, Canvas Size and Image Size left
## theirs under the content, so a window dragged taller carried its buttons up
## into its middle. An expanding spacer pins the row unless a
## child of *column* already expands, a list or a scrolling body, which pins it
## on its own. A spacer beside that child would take half the room the child was
## given.
func pinned_buttons(column: VBoxContainer) -> HBoxContainer:
    var pinned := false
    for child: Node in column.get_children():
        var control := child as Control
        if control != null and control.size_flags_vertical & Control.SIZE_EXPAND:
            pinned = true
    if not pinned:
        var spacer := Control.new()
        spacer.name = "ButtonsSpacer"
        spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
        column.add_child(spacer)
    var row := SaMake.row(column, "Buttons", SaTheme.GAP)
    row.alignment = BoxContainer.ALIGNMENT_END
    return row


## Every show builds a new OS window, so the owner is asked for after each one,
## the way `DockerWindow` asks for its own.
func _hold_above_transient_parent() -> void:
    held_by = DockerWindow.hold_above_transient_parent(self)


## Content starts where the drag bar actually ends, not where it was told to be.
func _sync_content_offset() -> void:
    if content == null or drag_handle == null:
        return
    content.offset_top = title_strip_height()


## How tall the title strip is in this window's own units, which is what the
## content starts below and what a cascaded dialog is moved by.
func title_strip_height() -> float:
    if drag_handle == null:
        return 0.0
    return maxf(drag_handle.size.y, drag_handle.get_combined_minimum_size().y)


## The title strip: a Sara drag bar with a close button on the right.
##
## Built here rather than by `DockerUtils.make_drag_bar`, which puts a single
## Label straight into the PanelContainer and so has nowhere to put a button. A
## docker is closed from the Dockers menu. A dialog has to carry its own way out.
func _build_drag_bar(bar_title: String) -> void:
    drag_handle = PanelContainer.new()
    drag_handle.name = "DragHandle"
    drag_handle.set_anchors_preset(Control.PRESET_TOP_WIDE)
    drag_handle.custom_minimum_size = Vector2(0.0, float(SaUI.px(DockerUtils.BASE_DRAG_H)))
    drag_handle.add_theme_stylebox_override("panel", SaTheme.make_drag_bar_style(false))
    _control_node.add_child(drag_handle)

    var row := SaMake.row(drag_handle, "Row")
    var label := SaGrip.before(SaMake.label(row, "TitleLabel", bar_title))
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # A title wider than the strip is cut and says so, where it ran off the
    # window's edge and took the close button with it: this label is the heading
    # of every dialog, and a filter's window shows no other.
    label.text_overrun_behavior = SaTheme.TEXT_CUT
    label.add_theme_color_override("font_color", SaTheme.palette.text_primary)
    maximise_button = SaDockerMaximise.build_button(row, self)
    maximise_button.visible = false
    close_button = SaMake.button(row, "CloseButton", "", tr("Close"))
    close_button.flat = true
    close_button.focus_mode = Control.FOCUS_NONE
    close_button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    SaUI.set_button_icon(close_button, "window_close", "X")
    # The window's own request to close, which Escape asks for as well, so a
    # subclass that answers it is answering both.
    close_button.pressed.connect(func() -> void: close_requested.emit())


## Fills Sara's window with this dialog, or puts it back, for the chord and the
## button alike, since `SaDockerMaximise.toggle_window` asks a window that has
## this method to do it itself.
##
## `_deriving_geometry` is held over the resize for the reason `DockerWindow`
## holds it: the filled size is not one a painter gave the dialog, and read
## back by the tracker it became the size the dialog opened at next time.
func toggle_maximised() -> String:
    maximise_toggling.emit()
    _deriving_geometry = true
    var said := SaDockerMaximise.toggle(self)
    _deriving_geometry = false
    # By the field rather than by name, because Preferences shows this button
    # under the name its scenarios click.
    SaDockerMaximise.write_tooltip(maximise_button, self)
    return said


## Retitles the window and its title strip for *text*, which a dialog that
## opens for more than one purpose asks on every open. The strip keeps the
## grip before the words, the way [method _build_drag_bar] writes it.
func retitle(text: String) -> void:
    title = text
    if drag_handle == null:
        return
    var title_label := drag_handle.find_child("TitleLabel", true, false) as Label
    if title_label != null:
        title_label.text = text


## `is_embedded()` is only meaningful once the window is in the tree, and it
## decides both the scale factor and the units the geometry is measured in.
func _ready() -> void:
    apply_window_scale()
    # After the scale is applied, so the dialog's own opening size is the first
    # thing the tracker sees rather than the raw constructor number, the order
    # `DockerWindow` connects in.
    if not size_changed.is_connected(_track_logical_size):
        size_changed.connect(_track_logical_size)

    resizer = DockerResizerScript.new(self)
    resizer.name = "Resizer"
    _control_node.add_child(resizer)

    # Parented to the Control rather than to the window: add_child() on a node
    # that is itself mid-_ready is rejected, and a rejected add leaves the node
    # orphaned rather than failing loudly. A dialog is not part of the layout,
    # so the handle is told so and its drags never fork the preset.
    _drag_handle_input = DockerDragHandleScript.new(false)
    _drag_handle_input.name = "DragHandleInput"
    _control_node.add_child(_drag_handle_input)
    _drag_handle_input.bind(self, drag_handle)

    # A Control can only draw inside its own viewport, so every Window that can
    # sit under the pointer needs its own overlay or the pointer is simply gone
    # over it: MOUSE_MODE_HIDDEN is process-global. It is the dialog's one feed of
    # `note_pointer_device` as well, which the suite of the lead hint after a pen holds.
    CursorOverlay.attach_to(self)

    if not EventBus.ui_scale_changed.is_connected(_on_ui_scale_changed):
        EventBus.ui_scale_changed.connect(_on_ui_scale_changed)
    # A `Window` is a `Viewport`, so the theme on the root does not cross into
    # one, and `DockerWindow` adopts the shared theme for itself. A dialog that
    # listened only for the UI scale would leave a painter dragging Font size
    # over Preferences watching one row move, the hint whose own text changed,
    # and nothing else.
    if not EventBus.ui_font_scale_changed.is_connected(_on_ui_font_scale_changed):
        EventBus.ui_font_scale_changed.connect(_on_ui_font_scale_changed)
    if not gui_focus_changed.is_connected(_on_gui_focus_changed):
        gui_focus_changed.connect(_on_gui_focus_changed)
    adopt_shared_theme()
    # Not called here but on the frame after this one, for the reason
    # `_fit_next_frame` gives.
    _fit_next_frame()


## The size this dialog needs to show what its subclass built, in logical units:
## the content's own demand, plus the drag bar above it.
##
## `content` is a plain `Control`, and a plain `Control` computes no minimum
## from its children, so the walk is over its direct children rather than one
## `get_combined_minimum_size` on it. Every dialog puts a container in there,
## which is why the walk is one node deep, and a hidden child is skipped because
## a row nobody can see takes no room.
func content_minimum_size() -> Vector2i:
    var needed := Vector2.ZERO
    for child in content.get_children():
        var control := child as Control
        if control == null or not control.visible:
            continue
        needed = needed.max(control.get_combined_minimum_size())
    var bar := maxf(drag_handle.size.y, drag_handle.get_combined_minimum_size().y)
    return Vector2i(int(ceil(needed.x)), int(ceil(needed.y + bar)))


## Opens at a size the content fits in, which is the larger of the two numbers a
## dialog has: the floor its constructor declared and what it went and built.
##
## The floor `_init_dialog` is handed is a guess made from a drawing, so a
## dialog that gains a row would open at a height its own column does not fit,
## with its buttons out of sight until resized. Nothing clips, so there is no
## sign of it on screen either.
##
## It grows the window to its content and shrinks it only to `host_room`, so a
## dialog dragged larger keeps what the painter gave it wherever the host has the
## room. A dialog taller or wider than its host is given the host's size: the
## window and the floor come down to the room, the host less `HOST_MARGIN` a
## side, because a floor over the host is a window Godot will not make smaller
## than the screen. Its `scrolling_body` is what takes the difference. A dialog
## with none, whose content cannot be made that small, keeps the floor its
## content needs and spends the margin before it loses a button, and past the
## whole host it is cut at the bottom edge rather than hanging past it with its
## title strip over the menus. So the floor a dialog declared yields where its
## content's does not. The size the dialog wants is kept in `logical_size` all the while, and a
## larger host gives it back.
##
## A change of size on a window that is already on screen takes half of it back
## off its position, so the centre `popup_centered` gave it stays where it was.
## The two are a frame apart, and by the time this runs `popup_centered` has
## already happened and the window is where the painter sees it.
##
## Both the frame it runs on and the numbers it is handed are the running app's,
## so a larger font scale grows the window to buttons it would otherwise cut
## off.
##
## Both writes go through `SaUI.window_size_for`, the one place that knows what a
## window measures its geometry in, and neither writes `content_scale_factor`
## (hard rule 7, one writer for UI scale).
##
## **A hidden window is not fitted at all**. A `Container` in a hidden window
## sorts none of its children, so nothing inside has a width yet, and a wrapping
## `Label` answers the height of its whole text one character wide, which would
## open a window far taller than the screen with its buttons off it. The fit
## grows and never shrinks, so the real number a frame later could not take it
## back. Every dialog installed at boot is hidden on that frame, which is why
## the guard is here rather than in any one window: `_on_visibility_changed` asks again on the frame the dialog is
## shown, and that is the first frame its numbers are real on.
##
## A window the maximise chord has filled its host with is left alone, because
## the chord's own rule says where it is and a fit would take it off the menus
## the painter asked it to cover.
func fit_opening_size() -> void:
    if not is_inside_tree() or not visible or content == null or drag_handle == null:
        return
    if SaDockerMaximise.is_maximised(self):
        return
    var unshown := _fit_scrolling_body()
    var needed := content_minimum_size()
    var whole := host_room(0)
    var has_room := whole.x > 0 and whole.y > 0
    needed.x += _scroll_bar_to_come(unshown, needed.y)
    logical_min_size = logical_min_size.max(needed)
    logical_size = logical_size.max(logical_min_size).max(Vector2i(needed.x, needed.y + unshown))
    var most := Vector2i.ZERO
    if has_room:
        # A declared floor is a guess and yields to the room. What the content
        # needs may take the margin as well, up to the whole host.
        var room := host_room()
        logical_min_size = logical_min_size.min(room.max(needed.min(whole)))
        most = room.max(logical_min_size)
    # Read before the floor is written, because a window answers a new `min_size`
    # by growing to it on the spot: read after, the growth would already be in
    # the number, no growth would be seen, and the centre `popup_centered` gave
    # the window would stay where the smaller one had been, with the bottom of
    # the grown window and its buttons under the screen's edge.
    var before := size
    # Both writes are this class's own, the floor's growth as well, and the size
    # starts from the one the dialog wants as well as the one it has, so a larger
    # host gives back what a smaller one took. Tracked, the room of a window at
    # scale 2 became the dialog's size, and New Document opened 592 wide at
    # scale 1 on the screen that had just held 640 of it.
    _deriving_geometry = true
    min_size = SaUI.window_size_for(self, logical_min_size)
    var fitted := size.max(SaUI.window_size_for(self, logical_size)).max(min_size)
    if has_room:
        fitted = fitted.min(SaUI.window_size_for(self, most))
    size = fitted
    _deriving_geometry = false
    _fitted_size = size
    if visible and size != before:
        var grown := size - before
        # Half of the change, in whole pixels, which is the whole of what an odd
        # number of them can give.
        @warning_ignore("integer_division")
        position -= Vector2i(grown.x / 2, grown.y / 2)
    _keep_inside_host()
    if size != before:
        cascade_off_the_open_dialogs()


## The width the scrolling body's bar is about to take, in the units of
## `content_minimum_size`, or
## nought when the bar shows already or the body will not scroll.
##
## A `ScrollContainer` counts its vertical bar in its minimum width only while
## the bar shows, and it shows only once the window is cut shorter than what the
## body holds, after this fit has measured the width. So a dialog the host makes
## scroll opened a bar's width narrower than its rows and the bar, and its
## buttons ended past its right edge: Import Fit at scale 2 on a 1280 by 800
## screen, once the bar was made wide enough for a pen.
func _scroll_bar_to_come(unshown: int, needed_height: int) -> int:
    if scrolling_body == null or unshown <= 0:
        return 0
    var bar := scrolling_body.get_v_scroll_bar()
    if bar == null or bar.visible:
        return 0
    var room := host_room()
    if room.y <= 0 or room.y >= needed_height + unshown:
        return 0
    # In the content's own units, as `content_minimum_size` measures it.
    return ceili(bar.get_combined_minimum_size().x)


## Asks no more of the scrolling body than `SCROLLING_BODY_FLOOR`, and answers the
## logical height its child wants beyond that, which `fit_opening_size` puts into
## the size the dialog opens at and never into its floor.
##
## A body that asked for the whole of its child's height wherever the host has
## the room would make that the floor, and the engine would refuse any drag
## under it, so a widened window would keep its height with a blank band in it,
## because the floor only grows. The window opens at the same height either
## way, it is the floor that comes down. The child's own
## minimum is the wanted height: it answers for the width it has been laid out
## at, which is why this runs on the frame the dialog is shown and not in
## `_ready` (see `_fit_next_frame`).
func _fit_scrolling_body() -> int:
    if scrolling_body == null or scrolling_body.get_child_count() == 0:
        return 0
    var child := scrolling_body.get_child(0) as Control
    if child == null:
        return 0
    # A wrapping label keeps the lines it last wrapped, and asks again only when
    # told to, so the number it gives is for the width it had when it last did.
    child.update_minimum_size()
    var wanted := ceili(child.get_combined_minimum_size().y)
    var asked := mini(wanted, SCROLLING_BODY_FLOOR)
    scrolling_body.custom_minimum_size.y = float(asked)
    return wanted - asked


## The rectangle this dialog is kept in, in whatever space its `position` is
## measured in: the one `SaDockerMaximise` fills, which is the host viewport when
## embedded and the screen's usable rectangle for a real OS window, less the main
## window's top bar.
func host_rect() -> Rect2i:
    return below_the_bar(SaDockerMaximise.host_rect(self))


## *host* with everything above `top_inset` taken off its top.
##
## An embedded dialog measures the bar from its host's own top edge, since its
## host is the main window. A real OS window measures it from where the main
## window is on the screen, in the main window's scale, because the bar is in
## that window and not in this one. A bar outside *host* takes nothing off it.
## Public because `SaSettingsFrame` asks the same of the host it measures itself,
## so Preferences keeps the same top as every other dialog.
func below_the_bar(host: Rect2i) -> Rect2i:
    return below_the_bar_of(self, host)


## The same rule for any *window*, a docker as well as a dialog, which is how
## the resize grip and the ALT-right drag keep a docker's top under the bar
## without a second copy of it.
static func below_the_bar_of(window: Window, host: Rect2i) -> Rect2i:
    var inset := int(top_inset.call()) if top_inset.is_valid() else 0
    if inset <= 0 or host.size.y <= 0:
        return host
    var top := host.position.y + inset
    if not window.is_embedded():
        var main := window.get_tree().root if window.is_inside_tree() else null
        if main == null:
            return host
        top = main.position.y + ceili(inset * main.content_scale_factor)
    if top <= host.position.y or top >= host.end.y:
        return host
    return Rect2i(host.position.x, top, host.size.x, host.end.y - top)


## How much of `host_rect` this dialog is fitted to, in logical units: the host
## less *margin* on every side, `HOST_MARGIN` unless asked for another, or nought
## when there is no host to ask yet.
func host_room(margin: int = HOST_MARGIN) -> Vector2i:
    var host := host_rect()
    if host.size.x <= 0 or host.size.y <= 0:
        return Vector2i.ZERO
    var factor := maxf(SaUI.window_scale(self), 0.01)
    return Vector2i(int(host.size.x / factor) - 2 * margin, int(host.size.y / factor) - 2 * margin)


## Moves the window until it lies inside its host, and never resizes it.
##
## A window larger than the host keeps its top-left corner on the host's, because
## the title strip is what a painter drags it back by. The host is `host_rect`,
## which starts below the main window's top bar, and `HOST_MARGIN` is kept on
## both sides of an axis the window leaves room for it on. Without it a dialog
## the room has just been measured for would sit flush under the bar with both
## margins below it.
func _keep_inside_host() -> void:
    position = _clamped_to_host(position)


## Where *at* lies once it is moved inside the host by the rule above, and *at*
## itself when there is no host to ask yet.
func _clamped_to_host(at: Vector2i) -> Vector2i:
    var host := host_rect()
    if host.size.x <= 0 or host.size.y <= 0:
        return at
    var first := host.position
    var last := host.end - size
    var margin := SaUI.window_size_for(self, Vector2i(HOST_MARGIN, HOST_MARGIN))
    if last.x - first.x >= 2 * margin.x:
        first.x += margin.x
        last.x -= margin.x
    if last.y - first.y >= 2 * margin.y:
        first.y += margin.y
        last.y -= margin.y
    return Vector2i(clampi(at.x, first.x, maxi(last.x, first.x)), clampi(at.y, first.y, maxi(last.y, first.y)))


## Asks `fit_opening_size` on the next frame rather than in `_ready`, because the
## answer is not available yet.
##
## **A wrapping `Label` answers its minimum with the height of its whole text
## until the frame that draws it**, so a dialog measured in `_ready` looks like it
## needs its hints to run off the bottom: the export dialog's two note lines
## claimed 1263 pixels against the 380 the window opens at, and its fitted height
## came out 3089. One frame later the same dialog answers 345 high, which is the
## number the painter's own layout gives it.
##
## A `SceneTreeTimer` rather than an `await get_tree().process_frame`, because a
## timer's connection dies with this window: a suite that builds a dialog and
## frees it in the same frame would otherwise resume on a freed instance and take
## the run down with it.
func _fit_next_frame() -> void:
    var tree := get_tree()
    if tree == null:
        return
    var timer := tree.create_timer(0.0, true, false, true)
    timer.timeout.connect(fit_opening_size)


## Re-derive geometry from the logical size for however this window is hosted.
func apply_window_scale() -> void:
    _deriving_geometry = true
    SaUI.apply_to_window(self)
    size = SaUI.window_size_for(self, logical_size)
    min_size = SaUI.window_size_for(self, logical_min_size)
    _deriving_geometry = false


## Remember, in logical units, whatever size something other than this class just
## gave the window.
##
## A dragged corner and a capture's resize write `size` and not `logical_size`,
## so without this the next interface scale change would re-derive the size
## from the constructor's number and snap every dialog a painter had dragged
## back to its default. `DockerWindow` closes the same gap for a docker, and
## this is one class answering for every dialog.
##
## **The divisor is the scale last applied to this window**, `APPLIED_SCALE_META`,
## for the reason `DockerWindow._track_logical_size` gives: what `SaUI.window_scale`
## answers can change a frame before the geometry is re-derived.
func _track_logical_size() -> void:
    if _deriving_geometry or size == _fitted_size:
        return
    var applied: float = get_meta(SaUI.APPLIED_SCALE_META, 0.0)
    if applied <= 0.0:
        return
    logical_size = Vector2i(roundi(size.x / applied), roundi(size.y / applied))


## A new scale is a new host as well: the main window measures half as many
## logical units across at 2 as at 1, so an open dialog is fitted to it again.
## On the next frame, because the main window takes the new scale in a handler of
## the same signal and which of the two runs first is not this class's to say.
func _on_ui_scale_changed(_scale: float) -> void:
    apply_window_scale()
    adopt_shared_theme()
    _fit_next_frame()


## Text changed size and nothing else did, so the geometry is left exactly where
## the painter put it and only the theme pass runs. `apply_window_scale` is
## deliberately not called: a font change moves no geometry, so there is nothing
## to re-derive.
##
## **`SaUI.apply_ui_theme(self)` is deliberately not called here**, though it is
## what `DockerWindow` runs beside the same line, and both halves of that were
## measured rather than reasoned about. It reaches a further 12 per cent of the
## Preferences window, the category list down the left, whose buttons carry a
## font override of their own. It reaches it by overwriting every override in
## the window, and the ones it flattens are the hints: `SaSettingsRows` draws a
## row's sentence smaller than its label, and after the pass the two are the same
## size, so a page that had a hierarchy has none. It also walks the window over
## a font change, and a position put back by hand is moved again on a later
## frame. Reading the theme
## alone is exact: the same window at the same scale before and after a round
## trip differs by nought texels. What the theme does not reach is a control that
## asked for a size of its own, a heading or a hint, and `SaUI.refit_text` sizes
## those and only those again.
func _on_ui_font_scale_changed(_font_scale: float) -> void:
    adopt_shared_theme()
    SaUI.refit_text(self)


## A `Window` is a `Viewport`, so a theme set on the root does not reach into it.
## Public because a dialog that builds its controls after `_ready`, which the
## Preferences frame does on every page switch, has to say so.
func adopt_shared_theme() -> void:
    var shared := SaUI.shared_theme
    if shared != null and theme != shared:
        theme = shared


## Escape closes the dialog as its × does, once no text field holds the keyboard.
##
## A painter's hand closes a window with Escape. Nothing here reads the key.
## `ShortcutRouter.escape_in_a_dialog` does, from the window's `window_input`,
## which runs before anything inside the window: a text field lets go first, and
## the next Escape emits `close_requested`, the signal the × emits, so every
## subclass closes one way whichever of the two the painter used.
##
## The router is the one reader rather than each dialog's own `_input`, because
## the router has let a field go by the time `_input` looks, so an Escape typed
## into Preferences' search box would close Preferences.


## Enter presses the button the outline is on, and the default button only when
## the outline is on no button.
##
## Here rather than in `_input`, because Enter only belongs to the dialog when
## nothing else wanted it: a `LineEdit` eats Return to submit what was typed, and
## a number field's submit is answered by `_on_number_submitted` below.
##
## **A focused `Button` does not take the key.** Godot 4.7's `BaseButton` reads
## Enter as `ui_accept`, counts the press as the start of a click and presses
## itself on the release, and it accepts neither edge. So the press comes on
## down to here, and pressing the default on it would close the dialog before
## the release reached the button the painter chose: with the outline on Colour
## Space's Cancel, one Enter would assign sRGB to the whole painting. So the
## button with the outline keeps the press, and the release presses it.
##
## **The outline, not the focus.** A button a pointer clicked holds the focus
## with its outline hidden, which is `has_focus(true)` answering false. Godot
## would still press that button on the release, and the painter, who sees no
## outline anywhere, means the dialog's answer, so the default answers and the
## hidden focus is let go first, or the release would press the clicked button
## as well on a dialog the default leaves open. A held Enter is one press, the
## way the button reads it too.
func _unhandled_key_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
        return
    var focused := gui_get_focus_owner()
    if focused is BaseButton and is_focusable(focused) and focused.has_focus(true):
        set_input_as_handled()
        return
    if is_focusable(default_button):
        if focused is BaseButton:
            gui_release_focus()
        default_button.pressed.emit()
        set_input_as_handled()


## Whether *control* is the text box of a number field, a `FactorSlider`'s or a
## `SpinBox`'s, whose Enter means "take this number" and nothing more.
##
## A name field is left out on purpose. Its Enter already means something in the
## dialogs that have one, Rename in Rename Layer, Create in New Module and a rename
## in the Brush Editor, each wired by its own dialog, and pressing the default
## after it would answer twice: New Module keeps its window up to say a name is
## taken, and the second Create would say it again.
static func is_number_field(control: Control) -> bool:
    if not control is LineEdit:
        return false
    var holder := control.get_parent()
    return holder is FactorSlider or holder is SpinBox


## Every number field is told to answer with the default the first time it holds
## the keyboard, whenever its dialog built it, so a page built on the way up is
## covered as surely as one built in `_init`.
##
## **Deferred**, because a `SpinBox` takes the typed number from its text box on
## a deferred call of its own. A connection made later is queued later, so the
## default reads the number the painter typed rather than the one before it.
func _on_gui_focus_changed(control: Control) -> void:
    if not is_number_field(control):
        return
    var field := control as LineEdit
    if not field.text_submitted.is_connected(_on_number_submitted):
        field.text_submitted.connect(_on_number_submitted, CONNECT_DEFERRED)


func _on_number_submitted(_text: String) -> void:
    answer_for_a_number_field()


## The default's press once a number field has taken its number, which is what
## Enter typed into the field comes to.
##
## Public because a suite calls it: the field's own submit is on a deferred call
## and a suite has no frame to let it land, the reason `fit_opening_size` gives.
## The route to it on the running app is
## `scenarios/enter-presses-the-button-the-outline-is-on.json`, which types a
## radius into Feather and presses Enter.
func answer_for_a_number_field() -> void:
    if number_field_answers and visible and is_focusable(default_button):
        default_button.pressed.emit()


## Puts focus inside the dialog every time it is shown, so Tab has somewhere to
## start and the first control is announced rather than silently current.
##
## Deferred, because `popup_centered()` flips `visible` before the window is
## mapped and takes focus for itself, and a grab made in that frame is dropped.
func _on_visibility_changed() -> void:
    _hold_above_transient_parent()
    _leave_the_trail()
    if not visible:
        remove_from_group(OPEN_GROUP)
    else:
        _trail_ticket = SaTrail.enter("the dialog %s" % title)
        _cascade_later()
        focus_first_control.call_deferred()
        # A dialog builds its controls in `_init` and is shown much later, so a
        # Font size change made while it was hidden has to be picked up here. The
        # same reason the dropdown line below runs on every open.
        adopt_shared_theme()
        # Every open asks again, because a dialog whose page is built or filled
        # by its subclass on the way up (`SaSettingsWindow`, the filter browser)
        # has content it did not have when `_ready` measured it.
        _fit_next_frame()
        # The line that walked this dialog for `OptionButton`s on every open,
        # taking the engine's radio dots off their rows, is gone with the last
        # of those controls. Every dropdown here is an `SaChoiceButton`, whose
        # rows Sara builds and marks itself.


## Gives back the place that stood in the trail before the dialog showed, on its
## hide and on its leaving the tree. A window that leaves the tree showing says
## nothing of its visibility, so without this a dialog freed while it shows
## would name itself in every stall after it.
func _leave_the_trail() -> void:
    SaTrail.give_back(_trail_ticket)
    _trail_ticket = SaTrail.NOTED


## Asks `cascade_off_the_open_dialogs` for the end of the frame, because neither
## signal of a show says where the window is. A `Window` is visible from the
## moment it joins the tree, at (0, 0), so the first `popup_centered` of a dialog
## changes no visibility and only `about_to_popup` hears of it, before it has
## moved. A later show hears `visibility_changed` with the position it will keep.
## One call after both has the answer in either case, and runs once more,
## harmlessly, when both were heard.
func _cascade_later() -> void:
    cascade_off_the_open_dialogs.call_deferred()


## Moves a dialog that opened over another's title strip to a title strip down
## and right of that dialog, once for every dialog whose strip it would still
## hide, inside the host, and raises it. Then it counts among the dialogs on
## screen.
##
## Corners and centres both say nothing of overlap: two dialogs of two heights
## centred on one host have corners a few pixels apart, and the taller hides the
## shorter whole. So the test reads the rectangles: a dialog is on another when it covers the other's
## title strip. The move is to the other's corner plus a step, never up or left
## of where the dialog was, so it lands a strip down and right of the one below
## whatever their sizes. A dialog a painter dragged off the strip is not on
## another and stays where it was put. A host too small to move into ends the
## walk with the window where the host allowed it.
##
## A dialog joins the group here and not when it is shown, so of two dialogs
## shown in one frame the first is on screen when the second looks and not the
## other way about. The dialogs already in it are the ones it was shown over.
##
## `fit_opening_size` asks again when it changes the size, because a dialog that
## opens clear of another's strip at its declared height can be grown over the
## strip by the fit a frame later, about its centre, which a walk at the show
## alone would leave covering the other.
##
## Public because a suite calls it: the deferred call has no frame to land in.
func cascade_off_the_open_dialogs() -> void:
    if not is_inside_tree() or not visible:
        return
    if not is_in_group(OPEN_GROUP):
        _shown_over.clear()
        for node: Node in get_tree().get_nodes_in_group(OPEN_GROUP):
            _shown_over.append(node.get_instance_id())
    var strip := ceili(title_strip_height())
    var step := SaUI.window_size_for(self, Vector2i(strip, strip))
    var moved := false
    for _attempt in CASCADE_ATTEMPTS:
        if step.x <= 0 or step.y <= 0:
            break
        var below := _open_dialog_whose_strip_it_hides(step)
        if below == null:
            break
        var next := _clamped_to_host(position.max(below.position + step))
        if next == position:
            break
        position = next
        moved = true
    if moved:
        grab_focus()
    add_to_group(OPEN_GROUP)


## The first dialog this one was shown over, still on screen in this window's
## host, whose title strip, *step* tall, this window's rectangle covers, or null.
func _open_dialog_whose_strip_it_hides(step: Vector2i) -> SaDialogWindow:
    var host := get_parent().get_viewport()
    var mine := Rect2i(position, size)
    for node: Node in get_tree().get_nodes_in_group(OPEN_GROUP):
        var other := node as SaDialogWindow
        if other == null or other == self or not other.visible:
            continue
        if not _shown_over.has(other.get_instance_id()):
            continue
        if other.get_parent().get_viewport() != host:
            continue
        if mine.intersects(Rect2i(other.position, Vector2i(other.size.x, step.y))):
            return other
    return null


## The dialogs on screen in *root*, bottom to top, each with its title and the
## rectangle it fills in the host. A shot shows the stacking and cannot say it in
## numbers, and the cascade's promise is about both: the second dialog is a title strip down
## and right of the first, and above it.
static func capture_open(root: Window) -> Array:
    var rows: Array = []
    for window: Window in root.get_embedded_subwindows():
        var dialog := window as SaDialogWindow
        if dialog == null or not dialog.visible:
            continue
        (
            rows
            . append(
                {
                    "title": dialog.title,
                    "position": [dialog.position.x, dialog.position.y],
                    "size": [dialog.size.x, dialog.size.y],
                }
            )
        )
    return rows


## Focus the control the dialog opens on, unless something in it already has it.
func focus_first_control() -> void:
    if not visible or gui_get_focus_owner() != null:
        return
    var target := first_focus
    if not is_focusable(target):
        target = first_focusable(content)
    if target != null:
        target.grab_focus()


## Whether the Tab walk can land on *control*: it exists, it is on screen, it
## takes focus, and it is not a disabled button.
static func is_focusable(control: Control) -> bool:
    if control == null or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
        return false
    var button := control as BaseButton
    return button == null or not button.disabled


## The first control under *root*, in tree order, that Tab could land on.
static func first_focusable(root: Node) -> Control:
    if root == null:
        return null
    for child in root.get_children():
        var control := child as Control
        if is_focusable(control):
            return control
        var deeper := first_focusable(child)
        if deeper != null:
            return deeper
    return null
